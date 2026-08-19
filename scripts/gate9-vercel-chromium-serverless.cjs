const puppeteer = require('puppeteer-core');
const chromium = require('@sparticuz/chromium');

const BASE = 'https://kdkmp-development.vercel.app';
const LOGIN = `${BASE}/api/internal/browser-smoke-login?key=GW4E0-EiyZ3nxcaPIUYnijY2cTvmLuyqfuGVinSnvAyz3omLbQFwNl7Qqp914rUM`;
const results = [];

function record(id, pass, detail) {
  const row = { id, pass: Boolean(pass), detail };
  results.push(row);
  console.log(`${row.pass ? 'PASS' : 'FAIL'} ${id}: ${detail}`);
}

async function visible(page, selector) {
  return page.$eval(selector, (el) => {
    const s = getComputedStyle(el); const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0 && r.width > 0 && r.height > 0;
  }).catch(() => false);
}

async function login(page) {
  await page.goto(LOGIN, { waitUntil: 'networkidle2', timeout: 90000 });
  await page.waitForFunction(() => location.pathname.startsWith('/dashboard') && !document.querySelector('.login-page'), { timeout: 30000 });
}

async function main() {
  chromium.setGraphicsMode = false;
  const executablePath = await chromium.executablePath();
  const browser = await puppeteer.launch({
    executablePath,
    args: chromium.args,
    defaultViewport: chromium.defaultViewport,
    headless: 'shell',
  });

  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(20000);
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await login(page);
    record('UAT-9000-auth-shell', await visible(page, '.sidebar'), `authenticated=${page.url()}`);

    await page.evaluate(() => { document.body.tabIndex = -1; document.body.focus(); });
    let focus = null;
    for (let i = 0; i < 24; i++) {
      await page.keyboard.press('Tab');
      focus = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        const s = getComputedStyle(el); const r = el.getBoundingClientRect();
        const ow = Number.parseFloat(s.outlineWidth || '0') || 0;
        const indicator = r.width > 0 && r.height > 0 && ((s.outlineStyle !== 'none' && ow > 0) || (s.boxShadow && s.boxShadow !== 'none'));
        return { tag: el.tagName, href: el.getAttribute('href'), text: (el.textContent || '').trim().slice(0, 40), outline: `${s.outlineStyle} ${s.outlineWidth}`, shadow: s.boxShadow, indicator };
      });
      if (focus?.indicator) break;
    }
    record('UAT-9001', Boolean(focus?.indicator), JSON.stringify(focus));

    const nav = await page.$('.sidebar a.nav-link:not(.disabled):not([href="/dashboard"])');
    let pressed = false; let pressedDetail = 'no link';
    if (nav) {
      const box = await nav.boundingBox();
      if (box) {
        const style = () => nav.evaluate((el) => { const s = getComputedStyle(el); return { bg:s.backgroundColor, transform:s.transform, opacity:s.opacity, color:s.color, filter:s.filter }; });
        const before = await style();
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await page.mouse.down(); await new Promise((r) => setTimeout(r, 100));
        const during = await style(); await page.mouse.up();
        pressed = Object.keys(before).some((k) => before[k] !== during[k]);
        pressedDetail = `${JSON.stringify(before)} -> ${JSON.stringify(during)}`;
      }
    }
    record('UAT-9002', pressed, pressedDetail);

    const routePage = await browser.newPage();
    await routePage.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await routePage.setCacheEnabled(false);
    await login(routePage);
    await routePage.setRequestInterception(true);
    let transition = false;
    routePage.on('request', (request) => {
      try {
        const u = new URL(request.url()); const h = request.headers();
        const acct = u.origin === BASE && u.pathname === '/dashboard/accounting';
        const prefetch = h['next-router-prefetch'] === '1' || h.purpose === 'prefetch' || String(h['sec-purpose'] || '').includes('prefetch');
        if (acct && prefetch && !transition) return request.abort().catch(() => {});
        if (acct && transition) return setTimeout(() => request.continue().catch(() => {}), 1800);
      } catch {}
      request.continue().catch(() => {});
    });
    const target = await routePage.$('.sidebar a.nav-link[href="/dashboard/accounting"]');
    let loading = false; let arrived = false;
    if (target) {
      const loadingPromise = routePage.waitForSelector('.loading-shell[role="status"], [role="status"][aria-label="Memuat halaman"], [aria-busy="true"]', { visible:true, timeout:10000 }).then(() => true).catch(() => false);
      transition = true; await target.click(); loading = await loadingPromise;
      arrived = await routePage.waitForFunction(() => location.pathname === '/dashboard/accounting', { timeout:25000 }).then(() => true).catch(() => false);
    }
    record('UAT-9004', loading && arrived, `loading=${loading}, arrived=${arrived}, url=${routePage.url()}`);
    await routePage.close();

    await page.emulateMediaFeatures([{ name:'prefers-reduced-motion', value:'reduce' }]);
    await page.goto(`${BASE}/dashboard`, { waitUntil:'networkidle2', timeout:90000 });
    const reduced = await page.evaluate(() => {
      const probe = document.createElement('div'); probe.className='loading-card'; document.body.appendChild(probe);
      const s = getComputedStyle(probe,'::after');
      const vals = String(s.animationDuration).split(',').map((v) => v.trim());
      const max = vals.reduce((m,v) => Math.max(m, v.endsWith('ms') ? parseFloat(v)/1000 : (v.endsWith('s') ? parseFloat(v) : 0)),0);
      const out = { media:matchMedia('(prefers-reduced-motion: reduce)').matches, name:s.animationName, duration:s.animationDuration, seconds:max };
      probe.remove(); return out;
    });
    record('UAT-9005', reduced.media && (reduced.name === 'none' || reduced.seconds <= 0.02), JSON.stringify(reduced));
    await page.emulateMediaFeatures([]);

    let tapEvents = 0;
    await page.exposeFunction('__uatTapObserved', () => { tapEvents += 1; });
    await page.setViewport({ width:390, height:844, deviceScaleFactor:1, isMobile:true, hasTouch:true });
    await page.goto(`${BASE}/dashboard`, { waitUntil:'networkidle2', timeout:90000 });
    const mobile = await page.evaluate(() => {
      const vis=(el)=>{ if(!el)return false; const s=getComputedStyle(el),r=el.getBoundingClientRect(); return s.display!=='none'&&s.visibility!=='hidden'&&r.width>0&&r.height>0; };
      const t=document.querySelector('.mobile-menu-trigger'), r=t?.getBoundingClientRect(), s=t?getComputedStyle(t):null;
      return { width:innerWidth, docWidth:document.documentElement.scrollWidth, sidebar:vis(document.querySelector('.sidebar')), bar:vis(document.querySelector('.mobile-bar')), trigger:vis(t), h:r?.height||0, w:r?.width||0, touch:s?.touchAction||'' };
    });
    let menuOpen=false, href=null, routeChanged=false;
    if (mobile.trigger) {
      await page.tap('.mobile-menu-trigger');
      menuOpen = await page.$eval('.mobile-menu',(el)=>Boolean(el.open)).catch(()=>false);
      const links = await page.$$('.mobile-menu-panel a.mobile-nav-link:not(.disabled)');
      for (const link of links) {
        const c = await link.evaluate((el)=>{ const s=getComputedStyle(el),r=el.getBoundingClientRect(); return { href:el.getAttribute('href'), visible:s.display!=='none'&&s.visibility!=='hidden'&&r.width>0&&r.height>0 }; }).catch(()=>null);
        if (!c?.visible || !c.href || c.href === '/dashboard') continue;
        href=c.href;
        await link.evaluate((el)=>{ el.scrollIntoView({block:'center'}); el.addEventListener('click',()=>window.__uatTapObserved(),{capture:true}); });
        const box=await link.boundingBox(); if(!box) continue;
        await page.touchscreen.tap(box.x+box.width/2,box.y+box.height/2);
        routeChanged = await page.waitForFunction((h)=>location.pathname===h,{timeout:20000},href).then(()=>true).catch(()=>false);
        break;
      }
    }
    const mobilePass = mobile.bar && !mobile.sidebar && mobile.trigger && mobile.h >= 44 && mobile.docWidth <= mobile.width + 2 && mobile.touch === 'manipulation' && menuOpen && routeChanged && tapEvents === 1;
    record('UAT-9003', mobilePass, `${JSON.stringify(mobile)}, menuOpen=${menuOpen}, href=${href}, tapEvents=${tapEvents}, routeChanged=${routeChanged}`);

    const routes=['/dashboard/accounting','/dashboard/procurement','/dashboard/inventory','/dashboard/audit'];
    let table=null;
    for (const r of routes) {
      await page.goto(`${BASE}${r}`, {waitUntil:'networkidle2',timeout:90000});
      table=await page.evaluate(()=>{ const w=document.querySelector('.data-table-wrap'); if(!w)return null; const s=getComputedStyle(w); return { path:location.pathname, viewport:innerWidth, documentWidth:document.documentElement.scrollWidth, client:w.clientWidth, scroll:w.scrollWidth, overflowX:s.overflowX, local:['auto','scroll'].includes(s.overflowX), contained:document.documentElement.scrollWidth<=innerWidth+2 }; });
      if(table) break;
    }
    record('UAT-9006', Boolean(table?.local && table?.contained), table ? JSON.stringify(table) : 'no table wrapper found');

    const failed=results.filter((r)=>!r.pass);
    console.log(`GATE9_RESULT_JSON=${JSON.stringify({ chromium:await browser.version(), results, failed:failed.map((r)=>r.id) })}`);
    if(failed.length) process.exitCode=1;
  } finally { await browser.close(); }
}
main().catch((e)=>{ console.error('GATE9_FATAL',e?.stack||e); process.exit(1); });
