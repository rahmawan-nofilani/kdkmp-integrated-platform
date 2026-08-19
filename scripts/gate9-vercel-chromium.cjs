const puppeteer = require('puppeteer');

const BASE = 'https://kdkmp-development.vercel.app';
const LOGIN = `${BASE}/api/internal/browser-smoke-login?key=GW4E0-EiyZ3nxcaPIUYnijY2cTvmLuyqfuGVinSnvAyz3omLbQFwNl7Qqp914rUM`;
const results = [];

function record(id, pass, detail) {
  const row = { id, pass: Boolean(pass), detail };
  results.push(row);
  console.log(`${row.pass ? 'PASS' : 'FAIL'} ${id}: ${detail}`);
}

async function isVisible(page, selector) {
  return page.$eval(selector, (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0 && r.width > 0 && r.height > 0;
  }).catch(() => false);
}

async function login(page) {
  await page.goto(LOGIN, { waitUntil: 'networkidle2', timeout: 90000 });
  await page.waitForFunction(() => location.pathname.startsWith('/dashboard'), { timeout: 30000 });
  const ok = await page.evaluate(() => location.pathname.startsWith('/dashboard') && !document.querySelector('.login-page'));
  if (!ok) throw new Error(`Browser session bridge did not reach dashboard: ${page.url()}`);
}

