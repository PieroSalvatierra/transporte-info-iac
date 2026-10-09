'use strict';

const CFG = window.APP_CONFIG;
const REDIRECT = window.location.origin + '/';
const $ = (s) => document.querySelector(s);

// ── Sesión (token JWT de Cognito, flujo implícito) ───────────────────────────
function decodeJwt(token) {
  try {
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(decodeURIComponent(escape(atob(payload))));
  } catch (e) { return null; }
}

function captureToken() {
  const h = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  const t = h.get('id_token');
  if (t) {
    sessionStorage.setItem('idToken', t);
    history.replaceState(null, '', window.location.pathname);
  }
}

function session() {
  const token = sessionStorage.getItem('idToken');
  const claims = token && decodeJwt(token);
  if (!claims || claims.exp * 1000 < Date.now()) {
    sessionStorage.removeItem('idToken');
    return null;
  }
  const raw = claims['cognito:groups'] || [];
  return { token, email: claims.email, groups: Array.isArray(raw) ? raw : String(raw).split(/[\s,]+/) };
}

// ── Utilidades de interfaz (siempre textContent: sin XSS) ────────────────────
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  Object.entries(attrs || {}).forEach(([k, v]) => (k === 'class' ? (el.className = v) : el.setAttribute(k, v)));
  kids.flat().forEach((c) => c != null && el.append(c.nodeType ? c : document.createTextNode(String(c))));
  return el;
}

function flash(text, isError) {
  const m = $('#msg');
  m.textContent = text;
  m.className = 'msg' + (isError ? ' error' : '');
  m.hidden = false;
  clearTimeout(flash.t);
  flash.t = setTimeout(() => (m.hidden = true), 7000);
}

async function api(path, opts = {}) {
  const s = session();
  const headers = { 'content-type': 'application/json' };
  if (s) headers.authorization = s.token;
  const res = await fetch(CFG.apiUrl + path, { ...opts, headers });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || data.message || `Error ${res.status}`);
  return data;
}

// ── Datos ────────────────────────────────────────────────────────────────────
let RUTAS = [];

function cardRuta(r) {
  return h('article', { class: 'card' },
    h('h3', {}, r.nombre),
    h('span', { class: 'pill ' + r.estado }, r.estado),
    h('p', {}, `${r.origen} → ${r.destino}`),
    r.horario && h('p', { class: 'meta' }, r.horario),
    r.tarifa && h('p', { class: 'meta' }, 'Tarifa: ' + r.tarifa),
    h('p', { class: 'meta' }, r.empresa),
    r.paradas && r.paradas.length ? h('ol', { class: 'stops' }, r.paradas.map((p) => h('li', {}, p))) : null);
}

async function cargarRutas() {
  try {
    const q = encodeURIComponent($('#q').value.trim());
    const { rutas } = await api('/rutas' + (q ? `?q=${q}` : ''));
    RUTAS = rutas;
    $('#rutas').replaceChildren(...(rutas.length ? rutas.map(cardRuta) : [h('p', {}, 'No hay rutas que coincidan.')]));
    rellenarSelectores();
  } catch (e) { flash(e.message, true); }
}

function rellenarSelectores() {
  const opts = (blank) => [blank && h('option', { value: '' }, blank), ...RUTAS.map((r) => h('option', { value: r.rutaId }, r.nombre))].filter(Boolean);
  const f = $('#f-ruta'); const keep = f.value;
  f.replaceChildren(...opts('Todas las rutas')); f.value = keep;
  $('#form-inc [name=rutaId]').replaceChildren(...opts());
}

async function cargarIncidentes() {
  try {
    const ruta = $('#f-ruta').value;
    const { incidentes } = await api('/incidentes' + (ruta ? `?ruta=${encodeURIComponent(ruta)}` : ''));
    const nombre = (id) => (RUTAS.find((r) => r.rutaId === id) || {}).nombre || id;
    $('#incidentes').replaceChildren(...(incidentes.length
      ? incidentes.map((i) => h('article', { class: 'card' },
          h('h3', {}, nombre(i.rutaId)),
          h('span', { class: 'pill ' + i.tipo }, i.tipo),
          h('p', {}, i.descripcion),
          i.ubicacion && h('p', { class: 'meta' }, 'Ubicación: ' + i.ubicacion),
          h('p', { class: 'meta' }, new Date(i.ts).toLocaleString('es-PE'))))
      : [h('p', {}, 'No hay incidentes activos. ¡Buen viaje!')]));
  } catch (e) { flash(e.message, true); }
}

