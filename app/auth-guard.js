// ═══════════════════════════════════════════════════════════════════
// auth-guard.js — Guardián de sesión Damu SGC
// Inyectado en el <head> de TODAS las páginas protegidas en app/
// Requiere: supabase-js CDN debe cargarse ANTES que este script
// ═══════════════════════════════════════════════════════════════════
(function () {
  'use strict';

  var SUPABASE_URL      = 'https://iaqvcpxselfjwbstcnma.supabase.co';
  var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlhcXZjcHhzZWxmandic3Rjbm1hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyOTkwODgsImV4cCI6MjA5Njg3NTA4OH0.EzadAJxFjKdru0xpy6YGhIRc-Lk1_QroLSAM0fKdJM0';

  // 1 — Ocultar inmediatamente: evita flash de contenido protegido
  document.documentElement.style.visibility = 'hidden';

  // 2 — Inicializar cliente Supabase (expuesto globalmente)
  var _sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  window.__damuSupabase = _sb;

  // 3 — Cierre de sesión (llamado por el botón "Salir" del nav)
  window.__damuSignOut = async function () {
    // scope:'local' limpia solo esta sesión/dispositivo sin revocar las de otros dispositivos.
    // signOut() sin scope usa 'global' por defecto en Supabase JS v2 ≥2.47 e invalida
    // todos los tokens del usuario en el servidor, cerrando sesión en todos los equipos.
    try { await _sb.auth.signOut({ scope: 'local' }); } catch (e) {}
    ['damu_role', 'damu_perfil', 'damu_session',
     'damu_empresa_id', 'damu_empresa_nombre', 'damu_codigo_invitacion']
      .forEach(function (k) { localStorage.removeItem(k); });
    window.location.href = '../index.html';
  };

  // 4 — Verificar sesión activa en Supabase
  _sb.auth.getSession().then(function (result) {
    var session = result && result.data && result.data.session;

    if (!session) {
      // Sin sesión válida → redirigir al portal de login
      window.location.replace('../auth/portal.html');
      return;
    }

    // Sesión válida: el rol elegido en el login (localStorage) tiene prioridad
    // sobre el metadata del signup, para soportar usuarios con doble perfil.
    var user   = session.user;
    var meta   = (user && user.user_metadata) ? user.user_metadata : {};
    var perfil = localStorage.getItem('damu_role')
              || localStorage.getItem('damu_perfil')
              || meta.role
              || meta.perfil
              || 'productor';

    // Persistir perfil y datos de sesión
    localStorage.setItem('damu_role',   perfil);
    localStorage.setItem('damu_perfil', perfil);
    localStorage.setItem('damu_session', JSON.stringify({
      email: user.email, userId: user.id, perfil: perfil, ts: Date.now()
    }));

    window.__damuPerfil = perfil;
    window.__damuUser   = user;

    _renderizar(perfil, user);

  }).catch(function () {
    // Error de red: usar sesión guardada en localStorage como fallback
    var localSess = JSON.parse(localStorage.getItem('damu_session') || 'null');
    if (!localSess) {
      window.location.replace('../auth/portal.html');
      return;
    }
    var perfil = localStorage.getItem('damu_role') || localStorage.getItem('damu_perfil') || 'productor';
    window.__damuPerfil = perfil;
    window.__damuUser   = { email: localSess.email || '' };
    _renderizar(perfil, window.__damuUser);
  });

  // ── Montar el nav privado y mostrar la página ────────────────────
  function _renderizar(perfil, user) {
    function montar() {
      var el = document.getElementById('app-nav');
      if (el) el.outerHTML = _construirNav(perfil, user);
      document.documentElement.style.visibility = 'visible';
    }
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', montar);
    } else {
      montar();
    }
  }

  // ── Constructor del menú privado dinámico ────────────────────────
  function _construirNav(perfil, user) {
    var path       = window.location.pathname;
    var email      = (user && user.email) ? user.email : '';
    var emailCorto = email.length > 24 ? email.slice(0, 24) + '…' : email;

    function esActivo(archivo) {
      return path.indexOf(archivo) !== -1;
    }

    function enlace(archivo, icono, etiqueta) {
      var cls = esActivo(archivo)
        ? 'flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-semibold no-underline text-emerald-400 bg-slate-700/60'
        : 'flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm no-underline text-slate-300 hover:text-white hover:bg-slate-700 transition-colors';
      return '<a href="' + archivo + '" class="' + cls + '">' + icono + ' ' + etiqueta + '</a>';
    }

    // ── Ítems del menú desplegable "Herramientas" ───────────────
    var clsDropBase = 'flex items-center gap-2 px-4 py-2.5 text-sm no-underline transition-colors ';
    function dropItem(archivo, icono, etiqueta) {
      var cls = clsDropBase + (esActivo(archivo)
        ? 'text-emerald-400 bg-slate-700/60 font-semibold'
        : 'text-slate-300 hover:text-white hover:bg-slate-700/80');
      return '<a href="' + archivo + '" class="' + cls + '">' + icono + ' ' + etiqueta + '</a>';
    }

    // Mapa de Ruta aparece para ambos roles; Escanear QR solo para transportista
    var itemsDrop = dropItem('simulador-ruta.html', '🗺️', 'Mapa de Ruta');
    if (perfil !== 'productor') {
      itemsDrop += dropItem('escaner-qr.html', '📷', 'Escanear QR');
    }

    var hayHerramientaActiva = esActivo('simulador-ruta.html') || esActivo('escaner-qr.html');
    var clsDropBtn = 'flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm border-0 cursor-pointer transition-colors '
      + (hayHerramientaActiva
          ? 'text-emerald-400 bg-slate-700/60 font-semibold'
          : 'bg-transparent text-slate-300 hover:text-white hover:bg-slate-700');

    // Dropdown "Herramientas": onmouseenter/leave en el div padre para
    // que la transición de botón → panel no dispare el cierre prematuramente
    var dropdown =
      '<div class="relative flex-shrink-0"'
      + ' onmouseenter="this.lastElementChild.classList.remove(\'hidden\')"'
      + ' onmouseleave="this.lastElementChild.classList.add(\'hidden\')">'
        + '<button type="button" class="' + clsDropBtn + '">'
          + '🛠️ Herramientas'
          + '<svg class="w-3 h-3 ml-0.5 opacity-60" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">'
            + '<path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/>'
          + '</svg>'
        + '</button>'
        + '<div class="hidden absolute top-full left-0 mt-1 w-52 bg-slate-800 border border-slate-700/80 rounded-xl shadow-2xl z-[200] py-1 overflow-hidden">'
          + itemsDrop
        + '</div>'
      + '</div>';

    // ── Nav final según perfil ────────────────────────────────────
    var enlaces = '';
    if (perfil === 'productor') {
      // Productora: Calculadora REP + Dashboard REP + dropdown Herramientas
      enlaces = enlace('calculadora-rep.html', '🧾', 'Calculadora REP') + enlace('dashboard-productor.html', '📊', 'Dashboard REP') + dropdown;
    } else {
      // Transportista: Dashboard KPI + dropdown Herramientas (Mapa de Ruta + Escanear QR)
      enlaces = enlace('dashboard-kpi.html', '📊', 'Dashboard KPI') + dropdown;
    }

    // ── Badge de perfil ──────────────────────────────────────────
    var badge = perfil === 'productor'
      ? '<span class="hidden sm:inline-flex items-center gap-1 text-xs bg-emerald-900/50 border border-emerald-700/60 text-emerald-300 px-2.5 py-1 rounded-full font-semibold">🏭 Productora</span>'
      : '<span class="hidden sm:inline-flex items-center gap-1 text-xs bg-blue-900/50 border border-blue-700/60 text-blue-300 px-2.5 py-1 rounded-full font-semibold">🚚 Transportista</span>';

    return (
      '<nav class="bg-slate-900 sticky top-0 z-50 flex items-center justify-between px-6 md:px-8 h-16 shadow-xl gap-4">' +

        // Logo
        '<a href="../index.html" class="flex items-center gap-3 no-underline flex-shrink-0">' +
          '<div class="w-9 h-9 rounded-full bg-emerald-600 flex items-center justify-center font-black text-white text-lg">D</div>' +
          '<div class="hidden md:block leading-tight">' +
            '<span class="text-white font-bold text-base leading-none block">Damu SGC</span>' +
            '<span class="text-emerald-400 text-xs leading-none">Plataforma privada</span>' +
          '</div>' +
        '</a>' +

        // Herramientas del perfil (centro)
        '<div class="flex items-center gap-1 flex-1 justify-center">' +
          enlaces +
        '</div>' +

        // Usuario + botón Salir (derecha)
        '<div class="flex items-center gap-2 flex-shrink-0">' +
          badge +
          '<span class="hidden lg:block text-xs text-slate-400 max-w-[150px] truncate">' + emailCorto + '</span>' +
          '<button onclick="__damuSignOut()" ' +
            'class="flex items-center gap-1.5 text-xs font-semibold bg-red-900/30 hover:bg-red-800/50 border border-red-800/50 text-red-400 hover:text-red-300 px-3 py-1.5 rounded-lg transition-colors cursor-pointer">' +
            '<svg class="w-3.5 h-3.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">' +
              '<path stroke-linecap="round" stroke-linejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/>' +
            '</svg>' +
            'Salir' +
          '</button>' +
        '</div>' +

      '</nav>'
    );
  }

})();
