// Hand-authored compatibility rule, isolated from page JavaScript by WKContentWorld.
// It touches only mobile YouTube's body padding. The site's independently inset header stays intact.
(() => {
    if (location.hostname !== 'm.youtube.com' || window !== window.top) return;
    let enabled = false;
    let timer = null;
    let style = null;
    let probe = null;
    let observedBody = null;
    let observedApp = null;
    let observedHeader = null;
    let failureCount = 0;
    let stopped = false;
    let lastResult = { state: 'original' };
    const rootObserver = new MutationObserver(schedule);
    const sizeObserver = new ResizeObserver(schedule);
    const finite = value => Number.isFinite(value) ? value : 0;
    const px = value => finite(parseFloat(value));
    const near = (a, b) => Math.abs(a - b) <= 1;

    function removeRule() {
        if (style) { style.remove(); style = null; }
    }

    function safeInsets() {
        if (!probe?.isConnected) {
            probe = document.createElement('duo-safe-area-probe');
            probe.setAttribute('aria-hidden', 'true');
            probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;width:0;height:0;overflow:hidden;' +
                'padding-left:env(safe-area-inset-left, 0px);padding-right:env(safe-area-inset-right, 0px);';
            document.documentElement.appendChild(probe);
        }
        const css = getComputedStyle(probe);
        return { left: px(css.paddingLeft), right: px(css.paddingRight) };
    }

    function observe(app, header) {
        if (observedBody === document.body && observedApp === app && observedHeader === header) return;
        rootObserver.disconnect();
        sizeObserver.disconnect();
        observedBody = document.body;
        observedApp = app;
        observedHeader = header;
        if (document.body) rootObserver.observe(document.body, { attributes: true, attributeFilter: ['class', 'style'], childList: true });
        if (app) {
            rootObserver.observe(app, { childList: true });
            sizeObserver.observe(app);
        }
        if (header) {
            rootObserver.observe(header, { attributes: true, attributeFilter: ['class', 'style'], childList: true });
            sizeObserver.observe(header);
        }
    }

    function schedule() {
        if (!enabled || stopped || timer !== null) return;
        // Coalesce SPA replacements and resizes; no whole-page scans or per-scroll work.
        timer = setTimeout(() => { timer = null; apply(); }, 120);
    }

    function apply() {
        if (!enabled || stopped || location.hostname !== 'm.youtube.com') {
            removeRule();
            lastResult = { state: 'original' };
            return;
        }
        // Do not reflow while an input is focused, pinching, or playing fullscreen video.
        const active = document.activeElement;
        if (active?.matches('input,textarea') || active?.isContentEditable ||
            Math.abs((window.visualViewport?.scale || 1) - 1) > 0.01 || document.fullscreenElement) return;
        const body = document.body, app = document.querySelector('ytm-app'), header = document.querySelector('ytm-mobile-topbar-renderer') || document.querySelector('ytm-header');
        observe(app, header);
        if (!body || !app || !header) { removeRule(); lastResult = { state: 'unsupported' }; return; }
        const safe = safeInsets();
        if (safe.left + safe.right < 1) { removeRule(); lastResult = { state: 'no-side-inset' }; return; }
        if (style?.sheet) style.sheet.disabled = true;
        const bodyCSS = getComputedStyle(body), headerCSS = getComputedStyle(header);
        const original = { left: px(bodyCSS.paddingLeft), right: px(bodyCSS.paddingRight) };
        const bodyRect = body.getBoundingClientRect(), appRect = app.getBoundingClientRect();
        const viewport = document.documentElement.clientWidth;
        // Only remove a verified safe-area-only gutter, never ordinary site spacing/max-width.
        const left = safe.left > 0 && near(original.left, safe.left) ? safe.left : 0;
        const right = safe.right > 0 && near(original.right, safe.right) ? safe.right : 0;
        const headerProtected = (!left || px(headerCSS.paddingLeft) >= left - 1) &&
            (!right || px(headerCSS.paddingRight) >= right - 1);
        const recognized = left + right > 0 && headerProtected &&
            ['fixed', 'sticky'].includes(headerCSS.position) &&
            bodyCSS.transform === 'none' && getComputedStyle(app).transform === 'none' &&
            near(bodyRect.width, viewport) && near(appRect.width + original.left + original.right, viewport);
        if (!recognized) { removeRule(); lastResult = { state: 'unsupported' }; return; }

        const previousHeader = header.getBoundingClientRect();
        const headerPadding = [headerCSS.paddingLeft, headerCSS.paddingRight];
        if (!style?.isConnected) {
            style = document.createElement('style');
            (document.head || document.documentElement).appendChild(style);
        }
        const rule = `body { ${left ? 'padding-left:0px!important;' : ''}${right ? 'padding-right:0px!important;' : ''} }`;
        if (style.textContent !== rule) style.textContent = rule;
        if (style.sheet) style.sheet.disabled = false;
        const fitted = app.getBoundingClientRect(), fittedHeader = header.getBoundingClientRect();
        const fittedHeaderCSS = getComputedStyle(header);
        const valid = near(fitted.width, appRect.width + left + right) &&
            fitted.left >= -1 && fitted.right <= viewport + 1 &&
            near(fittedHeader.x, previousHeader.x) && near(fittedHeader.width, previousHeader.width) &&
            fittedHeaderCSS.paddingLeft === headerPadding[0] && fittedHeaderCSS.paddingRight === headerPadding[1];
        if (!valid) {
            removeRule();
            failureCount += 1;
            stopped = failureCount >= 3;
            lastResult = { state: 'fallback' };
            return;
        }
        lastResult = { state: 'fitted', viewport, before: appRect.width, after: fitted.width, reclaimed: left + right };
    }

    function update(value) {
        enabled = value === true;
        stopped = false;
        failureCount = 0;
        if (timer !== null) { clearTimeout(timer); timer = null; }
        if (!enabled) {
            rootObserver.disconnect(); sizeObserver.disconnect();
            observedBody = null; observedApp = null; observedHeader = null;
            removeRule(); probe?.remove(); probe = null;
            lastResult = { state: 'original' };
        } else { apply(); }
        return lastResult;
    }

    addEventListener('resize', schedule, { passive: true });
    addEventListener('pageshow', schedule);
    document.addEventListener('focusout', schedule);
    document.addEventListener('fullscreenchange', schedule);
    window.visualViewport?.addEventListener('resize', schedule, { passive: true });
    // Read-only numeric diagnostics; there is no page-to-native message handler.
    globalThis.__duoYouTubeLayout = { update, inspect: () => lastResult };
})();
