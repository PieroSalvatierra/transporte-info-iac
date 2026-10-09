'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');

// Cliente reutilizable entre invocaciones.
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'content-type': 'application/json; charset=utf-8' },
  body: JSON.stringify(body),
});

// Cuerpo JSON de la petición (HTTP API v2).
function parseBody(event) {
  if (!event.body) throw new HttpError(400, 'Falta el cuerpo de la petición');
  try {
    const raw = event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
    const data = JSON.parse(raw);
    if (data === null || typeof data !== 'object' || Array.isArray(data)) throw new Error('no es un objeto');
    return data;
  } catch (e) {
    throw new HttpError(400, 'JSON inválido');
  }
}

// Claims del token JWT ya validado por API Gateway.
function claims(event) {
  const c = (event.requestContext && event.requestContext.authorizer && event.requestContext.authorizer.jwt && event.requestContext.authorizer.jwt.claims) || {};
  return c;
}

// En HTTP API el claim "cognito:groups" llega como "[conductor empresa]" o "conductor".
function groups(event) {
  const raw = claims(event)['cognito:groups'];
  if (!raw) return [];
  if (Array.isArray(raw)) return raw;
  return String(raw).replace(/^\[|\]$/g, '').split(/[\s,]+/).filter(Boolean);
}

function requireUser(event) {
  const c = claims(event);
  if (!c.sub) throw new HttpError(401, 'Debes iniciar sesión');
  return { sub: c.sub, email: c.email || null, groups: groups(event) };
}

function requireGroup(event, ...allowed) {
  const user = requireUser(event);
  if (!user.groups.some((g) => allowed.includes(g))) {
    throw new HttpError(403, `Se requiere el rol: ${allowed.join(' o ')}`);
  }
  return user;
}

// Texto limpio: sin caracteres de control y con longitud acotada.
function text(value, field, { min = 1, max = 100, required = true } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw new HttpError(400, `Falta el campo "${field}"`);
    return undefined;
  }
  if (typeof value !== 'string') throw new HttpError(400, `"${field}" debe ser texto`);
  // eslint-disable-next-line no-control-regex
  const clean = value.replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  if (clean.length < min || clean.length > max) {
    throw new HttpError(400, `"${field}" debe tener entre ${min} y ${max} caracteres`);
  }
  return clean;
}

// Envuelve un handler: convierte HttpError en respuestas y oculta errores internos.
const wrap = (fn) => async (event, context) => {
  try {
    return await fn(event, context);
  } catch (err) {
    if (err instanceof HttpError) return json(err.status, { error: err.message });
    console.error(JSON.stringify({ msg: 'error no controlado', error: err.message, stack: err.stack }));
    return json(500, { error: 'Error interno' });
  }
};

module.exports = { ddb, HttpError, json, parseBody, claims, groups, requireUser, requireGroup, text, wrap };
