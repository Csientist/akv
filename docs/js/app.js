    function showPage(id) {
    document.querySelectorAll('.page').forEach(p => {
      p.classList.remove('active');
      p.style.opacity = '';
      p.style.transform = '';
    });
    const page = document.getElementById('page-' + id);
    page.classList.add('active');

    // Desktop nav active state
    document.querySelectorAll('.nav-links a').forEach(a => a.classList.remove('active'));
    const el = document.getElementById('nav-' + id);
    if (el) el.classList.add('active');

    // Drawer active state
    document.querySelectorAll('.nav-drawer a').forEach(a => a.classList.remove('active'));
    const del = document.getElementById('drawer-' + id);
    if (del) del.classList.add('active');

    window.scrollTo({ top: 0, behavior: 'instant' });

    // Reset then re-observe animations on new page
    requestAnimationFrame(() => {
      initScrollAnimations();
      initSectionLabels();
    });
    return false;
  }

  function scrollDoc(id, linkEl) {
    if (linkEl) {
      const sidebar = linkEl.closest('.docs-sidebar');
      if (sidebar) sidebar.querySelectorAll('.sidebar-link').forEach(l => l.classList.remove('active'));
      linkEl.classList.add('active');
    }
    const el = document.getElementById(id);
    if (el) setTimeout(() => el.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50);
    return false;
  }

  function toggleDrawer() {
    const drawer = document.getElementById('nav-drawer');
    const btn = document.getElementById('hamburger');
    const isOpen = drawer.classList.contains('open');
    if (isOpen) {
      closeDrawer();
    } else {
      drawer.style.display = 'flex';
      // Force reflow so transition fires
      drawer.offsetHeight;
      drawer.classList.add('open');
      btn.classList.add('open');
      document.body.style.overflow = 'hidden';
    }
  }

  function closeDrawer() {
    const drawer = document.getElementById('nav-drawer');
    const btn = document.getElementById('hamburger');
    drawer.classList.remove('open');
    btn.classList.remove('open');
    document.body.style.overflow = '';
    setTimeout(() => { if (!drawer.classList.contains('open')) drawer.style.display = ''; }, 280);
  }

  document.addEventListener('click', function(e) {
    const drawer = document.getElementById('nav-drawer');
    const btn = document.getElementById('hamburger');
    if (drawer.classList.contains('open') && !drawer.contains(e.target) && !btn.contains(e.target)) {
      closeDrawer();
    }
  });

  // ── Scroll animation observer ──
  function initScrollAnimations() {
    const targets = document.querySelectorAll(
      '.page.active .fade-up, .page.active .release, .page.active .arch-card, .page.active .callout'
    );
    const obs = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.classList.add('visible');
          obs.unobserve(e.target);
        }
      });
    }, { threshold: 0.08, rootMargin: '0px 0px -40px 0px' });
    targets.forEach(el => obs.observe(el));
  }

  // ── Section label line animation ──
  function initSectionLabels() {
    const labels = document.querySelectorAll('.page.active .section-label');
    const obs = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.classList.add('line-visible');
          obs.unobserve(e.target);
        }
      });
    }, { threshold: 0.5 });
    labels.forEach(l => obs.observe(l));
  }

  // ── Nav scroll shadow ──
  window.addEventListener('scroll', () => {
    const nav = document.querySelector('nav');
    nav.style.boxShadow = window.scrollY > 10
      ? '0 2px 24px rgba(0,0,0,.35)'
      : 'none';
  }, { passive: true });

  document.addEventListener('DOMContentLoaded', () => {
    initScrollAnimations();
    initSectionLabels();
  });
