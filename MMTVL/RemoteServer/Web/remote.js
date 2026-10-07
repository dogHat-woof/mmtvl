'use strict';
// MMTVL phone remote (M5). Talks to the Mac over ws://<host>:<port + 1>/ (D24).
const TOKEN_KEY = 'mmtvl.token';
const MODE_KEY = 'mmtvl.mode';
const $ = (id) => document.getElementById(id);
let ws = null;
let retryDelay = 1000;
let retryTimer = null;
let toastTimer = null;

function storedToken() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } }
function storeToken(t) { try { t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY); } catch {} }
function storedMode() { try { return localStorage.getItem(MODE_KEY); } catch { return null; } }
function storeMode(m) { try { localStorage.setItem(MODE_KEY, m); } catch {} }
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

// M7b L11: D-pad or trackpad, remembered on the phone.
function setMode(mode) {
  const trackpad = mode === 'trackpad';
  document.querySelector('.dpad').hidden = trackpad;
  $('trackpad').hidden = !trackpad;
  $('mode-toggle').textContent = trackpad ? 'D-pad' : 'Trackpad';
  $('mode-toggle').setAttribute('aria-label', trackpad ? 'Switch to D-pad' : 'Switch to trackpad');
  storeMode(trackpad ? 'trackpad' : 'dpad');
}

// One finger moves, a quick tap clicks, two fingers scroll (content follows them), a two-finger tap right-clicks.
// Movement is summed and sent once per animation frame, in CSS pixels rounded to 0.1 (the rest carries over).
function bindTrackpad() {
  const pad = $('trackpad');
  const pointers = new Map();
  let move = { x: 0, y: 0 }, scroll = { x: 0, y: 0 }, frame = 0, gesture = null;
  const round = (v) => Math.round(v * 10) / 10;
  function flush() {
    frame = 0;
    for (const [type, acc] of [['pointer', move], ['scroll', scroll]]) {
      const dx = round(acc.x), dy = round(acc.y);
      if (!dx && !dy) continue;
      send({ type, dx, dy });
      acc.x -= dx; acc.y -= dy;
    }
  }
  const reset = () => {
    pointers.clear(); gesture = null;
    move = { x: 0, y: 0 }; scroll = { x: 0, y: 0 };
  };
  pad.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    pad.setPointerCapture(e.pointerId);
    if (pointers.size === 0) gesture = { start: performance.now(), moved: 0, maxPointers: 0 };
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    gesture.maxPointers = Math.max(gesture.maxPointers, pointers.size);
  });
  pad.addEventListener('pointermove', (e) => {
    const p = pointers.get(e.pointerId);
    if (!p || !gesture) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    p.x = e.clientX; p.y = e.clientY;
    if (!dx && !dy) return;
    gesture.moved += Math.hypot(dx, dy);
    if (pointers.size === 1) { move.x += dx; move.y += dy; }
    else { scroll.x += dx / pointers.size; scroll.y += dy / pointers.size; }
    if (!frame) frame = requestAnimationFrame(flush);
  });
  pad.addEventListener('pointerup', (e) => {
    if (!pointers.delete(e.pointerId) || pointers.size > 0 || !gesture) return;
    const g = gesture; gesture = null;
    if (performance.now() - g.start < 250 && g.moved < 10) {
      send({ type: 'click', button: g.maxPointers >= 2 ? 'right' : 'left' });
      if (navigator.vibrate) navigator.vibrate(5);
    }
  });
  pad.addEventListener('pointercancel', reset);
  $('mode-toggle').addEventListener('click', () => setMode($('trackpad').hidden ? 'trackpad' : 'dpad'));
  setMode(storedMode() === 'trackpad' ? 'trackpad' : 'dpad');
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
bindButtons(); bindKeyboard(); bindTrackpad(); bindPairing(); connect();
