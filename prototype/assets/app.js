/* Prototype behaviour only — no backend. Replace with app.js when ported. */
(function () {
  'use strict';

  /* ---------- Theme (dark default, remembered) ---------- */
  var THEME_KEY = 'cctv-proto-theme';
  var root = document.documentElement;

  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    document.querySelectorAll('[data-theme-toggle]').forEach(function (btn) {
      btn.setAttribute('aria-label', theme === 'dark' ? 'Aktifkan mode terang' : 'Aktifkan mode gelap');
      btn.setAttribute('aria-pressed', String(theme === 'light'));
    });
  }

  var saved = null;
  try { saved = localStorage.getItem(THEME_KEY); } catch (e) {}
  applyTheme(saved || 'dark');

  document.addEventListener('click', function (event) {
    var toggle = event.target.closest('[data-theme-toggle]');
    if (toggle) {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      applyTheme(next);
      try { localStorage.setItem(THEME_KEY, next); } catch (e) {}
      return;
    }

    /* ---------- Grid presets ---------- */
    var preset = event.target.closest('[data-cols-set]');
    if (preset) {
      var wall = document.querySelector('.wall');
      if (!wall) return;
      wall.setAttribute('data-cols', preset.getAttribute('data-cols-set'));
      document.querySelectorAll('[data-cols-set]').forEach(function (b) {
        b.setAttribute('aria-pressed', String(b === preset));
      });
      return;
    }

    /* ---------- Camera filter chips ---------- */
    var chip = event.target.closest('[data-filter]');
    if (chip) {
      var filter = chip.getAttribute('data-filter');
      document.querySelectorAll('[data-filter]').forEach(function (b) {
        b.setAttribute('aria-pressed', String(b === chip));
      });
      document.querySelectorAll('[data-state]').forEach(function (el) {
        if (el.classList.contains('camitem') || el.classList.contains('tile')) {
          var visible = filter === 'all' || el.getAttribute('data-state') === filter;
          el.hidden = !visible;
        }
      });
      return;
    }

    /* ---------- Camera search ---------- */
    var search = event.target.closest('[data-cam-search]');
    if (search) return;

    /* ---------- Expand tile (Enter/Space also works) ---------- */
    var tile = event.target.closest('.tile');
    if (tile && !event.target.closest('.tile__btn')) {
      var isExpanded = tile.getAttribute('data-expanded') === 'true';
      document.querySelectorAll('.tile[data-expanded="true"]').forEach(function (t) {
        t.setAttribute('data-expanded', 'false');
        t.setAttribute('aria-expanded', 'false');
      });
      if (!isExpanded) {
        tile.setAttribute('data-expanded', 'true');
        tile.setAttribute('aria-expanded', 'true');
      }
      return;
    }

    /* ---------- Admin sidebar collapse ---------- */
    var collapse = event.target.closest('[data-collapse]');
    if (collapse) {
      var shell = document.querySelector('.shell');
      var next = shell.getAttribute('data-collapsed') !== 'true';
      shell.setAttribute('data-collapsed', String(next));
      collapse.setAttribute('aria-pressed', String(next));
      return;
    }
  });

  /* ---------- Keyboard: tiles and camlist are operable without a mouse ---------- */
  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    var tile = event.target.closest && event.target.closest('.tile, .camitem');
    if (!tile) return;
    event.preventDefault();
    tile.click();
  });

  /* ---------- Camera search filter ---------- */
  document.addEventListener('input', function (event) {
    var input = event.target.closest('[data-cam-search]');
    if (!input) return;
    var q = input.value.trim().toLowerCase();
    document.querySelectorAll('.camitem').forEach(function (item) {
      var haystack = (item.getAttribute('data-name') || item.textContent).toLowerCase();
      item.hidden = q !== '' && haystack.indexOf(q) === -1;
    });
  });

  /* ---------- Clocks (mono, tabular) ---------- */
  function tick() {
    var now = new Date();
    var hh = String(now.getHours()).padStart(2, '0');
    var mm = String(now.getMinutes()).padStart(2, '0');
    var ss = String(now.getSeconds()).padStart(2, '0');
    document.querySelectorAll('[data-clock]').forEach(function (el) { el.textContent = hh + ':' + mm + ':' + ss; });
    document.querySelectorAll('[data-datetime]').forEach(function (el) {
      el.textContent = now.toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' });
    });
  }
  tick();
  setInterval(tick, 1000);

  /* ---------- Password visibility (login) ---------- */
  document.addEventListener('click', function (event) {
    var btn = event.target.closest('[data-toggle-pass]');
    if (!btn) return;
    var input = document.getElementById(btn.getAttribute('data-toggle-pass'));
    if (!input) return;
    var show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    btn.setAttribute('aria-pressed', String(show));
    btn.setAttribute('aria-label', show ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi');
  });

  /* ---------- Inline validation demo (login) ---------- */
  var form = document.querySelector('[data-demo-form]');
  if (form) {
    form.addEventListener('submit', function (event) {
      event.preventDefault();
      var summary = document.getElementById('form-summary');
      var invalid = 0;
      form.querySelectorAll('.input[required]').forEach(function (input) {
        var wrap = document.getElementById(input.id + '-error');
        var bad = input.value.trim() === '';
        if (wrap) wrap.hidden = !bad;
        input.setAttribute('aria-invalid', String(bad));
        if (bad) invalid += 1;
      });
      if (summary) {
        summary.hidden = invalid === 0;
        if (invalid > 0) {
          summary.textContent = invalid + ' kolom belum diisi. Periksa kolom yang ditandai.';
          var firstBad = form.querySelector('.input[aria-invalid="true"]');
          if (firstBad) firstBad.focus();
        }
      }
    });
  }
})();
