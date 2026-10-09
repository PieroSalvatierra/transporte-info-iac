'use strict';

const { GetCommand, PutCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const {
  SNSClient,
  SubscribeCommand,
  ListSubscriptionsByTopicCommand,
  SetSubscriptionAttributesCommand,
  UnsubscribeCommand,
} = require('@aws-sdk/client-sns');
const { ddb, HttpError, json, parseBody, requireUser, wrap } = require('./common');

const sns = new SNSClient({});

const RUTA_ID = /^[A-Za-z0-9_-]{1,40}$/;

// ── Rutas ────────────────────────────────────────────────────────────────────
async function listarRutas(event) {
  const q = ((event.queryStringParameters && event.queryStringParameters.q) || '').trim().toLowerCase();
  const items = [];
  let key;
  for (let page = 0; page < 5; page++) {
    const r = await ddb.send(new ScanCommand({ TableName: process.env.TABLE_RUTAS, ExclusiveStartKey: key }));
    items.push(...(r.Items || []));
    key = r.LastEvaluatedKey;
    if (!key) break;
  }
  const filtradas = q
    ? items.filter((r) =>
        [r.nombre, r.origen, r.destino, r.empresa, ...(r.paradas || [])]
          .filter(Boolean)
          .some((t) => String(t).toLowerCase().includes(q)))
    : items;
  filtradas.sort((a, b) => String(a.nombre).localeCompare(String(b.nombre)));
  return json(200, { rutas: filtradas });
}

async function obtenerRuta(event) {
  const id = event.pathParameters && event.pathParameters.rutaId;
  if (!id || !RUTA_ID.test(id)) throw new HttpError(400, 'rutaId inválido');
  const r = await ddb.send(new GetCommand({ TableName: process.env.TABLE_RUTAS, Key: { rutaId: id } }));
  if (!r.Item) throw new HttpError(404, 'Ruta no encontrada');
  return json(200, r.Item);
}

// ── Incidentes ───────────────────────────────────────────────────────────────
async function listarIncidentes(event) {
  const ruta = event.queryStringParameters && event.queryStringParameters.ruta;
  let r;
  if (ruta) {
    if (!RUTA_ID.test(ruta)) throw new HttpError(400, 'ruta inválida');
    r = await ddb.send(new QueryCommand({
      TableName: process.env.TABLE_INCIDENTES,
      KeyConditionExpression: 'rutaId = :r',
      ExpressionAttributeValues: { ':r': ruta },
      ScanIndexForward: false,
      Limit: 50,
    }));
  } else {
    r = await ddb.send(new QueryCommand({
      TableName: process.env.TABLE_INCIDENTES,
      IndexName: 'estado-ts',
      KeyConditionExpression: 'estado = :e',
      ExpressionAttributeValues: { ':e': 'activo' },
      ScanIndexForward: false,
      Limit: 50,
    }));
  }
  // TTL de DynamoDB puede tardar horas en borrar: se ocultan los vencidos.
  const ahora = Math.floor(Date.now() / 1000);
  const incidentes = (r.Items || []).filter((i) => !i.expiraEn || i.expiraEn > ahora);
  return json(200, { incidentes });
}

// ── Favoritos (requiere sesión) ──────────────────────────────────────────────
async function obtenerFavoritos(event) {
  const user = requireUser(event);
  const r = await ddb.send(new GetCommand({ TableName: process.env.TABLE_USUARIOS, Key: { userId: user.sub } }));
  return json(200, { rutas: (r.Item && r.Item.rutas) || [] });
}

// Mantiene UNA suscripción de correo por usuario con filtro por sus rutas.
async function sincronizarSuscripcion(email, rutas) {
  const topic = process.env.TOPIC_ARN;
  let existente = null;
  let token;
  do {
    const r = await sns.send(new ListSubscriptionsByTopicCommand({ TopicArn: topic, NextToken: token }));
    existente = (r.Subscriptions || []).find((s) => s.Protocol === 'email' && s.Endpoint === email) || existente;
    token = r.NextToken;
  } while (token && !existente);

  const confirmada = existente && existente.SubscriptionArn && existente.SubscriptionArn.startsWith('arn:');

  if (rutas.length === 0) {
    if (confirmada) await sns.send(new UnsubscribeCommand({ SubscriptionArn: existente.SubscriptionArn }));
    return 'ninguna';
  }
  const filtro = JSON.stringify({ ruta: rutas });
  if (confirmada) {
    await sns.send(new SetSubscriptionAttributesCommand({
      SubscriptionArn: existente.SubscriptionArn,
      AttributeName: 'FilterPolicy',
      AttributeValue: filtro,
    }));
    return 'activa';
  }
  if (!existente) {
    await sns.send(new SubscribeCommand({
      TopicArn: topic,
      Protocol: 'email',
      Endpoint: email,
      Attributes: { FilterPolicy: filtro, FilterPolicyScope: 'MessageAttributes' },
      ReturnSubscriptionArn: true,
    }));
  }
  return 'pendiente-de-confirmacion';
}

async function guardarFavoritos(event) {
  const user = requireUser(event);
  const body = parseBody(event);
  if (!Array.isArray(body.rutas) || body.rutas.length > 20) {
    throw new HttpError(400, '"rutas" debe ser una lista de hasta 20 ids');
  }
  const rutas = [...new Set(body.rutas)];
  if (!rutas.every((r) => typeof r === 'string' && RUTA_ID.test(r))) throw new HttpError(400, 'Hay ids de ruta inválidos');

  await ddb.send(new PutCommand({
    TableName: process.env.TABLE_USUARIOS,
    Item: { userId: user.sub, email: user.email, rutas, updatedAt: new Date().toISOString() },
  }));

  let suscripcion = 'sin-correo';
  if (user.email) {
    try {
      suscripcion = await sincronizarSuscripcion(user.email, rutas);
    } catch (err) {
      // Los favoritos ya se guardaron; la suscripción se puede reintentar.
      console.error(JSON.stringify({ msg: 'no se pudo sincronizar la suscripción SNS', error: err.message }));
      suscripcion = 'error-reintentar';
    }
  }
  return json(200, { rutas, suscripcion });
}

const handler = wrap(async (event) => {
  switch (event.routeKey) {
    case 'GET /rutas': return listarRutas(event);
    case 'GET /rutas/{rutaId}': return obtenerRuta(event);
    case 'GET /incidentes': return listarIncidentes(event);
    case 'GET /favoritos': return obtenerFavoritos(event);
    case 'PUT /favoritos': return guardarFavoritos(event);
    default: throw new HttpError(404, 'Ruta no encontrada');
  }
});

module.exports = { handler };
