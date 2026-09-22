// Saleo Design – Animationen (Vanilla JS, keine Abhängigkeiten)
(function () {
  'use strict';
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Bild-Fallback: fehlende Fotos als ruhige Creme-Fläche
  document.querySelectorAll('img').forEach(function (img) {
    img.addEventListener('error', function () {
      img.classList.add('img-error');
      if (img.parentElement) img.parentElement.classList.add('img-frame-error');
    });
  });

  // Sanftes Einblenden beim Scrollen
  var reveals = document.querySelectorAll('.reveal');
  if (reduced || !('IntersectionObserver' in window)) {
    reveals.forEach(function (el) { el.classList.add('sichtbar'); });
  } else {
    var batch = 0;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        var el = e.target;
        el.style.transitionDelay = ((batch % 6) * 90) + 'ms';
        el.classList.add('sichtbar');
        io.unobserve(el);
        batch++;
        setTimeout(function () { batch = Math.max(0, batch - 1); }, 400);
      });
    }, { threshold: 0.12 });
    reveals.forEach(function (el) { io.observe(el); });
  }

  if (reduced) return;

  // Sanftes Scrollen per Mausrad (Touch und Tastatur bleiben nativ)
  var target = window.scrollY, current = window.scrollY, raf = null;
  function maxScroll() { return document.documentElement.scrollHeight - window.innerHeight; }
  function tick() {
    if (Math.abs(window.scrollY - current) > 2) { current = window.scrollY; target = Math.max(0, Math.min(maxScroll(), target)); }
    current += (target - current) * 0.1;
    if (Math.abs(target - current) < 0.5) { current = target; window.scrollTo(0, current); raf = null; return; }
    window.scrollTo(0, current);
    raf = requestAnimationFrame(tick);
  }
  window.addEventListener('wheel', function (e) {
    if (e.ctrlKey) return;
    e.preventDefault();
    target = Math.max(0, Math.min(maxScroll(), target + e.deltaY));
    if (!raf) raf = requestAnimationFrame(tick);
  }, { passive: false });
  window.addEventListener('scroll', function () {
    if (raf) return;
    target = window.scrollY; current = window.scrollY;
  }, { passive: true });

  // Ankerlinks nutzen das sanfte Scrollen
  document.querySelectorAll('a[href^="#"]').forEach(function (a) {
    a.addEventListener('click', function (e) {
      var ziel = document.querySelector(a.getAttribute('href'));
      if (!ziel) return;
      e.preventDefault();
      target = ziel.getBoundingClientRect().top + window.scrollY - 24;
      if (!raf) raf = requestAnimationFrame(tick);
      history.pushState(null, '', a.getAttribute('href'));
    });
  });

  // Fotokarten weichen dem Cursor sanft aus
  var cards = Array.prototype.slice.call(document.querySelectorAll('.karte'));
  var moveRaf = null;
  if (cards.length) {
    window.addEventListener('mousemove', function (e) {
      if (moveRaf) return;
      moveRaf = requestAnimationFrame(function () {
        moveRaf = null;
        cards.forEach(function (card) {
          var r = card.getBoundingClientRect();
          var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
          var dx = cx - e.clientX, dy = cy - e.clientY;
          var d = Math.hypot(dx, dy), radius = 170;
          if (d < radius && d > 0.01) {
            var f = ((radius - d) / radius) * 46;
            card.style.translate = (dx / d * f) + 'px ' + (dy / d * f) + 'px';
          } else if (card.style.translate) {
            card.style.translate = '';
          }
        });
      });
    }, { passive: true });
  }

  // Bildwechsler mit weichen Überblendungen
  var slides = Array.prototype.slice.call(document.querySelectorAll('.slide-innen img'));
  if (slides.length > 1) {
    Promise.all(slides.map(function (img) {
      return img.decode ? img.decode().catch(function () {}) : Promise.resolve();
    })).then(function () {
      var idx = 0;
      setInterval(function () {
        slides[idx].classList.remove('aktiv');
        idx = (idx + 1) % slides.length;
        slides[idx].classList.add('aktiv');
      }, 2200);
    });
  }
})();