async function cargarFavoritas() {
  try {
    const { rutas: favs } = await api('/favoritos');
    $('#favs').replaceChildren(...RUTAS.map((r) => {
      const cb = h('input', { type: 'checkbox', value: r.rutaId });
      cb.checked = favs.includes(r.rutaId);
      return h('label', {}, cb, r.nombre);
    }));
  } catch (e) { flash(e.message, true); }
}

// ── Acciones ─────────────────────────────────────────────────────────────────
async function guardarFavoritas() {
  try {
    const rutas = [...document.querySelectorAll('#favs input:checked')].map((c) => c.value);
    const r = await api('/favoritos', { method: 'PUT', body: JSON.stringify({ rutas }) });
    const extra = {
      'pendiente-de-confirmacion': ' Revisa tu correo y confirma la suscripción de Amazon SNS.',
      'activa': ' Avisos activos.',
      'error-reintentar': ' No se pudo activar el aviso por correo; inténtalo de nuevo.',
    }[r.suscripcion] || '';
    flash('Rutas guardadas.' + extra, r.suscripcion === 'error-reintentar');
  } catch (e) { flash(e.message, true); }
}

async function enviarIncidente(ev) {
  ev.preventDefault();
  const f = new FormData(ev.target);
  try {
    await api('/incidentes', { method: 'POST', body: JSON.stringify(Object.fromEntries(f)) });
    flash('Incidente reportado. Gracias por avisar.');
    ev.target.reset();
  } catch (e) { flash(e.message, true); }
}

async function publicarRuta(ev) {
  ev.preventDefault();
  const f = Object.fromEntries(new FormData(ev.target));
  f.paradas = String(f.paradas || '').split('\n').map((s) => s.trim()).filter(Boolean);
  try {
    await api('/rutas', { method: 'POST', body: JSON.stringify(f) });
    flash('Ruta publicada.');
    ev.target.reset();
    cargarRutas();
  } catch (e) { flash(e.message, true); }
}

// ── Pestañas y sesión ────────────────────────────────────────────────────────
function showTab(name) {
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
  document.querySelectorAll('.panel').forEach((p) => (p.hidden = p.id !== 'tab-' + name));
  if (name === 'incidentes') cargarIncidentes();
  if (name === 'favoritas') cargarFavoritas();
}

function pintarSesion() {
  const s = session();
  $('#who').textContent = s ? s.email + (s.groups.filter(Boolean).length ? ` (${s.groups.filter(Boolean).join(', ')})` : '') : 'Navegando sin sesión';
  $('#btn-login').hidden = !!s;
  $('#btn-logout').hidden = !s;
  document.querySelectorAll('[data-auth]').forEach((t) => {
    const need = t.dataset.auth;
    t.hidden = !s || (need === 'conductor' && !s.groups.some((g) => ['conductor', 'empresa'].includes(g))) || (need === 'empresa' && !s.groups.includes('empresa'));
  });
}

function init() {
  captureToken();
  $('#env').textContent = CFG.environment;
  $('#btn-login').onclick = () => {
    location.href = `https://${CFG.cognitoDomain}/login?client_id=${CFG.clientId}&response_type=token&scope=openid+email+profile&redirect_uri=${encodeURIComponent(REDIRECT)}`;
  };
  $('#btn-logout').onclick = () => {
    sessionStorage.removeItem('idToken');
    location.href = `https://${CFG.cognitoDomain}/logout?client_id=${CFG.clientId}&logout_uri=${encodeURIComponent(REDIRECT)}`;
  };
  document.querySelectorAll('.tab').forEach((t) => (t.onclick = () => showTab(t.dataset.tab)));
  $('#btn-buscar').onclick = cargarRutas;
  $('#q').addEventListener('keydown', (e) => e.key === 'Enter' && cargarRutas());
  $('#btn-inc').onclick = cargarIncidentes;
  $('#btn-fav').onclick = guardarFavoritas;
  $('#form-inc').onsubmit = enviarIncidente;
  $('#form-ruta').onsubmit = publicarRuta;
  pintarSesion();
  cargarRutas();
}

init();
