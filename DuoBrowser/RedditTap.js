/* DuoBrowser Reddit tap */
(() => {
    'use strict';
    let pending = null;
    document.addEventListener('click', event => {
        pending = null;
        if (!event.isTrusted || event.button !== 0) return;
        const anchor = event.composedPath().find(node => node instanceof HTMLAnchorElement);
        if (!anchor || anchor.hasAttribute('download')) return;
        const url = anchor.href;
        if (url.length <= 8192) pending = { url, time: performance.now() };
    }, true);
    Object.defineProperty(globalThis, '__duoRedditTap', {
        value: Object.freeze({ consume(url) {
            const tap = pending;
            pending = null;
            return !!tap && tap.url === url && performance.now() - tap.time <= 1500;
        } })
    });
})();
