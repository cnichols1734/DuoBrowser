module.exports = async function(page, source) {
    let passed = 0;
    const assert = (value, label) => { if (!value) throw new Error(label); passed++; };
    // Same-document links exercise real default activation without leaving the fixture.
    await page.setContent('<a id="link" href="#reddit">Reddit</a><button>Elsewhere</button>');
    await page.evaluate(source);
    const consume = url => page.evaluate(url => globalThis.__duoRedditTap.consume(url), url);
    const url = await page.locator('a').evaluate(a => a.href);
    await page.evaluate(() => document.querySelector('a').click());
    assert(!await consume(url), 'programmatic click must not authorize handoff');
    await page.locator('a').click();
    assert(await consume(url), 'real pointer click authorizes exact destination');
    assert(!await consume(url), 'authorization is one-use');
    await page.locator('a').click();
    assert(!await consume('https://reddit.com/r/other/'), 'destination substitution is rejected');
    assert(!await consume(url), 'mismatched request consumes authorization');
    await page.locator('a').click();
    await page.waitForTimeout(1600);
    assert(!await consume(url), 'expired gesture is rejected');
    await page.locator('a').click();
    await page.locator('button').click();
    assert(!await consume(url), 'unrelated click clears previous gesture');
    await page.locator('a').focus();
    await page.keyboard.press('Enter');
    assert(await consume(url), 'keyboard activation is supported');
    await page.locator('a').click();
    await page.evaluate(() => document.querySelector('a').click());
    assert(!await consume(url), 'scripted click cannot reuse a preceding real gesture');
    await page.evaluate(() => window.addEventListener('click', event => {
        // A hostile page can intercept events before they reach document listeners.
        if (!event.isTrusted) event.stopImmediatePropagation();
    }, true));
    await page.locator('a').click();
    assert(await consume(url), 'trusted click is recorded before page window capture handlers');
    await page.locator('a').click();
    await page.evaluate(() => document.querySelector('a').click());
    assert(!await consume(url), 'window capture interruption cannot preserve a stale real-tap token');
    await page.evaluate(() => document.addEventListener('click', event => event.preventDefault(), { once: true }));
    await page.locator('a').click();
    await page.evaluate(url => {
        const detached = document.createElement('a');
        detached.href = url;
        detached.click();
    }, url);
    assert(!await consume(url), 'canceled tap cannot authorize a detached scripted anchor');
    await page.locator('a').evaluate(a => a.download = 'download');
    await page.locator('a').click();
    assert(!await consume(url), 'download links are excluded');
    return { passed };
};