async function main() {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });

  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(20000);
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await login(page);

    const sidebarVisible = await isVisible(page, '.sidebar');
    record('UAT-9000-auth-shell', sidebarVisible, `authenticated dashboard=${page.url()}, desktop sidebar visible=${sidebarVisible}`);

    // UAT-9001 — keyboard navigation + visible focus treatment.
    await page.evaluate(() => {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      document.body.tabIndex = -1;
      document.body.focus();
    });
    let focusEvidence = null;
    for (let i = 0; i < 24; i += 1) {
      await page.keyboard.press('Tab');
      const ev = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        const outlineWidth = Number.parseFloat(s.outlineWidth || '0') || 0;
        const hasOutline = s.outlineStyle !== 'none' && outlineWidth > 0;
        const hasShadow = Boolean(s.boxShadow && s.boxShadow !== 'none');
        const visible = r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
        return {
          tag: el.tagName,
          text: (el.textContent || '').trim().slice(0, 60),
          href: el.getAttribute('href'),
          outline: `${s.outlineStyle} ${s.outlineWidth}`,
          boxShadow: s.boxShadow,
          visible,
          indicator: visible && (hasOutline || hasShadow),
        };
      });
      if (ev?.indicator) { focusEvidence = ev; break; }
    }
    record('UAT-9001', Boolean(focusEvidence), focusEvidence ? `visible focus on ${focusEvidence.tag} ${focusEvidence.href || focusEvidence.text}; outline=${focusEvidence.outline}; shadow=${focusEvidence.boxShadow}` : 'no visible focus indicator found after 24 Tab presses');

    // UAT-9002 — pressed feedback on an enabled desktop navigation link.
    const navHandle = await page.$('.sidebar a.nav-link:not(.disabled):not([href="/dashboard"])');
    let pressedPass = false;
    let pressedDetail = 'no enabled desktop navigation link found';
    if (navHandle) {
      const box = await navHandle.boundingBox();
      if (box) {
        const readStyle = async () => navHandle.evaluate((el) => {
          const s = getComputedStyle(el);
          return { backgroundColor: s.backgroundColor, transform: s.transform, filter: s.filter, opacity: s.opacity, color: s.color };
        });
        const before = await readStyle();
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await page.mouse.down();
        await new Promise((resolve) => setTimeout(resolve, 100));
        const during = await readStyle();
        await page.mouse.up();
        pressedPass = ['backgroundColor', 'transform', 'filter', 'opacity', 'color'].some((key) => before[key] !== during[key]);
        pressedDetail = `before=${JSON.stringify(before)} during-active=${JSON.stringify(during)}`;
      }
    }
    record('UAT-9002', pressedPass, pressedDetail);

    // UAT-9004 — loading feedback during a deliberately slowed non-prefetched client transition.
    const routePage = await browser.newPage();
    routePage.setDefaultTimeout(20000);
    await routePage.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await routePage.setCacheEnabled(false);
    let transitionStarted = false;
    await routePage.setRequestInterception(true);
    routePage.on('request', (request) => {
      try {
        const headers = request.headers();
        const url = new URL(request.url());
        const isAccounting = url.origin === BASE && url.pathname === '/dashboard/accounting';
        const isPrefetch = headers['next-router-prefetch'] === '1' || headers.purpose === 'prefetch' || String(headers['sec-purpose'] || '').includes('prefetch');
        if (isAccounting && isPrefetch && !transitionStarted) {
          request.abort().catch(() => {});
          return;
        }
        if (isAccounting && transitionStarted) {
          setTimeout(() => request.continue().catch(() => {}), 1800);
          return;
        }
        request.continue().catch(() => {});
      } catch {
        request.continue().catch(() => {});
      }
    });
    await login(routePage);
    const accountingTarget = await routePage.$('.sidebar a.nav-link[href="/dashboard/accounting"]');
    let loadingSeen = false;
    let finalAccounting = false;
    if (accountingTarget) {
      const loadingPromise = routePage.waitForSelector('.loading-shell[role="status"], [role="status"][aria-label="Memuat halaman"], [aria-busy="true"]', { visible: true, timeout: 10000 }).then(() => true).catch(() => false);
      transitionStarted = true;
      await accountingTarget.click();
      loadingSeen = await loadingPromise;
      finalAccounting = await routePage.waitForFunction(() => location.pathname === '/dashboard/accounting', { timeout: 25000 }).then(() => true).catch(() => false);
    }
    record('UAT-9004', loadingSeen && finalAccounting, `loading observed=${loadingSeen}, final accounting route=${finalAccounting}, url=${routePage.url()}`);
    await routePage.close();

    // UAT-9005 — reduced motion suppresses meaningful loading animation.
    await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'reduce' }]);
    await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2', timeout: 90000 });
    const reduced = await page.evaluate(() => {
      const probe = document.createElement('div');
      probe.className = 'loading-card';
      document.body.appendChild(probe);
      const pseudo = getComputedStyle(probe, '::after');
      const duration = pseudo.animationDuration;
      const name = pseudo.animationName;
      const transition = getComputedStyle(document.querySelector('.nav-link') || probe).transitionDuration;
      probe.remove();
      const seconds = (value) => value.split(',').map((v) => v.trim()).reduce((max, v) => {
        if (v.endsWith('ms')) return Math.max(max, Number.parseFloat(v) / 1000);
        if (v.endsWith('s')) return Math.max(max, Number.parseFloat(v));
        return max;
      }, 0);
      return {
        media: matchMedia('(prefers-reduced-motion: reduce)').matches,
        animationName: name,
        animationDuration: duration,
        transitionDuration: transition,
        animationSeconds: seconds(duration),
      };
    });
    const reducedPass = reduced.media && (reduced.animationName === 'none' || reduced.animationSeconds <= 0.02);
    record('UAT-9005', reducedPass, JSON.stringify(reduced));
    await page.emulateMediaFeatures([]);

    // UAT-9003 — mobile nav/touch target + one physical tap => exactly one observed click and route change.
    let mobileTapEvents = 0;
    await page.exposeFunction('__uatTapObserved', () => { mobileTapEvents += 1; });
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
    await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2', timeout: 90000 });
    const mobile = await page.evaluate(() => {
      const visible = (el) => {
        if (!el) return false;
        const s = getComputedStyle(el); const r = el.getBoundingClientRect();
        return s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0 && r.width > 0 && r.height > 0;
      };
      const trigger = document.querySelector('.mobile-menu-trigger');
      const tr = trigger?.getBoundingClientRect();
      const ts = trigger ? getComputedStyle(trigger) : null;
      return {
        width: innerWidth,
        docWidth: document.documentElement.scrollWidth,
        sidebarVisible: visible(document.querySelector('.sidebar')),
        mobileBarVisible: visible(document.querySelector('.mobile-bar')),
        triggerVisible: visible(trigger),
        triggerHeight: tr?.height || 0,
        triggerWidth: tr?.width || 0,
        touchAction: ts?.touchAction || '',
      };
    });
    let menuOpen = false;
    let mobileHref = null;
    let mobileTapChangedRoute = false;
    if (mobile.triggerVisible) {
      await page.tap('.mobile-menu-trigger');
      menuOpen = await page.$eval('.mobile-menu', (el) => Boolean(el.open)).catch(() => false);
      const links = await page.$$('.mobile-menu-panel a.mobile-nav-link:not(.disabled)');
      for (const link of links) {
        const candidate = await link.evaluate((el) => {
          const s = getComputedStyle(el); const r = el.getBoundingClientRect();
          return { href: el.getAttribute('href'), visible: s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0 };
        }).catch(() => null);
        if (!candidate?.visible || !candidate.href || candidate.href === '/dashboard') continue;
        mobileHref = candidate.href;
        await link.evaluate((el) => {
          el.scrollIntoView({ block: 'center', inline: 'center' });
          el.addEventListener('click', () => window.__uatTapObserved(), { capture: true });
        });
        const box = await link.boundingBox();
        if (!box) continue;
        await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
        mobileTapChangedRoute = await page.waitForFunction((href) => location.pathname === href, { timeout: 20000 }, mobileHref).then(() => true).catch(() => false);
        break;
      }
    }
    const mobilePass = mobile.mobileBarVisible && !mobile.sidebarVisible && mobile.triggerVisible && mobile.triggerHeight >= 44 && mobile.docWidth <= mobile.width + 2 && mobile.touchAction === 'manipulation' && menuOpen && mobileTapChangedRoute && mobileTapEvents === 1;
    record('UAT-9003', mobilePass, `${JSON.stringify(mobile)}, menuOpen=${menuOpen}, href=${mobileHref}, node-side tapEvents=${mobileTapEvents}, routeChange=${mobileTapChangedRoute}`);

    // UAT-9006 — table containment on mobile.
    const tableCandidates = ['/dashboard/accounting', '/dashboard/procurement', '/dashboard/inventory', '/dashboard/audit'];
    let tableEvidence = null;
    for (const route of tableCandidates) {
      await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle2', timeout: 90000 });
      tableEvidence = await page.evaluate(() => {
        const wrap = document.querySelector('.data-table-wrap');
        if (!wrap) return null;
        const s = getComputedStyle(wrap);
        return {
          path: location.pathname,
          viewport: innerWidth,
          documentWidth: document.documentElement.scrollWidth,
          wrapClientWidth: wrap.clientWidth,
          wrapScrollWidth: wrap.scrollWidth,
          overflowX: s.overflowX,
          localScroller: ['auto', 'scroll'].includes(s.overflowX),
          pageContained: document.documentElement.scrollWidth <= innerWidth + 2,
        };
      });
      if (tableEvidence) break;
    }
    const tablePass = Boolean(tableEvidence?.localScroller && tableEvidence?.pageContained);
    record('UAT-9006', tablePass, tableEvidence ? JSON.stringify(tableEvidence) : 'no .data-table-wrap found on permitted table-heavy routes');

    const failed = results.filter((row) => !row.pass);
    console.log(`GATE9_RESULT_JSON=${JSON.stringify({ chromium: await browser.version(), results, failed: failed.map((row) => row.id) })}`);
    if (failed.length) process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error('GATE9_FATAL', error && error.stack ? error.stack : error);
  process.exit(1);
});
