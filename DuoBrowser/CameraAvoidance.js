(() => {
  if (globalThis.__duoCamera || window.top !== window || !/^(https?:|file:)$/.test(location.protocol)) return;
  const selector = 'a[href],button,input:not([type=hidden]),select,textarea,[role=button]';
  const marker = 'data-duo-camera-' + Math.random().toString(36).slice(2);
  const style = document.createElement('style');
  let geometry = null, timer = 0, touchedUntil = 0, owned = [], stopped = false;
  const observer = new MutationObserver(() => schedule());
  const overlaps = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
  function reset() {
    observer.disconnect();
    for (const node of owned) node.removeAttribute(marker);
    owned = [];
    style.textContent = '';
    style.remove();
  }
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(run, 180);
  }
  function run() {
    if (stopped || !geometry) return;
    if (Date.now() < touchedUntil) { schedule(); return; }
    if (document.fullscreenElement ||
        Math.abs((visualViewport?.scale ?? 1) - 1) > .01 ||
        (document.activeElement?.matches('input,textarea,select') || document.activeElement?.isContentEditable)) return;
    reset();
    if (!geometry.enabled || !geometry.width || !geometry.height) return;
    // UIKit points map to the visual CSS viewport. Zoom is deliberately deferred.
    const sx = (visualViewport?.width ?? innerWidth) / geometry.width;
    const sy = sx;
    const ox = visualViewport?.offsetLeft ?? 0, oy = visualViewport?.offsetTop ?? 0;
    const regions = geometry.regions.slice(0, 8).map(r => ({
      left: r.x * sx + ox, top: r.y * sy + oy,
      right: (r.x + r.width) * sx + ox, bottom: (r.y + r.height) * sy + oy
    }));
    const candidates = new Set();
    for (const r of regions) {
      for (const x of [r.left + 1, (r.left + r.right) / 2, r.right - 1]) {
        for (const y of [r.top + 1, (r.top + r.bottom) / 2, r.bottom - 1]) {
          for (const hit of document.elementsFromPoint(x, y).slice(0, 6)) {
            const control = hit.closest(selector);
            if (control instanceof HTMLElement) candidates.add(control);
          }
        }
      }
    }
    const rules = [];
    for (const node of [...candidates].slice(0, 8)) {
      const old = node.getBoundingClientRect(), css = getComputedStyle(node);
      if (!old.width || !old.height || old.width > 180 || old.height > 100 || css.transform !== 'none' ||
          css.translate !== 'none' || css.position === 'sticky' || css.visibility !== 'visible' ||
          Number(css.opacity) < .9 || node === document.activeElement || node.contains(document.activeElement)) continue;
      const collisions = regions.filter(r => overlaps(old, r));
      if (!collisions.length) continue;
      const left = Math.min(...collisions.map(r => r.left)) - old.right - 6;
      const down = Math.max(...collisions.map(r => r.bottom)) - old.top + 6;
      const choices = [[left, 0], [0, down]];
      for (const [dx, dy] of choices) {
        if (Math.abs(dx) + Math.abs(dy) > 110) continue;
        const target = {left: old.left + dx, right: old.right + dx, top: old.top + dy, bottom: old.bottom + dy};
        if (target.left < ox + 4 || target.right > ox + (visualViewport?.width ?? innerWidth) - 4 ||
            target.top < oy || target.bottom > oy + (visualViewport?.height ?? innerHeight) || regions.some(r => overlaps(target, r))) continue;
        const points = [[target.left + 2, target.top + 2], [target.right - 2, target.bottom - 2],
          [(target.left + target.right) / 2, (target.top + target.bottom) / 2]];
        // Do not cover another control or a separate text/image content block.
        const blocked = points.some(([x,y]) => document.elementsFromPoint(x,y).slice(0,6).some(el =>
          el !== node && !node.contains(el) && !el.contains(node) &&
          (el.matches(selector + ',img,video,p,h1,h2,h3') || el.childElementCount === 0 && el.textContent.trim())));
        if (blocked) continue;
        const index = owned.length;
        const rule = `[${marker}="${index}"]{translate:${dx}px ${dy}px!important;}`;
        node.setAttribute(marker, String(index));
        style.textContent = rules.join('\n') + '\n' + rule;
        if (!style.isConnected) document.documentElement.append(style);
        const actual = node.getBoundingClientRect();
        const hits = points.every(([x,y]) => { const hit = document.elementFromPoint(x,y); return hit === node || node.contains(hit); });
        if (Math.abs(actual.left - target.left) > 1 || Math.abs(actual.top - target.top) > 1 || !hits ||
            regions.some(r => overlaps(actual, r)) || document.documentElement.scrollWidth > innerWidth + 1) {
          node.removeAttribute(marker); style.textContent = rules.join('\n'); continue;
        }
        rules.push(rule); owned.push(node);
        break;
      }
    }
    for (const node of owned) {
      observer.observe(node, {attributes:true, attributeFilter:['style','class']});
      if (node.parentElement) observer.observe(node.parentElement, {childList:true, attributes:true, attributeFilter:['style','class']});
    }
    if (document.body) observer.observe(document.body, {childList:true});
  }
  globalThis.__duoCamera = { update(value) {
    if (!value || !Array.isArray(value.regions) || !Number.isFinite(value.width) || !Number.isFinite(value.height)) return;
    geometry = value;
    if (!value.enabled) { clearTimeout(timer); reset(); }
    else schedule();
  }};
  addEventListener('resize', schedule, {passive:true});
  addEventListener('scroll', schedule, {passive:true});
  addEventListener('focusout', schedule);
  addEventListener('touchstart', () => { touchedUntil = Date.now() + 500; }, {passive:true});
  addEventListener('touchend', schedule, {passive:true});
  addEventListener('pagehide', () => { clearTimeout(timer); reset(); stopped = true; });
  addEventListener('pageshow', () => { stopped = false; schedule(); });
  visualViewport?.addEventListener('resize', schedule, {passive:true});
})();
