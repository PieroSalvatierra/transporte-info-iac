'use strict';
// Pruebas locales de las 4 Lambdas con AWS simulado (no usa red ni credenciales).
//   node tests/run.js
const assert = require('assert');
const Module = require('module');
const path = require('path');

// ── AWS simulado en memoria ──────────────────────────────────────────────────
const db = { rutas: new Map(), incidentes: [], usuarios: new Map() };
const sent = { sqs: [], sns: [] };
let subs = [];

class Cmd { constructor(input) { this.input = input; } }
const names = ['GetCommand', 'PutCommand', 'QueryCommand', 'ScanCommand'];
const fakeLib = Object.fromEntries(names.map((n) => [n, { [n]: class extends Cmd {} }[n]]));
fakeLib.DynamoDBDocumentClient = {
  from: () => ({
    async send(cmd) {
      const { TableName: t, Key, Item, IndexName, ExpressionAttributeValues: v, ConditionExpression } = cmd.input;
      const kind = cmd.constructor.name;
      if (t.endsWith('rutas')) {
        if (kind === 'GetCommand') return { Item: db.rutas.get(Key.rutaId) };
        if (kind === 'ScanCommand') return { Items: [...db.rutas.values()] };
        if (kind === 'PutCommand') {
          if (ConditionExpression && db.rutas.has(Item.rutaId)) throw new Error('ConditionalCheckFailed');
          db.rutas.set(Item.rutaId, Item); return {};
        }
      }
      if (t.endsWith('incidentes')) {
        if (kind === 'PutCommand') { db.incidentes.push(Item); return {}; }
        if (kind === 'QueryCommand') {
          const rows = IndexName ? db.incidentes.filter((i) => i.estado === v[':e']) : db.incidentes.filter((i) => i.rutaId === v[':r']);
          return { Items: rows.sort((a, b) => b.ts.localeCompare(a.ts)) };
        }
      }
      if (t.endsWith('usuarios')) {
        if (kind === 'GetCommand') return { Item: db.usuarios.get(Key.userId) };
        if (kind === 'PutCommand') { db.usuarios.set(Item.userId, Item); return {}; }
      }
      throw new Error('comando no simulado: ' + kind + ' ' + t);
    },
  }),
};

const snsCmds = ['SubscribeCommand', 'ListSubscriptionsByTopicCommand', 'SetSubscriptionAttributesCommand', 'UnsubscribeCommand', 'PublishCommand'];
const fakeSns = Object.fromEntries(snsCmds.map((n) => [n, { [n]: class extends Cmd {} }[n]]));
fakeSns.SNSClient = class {
  async send(cmd) {
    const k = cmd.constructor.name;
    if (k === 'PublishCommand') { sent.sns.push(cmd.input); return {}; }
    if (k === 'ListSubscriptionsByTopicCommand') return { Subscriptions: subs };
    if (k === 'SubscribeCommand') { subs.push({ Protocol: 'email', Endpoint: cmd.input.Endpoint, SubscriptionArn: 'pending confirmation', attrs: cmd.input.Attributes }); return {}; }
    if (k === 'SetSubscriptionAttributesCommand') { sent.sns.push({ set: cmd.input }); return {}; }
    if (k === 'UnsubscribeCommand') { sent.sns.push({ unsub: cmd.input }); return {}; }
    throw new Error('sns no simulado ' + k);
  }
};
const fakeSqs = { SQSClient: class { async send(cmd) { if (process.env.SQS_FAIL) throw new Error('sqs caído'); sent.sqs.push(cmd.input); return {}; } }, SendMessageCommand: class extends Cmd {} };

const fakes = {
  '@aws-sdk/client-dynamodb': { DynamoDBClient: class {} },
  '@aws-sdk/lib-dynamodb': fakeLib,
  '@aws-sdk/client-sns': fakeSns,
  '@aws-sdk/client-sqs': fakeSqs,
};
const origLoad = Module._load;
Module._load = function (request, ...rest) { return fakes[request] || origLoad.call(this, request, ...rest); };

process.env.TABLE_RUTAS = 'x-rutas'; process.env.TABLE_INCIDENTES = 'x-incidentes'; process.env.TABLE_USUARIOS = 'x-usuarios';
process.env.QUEUE_URL = 'https://sqs/q'; process.env.TOPIC_ARN = 'arn:aws:sns:us-east-1:1:alertas'; process.env.INCIDENT_TTL_DAYS = '3';

const src = path.join(__dirname, '..', 'lambdas', 'src');
const consulta = require(path.join(src, 'consulta')).handler;
const empresa = require(path.join(src, 'empresa')).handler;
const incidentes = require(path.join(src, 'incidentes')).handler;
const notificador = require(path.join(src, 'notificador')).handler;

