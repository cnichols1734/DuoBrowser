// Fixed layout operations, isolated from page JavaScript by WKContentWorld.
// No host names, site selectors, page text, model output, or native message bridge.
(() => {
    if (window !== window.top || !['http:', 'https:', 'file:'].includes(location.protocol)) return;
    let enabled = false, timer = null, style = null, probe = null, target = null;
    let watched = [], failures = 0, stopped = false;
    let touching = false, lastScroll = -Infinity;
    let lastResult = { state: 'original' };
    const marker = `data-duo-fit-${Math.random().toString(36).slice(2)}`;
    const mutationObserver = new MutationObserver(schedule);
    const sizeObserver = new ResizeObserver(schedule);
    const px = value => Number.isFinite(parseFloat(value)) ? parseFloat(value) : 0;
    const near = (a, b) => Math.abs(a - b) <= 1;
    const rect = element => element.getBoundingClientRect();
    const unchanged = (a, b) => near(a.x, b.x) && near(a.y, b.y) && near(a.width, b.width) && near(a.height, b.height);
    const untransformed = css => css.transform === 'none' && css.translate === 'none' &&
        css.rotate === 'none' && css.scale === 'none' && (css.zoom === 'normal' || near(px(css.zoom), 1));

    function removeRule() {
        style?.remove(); style = null;
        if (target?.getAttribute(marker) === '1') target.removeAttribute(marker);
        target = null;
    }

    function safeInsets() {
        if (!probe?.isConnected) {
            probe = document.createElement('duo-safe-area-probe');
            probe.setAttribute('aria-hidden', 'true');
            probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;width:0;height:0;overflow:hidden;' +
                'padding-left:env(safe-area-inset-left,0px);padding-right:env(safe-area-inset-right,0px);';
            document.documentElement.appendChild(probe);
        }
        const css = getComputedStyle(probe);
        return { left: px(css.paddingLeft), right: px(css.paddingRight) };
    }

    // Inspect only a bounded portion of the structural tree. Never traverse the whole feed.
    function structure(body) {
        const queue = [{ element: body, depth: 0 }], found = [];
        for (let index = 0; index < queue.length && index < 160; index++) {
            const item = queue[index], element = item.element;
            if (!(element instanceof HTMLElement) || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(element.tagName)) continue;
            const css = getComputedStyle(element);
            if (css.display === 'none' || css.visibility === 'hidden') continue;
            found.push({ ...item, css, box: rect(element) });
            if (item.depth < 4) {
                for (const child of element.children) {
                    if (queue.length >= 160) break;
                    queue.push({ element: child, depth: item.depth + 1 });
                }
            }
        }
        return found;
    }

    function observe(elements) {
        const next = [...new Set(elements.filter(Boolean))];
        if (next.length === watched.length && next.every((element, i) => element === watched[i])) return;
        mutationObserver.disconnect(); sizeObserver.disconnect(); watched = next;
        for (const element of watched) {
            // Our marker is deliberately excluded, preventing an observer feedback loop.
            mutationObserver.observe(element, { attributes: true, attributeFilter: ['class', 'style'], childList: true });
            sizeObserver.observe(element);
        }
    }

    function schedule() {
        if (!enabled || stopped || timer !== null) return;
        timer = setTimeout(() => { timer = null; apply(); }, 160);
    }

    function fallback(state, failed = false) {
        removeRule();
        if (failed) { failures++; stopped = failures >= 3; }
        lastResult = { state };
    }

    function candidate(item, safe, viewport) {
        const { element, css, box, depth } = item;
        if (depth > 2 || !near(box.x, 0) || !near(box.width, viewport) || !untransformed(css) ||
            ['fixed', 'absolute', 'sticky'].includes(css.position) ||
            px(css.borderLeftWidth) + px(css.borderRightWidth) > 0 ||
            px(css.marginLeft) + px(css.marginRight) !== 0) return null;
        // A numeric match alone is insufficient: both protected header and responsive content must validate below.
        const padding = { left: px(css.paddingLeft), right: px(css.paddingRight) };
        const left = safe.left > 1 && near(padding.left, safe.left) ? padding.left : 0;
        const right = safe.right > 1 && near(padding.right, safe.right) ? padding.right : 0;
        if (left + right === 0) return null;
        const available = viewport - padding.left - padding.right;
        const children = Array.from(element.children).slice(0, 32).filter(child => {
            const childCSS = getComputedStyle(child), childBox = rect(child);
            return child instanceof HTMLElement && childCSS.display !== 'none' && untransformed(childCSS) &&
                !['fixed', 'absolute', 'sticky'].includes(childCSS.position) &&
                near(childBox.width, available) && childBox.height > 0;
        });
        const content = children.sort((a, b) => rect(b).height - rect(a).height)[0];
        if (!content) return null;
        return { element, content, left, right, before: rect(content), depth };
    }

    function headerSnapshot(element) {
        // Record actual descendant geometry, not only the header's outer box.
        const queue = [element], boxes = [];
        for (let index = 0; index < queue.length; index++) {
            if (index >= 96) return null;
            const node = queue[index];
            if (!(node instanceof HTMLElement)) continue;
            const css = getComputedStyle(node);
            if (css.display === 'none' || css.visibility === 'hidden') continue;
            boxes.push({ element: node, box: rect(node) });
            for (const child of node.children) {
                if (queue.length >= 97) return null;
                queue.push(child);
            }
        }
        return boxes;
    }

    function apply() {
        if (!enabled || stopped) return;
        if (touching || performance.now() - lastScroll < 240) { schedule(); return; }
        const active = document.activeElement;
        if (active?.matches('input,textarea,select') || active?.isContentEditable ||
            Math.abs((visualViewport?.scale || 1) - 1) > 0.01 || document.fullscreenElement) return;
        const body = document.body, root = document.documentElement;
        if (!body) return;
        observe([body, ...watched.filter(element => element.isConnected && element !== body)]);
        const safe = safeInsets();
        if (safe.left + safe.right < 1) { fallback('no-side-inset'); return; }
        if (style?.sheet) style.sheet.disabled = true;
        const viewport = root.clientWidth;
        if (!near(innerWidth, viewport) || root.scrollWidth > viewport + 1 || !untransformed(getComputedStyle(root))) {
            fallback('unsupported'); return;
        }
        const nodes = structure(body);
        const candidates = nodes.map(item => candidate(item, safe, viewport)).filter(Boolean);
        // Refuse multiple independently matching wrappers rather than guessing which spacing is intentional.
        if (candidates.length !== 1) { observe([body, ...nodes.filter(item => item.depth === 1).map(item => item.element)]); fallback('unsupported'); return; }
        const selected = candidates[0];
        // The first general rule requires an independently protected top bar. Layouts needing a newly
        // relocated camera control are left alone until the separate collision engine can verify them.
        const headers = nodes.filter(item => ['fixed', 'sticky'].includes(item.css.position) &&
            near(item.box.top, 0) && near(item.box.width, viewport) && item.box.height > 0);
        observe([body, selected.element, selected.content, ...headers.map(item => item.element)]);
        if (!headers.length || headers.some(item => !untransformed(item.css) ||
            (selected.left && px(item.css.paddingLeft) < selected.left - 1) ||
            (selected.right && px(item.css.paddingRight) < selected.right - 1))) {
            fallback('unsupported'); return;
        }
        const snapshots = headers.map(item => headerSnapshot(item.element));
        if (snapshots.some(snapshot => !snapshot)) { fallback('scan-limit'); return; }
        const previousHeaders = snapshots.flat();
        const priorScrollWidth = root.scrollWidth;
        if (target !== selected.element) {
            removeRule(); target = selected.element; target.setAttribute(marker, '1');
        }
        if (!style?.isConnected) {
            style = document.createElement('style');
            (document.head || root).appendChild(style);
        }
        const rule = `[${marker}="1"] {${selected.left ? 'padding-left:0px!important;' : ''}${selected.right ? 'padding-right:0px!important;' : ''}}`;
        if (style.textContent !== rule) style.textContent = rule;
        if (style.sheet) style.sheet.disabled = false;
        const after = rect(selected.content), gain = selected.left + selected.right;
        const valid = near(after.width, selected.before.width + gain) && after.left >= -1 && after.right <= viewport + 1 &&
            root.scrollWidth <= priorScrollWidth + 1 && previousHeaders.every(item => item.element.isConnected && unchanged(item.box, rect(item.element)));
        if (!valid) { fallback('fallback', true); return; }
        lastResult = { state: 'fitted', viewport, before: selected.before.width, after: after.width, reclaimed: gain };
    }

    function update(value) {
        enabled = value === true; stopped = false; failures = 0;
        if (timer !== null) { clearTimeout(timer); timer = null; }
        if (!enabled) {
            mutationObserver.disconnect(); sizeObserver.disconnect(); watched = [];
            removeRule(); probe?.remove(); probe = null; lastResult = { state: 'original' };
        } else { apply(); }
        return lastResult;
    }
    addEventListener('resize', schedule, { passive: true });
    addEventListener('scroll', () => { lastScroll = performance.now(); schedule(); }, { passive: true, capture: true });
    addEventListener('touchstart', () => { touching = true; }, { passive: true, capture: true });
    for (const name of ['touchend', 'touchcancel']) addEventListener(name, event => {
        touching = event.touches.length > 0; schedule();
    }, { passive: true, capture: true });
    addEventListener('pageshow', schedule);
    document.addEventListener('focusout', schedule);
    document.addEventListener('fullscreenchange', schedule);
    window.visualViewport?.addEventListener('resize', schedule, { passive: true });
    // Numeric local state only. No page content is returned to native code.
    globalThis.__duoPageLayout = { update, inspect: () => lastResult };
})();
