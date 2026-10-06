'use strict';
// MMTVL phone remote (M5). Talks to the Mac over ws://<host>:<port + 1>/ (D24).
const TOKEN_KEY = 'mmtvl.token';
const $ = (id) => document.getElementById(id);
let ws = null;
let retryDelay = 1000;
let retryTimer = null;
let toastTimer = null;

function storedToken() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } }
function storeToken(t) { try { t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY); } catch {} }
function socketURL() { return `ws://${location.hostname}:${Number(location.port || 80) + 1}/`; }
function send(obj) { if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj)); }
function hashCode() { const m = location.hash.match(/pair=(\d{4})/); return m ? m[1] : null; }
function clearHash() { history.replaceState(null, '', location.pathname); }
function phoneName() {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua)) return 'iPad';
  if (/Android/.test(ua)) return 'Android phone';
  return 'Browser';
}
function show(view) { for (const v of ['connecting', 'pairing', 'remote']) $(v).hidden = v !== view; }
function toast(text) {
  $('toast').textContent = text; $('toast').hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { $('toast').hidden = true; }, 2000);
}

function connect() {
  clearTimeout(retryTimer);
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;
  show('connecting');
  const socket = new WebSocket(socketURL());
  ws = socket;
  socket.onopen = () => {
    retryDelay = 1000;
    const token = storedToken();
    const code = hashCode();
    if (token) send({ type: 'hello', token });
    else if (code) send({ type: 'pair', code, name: phoneName() });
    else show('pairing');
  };
  socket.onmessage = (e) => { try { handle(JSON.parse(e.data)); } catch {} };
  socket.onclose = () => {
    if (ws !== socket) return;
    ws = null; show('connecting');
    retryTimer = setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, 10000);
  };
}

function handle(m) {
  switch (m.type) {
    case 'welcome': show('remote'); break;
    case 'paired': storeToken(m.token); clearHash(); show('remote'); break;
    case 'authFailed':
      storeToken(null);
      if (hashCode()) send({ type: 'pair', code: hashCode(), name: phoneName() }); else show('pairing');
      break;
    case 'pairFailed': clearHash(); $('pair-error').textContent = m.message; show('pairing'); break;
    case 'status': $('front-app').textContent = m.launcherActive ? 'MMTVL' : m.frontApp; break;
    case 'toast': toast(m.message); break;
    case 'volume':
      if (typeof m.level === 'number') toast(m.muted ? 'Muted' : `Volume ${Math.round(m.level * 100)}%`);
      break;
  }
}

function bindButtons() {
  for (const b of document.querySelectorAll('[data-command]')) {
    let delay = null, interval = null;
    const command = b.dataset.command;
    const stop = () => { clearTimeout(delay); clearInterval(interval); b.classList.remove('pressed'); };
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      b.classList.add('pressed');
      send({ type: 'command', command });
      if (navigator.vibrate) navigator.vibrate(10);
      if (b.hasAttribute('data-repeat')) {
        delay = setTimeout(() => { interval = setInterval(() => send({ type: 'command', command }), 120); }, 450);
      }
    });
    for (const t of ['pointerup', 'pointercancel', 'pointerleave']) b.addEventListener(t, stop);
  }
  for (const b of document.querySelectorAll('[data-volume]')) {
    const release = () => b.classList.remove('pressed');
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      b.classList.add('pressed');
      send({ type: 'volume', action: b.dataset.volume });
    });
    for (const t of ['pointerup', 'pointercancel', 'pointerleave']) b.addEventListener(t, release);
  }
}

function bindKeyboard() {
  const input = $('text');
  // A click, not pointerdown: iOS only opens the soft keyboard when focus() runs inside a click.
  $('keyboard-open').addEventListener('click', () => {
    $('keyboard').hidden = false; input.value = ''; send({ type: 'textBegin' }); input.focus();
  });
  $('keyboard-close').addEventListener('click', () => { input.blur(); $('keyboard').hidden = true; });
  input.addEventListener('input', () => send({ type: 'text', value: input.value }));
  $('text-form').addEventListener('submit', (e) => {
    e.preventDefault(); send({ type: 'submit' }); input.value = ''; send({ type: 'textBegin' });
  });
}

function bindPairing() {
  $('pair-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const code = $('pair-code').value.trim();
    if (/^\d{4}$/.test(code)) { $('pair-error').textContent = ''; send({ type: 'pair', code, name: phoneName() }); }
  });
}

// Long presses (held arrows) shouldn't open the browser's context menu.
document.addEventListener('contextmenu', (e) => e.preventDefault());
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') connect(); });
bindButtons(); bindKeyboard(); bindPairing(); connect();