// ── Ayudas ───────────────────────────────────────────────────────────────────
const ev = (routeKey, { body, qs, params, user } = {}) => ({
  routeKey,
  queryStringParameters: qs,
  pathParameters: params,
  body: body === undefined ? undefined : JSON.stringify(body),
  requestContext: user ? { authorizer: { jwt: { claims: user } } } : {},
});
const U = {
  pasajero: { sub: 'u-pas', email: 'pas@x.pe' },
  conductor: { sub: 'u-con', email: 'con@x.pe', 'cognito:groups': '[conductor]' },
  empresa: { sub: 'u-emp', email: 'emp@x.pe', 'cognito:groups': '[empresa]' },
  otraEmpresa: { sub: 'u-emp2', email: 'emp2@x.pe', 'cognito:groups': 'empresa' },
};
const body = (r) => JSON.parse(r.body);
let n = 0;
const ok = (name) => { n++; console.log('  ✓ ' + name); };

(async () => {
  console.log('empresa-lambda');
  let r = await empresa(ev('POST /rutas', { body: { nombre: 'X', origen: 'a', destino: 'b' } }));
  assert.strictEqual(r.statusCode, 401); ok('sin sesión → 401');
  r = await empresa(ev('POST /rutas', { user: U.conductor, body: { nombre: 'Ruta Uno', origen: 'A1', destino: 'B1' } }));
  assert.strictEqual(r.statusCode, 403); ok('conductor no puede publicar rutas → 403');
  r = await empresa(ev('POST /rutas', { user: U.empresa, body: { nombre: 'Ruta Uno', origen: 'Plaza', destino: 'Mall', paradas: ['Plaza', 'Larco', 'Mall'], horario: '6-22' } }));
  assert.strictEqual(r.statusCode, 201, r.body);
  const ruta = body(r);
  assert.match(ruta.rutaId, /^R-[0-9a-f]{8}$/); assert.strictEqual(ruta.empresaId, 'u-emp'); ok('empresa publica ruta → 201');
  r = await empresa(ev('POST /rutas', { user: U.empresa, body: { nombre: 'Ruta Uno', origen: 'Plaza', destino: 'Mall', estado: 'rota' } }));
  assert.strictEqual(r.statusCode, 400); ok('estado inválido → 400');
  r = await empresa(ev('PUT /rutas/{rutaId}', { user: U.otraEmpresa, params: { rutaId: ruta.rutaId }, body: { nombre: 'Robada' } }));
  assert.strictEqual(r.statusCode, 403); ok('otra empresa no puede editar → 403');
  r = await empresa(ev('PUT /rutas/{rutaId}', { user: U.empresa, params: { rutaId: ruta.rutaId }, body: { estado: 'desviada' } }));
  assert.strictEqual(r.statusCode, 200); assert.strictEqual(body(r).estado, 'desviada'); assert.strictEqual(body(r).nombre, 'Ruta Uno'); ok('la dueña actualiza el estado → 200');
  r = await empresa(ev('POST /rutas', { user: U.empresa }));
  assert.strictEqual(r.statusCode, 400); ok('sin cuerpo → 400');

  console.log('consulta-lambda (público)');
  db.rutas.set('R-DEMO-01', { rutaId: 'R-DEMO-01', nombre: 'Trujillo Centro - Huanchaco', origen: 'Plaza de Armas', destino: 'Huanchaco', paradas: ['Óvalo Larco'] });
  r = await consulta(ev('GET /rutas'));
  assert.strictEqual(r.statusCode, 200); assert.strictEqual(body(r).rutas.length, 2); ok('lista rutas sin sesión');
  r = await consulta(ev('GET /rutas', { qs: { q: 'huanchaco' } }));
  assert.strictEqual(body(r).rutas.length, 1); ok('busca por texto');
  r = await consulta(ev('GET /rutas', { qs: { q: 'óvalo' } }));
  assert.strictEqual(body(r).rutas.length, 1); ok('busca por paradero');
  r = await consulta(ev('GET /rutas/{rutaId}', { params: { rutaId: 'R-DEMO-01' } }));
  assert.strictEqual(r.statusCode, 200); ok('detalle de ruta');
  r = await consulta(ev('GET /rutas/{rutaId}', { params: { rutaId: 'NOEXISTE' } }));
  assert.strictEqual(r.statusCode, 404); ok('ruta inexistente → 404');
  r = await consulta(ev('GET /rutas/{rutaId}', { params: { rutaId: "x'; drop" } }));
  assert.strictEqual(r.statusCode, 400); ok('id con caracteres raros → 400');

  console.log('incidentes-lambda');
  const inc = { rutaId: 'R-DEMO-01', tipo: 'accidente', descripcion: 'Choque leve en Av. Larco', ubicacion: 'Av. Larco' };
  r = await incidentes(ev('POST /incidentes', { user: U.pasajero, body: inc }));
  assert.strictEqual(r.statusCode, 403); ok('pasajero no puede reportar → 403');
  r = await incidentes(ev('POST /incidentes', { user: U.conductor, body: { ...inc, tipo: 'platillo' } }));
  assert.strictEqual(r.statusCode, 400); ok('tipo inválido → 400');
  r = await incidentes(ev('POST /incidentes', { user: U.conductor, body: { ...inc, rutaId: 'NOEXISTE' } }));
  assert.strictEqual(r.statusCode, 404); ok('ruta inexistente → 404');
  r = await incidentes(ev('POST /incidentes', { user: U.conductor, body: inc }));
  assert.strictEqual(r.statusCode, 201, r.body); assert.strictEqual(body(r).notificado, true);
  assert.strictEqual(db.incidentes.length, 1); assert.strictEqual(sent.sqs.length, 1);
  const ttl = db.incidentes[0].expiraEn - Math.floor(Date.now() / 1000);
  assert.ok(ttl > 2.9 * 86400 && ttl <= 3 * 86400); assert.strictEqual(body(r).reportadoPor, undefined); ok('conductor reporta → DynamoDB + SQS + TTL 3 días');
  process.env.SQS_FAIL = '1';
  r = await incidentes(ev('POST /incidentes', { user: U.conductor, body: inc }));
  assert.strictEqual(r.statusCode, 201); assert.strictEqual(body(r).notificado, false); delete process.env.SQS_FAIL; ok('si SQS falla, el incidente igual se guarda');

  console.log('consulta-lambda (incidentes)');
  r = await consulta(ev('GET /incidentes'));
  assert.strictEqual(body(r).incidentes.length, 2); ok('lista incidentes activos sin sesión');
  r = await consulta(ev('GET /incidentes', { qs: { ruta: 'R-DEMO-01' } }));
  assert.strictEqual(body(r).incidentes.length, 2); ok('filtra por ruta');
  db.incidentes[0].expiraEn = Math.floor(Date.now() / 1000) - 10;
  r = await consulta(ev('GET /incidentes'));
  assert.strictEqual(body(r).incidentes.length, 1); ok('oculta incidentes vencidos (TTL)');

  console.log('consulta-lambda (favoritos)');
  r = await consulta(ev('GET /favoritos'));
  assert.strictEqual(r.statusCode, 401); ok('favoritos exige sesión → 401');
  r = await consulta(ev('PUT /favoritos', { user: U.pasajero, body: { rutas: ['R-DEMO-01'] } }));
  assert.strictEqual(r.statusCode, 200); assert.strictEqual(body(r).suscripcion, 'pendiente-de-confirmacion');
  assert.deepStrictEqual(JSON.parse(subs[0].attrs.FilterPolicy), { ruta: ['R-DEMO-01'] }); ok('guarda favoritos y suscribe el correo con filtro por ruta');
  subs[0].SubscriptionArn = 'arn:aws:sns:us-east-1:1:alertas:abc';
  r = await consulta(ev('PUT /favoritos', { user: U.pasajero, body: { rutas: ['R-DEMO-01', 'R-DEMO-02'] } }));
  assert.strictEqual(body(r).suscripcion, 'activa');
  assert.deepStrictEqual(JSON.parse(sent.sns.at(-1).set.AttributeValue), { ruta: ['R-DEMO-01', 'R-DEMO-02'] }); ok('suscripción confirmada: actualiza el filtro');
  r = await consulta(ev('GET /favoritos', { user: U.pasajero }));
  assert.deepStrictEqual(body(r).rutas, ['R-DEMO-01', 'R-DEMO-02']); ok('lee sus favoritos');
  r = await consulta(ev('PUT /favoritos', { user: U.pasajero, body: { rutas: [] } }));
  assert.strictEqual(body(r).suscripcion, 'ninguna'); assert.ok(sent.sns.at(-1).unsub); ok('sin favoritos: cancela la suscripción');
  r = await consulta(ev('PUT /favoritos', { user: U.pasajero, body: { rutas: ['ok', '<script>'] } }));
  assert.strictEqual(r.statusCode, 400); ok('ids inválidos → 400');

  console.log('notificador-lambda');
  const msg = JSON.parse(sent.sqs[0].MessageBody);
  const res = await notificador({ Records: [{ messageId: 'm1', body: JSON.stringify(msg) }, { messageId: 'm2', body: 'no-es-json' }] });
  assert.deepStrictEqual(res, { batchItemFailures: [{ itemIdentifier: 'm2' }] });
  const pub = sent.sns.find((s) => s.MessageAttributes);
  assert.strictEqual(pub.MessageAttributes.ruta.StringValue, 'R-DEMO-01');
  assert.match(pub.Subject, /^Accidente en /); ok('publica en SNS con atributo "ruta"; el mensaje roto se reintenta');

  console.log(`\n${n} pruebas OK`);
})().catch((e) => { console.error('\nFALLÓ:', e); process.exit(1); });
