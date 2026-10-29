// Bounded, reversible geometry fitting in the isolated PageLayout content world.
// Only bundled operations; no page messages, content export, persistence, or model code.
(() => {
  if (globalThis.__duoCamera || window.top !== window || !/^(https?:|file:)$/.test(location.protocol)) return;
  const controls = 'a[href],button,input:not([type=hidden]),select,textarea,[role=button],[role=tab],summary';
  const textBlocks = 'p,h1,h2,h3,h4,h5,h6,blockquote';
  const marker = 'data-duo-camera-' + Math.random().toString(36).slice(2);
  const sheet = document.createElement('style');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const QUIET = 240, DURATION = 420, MAX_MOVE = 320, MAX_NODES = 48;
  let geometry = null, timer = 0, touching = false, lastScroll = -Infinity, stopped = false;
  let ledger = new Map(), animations = new Map(), serial = 0;
  let bodySize = '', settlingScroll = null;
  const rect = el => el.getBoundingClientRect();
  const near = (a, b) => Math.abs(a - b) < 1;
  const overlaps = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
  const shifted = (r, x, y) => ({left:r.left+x, right:r.right+x, top:r.top+y, bottom:r.bottom+y});
  const plain = (css, ownedMotion = false) => (ownedMotion || css.transform === 'none') && css.translate === 'none' && css.rotate === 'none' &&
    css.scale === 'none' && (css.zoom === 'normal' || Number(css.zoom) === 1);
  const editing = () => document.activeElement?.matches('input,textarea,select') || document.activeElement?.isContentEditable ||
    (getSelection()?.rangeCount > 0 && !getSelection().isCollapsed);
  const unavailable = () => document.hidden || document.fullscreenElement || editing() ||
    Math.abs((visualViewport?.scale ?? 1) - 1) > .01;
  const authorMotion = el => el.getAnimations().some(a => a !== animations.get(el));
  const observer = new MutationObserver(records => {
    if (records.some(r => r.target !== sheet && r.target.parentNode !== sheet)) schedule();
  });
  const sizeObserver = new ResizeObserver(() => {
    const r = document.body?.getBoundingClientRect();
    if (r && `${r.width},${r.height}` !== bodySize) schedule();
  });

  function cancelAnimations() {
    for (const a of animations.values()) a.cancel();
    animations.clear();
  }
  function reset() {
    observer.disconnect(); sizeObserver.disconnect(); cancelAnimations();
    for (const el of ledger.keys()) el.removeAttribute(marker);
    ledger.clear(); sheet.textContent = ''; sheet.remove();
  }
  function rules() {
    // Disable scroll anchoring only for our layout transaction. It is removed before yielding.
    sheet.textContent = [...ledger].map(([el, p]) => `[${marker}="${p.id}"]{${p.css};transition:none!important}`).join('\n');
    if (!sheet.isConnected) document.documentElement.appendChild(sheet);
  }
  function own(el, css, side = null, actions = null) {
    const p = {id:++serial, css, side, actions};
    el.setAttribute(marker, String(p.id)); ledger.set(el, p); rules();
  }
  function undo(el) {
    el.removeAttribute(marker); ledger.delete(el); rules();
  }
  function schedule() {
    clearTimeout(timer);
    if (!stopped && geometry?.enabled) timer = setTimeout(settle, QUIET);
  }
  function moving(event) {
    // A synchronous reading-position correction is not a new user scroll. Its
    // queued event must not freeze the sideways animation we just started.
    if (event?.type === 'scroll' && (event.target === document || event.target === window) &&
        settlingScroll && near(scrollX, settlingScroll.x) && near(scrollY, settlingScroll.y)) {
      settlingScroll = null; return;
    }
    settlingScroll = null;
    lastScroll = performance.now();
    // Freeze at the current presentation, including when a new swipe interrupts settling.
    for (const a of animations.values()) if (a.playState === 'running') a.pause();
    schedule();
  }
  function regionsNow() {
    const scale = (visualViewport?.width ?? innerWidth) / geometry.width;
    const x = visualViewport?.offsetLeft ?? 0, y = visualViewport?.offsetTop ?? 0;
    return geometry.regions.map(r => ({left:r.x*scale+x, top:r.y*scale+y,
      right:(r.x+r.width)*scale+x, bottom:(r.y+r.height)*scale+y}));
  }
  function safe(el) {
    if (!(el instanceof HTMLElement) || !el.isConnected || el.contains(document.activeElement)) return false;
    const css = getComputedStyle(el);
    if (!plain(css) || css.visibility !== 'visible' || Number(css.opacity) < .9 || css.position === 'sticky' ||
        css.writingMode !== 'horizontal-tb' || authorMotion(el)) return false;
    for (let p = el.parentElement, depth = 0; p && depth < 24; p = p.parentElement, depth++) {
      const c = getComputedStyle(p);
      if (!plain(c) || (c.position === 'sticky' && el.matches(textBlocks)) || /hidden|clip|auto|scroll/.test(c.overflowX + c.overflowY) ||
          p.isContentEditable || authorMotion(p)) return false;
      if (p === document.body) return true;
    }
    return false;
  }
  function group(el) {
    // Keep small clusters together without translating a whole toolbar or article.
    for (let p = el.parentElement, i = 0; p && p !== document.body && i < 2; p = p.parentElement, i++) {
      const r = rect(p);
      if (r.width > 180 || r.height > 100 || p.children.length > 6) break;
      const walker = document.createTreeWalker(p, NodeFilter.SHOW_ELEMENT);
      let count = 0, actions = 0, supported = true;
      while (walker.nextNode()) {
        if (++count > 48 || walker.currentNode.matches(textBlocks + ',img,video,iframe')) { supported = false; break; }
        if (walker.currentNode.matches(controls)) actions++;
      }
      if (!supported) break;
      if (actions > 1) return p;
    }
    return el;
  }
  function controlRow(el) {
    for (let p = el.parentElement, depth = 0; p && p !== document.body && depth < 4; p = p.parentElement, depth++) {
      const r = rect(p), c = getComputedStyle(p);
      if (r.height > 100) break;
      if (r.width <= 180 || !['flex', 'grid'].includes(c.display) || !safe(p)) continue;
      if (p.children.length > 64) return null;
      const actions = [], guards = [], pending = [...p.children];
      let visited = 0;
      while (pending.length) {
        if (++visited > 64) return null;
        const n = pending.pop(), style = getComputedStyle(n), box = rect(n);
        if (style.display === 'none') { guards.push(n); continue; }
        // Closed offcanvas navigation often lives inside the header. Changing
        // row width must leave that panel unchanged; never transform its parent.
        if ((box.right <= 0 || box.left >= innerWidth || box.bottom <= 0 || box.top >= innerHeight) &&
            (!plain(style) || ['absolute', 'fixed'].includes(style.position)) && !authorMotion(n)) {
          guards.push(n); continue;
        }
        if (n.matches(textBlocks + ',input,textarea,select,video,iframe,canvas') ||
            !plain(style, animations.has(n)) || authorMotion(n) || actions.length >= 12) return null;
        if (n.matches(controls) && box.width && box.height) actions.push(n);
        if (pending.length+n.children.length+visited > 64) return null;
        pending.push(...n.children);
      }
      if (actions.length >= 2 && actions.every(canAnimateUnit)) return {el:p, actions, guards};
    }
    return null;
  }
  function candidates(regions, old) {
    const found = new Set([...old.keys(), ...[...old.values()].flatMap(p => p.actions ?? [])]);
    for (const r of regions) {
      const steps = Math.min(10, Math.max(2, Math.ceil((r.bottom-r.top)/18)));
      const heights = Array.from({length:steps+1}, (_, i) => r.top+1+(r.bottom-r.top-2)*i/steps);
      for (const x of [r.left+1, (r.left+r.right)/2, r.right-1]) {
        for (const y of heights) {
          for (const hit of document.elementsFromPoint(x, y).slice(0, 6)) {
            const text = hit.closest(textBlocks), control = hit.closest(controls);
            if (text) found.add(text);
            else if (control) { found.add(group(control)); found.add(control); }
          }
        }
      }
    }
    return [...found].filter(el => el instanceof HTMLElement && el.isConnected).slice(0, 12);
  }
  function textRects(el) {
    // Preserve real DOM text and links. Never split, clone, truncate or scale glyphs.
    const nodes = document.createTreeWalker(el, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    let count = 0, elements = 0, characters = 0;
    while (nodes.nextNode()) {
      if (++count > 96) return null;
      if (nodes.currentNode.nodeType === Node.TEXT_NODE) {
        characters += nodes.currentNode.length;
        if (characters > 8192) return null;
        continue;
      }
      if (++elements > 32 || !/^(A|SPAN|EM|STRONG|B|I|U|S|SMALL|BR|MARK|ABBR|TIME)$/.test(nodes.currentNode.tagName)) return null;
      const css = getComputedStyle(nodes.currentNode);
      if (!plain(css) || /absolute|fixed|sticky/.test(css.position)) return null;
    }
    const range = document.createRange(); range.selectNodeContents(el);
    const lines = [...range.getClientRects()].filter(r => r.width > 0 && r.height > 0);
    return lines.length && lines.length <= 64 ? lines : null;
  }
  function flowFollowers(el) {
    // Follow a bounded local block flow through nested site shells. Grid/flex
    // ancestors are allowed only around that flow, with measured geometry guards.
    // Offscreen subtrees need no animation or descendant walk.
    // Complex siblings can follow natural flow without a transform that would
    // reparent their fixed descendants; their outer geometry is still validated.
    const result = [el], guards = [], ancestors = [];
    let inspected = 0;
    for (let current = el, depth = 0; current !== document.body && depth < 24; depth++) {
      const parent = current.parentElement;
      if (!parent) return null;
      const css = getComputedStyle(parent);
      if (!plain(css) || (depth === 0 && !['block', 'flow-root'].includes(css.display)) ||
          !['block', 'flow-root', 'grid', 'flex'].includes(css.display) ||
          css.columnCount !== 'auto' || css.columnWidth !== 'auto' || css.height === '0px') return null;
      if (parent.childNodes.length > 192 ||
          [...parent.childNodes].some(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim())) return null;
      ancestors.push(parent);
      for (let next = parent.firstElementChild; next; next = next.nextElementSibling) {
        if (++inspected > 192) return null;
        if (next === current || /^(SCRIPT|STYLE|LINK|META)$/.test(next.tagName)) continue;
        const c = getComputedStyle(next), r = rect(next);
        if (c.display === 'none' || !r.width || !r.height) continue;
        guards.push(next);
        if (r.bottom <= 0 || r.top >= innerHeight || c.position === 'fixed' || c.position === 'sticky') continue;
        if (!plain(c, animations.has(next)) || !['static', 'relative'].includes(c.position) ||
            c.float !== 'none' || authorMotion(next) || !canAnimateUnit(next)) continue;
        result.push(next);
        if (result.length > MAX_NODES) return null;
      }
      if (parent === document.body) return Object.assign(result, {guards, ancestors});
      current = parent;
    }
    return null;
  }
  function canAnimateUnit(el) {
    // A transform changes the containing block of fixed descendants. Never animate
    // such a subtree or inspect an unbounded article just to prove it safe.
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_ELEMENT);
    for (let n = 0; walker.nextNode(); n++) {
      if (n >= 96 || /fixed|sticky/.test(getComputedStyle(walker.currentNode).position)) return false;
    }
    return true;
  }
  function within(r, regions) {
    const x = visualViewport?.offsetLeft ?? 0, y = visualViewport?.offsetTop ?? 0;
    return r.left >= x+4 && r.right <= x+(visualViewport?.width ?? innerWidth)-4 &&
      r.top >= y && r.bottom <= y+(visualViewport?.height ?? innerHeight) && !regions.some(o => overlaps(r, o));
  }
  function destinationFree(el, target) {
    // Sample the destination densely enough for text lines and small neighbouring controls.
    for (let y = target.top+2; y < target.bottom; y += Math.max(6, (target.bottom-target.top)/12)) {
      for (let x = target.left+2; x < target.right; x += Math.max(8, (target.right-target.left)/12)) {
        // Check the foreground hit: a sticky toolbar can cover
        // article text underneath without that text occupying this destination.
        const hit = document.elementFromPoint(x, y);
        if (!hit || hit === el || el.contains(hit) || hit.contains(el)) continue;
        if (hit.closest(controls + ',' + textBlocks + ',img,video,iframe,canvas,svg') ||
            hit.childElementCount === 0 && hit.textContent.trim()) return false;
      }
    }
    return true;
  }
  function pageChrome(hit) {
    // Existing compact sticky bars legitimately cover article lines. Do not
    // mistake those hidden lines for a broken destination or a reading anchor.
    for (let n = hit, depth = 0; n && depth < 8; n = n.parentElement, depth++) {
      const c = getComputedStyle(n), r = rect(n), inset = parseFloat(c.top);
      if (['fixed', 'sticky'].includes(c.position) && Number.isFinite(inset) &&
          r.top <= inset+1 && r.width >= innerWidth*.75 && r.height <= innerHeight*.4) return true;
    }
    return false;
  }
  function reachable(el, isText) {
    const boxes = isText ? textRects(el) : [rect(el), ...(ledger.get(el)?.actions ?? [...el.querySelectorAll(controls)]).map(rect)].filter(r => r.width > 0 && r.height > 0);
    let visible = 0;
    const valid = boxes?.every(r => {
      if (r.bottom <= 0 || r.top >= innerHeight || r.right <= 0 || r.left >= innerWidth) return true;
      const y = Math.max(.5, Math.min(innerHeight-.5, (r.top+r.bottom)/2));
      const hit = document.elementFromPoint((r.left+r.right)/2, y);
      if (hit === el || el.contains(hit)) { visible++; return true; }
      return isText && pageChrome(hit);
    });
    return valid && visible > 0;
  }
  function move(el, regions, isText) {
    const box = rect(el), lines = isText ? textRects(el) : [box];
    if (!lines || !lines.some(line => regions.some(r => overlaps(line, r)))) return false;
    if (box.height > (isText ? 320 : 100) || (!isText && box.width > 180)) return false;
    const collisions = regions.filter(r => lines.some(line => overlaps(line, r)));
    const choices = [
      [Math.min(...collisions.map(r => r.left))-box.right-8, 0],
      [Math.max(...collisions.map(r => r.right))-box.left+8, 0],
      [0, Math.max(...collisions.map(r => r.bottom))-box.top+8],
      [0, Math.min(...collisions.map(r => r.top))-box.bottom-8]
    ];
    for (const [dx, dy] of choices) {
      if (isText && dy !== 0) continue;
      if (Math.abs(dx)+Math.abs(dy) > (isText ? MAX_MOVE : 110)) continue;
      const target = shifted(box, dx, dy);
      if (!within(target, regions) || !destinationFree(el, target)) continue;
      own(el, `translate:${dx}px ${dy}px!important`);
      const actual = rect(el);
      if (near(actual.left, target.left) && near(actual.top, target.top) &&
          document.documentElement.scrollWidth <= innerWidth+1 && reachable(el, isText)) return true;
      undo(el);
    }
    return false;
  }
  function fitControlRow(row, regions) {
    if (!row || [...ledger.keys()].some(n => row.el.contains(n))) return false;
    const box = rect(row.el), height = document.documentElement.scrollHeight;
    const css = getComputedStyle(row.el);
    const blocked = regions.filter(r => overlaps(box, r));
    if (!blocked.length) return false;
    let left = box.left, right = box.right;
    for (const r of blocked) {
      if (r.left-box.left >= box.right-r.right) right = Math.min(right, r.left-8);
      else left = Math.max(left, r.right+8);
    }
    if (right-left < box.width*.6 || box.width-(right-left) > 120) return false;
    const sizes = row.actions.map(n => rect(n));
    const guardBoxes = row.guards.map(rect);
    own(row.el, `box-sizing:border-box!important;width:${right-left}px!important;max-width:${right-left}px!important;` +
      `margin-left:${(parseFloat(css.marginLeft)||0)+left-box.left}px!important`, null, row.actions);
    const after = rect(row.el), boxes = row.actions.map(rect);
    const valid = near(after.left,left) && near(after.right,right) && near(after.top,box.top) && near(after.height,box.height) &&
      document.documentElement.scrollHeight === height && row.guards.every((n,i) => {
        const a = guardBoxes[i], b = rect(n);
        return near(a.left,b.left) && near(a.top,b.top) && near(a.width,b.width) && near(a.height,b.height);
      }) && boxes.every((r,i) =>
        near(r.width,sizes[i].width) && near(r.height,sizes[i].height) && near(r.top,sizes[i].top) &&
        within(r,regions) && reachable(row.actions[i],false) && !boxes.some((b,j) => i !== j && overlaps(r,b)));
    if (valid) return true;
    undo(row.el); return false;
  }
  function fitTextSide(el, regions, followers) {
    if (!followers || geometry.voiceOver || !followers.every(canAnimateUnit)) return false;
    const box = rect(el), lines = textRects(el), css = getComputedStyle(el);
    if (!lines || !['static', 'relative'].includes(css.position) || css.float !== 'none' ||
        css.display !== 'block' || box.height > 320) return false;
    if (!lines.some(line => regions.some(r => overlaps(line, r)))) return false;
    const before = new Map(followers.guards.map(n => [n, rect(n)]));
    const shells = new Map(followers.ancestors.map(n => [n, rect(n)]));
    const beforeHeight = document.documentElement.scrollHeight;
    const minimum = Math.max(180, box.width * .6);
    let left = box.left, right = box.right, side = null;
    // Narrow only after scrolling has stopped. Reflow is a single synchronous
    // transaction; the subsequent visual motion is horizontal, without text scaling.
    for (let step = 0; step <= regions.length; step++) {
      const current = rect(el);
      const blocked = regions.filter(r => overlaps(current, r));
      if (!blocked.length) break;
      for (const region of blocked) {
        const roomLeft = region.left - 8 - left, roomRight = right - region.right - 8;
        if (roomLeft >= roomRight && roomLeft >= minimum) {
          right = Math.min(right, region.left - 8); side = 'right';
        } else if (roomRight >= minimum) {
          left = Math.max(left, region.right + 8); side = 'left';
        } else { undo(el); return false; }
      }
      if (right-left < minimum || box.width-(right-left) > 180) { undo(el); return false; }
      own(el, `box-sizing:border-box!important;width:${right-left}px!important;max-width:${right-left}px!important;` +
        `margin-left:${(parseFloat(css.marginLeft)||0)+left-box.left}px!important`, side);
    }
    const after = rect(el), growth = after.height-box.height;
    const valid = side && near(after.top, box.top) && near(after.left, left) && near(after.right, right) &&
      growth >= -1 && growth <= 160 && after.height <= 480 && !regions.some(r => overlaps(after, r)) &&
      document.documentElement.scrollWidth <= innerWidth+1 && document.documentElement.scrollHeight <= beforeHeight+growth+1 &&
      [...before].every(([n, a]) => {
        const b = rect(n), delta = b.top-a.top;
        return near(a.left, b.left) && near(a.width, b.width) && near(a.height, b.height) &&
          (near(delta, 0) || near(delta, growth)) &&
          (a.top < box.bottom || b.top >= after.bottom-1);
      }) && [...shells].every(([n, a]) => {
        const b = rect(n);
        return near(a.left, b.left) && near(a.top, b.top) && near(a.width, b.width) &&
          b.height >= a.height-1 && b.height <= a.height+growth+1;
      });
    if (valid && reachable(el, true)) return true;
    undo(el); return false;
  }
  function animateFrom(before, old, reading) {
    if (reduced.matches || geometry.reduceMotion || geometry.voiceOver) return;
    for (const [el, start] of before) {
      if (!el.isConnected) continue;
      const end = rect(el), side = ledger.get(el)?.side ?? old.get(el)?.side;
      const resized = side && !near(start.width, end.width);
      const dx = resized && side === 'right' ? start.right-end.right : start.left-end.left;
      // The visible character is already anchored. Replaying the block's old
      // top would undo that correction when lines above it have rewrapped.
      const dy = el === reading?.el ? 0 : start.top-end.top;
      if (Math.abs(dx)+Math.abs(dy) < .5 || Math.abs(dx)+Math.abs(dy) > MAX_MOVE*2 ||
          (!resized && (!near(start.width, end.width) || !near(start.height, end.height))) ||
          (start.bottom < 0 && end.bottom < 0) || (start.top > innerHeight && end.top > innerHeight) ||
          getComputedStyle(el).transform !== 'none') continue;
      // The final layout is validated once. Only a compositor transform changes per frame.
      const a = el.animate([{transform:`translate(${dx}px,${dy}px)`, opacity:resized ? .8 : 1},
        {transform:'translate(0px,0px)', opacity:1}],
        {duration:DURATION, easing:'cubic-bezier(0.22, 1, 0.36, 1)'});
      animations.set(el, a);
      a.onfinish = () => { if (animations.get(el) === a) animations.delete(el); };
    }
  }
  function readingAnchor(before) {
    const visible = [...before].filter(([el, r]) => el.matches(textBlocks) && r.bottom > 0 && r.top < innerHeight &&
      ['static', 'relative'].includes(getComputedStyle(el).position));
    visible.sort((a, b) => a[1].top-b[1].top);
    for (const [el, box] of visible) {
      const lines = textRects(el);
      const line = lines?.find(r => {
        if (r.bottom <= 0 || r.top >= innerHeight) return false;
        const hit = document.elementFromPoint((r.left+r.right)/2, Math.max(.5,Math.min(innerHeight-.5,(r.top+r.bottom)/2)));
        return hit === el || el.contains(hit);
      });
      if (box.top >= 0 && line && line === lines[0]) return {el, top:box.top, measure:() => rect(el).top};
      // Anchor a real visible character when earlier lines are above the screen
      // or behind the site's sticky header; keep that word fixed as lines rewrap.
      if (!line) continue;
      const range = document.caretRangeFromPoint?.(Math.max(.5, line.left+1),
        Math.max(.5, Math.min(innerHeight-.5, (line.top+line.bottom)/2)));
      const node = range?.startContainer, offset = range?.startOffset;
      if (node?.nodeType !== Node.TEXT_NODE || !el.contains(node) || offset >= node.length) continue;
      range.setEnd(node, offset+1);
      const top = range.getBoundingClientRect().top;
      return {el, top, measure:() => range.getBoundingClientRect().top};
    }
    return null;
  }
  function scrollInstantly(x, y) {
    if (near(scrollX, x) && near(scrollY, y)) return;
    // WebKit quantizes document scroll offsets; use the nearest CSS pixel rather
    // than allowing repeated fractional corrections to round in one direction.
    window.scrollTo({left:x, top:Math.round(y), behavior:'instant'});
    settlingScroll = {x:scrollX, y:scrollY};
  }
  function keepReadingPosition(anchor, scroll) {
    const delta = anchor ? anchor.measure()-anchor.top : 0;
    const y = anchor ? scrollY+delta : scroll.y;
    if (Math.abs(delta) > MAX_MOVE || y < -1 || y > Math.max(0, document.documentElement.scrollHeight-innerHeight)+1) return false;
    scrollInstantly(scroll.x, Math.max(0, y));
    return !anchor || near(anchor.measure(), anchor.top);
  }
  function settle() {
    timer = 0;
    if (stopped || !geometry?.enabled) return;
    if (touching || performance.now()-lastScroll < QUIET) { schedule(); return; }
    if (unavailable()) return;
    const regions = regionsNow(), old = new Map(ledger), nodes = candidates(regions, old);
    const motion = new Set([...old.keys(), ...animations.keys(), ...nodes]);
    // Pause/cancel only our animations; author animation remains a conservative fallback.
    const followers = new Map(), rows = new Map();
    for (const el of nodes) {
      if (el.matches(textBlocks)) continue;
      const row = controlRow(el);
      if (row) { rows.set(el, row); for (const action of row.actions) motion.add(action); }
    }
    for (const el of nodes) {
      if (!el.matches(textBlocks)) continue;
      // Running owned animations must not prevent us finding their ordinary flow siblings.
      for (const a of animations.values()) a.pause();
      const f = flowFollowers(el);
      if (f) { followers.set(el, f); for (const n of f) motion.add(n); }
    }
    if (motion.size > MAX_NODES) { for (const a of animations.values()) a.play(); return; }
    const before = new Map([...motion].filter(n => n.isConnected).map(n => [n, rect(n)]));
    const scroll = {x:scrollX, y:scrollY};
    const reading = readingAnchor(before);
    // Suppress browser scroll anchoring for this synchronous transaction, then restore author style.
    const root = document.documentElement, anchor = root.style.getPropertyValue('overflow-anchor');
    const priority = root.style.getPropertyPriority('overflow-anchor');
    observer.disconnect();
    root.style.setProperty('overflow-anchor', 'none', 'important');
    reset();
    try {
      let stable = keepReadingPosition(reading, scroll);
      for (const el of stable ? nodes : []) {
        if ([...ledger.keys()].some(p => p.contains(el) || el.contains(p)) || !safe(el) || !canAnimateUnit(el)) continue;
        const isText = el.matches(textBlocks);
        if (isText && (geometry.voiceOver || !reachable(el, true))) continue;
        if (!move(el, regions, isText)) {
          if (isText) fitTextSide(el, regions, followers.get(el));
          else fitControlRow(rows.get(el), regions);
        }
        if (!keepReadingPosition(reading, scroll)) { stable = false; break; }
      }
      if (stable) stable = [...ledger.keys()].every(el => {
        const boxes = el.matches(textBlocks) ? textRects(el) : [rect(el)];
        return boxes && !boxes.some(box => regions.some(region => overlaps(box, region))) && reachable(el, el.matches(textBlocks));
      });
      if (!stable) {
        // If anchoring would clamp at a document edge or invalidate a destination,
        // retain the previous fitting instead of moving the reader's text away.
        reset(); ledger = old;
        for (const [el, plan] of ledger) el.setAttribute(marker, String(plan.id));
        rules();
        scrollInstantly(scroll.x, scroll.y);
      }
      animateFrom(before, old, reading);
    } finally {
      if (anchor) root.style.setProperty('overflow-anchor', anchor, priority);
      else root.style.removeProperty('overflow-anchor');
      observer.observe(document.body, {subtree:true, childList:true, attributes:true, attributeFilter:['class','style']});
      observer.takeRecords();
      const r = rect(document.body); bodySize = `${r.width},${r.height}`;
      sizeObserver.observe(document.body);
    }
  }
  function valid(value) {
    return value && typeof value.enabled === 'boolean' && Number.isFinite(value.width) && value.width > 0 && value.width <= 10000 &&
      Number.isFinite(value.height) && value.height > 0 && value.height <= 10000 && Array.isArray(value.regions) && value.regions.length <= 8 &&
      value.regions.every(r => r && ['x','y','width','height'].every(k => Number.isFinite(r[k])) &&
        r.width >= 0 && r.height >= 0 && Math.abs(r.x) <= 10000 && Math.abs(r.y) <= 10000 && r.width <= 10000 && r.height <= 10000);
  }
  globalThis.__duoCamera = {update(value) {
    if (!valid(value)) return;
    const next = {enabled:value.enabled, width:value.width, height:value.height,
      regions:value.regions.map(r => ({x:r.x,y:r.y,width:r.width,height:r.height})),
      reduceMotion:value.reduceMotion === true, voiceOver:value.voiceOver === true};
    if (JSON.stringify(next) === JSON.stringify(geometry)) return;
    geometry = next;
    if (!value.enabled) { clearTimeout(timer); reset(); }
    else schedule();
  }};
  addEventListener('scroll', moving, {passive:true, capture:true});
  addEventListener('resize', () => { moving(); });
  addEventListener('touchstart', () => { touching = true; moving(); }, {passive:true, capture:true});
  for (const name of ['touchend','touchcancel']) addEventListener(name, e => { touching = e.touches.length > 0; schedule(); }, {passive:true, capture:true});
  addEventListener('pointerdown', () => { touching = true; moving(); }, {passive:true, capture:true});
  for (const name of ['pointerup','pointercancel']) addEventListener(name, () => { touching = false; schedule(); }, {passive:true, capture:true});
  addEventListener('focusin', moving, {capture:true});
  addEventListener('focusout', schedule);
  addEventListener('pagehide', () => { clearTimeout(timer); stopped = true; reset(); });
  addEventListener('pageshow', () => { stopped = false; touching = false; schedule(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) { clearTimeout(timer); cancelAnimations(); touching = false; } else schedule(); });
  document.addEventListener('selectionchange', () => { if (editing()) moving(); else schedule(); });
  document.addEventListener('fullscreenchange', schedule);
  // WebKit/Chromium can emit load for our own freshly attached stylesheet.
  document.addEventListener('load', event => { if (event.target !== sheet) schedule(); }, true);
  document.fonts?.addEventListener('loadingdone', schedule);
  visualViewport?.addEventListener('resize', moving, {passive:true});
  reduced.addEventListener('change', () => { if (reduced.matches) cancelAnimations(); schedule(); });
})();
