'use strict';

const { randomUUID } = require('crypto');
const { GetCommand, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const { ddb, HttpError, json, parseBody, requireGroup, text, wrap } = require('./common');

const sqs = new SQSClient({});

const TIPOS = ['accidente', 'congestion', 'desvio', 'obra', 'falla', 'clima', 'otro'];
const RUTA_ID = /^[A-Za-z0-9_-]{1,40}$/;

// POST /incidentes : el conductor (o la empresa) reporta un incidente en una ruta.
async function reportar(event) {
  const user = requireGroup(event, 'conductor', 'empresa');
  const body = parseBody(event);

  const rutaId = body.rutaId;
  if (typeof rutaId !== 'string' || !RUTA_ID.test(rutaId)) throw new HttpError(400, 'rutaId inválido');
  if (!TIPOS.includes(body.tipo)) throw new HttpError(400, `"tipo" debe ser: ${TIPOS.join(', ')}`);
  const descripcion = text(body.descripcion, 'descripcion', { min: 5, max: 280 });
  const ubicacion = text(body.ubicacion, 'ubicacion', { max: 100, required: false });

  const ruta = await ddb.send(new GetCommand({ TableName: process.env.TABLE_RUTAS, Key: { rutaId } }));
  if (!ruta.Item) throw new HttpError(404, 'La ruta no existe');

  const ahora = new Date();
  const ttlDias = parseInt(process.env.INCIDENT_TTL_DAYS || '7', 10);
  const incidente = {
    rutaId,
    ts: ahora.toISOString(),
    id: randomUUID(),
    tipo: body.tipo,
    descripcion,
    ubicacion,
    estado: 'activo',
    reportadoPor: user.sub,
    rol: user.groups.includes('conductor') ? 'conductor' : 'empresa',
    expiraEn: Math.floor(ahora.getTime() / 1000) + ttlDias * 86400,
  };
  await ddb.send(new PutCommand({ TableName: process.env.TABLE_INCIDENTES, Item: incidente }));

  // Evento para el notificador. Si falla, el incidente ya está guardado y visible.
  let notificado = true;
  try {
    await sqs.send(new SendMessageCommand({
      QueueUrl: process.env.QUEUE_URL,
      MessageBody: JSON.stringify({
        id: incidente.id,
        ts: incidente.ts,
        rutaId,
        rutaNombre: ruta.Item.nombre,
        tipo: incidente.tipo,
        descripcion,
        ubicacion,
      }),
    }));
  } catch (err) {
    notificado = false;
    console.error(JSON.stringify({ msg: 'no se pudo encolar el aviso', error: err.message, incidente: incidente.id }));
  }

  return json(201, { ...incidente, reportadoPor: undefined, notificado });
}

const handler = wrap(async (event) => {
  if (event.routeKey === 'POST /incidentes') return reportar(event);
  throw new HttpError(404, 'Ruta no encontrada');
});

module.exports = { handler };
