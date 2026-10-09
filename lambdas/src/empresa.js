'use strict';

const { randomUUID } = require('crypto');
const { GetCommand, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb, HttpError, json, parseBody, requireGroup, text, wrap } = require('./common');

const ESTADOS = ['operativa', 'suspendida', 'desviada'];
const RUTA_ID = /^[A-Za-z0-9_-]{1,40}$/;

// Valida y limpia los datos de una ruta enviados por la empresa.
function validarRuta(body) {
  const paradas = body.paradas === undefined ? [] : body.paradas;
  if (!Array.isArray(paradas) || paradas.length > 30) throw new HttpError(400, '"paradas" debe ser una lista de hasta 30 nombres');
  const estado = body.estado === undefined ? 'operativa' : body.estado;
  if (!ESTADOS.includes(estado)) throw new HttpError(400, `"estado" debe ser: ${ESTADOS.join(', ')}`);
  return {
    nombre: text(body.nombre, 'nombre', { min: 3, max: 80 }),
    origen: text(body.origen, 'origen', { min: 2, max: 80 }),
    destino: text(body.destino, 'destino', { min: 2, max: 80 }),
    horario: text(body.horario, 'horario', { max: 120, required: false }),
    tarifa: text(body.tarifa, 'tarifa', { max: 30, required: false }),
    paradas: paradas.map((p, i) => text(p, `paradas[${i}]`, { min: 2, max: 80 })),
    estado,
  };
}

// POST /rutas : la empresa publica una ruta nueva.
async function crearRuta(event) {
  const user = requireGroup(event, 'empresa');
  const datos = validarRuta(parseBody(event));
  const rutaId = `R-${randomUUID().slice(0, 8)}`;
  const item = {
    rutaId,
    ...datos,
    empresa: text(parseBody(event).empresa, 'empresa', { max: 80, required: false }) || user.email || 'Empresa',
    empresaId: user.sub,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  await ddb.send(new PutCommand({
    TableName: process.env.TABLE_RUTAS,
    Item: item,
    ConditionExpression: 'attribute_not_exists(rutaId)',
  }));
  return json(201, item);
}

// PUT /rutas/{rutaId} : solo la empresa dueña puede modificarla.
async function actualizarRuta(event) {
  const user = requireGroup(event, 'empresa');
  const id = event.pathParameters && event.pathParameters.rutaId;
  if (!id || !RUTA_ID.test(id)) throw new HttpError(400, 'rutaId inválido');

  const actual = await ddb.send(new GetCommand({ TableName: process.env.TABLE_RUTAS, Key: { rutaId: id } }));
  if (!actual.Item) throw new HttpError(404, 'Ruta no encontrada');
  if (actual.Item.empresaId !== user.sub) throw new HttpError(403, 'Esta ruta pertenece a otra empresa');

  const body = parseBody(event);
  const item = {
    ...actual.Item,
    ...validarRuta({ ...actual.Item, ...body }),
    updatedAt: new Date().toISOString(),
  };
  await ddb.send(new PutCommand({ TableName: process.env.TABLE_RUTAS, Item: item }));
  return json(200, item);
}

const handler = wrap(async (event) => {
  switch (event.routeKey) {
    case 'POST /rutas': return crearRuta(event);
    case 'PUT /rutas/{rutaId}': return actualizarRuta(event);
    default: throw new HttpError(404, 'Ruta no encontrada');
  }
});

module.exports = { handler };
