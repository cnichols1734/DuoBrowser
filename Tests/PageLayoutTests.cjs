// Real CSS layout tests. All requests are fulfilled with synthetic HTML; no live YouTube traffic.
async function runPageLayoutTests(page, source) {
    const p = await page.context().newPage();
    const results = [];
    let fixture = '';
    await p.setViewportSize({ width: 466, height: 678 });
    await p.route('**/*', route => route.fulfill({ contentType: 'text/html', body: fixture }));
    function assert(value, message) { if (!value) throw new Error(message); }
    async function setup({ host = 'm.youtube.com', padding = '0 84px 0 0', headerPadding = padding,
        extraCSS = '', headerTag = 'ytm-mobile-topbar-renderer', contents = true } = {}) {
        fixture = `<!doctype html><style>*{box-sizing:border-box}body{margin:0;padding:${padding}}
            ytm-app{display:block}ytm-header,ytm-mobile-topbar-renderer{position:fixed;left:0;top:0;width:100%;height:48px;padding:${headerPadding}}
            article{height:1500px}input{width:100px}${extraCSS}</style>
            ${contents ? `<ytm-app><${headerTag}><button>Search</button></${headerTag}><article><input value="kept"><a href="/next">Next</a></article></ytm-app>` : ''}`;
        await p.goto(`https://${host}/fixture`);
        await p.evaluate(() => {
            window.testInsets = { left: 0, right: 84 };
            window.testScale = 1;
            const original = window.getComputedStyle;
            window.getComputedStyle = function(element) {
                const css = original.call(window, element);
                if (element.tagName !== 'DUO-SAFE-AREA-PROBE') return css;
                // Chromium's desktop safe-area env is zero; substitute only the measured probe.
                return new Proxy(css, { get(target, key) {
                    if (key === 'paddingRight') return `${window.testInsets.right}px`;
                    if (key === 'paddingLeft') return `${window.testInsets.left}px`;
                    return Reflect.get(target, key, target);
                }});
            };
            Object.defineProperty(window.visualViewport, 'scale', { get: () => window.testScale });
        });
        await p.evaluate(source);
    }
    const update = value => p.evaluate(value => globalThis.__duoPageLayout?.update(value), value);
    const measure = () => p.evaluate(() => ({
        app: document.querySelector('ytm-app')?.getBoundingClientRect().width,
        padding: getComputedStyle(document.body).paddingRight,
        left: getComputedStyle(document.body).paddingLeft,
        header: getComputedStyle(document.querySelector('ytm-mobile-topbar-renderer,ytm-header')).paddingRight,
        state: globalThis.__duoPageLayout?.inspect().state,
        styles: document.querySelectorAll('style').length
    }));
    async function test(name, run) { await run(); results.push(name); }
    try {
        await test('feed expands to full width; header protection is unchanged', async () => {
            await setup(); const result = await update(true); const m = await measure();
            assert(result.reclaimed === 84 && m.app === 466 && m.header === '84px', JSON.stringify(m));
        });
        await test('legacy header is supported', async () => {
            await setup({ headerTag: 'ytm-header' }); await update(true);
            assert((await measure()).app === 466, 'legacy header');
        });
        await test('restore preserves newer author styles and removes owned DOM', async () => {
            await setup(); await update(true);
            await p.evaluate(() => { document.body.style.paddingRight = '100px'; });
            await update(false); const m = await measure();
            assert(m.padding === '100px' && m.styles === 1, JSON.stringify(m));
            assert(await p.locator('duo-safe-area-probe').count() === 0, 'probe leaked');
        });
        await test('ordinary site spacing is retained', async () => {
            await setup({ padding: '0 100px 0 0' }); await update(true);
            assert((await measure()).padding === '100px', 'removed ordinary padding');
        });
        await test('unprotected header falls back', async () => {
            await setup({ headerPadding: '0' }); await update(true);
            assert((await measure()).app === 382, 'unsafe header widened');
        });
        await test('nonresponsive feed rolls back', async () => {
            await setup({ extraCSS: 'ytm-app{max-width:382px}' }); await update(true);
            const m = await measure(); assert(m.padding === '84px' && m.state === 'fallback', JSON.stringify(m));
        });
        await test('same safe-area pattern works on an unrelated origin', async () => {
            await setup({ host: 'example.com' }); await update(true);
            assert((await measure()).app === 466, 'host-specific behavior');
        });
        await test('subframes receive no adapter', async () => {
            await setup();
            await p.evaluate(() => { const frame = document.createElement('iframe'); frame.srcdoc = '<p>Frame</p>'; document.body.appendChild(frame); });
            const handle = await p.locator('iframe').elementHandle();
            const frame = await handle.contentFrame(); await frame.evaluate(source);
            assert(await frame.evaluate(() => typeof globalThis.__duoPageLayout) === 'undefined', 'subframe gate');
        });
        await test('contenteditable defers reflow', async () => {
            await setup();
            await p.evaluate(() => { const editor = document.createElement('div'); editor.setAttribute('contenteditable', ''); editor.textContent = 'Kept'; document.body.appendChild(editor); editor.focus(); });
            await update(true); assert((await measure()).app === 382, 'reflow during contenteditable');
        });
        await test('disabling cancels pending observer work', async () => {
            await setup(); await update(true);
            await p.evaluate(() => document.body.classList.add('changed')); await update(false);
            await p.waitForTimeout(350); assert((await measure()).app === 382, 'reapplied after disabled');
        });
        await test('late app insertion is handled', async () => {
            await setup({ contents: false }); await update(true);
            await p.evaluate(() => { document.body.innerHTML = '<ytm-app><ytm-mobile-topbar-renderer>Header</ytm-mobile-topbar-renderer><article>Feed</article></ytm-app>'; });
            await p.waitForFunction(() => globalThis.__duoPageLayout.inspect().state === 'fitted');
            assert((await measure()).app === 466, 'late app');
        });
        await test('SPA header replacement revalidates and restores unsafe layout', async () => {
            await setup(); await update(true);
            await p.evaluate(() => {
                const header = document.createElement('ytm-mobile-topbar-renderer'); header.style.padding = '0';
                document.querySelector('ytm-mobile-topbar-renderer').replaceWith(header);
            });
            await p.waitForFunction(() => globalThis.__duoPageLayout.inspect().state === 'unsupported');
            assert((await measure()).app === 382, 'replacement not revalidated');
        });
        await test('typing defers reflow and preserves input value', async () => {
            await setup(); await p.locator('input').focus(); await update(true);
            assert((await measure()).app === 382, 'reflow while editing');
            await p.locator('input').blur();
            await p.waitForFunction(() => globalThis.__duoPageLayout.inspect().state === 'fitted');
            assert(await p.locator('input').inputValue() === 'kept', 'lost form');
        });
        await test('pinch zoom defers adaptation until normal scale', async () => {
            await setup(); await p.evaluate(() => { window.testScale = 2; }); await update(true);
            assert((await measure()).app === 382, 'reflow while pinching');
            await p.evaluate(() => { window.testScale = 1; visualViewport.dispatchEvent(new Event('resize')); });
            await p.waitForFunction(() => globalThis.__duoPageLayout.inspect().state === 'fitted');
        });
        await test('side changes use current geometry', async () => {
            await setup({ padding: '0 0 0 60px', headerPadding: '0 0 0 60px' });
            await p.evaluate(() => { window.testInsets = { left:60, right:0 }; });
            await update(true); const m = await measure(); assert(m.app === 466 && m.left === '0px', JSON.stringify(m));
            await p.evaluate(() => { window.testInsets = { left:0, right:0 }; window.dispatchEvent(new Event('resize')); });
            await p.waitForFunction(() => globalThis.__duoPageLayout.inspect().state === 'no-side-inset');
            assert((await measure()).left === '60px', 'pose did not restore');
        });
        await test('no ongoing DOM mutation loop after layout settles', async () => {
            await setup(); await update(true); await p.waitForTimeout(350);
            await p.evaluate(() => { window.mutations = 0; new MutationObserver(records => { window.mutations += records.length; }).observe(document.documentElement, { subtree:true, childList:true, attributes:true, characterData:true }); });
            await p.waitForTimeout(600); assert(await p.evaluate(() => window.mutations) === 0, 'mutation loop');
            assert((await measure()).styles === 2, 'duplicate styles');
        });
        await test('ordinary header and wrapper elements work without site selectors', async () => {
            await setup({ padding:'0', headerTag:'header', extraCSS:'header{position:fixed;left:0;top:0;width:100%;height:48px;padding-right:84px}' });
            await p.evaluate(() => {
                const app = document.querySelector('ytm-app');
                const container = document.createElement('section'); container.style.paddingRight = '84px';
                while (app.firstChild) container.appendChild(app.firstChild);
                app.replaceWith(container);
            });
            const result = await update(true); assert(result.after === 466, JSON.stringify(result));
            await update(false);
            assert(await p.locator('section').evaluate(e => getComputedStyle(e).paddingRight) === '84px', 'wrapper not restored');
        });
        await test('ordinary non-safe-area websites stay unchanged', async () => {
            await setup({ host:'news.example', padding:'0', extraCSS:'article{max-width:320px;margin:auto}' });
            await update(true); assert((await measure()).styles === 1, 'changed ordinary article');
            assert(await p.locator('article').evaluate(e => e.getBoundingClientRect().width) === 320, 'max width lost');
        });
        await test('transformed pages are left alone', async () => {
            await setup({ extraCSS:'body{transform:translateX(1px)}' }); await update(true);
            assert((await measure()).app === 382, 'changed transformed page');
        });
        await test('header child movement rolls back even when outer header stays still', async () => {
            await setup({ extraCSS:'ytm-mobile-topbar-renderer button{position:relative;left:10cqw}body{container-type:inline-size}' });
            await update(true); const m = await measure();
            assert(m.app === 382 && m.state === 'fallback', JSON.stringify(m));
        });
        await test('new horizontal overflow rolls back', async () => {
            await setup({ extraCSS:'article{container-type:inline-size}article:after{content:"";display:block;width:120cqw;height:1px}' });
            await update(true); assert((await measure()).app === 382, 'overflow committed');
        });
        await test('multiple root wrappers are not guessed between', async () => {
            await setup({ padding:'0', extraCSS:'section{padding-right:84px}main{height:200px}' });
            await p.evaluate(() => { document.querySelector('ytm-app').innerHTML += '<section><main></main></section><section><main></main></section>'; });
            const result = await update(true); assert(result.state === 'unsupported', JSON.stringify(result));
        });
        await test('header scan budget causes a conservative fallback', async () => {
            await setup();
            await p.evaluate(() => { document.querySelector('ytm-mobile-topbar-renderer').innerHTML = '<span></span>'.repeat(100); });
            await update(true); assert((await measure()).state === 'scan-limit', 'scan budget not enforced');
        });
        await test('header action remains clickable and form data is unchanged', async () => {
            await setup();
            await p.evaluate(() => { window.clicked = 0; document.querySelector('button').onclick = () => window.clicked++; });
            await update(true); await p.locator('button').click();
            assert(await p.evaluate(() => window.clicked) === 1, 'header action failed');
            assert(await p.locator('input').inputValue() === 'kept', 'input changed');
        });
        await test('gutter fitting waits for touch and momentum to stop', async () => {
            await setup();
            await p.evaluate(() => dispatchEvent(new Event('touchstart')));
            await update(true); await p.waitForTimeout(400);
            assert((await measure()).app === 382, 'gutter reflowed under a held finger');
            await p.evaluate(() => {
                const event = new Event('touchend'); Object.defineProperty(event, 'touches', {value:[]}); dispatchEvent(event);
            });
            for (let i = 0; i < 5; i++) {
                await p.evaluate(() => dispatchEvent(new Event('scroll'))); await p.waitForTimeout(90);
            }
            assert((await measure()).app === 382, 'gutter reflowed during momentum');
            await p.waitForTimeout(500);
            assert((await measure()).app === 466, 'gutter did not fit after settling');
        });
        return { passed: results.length, tests: results };
    } finally { await p.close(); }
}

if (typeof module !== 'undefined') {
    module.exports = runPageLayoutTests;
    if (require.main === module) {
        const fs = require('node:fs');
        const path = require('node:path');
        (async () => {
            const browser = await require('playwright').chromium.launch({ headless: true });
            try {
                const page = await browser.newPage();
                const source = fs.readFileSync(path.join(__dirname, '../DuoBrowser/PageLayout.js'), 'utf8');
                console.log(await runPageLayoutTests(page, source));
            } finally { await browser.close(); }
        })().catch(error => { console.error(error); process.exitCode = 1; });
    }
}
