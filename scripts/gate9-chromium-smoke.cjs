const puppeteer = require('puppeteer-core');
const { execSync } = require('node:child_process');

const BASE = 'https://kdkmp-development.vercel.app';
const LOGIN = `${BASE}/api/internal/browser-smoke-login?key=D6cq2n-XQFZUpW2TR9nMeJWCePLyLb7vQCvLQXr45rFsMHa1SWn-z7yl5wIPoBV1`;
const results = [];

function record(id, pass, detail) {
  results.push({ id, pass: Boolean(pass), detail });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${id}: ${detail}`);
}

async function visible(page, selector) {
  return page.$eval(selector, (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0 && r.width > 0 && r.height > 0;
  }).catch(() => false);
}

async function login(page) {
  await page.goto(LOGIN, { waitUntil: 'networkidle2', timeout: 60000 });
  await page.waitForFunction(() => location.pathname.startsWith('/dashboard'), { timeout: 30000 });
  const ok = await page.evaluate(() => location.pathname.startsWith('/dashboard') && !document.querySelector('.login-page'));
  if (!ok) throw new Error(`Browser session bridge did not reach dashboard: ${page.url()}`);
}

async function main() {
  const chrome = execSync('command -v google-chrome || command -v chromium || command -v chromium-browser', { encoding: 'utf8', shell: '/bin/bash' }).trim();
  console.log(`Chromium executable: ${chrome}`);
  const browser = await puppeteer.launch({
    executablePath: chrome,
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });

  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(15000);
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await login(page);

    const sidebarVisible = await visible(page, '.sidebar');
    record('UAT-9000-auth-shell', sidebarVisible, `authenticated dashboard=${page.url()}, desktop sidebar visible=${sidebarVisible}`);

    // UAT-9001 — keyboard navigation + visible focus treatment.
    await page.evaluate(() => {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      document.body.tabIndex = -1;
      document.body.focus();
    });
    let focusEvidence = null;
    for (let i = 0; i < 16; i += 1) {
      await page.keyboard.press('Tab');
      const ev = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        const outlineWidth = Number.parseFloat(s.outlineWidth || '0') || 0;
        const hasOutline = s.outlineStyle !== 'none' && outlineWidth > 0;
        const hasShadow = s.boxShadow && s.boxShadow !== 'none';
        const isVisible = r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
        return {
          tag: el.tagName,
          text: (el.textContent || '').trim().slice(0, 60),
          href: el.getAttribute('href'),
          outline: `${s.outlineStyle} ${s.outlineWidth}`,
          boxShadow: s.boxShadow,
          visible: isVisible,
          indicator: isVisible && (hasOutline || hasShadow),
        };
      });
      if (ev?.indicator) { focusEvidence = ev; break; }
    }
    record('UAT-9001', Boolean(focusEvidence), focusEvidence ? `focus indicator on ${focusEvidence.tag} ${focusEvidence.href || focusEvidence.text}: outline=${focusEvidence.outline}, shadow=${focusEvidence.boxShadow}` : 'no visible focus indicator found after 16 Tab presses');

    // UAT-9002 — pressed feedback on desktop navigation.
    const navHandle = await page.$('.sidebar .nav-link:not(.disabled)');
    let pressedPass = false;
    let pressedDetail = 'no desktop navigation link found';
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
        await new Promise((r) => setTimeout(r, 80));
        const during = await readStyle();
        await page.mouse.up();
        pressedPass = ['backgroundColor', 'transform', 'filter', 'opacity', 'color'].some((k) => before[k] !== during[k]);
        pressedDetail = `before=${JSON.stringify(before)} during-active=${JSON.stringify(during)}`;
      }
    }
    record('UAT-9002', pressedPass, pressedDetail);

    // UAT-9004 — prove loading UI on a genuinely non-prefetched client transition.
    const routePage = await browser.newPage();
    routePage.setDefaultTimeout(15000);
    await routePage.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await routePage.setCacheEnabled(false);
    let transitionStarted = false;
    await routePage.setRequestInterception(true);
    routePage.on('request', (request) => {
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
    });
    await login(routePage);
    const target = await routePage.$('.sidebar a.nav-link[href="/dashboard/accounting"]');
    let loadingSeen = false;
    let targetHref = null;
    if (target) {
      targetHref = await target.evaluate((el) => el.getAttribute('href'));
      const loadingPromise = routePage.waitForSelector('.loading-shell[role="status"], [role="status"][aria-label="Memuat halaman"]', { visible: true, timeout: 8000 }).then(() => true).catch(() => false);
      transitionStarted = true;
      await target.click();
      loadingSeen = await loadingPromise;
      await routePage.waitForFunction((href) => location.pathname === href, { timeout: 20000 }, targetHref).catch(() => {});
    }
    record('UAT-9004', loadingSeen, `prefetch blocked, target=${targetHref}, loading status observed=${loadingSeen}, final=${routePage.url()}`);
    await routePage.close();

    // UAT-9005 — prefers-reduced-motion suppresses meaningful loading animation.
    await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'reduce' }]);
    await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2', timeout: 60000 });
    const reduced = await page.evaluate(() => {
      const probe = document.createElement('div');
      probe.className = 'loading-card';
      document.body.appendChild(probe);
      const p = getComputedStyle(probe, '::after');
      const duration = p.animationDuration;
      const name = p.animationName;
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

    // UAT-9003 — mobile navigation, touch target, touch-action, and one physical tap => one route change.
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
    await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2', timeout: 60000 });
    const mobile = await page.evaluate(() => {
      const isVisible = (el) => {
        if (!el) return false;
        const s = getComputedStyle(el); const r = el.getBoundingClientRect();
        return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0;
      };
      const trigger = document.querySelector('.mobile-menu-trigger');
      const tr = trigger?.getBoundingClientRect();
      const ts = trigger ? getComputedStyle(trigger) : null;
      return {
        width: innerWidth,
        docWidth: document.documentElement.scrollWidth,
        sidebarVisible: isVisible(document.querySelector('.sidebar')),
        mobileBarVisible: isVisible(document.querySelector('.mobile-bar')),
        triggerVisible: isVisible(trigger),
        triggerHeight: tr?.height || 0,
        triggerWidth: tr?.width || 0,
        touchAction: ts?.touchAction || '',
      };
    });
    let mobileTapChangedRoute = false;
    let mobileClickCount = 0;
    let mobileHref = null;
    let menuOpen = false;
    if (mobile.triggerVisible) {
      await page.tap('.mobile-menu-trigger').catch(() => {});
      menuOpen = await page.$eval('.mobile-menu', (el) => Boolean(el.open)).catch(() => false);
      const links = await page.$$('.mobile-menu-panel a.nav-link:not(.disabled)');
      for (const link of links) {
        const candidate = await link.evaluate((el) => {
          const s = getComputedStyle(el); const r = el.getBoundingClientRect();
          return { href: el.getAttribute('href'), visible: s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0 };
        }).catch(() => null);
        if (!candidate?.visible || !candidate.href || candidate.href === '/dashboard') continue;
        mobileHref = candidate.href;
        await link.evaluate((el) => {
          el.scrollIntoView({ block: 'center', inline: 'center' });
          window.__uatMobileClicks = 0;
          el.addEventListener('click', () => { window.__uatMobileClicks += 1; }, true);
        });
        const box = await link.boundingBox();
        if (!box) continue;
        await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
        mobileTapChangedRoute = await page.waitForFunction((h) => location.pathname === h, { timeout: 15000 }, mobileHref).then(() => true).catch(() => false);
        mobileClickCount = await page.evaluate(() => window.__uatMobileClicks || 0).catch(() => 0);
        break;
      }
    }
    const mobilePass = mobile.mobileBarVisible && !mobile.sidebarVisible && mobile.triggerVisible && mobile.triggerHeight >= 44 && mobile.docWidth <= mobile.width + 2 && mobile.touchAction === 'manipulation' && menuOpen && mobileTapChangedRoute && mobileClickCount === 1;
    record('UAT-9003', mobilePass, `${JSON.stringify(mobile)}, menuOpen=${menuOpen}, href=${mobileHref}, one-touch clickCount=${mobileClickCount}, route change=${mobileTapChangedRoute}`);

    // UAT-9006 — find a table-heavy permitted page and assert page containment + local horizontal scroller.
    const candidates = ['/dashboard/accounting', '/dashboard/procurement', '/dashboard/inventory', '/dashboard/audit'];
    let tableEvidence = null;
    for (const route of candidates) {
      await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle2', timeout: 60000 });
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
          localScroller: ['auto', 'scroll'].includes(s.overflowX) && wrap.scrollWidth >= wrap.clientWidth,
          pageContained: document.documentElement.scrollWidth <= innerWidth + 2,
        };
      });
      if (tableEvidence) break;
    }
    const tablePass = Boolean(tableEvidence?.localScroller && tableEvidence?.pageContained);
    record('UAT-9006', tablePass, tableEvidence ? JSON.stringify(tableEvidence) : 'no .data-table-wrap found on accounting/procurement/inventory/audit routes');

    const failed = results.filter((r) => !r.pass);
    console.log(`GATE9_RESULT_JSON=${JSON.stringify({ chromium: await browser.version(), results, failed: failed.map((x) => x.id) })}`);
    if (failed.length) process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
