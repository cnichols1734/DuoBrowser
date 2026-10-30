module.exports = async function runSettlingTests(page, source) {
  const p = await page.context().newPage();
  const results = [];
  let html = '';
  const assert = (ok, name) => { if (!ok) throw new Error(name); results.push(name); };
  await p.setViewportSize({width:466, height:678});
  await p.route('**/*', r => r.fulfill({contentType:'text/html', body:html}));
  const region = {x:386,y:20,width:80,height:120};
  const geometry = (regions=[region], extra={}) => ({enabled:true,width:466,height:678,regions,...extra});
  const send = value => p.evaluate(v => __duoCamera.update(v), value);
  const box = id => p.locator('#'+id).evaluate(n => {
    const r=n.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height,right:r.right};
  });
  const lines = () => p.locator('#reading').evaluate(n => {
    const r=document.createRange();r.selectNodeContents(n);
    return [...r.getClientRects()].map(q=>[q.width,q.height]);
  });
  async function setup(css='', body='') {
    html=`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>
      body{margin:0;padding:24px 16px;font:18px/24px sans-serif}p{margin:0 0 24px}h2{margin:0 0 24px;font-size:20px}
      main{padding-bottom:1600px}button{min-height:44px}${css}</style><main>
      <p id="reading">A quiet reading page keeps its text stable during scrolling. After scrolling stops, this paragraph fits beside the camera. <a id="action" href="#done">Read more</a>.</p>
      <p id="following">The next paragraph follows ordinary text flow, keeping its spacing intact.</p>
      <h2 id="heading">Continue reading</h2>${body}</main>`;
    await p.goto('https://settling.example/'); await p.evaluate(source);
  }
  const settled = () => p.waitForTimeout(850);
  const fitted = async () => {const r=await box('reading');return r.right<=378 && r.width>=180 && r.y===24;};
  try {
    await setup();
    const original = await box('reading'), next = await box('following');
    const text = await p.locator('#reading').textContent();
    await p.evaluate(() => {
      window.motionSamples=[]; const until=performance.now()+1000;
      requestAnimationFrame(function sample() {
        const n=document.querySelector('#reading'),r=n.getBoundingClientRect();
        motionSamples.push({x:r.x,y:r.y,transform:getComputedStyle(n).transform,durations:n.getAnimations().map(a=>a.effect.getTiming().duration)});
        if(performance.now()<until)requestAnimationFrame(sample);
      });
    });
    await send(geometry()); await p.waitForTimeout(1100);
    assert(await p.evaluate(x=>motionSamples.some(s=>s.x>x+1 && s.x<88),original.x), 'text glides horizontally through intermediate positions');
    assert(await p.evaluate(()=>motionSamples.some(s=>s.durations.includes(420))), 'text uses bounded 420ms motion');
    const end = await box('reading'), after = await box('following');
    assert(await fitted(), 'paragraph fits beside the right camera without a gap above it');
    assert(await p.evaluate(()=>motionSamples.every(s=>Math.abs(s.y-24)<1)), 'colliding paragraph never moves vertically');
    assert(Math.abs((after.y-end.y-end.height)-(next.y-original.y-original.height))<1, 'following content preserves the natural paragraph gap');
    assert(await p.locator('#reading').textContent()===text && await p.locator('#reading').evaluate(n=>getComputedStyle(n).fontSize)==='18px', 'all original text and font size are preserved');
    assert(await p.evaluate(()=>motionSamples.every(s=>s.transform==='none'||Math.abs(new DOMMatrix(s.transform).a-1)<.001)), 'horizontal animation never scales glyphs');
    assert(await p.evaluate(()=>scrollY)===0, 'side fitting preserves scroll position');
    assert(await p.locator('p').count()===2, 'text remains in its original DOM without clones');
    await p.locator('#action').click();
    assert(new URL(p.url()).hash==='#done', 'link within fitted text remains functional');
    await send(geometry([], {enabled:false}));
    assert((await box('reading')).width===original.width, 'original layout restores the paragraph width');

    await setup(); const scrollingLines=await lines();
    await p.evaluate(()=>dispatchEvent(new Event('pointerdown'))); await send(geometry()); await p.waitForTimeout(650);
    assert((await box('reading')).width===434, 'no text fitting while finger is held down');
    await p.evaluate(()=>dispatchEvent(new Event('pointerup')));
    for(let i=0;i<5;i++) { await p.evaluate(()=>dispatchEvent(new Event('scroll'))); await p.waitForTimeout(90); }
    assert(JSON.stringify(await lines())===JSON.stringify(scrollingLines), 'line wrapping stays stable throughout momentum');
    await settled(); assert(await fitted(),'fits sideways after momentum ends');

    await setup(); await send(geometry()); await p.waitForTimeout(290);
    await p.evaluate(()=>dispatchEvent(new Event('pointerdown')));
    const paused = await box('reading'); await p.waitForTimeout(400);
    assert(Math.abs((await box('reading')).x-paused.x)<.5, 'new swipe freezes unfinished sideways motion without jumping');
    await p.evaluate(()=>dispatchEvent(new Event('pointerup'))); await settled();
    assert(await fitted(),'interrupted sideways settling resumes safely');

    await setup(); await send(geometry()); await settled(); const first = await box('reading');
    for(let i=0;i<3;i++){ await p.evaluate(()=>dispatchEvent(new Event('scroll'))); await settled(); }
    assert((await box('reading')).width===first.width, 'repeated settling never accumulates insets');
    await p.evaluate(()=>{dispatchEvent(new Event('pointerdown'));scrollTo(0,document.querySelector('#following').getBoundingClientRect().top+scrollY-8)});
    const readingTop = (await box('following')).y;
    await p.evaluate(()=>{
      window.verticalSamples=[];const until=performance.now()+1500;
      requestAnimationFrame(function sample(){const r=document.querySelector('#following').getBoundingClientRect();verticalSamples.push({x:r.x,y:r.y});if(performance.now()<until)requestAnimationFrame(sample)});
      dispatchEvent(new Event('pointerup'));
    });
    await p.waitForTimeout(1600);
    assert(Math.abs((await box('following')).y-readingTop)<1,'restoring an offscreen paragraph keeps the visible paragraph below the top edge');
    assert(await p.evaluate(y=>verticalSamples.every(r=>Math.abs(r.y-y)<1),readingTop),'reading position stays fixed throughout sideways animation');
    assert(await p.evaluate(()=>verticalSamples.some(r=>r.x>17)&&document.querySelector('#following').getAnimations().length===0),'anchor correction does not freeze its own horizontal animation');
    assert((await box('reading')).width===434 && (await box('following')).right<=378,'obsolete offscreen fitting is removed while the next paragraph fits sideways');
    await p.evaluate(()=>{window.anchorMutations=0;new MutationObserver(r=>anchorMutations+=r.length).observe(document.body,{subtree:true,attributes:true})});
    await p.waitForTimeout(1000);
    assert(await p.evaluate(()=>anchorMutations===0),'scroll anchoring converges without repeated layout work');
    await p.evaluate(()=>{dispatchEvent(new Event('pointerdown'));scrollTo(0,0);dispatchEvent(new Event('pointerup'))});await settled();
    assert(await fitted(),'reverse scrolling restores sideways fitting at the original paragraph top');

    await setup('html{scroll-behavior:smooth}');await send(geometry());await settled();
    await p.evaluate(()=>{dispatchEvent(new Event('pointerdown'));scrollTo({top:document.querySelector('#following').getBoundingClientRect().top+scrollY-8,behavior:'instant'});dispatchEvent(new Event('pointerup'))});
    await settled();
    assert(Math.abs((await box('following')).y-8)<1,'site smooth-scroll CSS cannot animate the reading-position correction');

    await setup(); await send(geometry()); await p.waitForTimeout(280);
    await send(geometry([{x:366,y:20,width:100,height:180}])); await settled();
    assert((await box('reading')).right<=358 && (await box('reading')).y===24,'wider island replaces the sideways target without pushing text down');
    await send(geometry([])); await settled();
    assert((await box('reading')).width===434,'island removal restores the original width');

    await setup(); await p.emulateMedia({reducedMotion:'reduce'}); await send(geometry()); await p.waitForTimeout(300);
    assert(await fitted() && await p.locator('#reading').evaluate(n=>n.getAnimations().length===0),'Reduce Motion fits beside the camera without animation');
    await p.emulateMedia({reducedMotion:'no-preference'});
    await setup(); await send(geometry([region],{reduceMotion:true})); await p.waitForTimeout(300);
    assert(await p.locator('#reading').evaluate(n=>n.getAnimations().length===0),'native Reduce Motion overrides page media preference');
    await setup(); await send(geometry([region],{voiceOver:true})); await settled();
    assert((await box('reading')).width===434,'VoiceOver keeps reading text in its original layout');

    await setup(); await p.evaluate(()=>{const r=document.createRange();r.selectNodeContents(document.querySelector('#reading'));getSelection().addRange(r)});
    await send(geometry()); await settled(); assert((await box('reading')).width===434,'selected text is not refitted');
    await setup(); await p.evaluate(()=>Object.defineProperty(visualViewport,'scale',{configurable:true,value:2}));
    await send(geometry());await settled();assert((await box('reading')).width===434,'pinch zoom defers text fitting');
    await setup('', '<input id="draft" value="unsent">'); await p.locator('#draft').focus();
    await send(geometry());await settled();assert((await box('reading')).width===434 && await p.locator('#draft').inputValue()==='unsent','editing preserves text and unsent form state');
    await setup('p{transform:rotate(.1deg)}');await send(geometry());await settled();
    assert(await p.locator('#reading').evaluate(n=>![...n.attributes].some(a=>a.name.startsWith('data-duo-camera-'))),'author transforms fall back');
    await setup('main{display:grid}'); await send(geometry());await settled();assert((await box('reading')).width===434,'complex flow falls back without reflow');

    await setup(); await send(geometry()); await p.waitForTimeout(50); await send(geometry([],{enabled:false})); await settled();
    assert((await box('reading')).width===434,'disable cancels pending text work');
    await setup(); await send(geometry()); await p.waitForTimeout(50); await p.evaluate(()=>dispatchEvent(new Event('pagehide')));await settled();
    assert((await box('reading')).width===434,'pagehide cancels stale document work');
    await setup(); await send(geometry([{x:NaN,y:20,width:80,height:120}]));await settled();
    assert((await box('reading')).width===434,'nonfinite bridge geometry is rejected');
    await send(geometry(Array(9).fill(region)));await settled();assert((await box('reading')).width===434,'oversized region messages are rejected');

    await setup();await send(geometry());await settled();
    await p.evaluate(()=>{window.changes=0;new MutationObserver(r=>window.changes+=r.length).observe(document.body,{subtree:true,attributes:true,childList:true})});
    await p.waitForTimeout(1000);assert(await p.evaluate(()=>window.changes)===0,'settled text causes no mutation loop');
    await p.evaluate(()=>document.querySelector('#reading').style.width='420px');await settled();
    await send(geometry([],{enabled:false}));assert(await p.locator('#reading').evaluate(n=>n.style.width)==='420px','rollback retains later author width edits');
    assert(await p.evaluate(()=>localStorage.length===0 && sessionStorage.length===0),'layout fitting stores no private page data');

    await setup('main{padding:0;height:1800px}#reading,#following,#heading{display:none}.cluster{position:absolute;right:10px;top:30px;display:flex;gap:8px}.cluster button{width:44px;height:44px;padding:0}', '<div class="cluster"><button id="one">One</button><button id="two">Two</button></div>');
    const one = await box('one'), two = await box('two'); await send(geometry());await settled();
    const movedOne = await box('one'), movedTwo = await box('two');
    assert(movedTwo.x < two.x && Math.abs((movedTwo.x-movedOne.x)-(two.x-one.x))<1,'related controls move as one group');
    await setup('', '<div style="position:fixed;inset:0;z-index:99;background:transparent"></div>');
    await send(geometry()); await settled();
    assert((await box('reading')).width===434,'occluding overlays reject destinations that fail hit testing');
    await setup(); await p.locator('#reading').evaluate(n => { n.textContent='Long '.repeat(1800); n.style.height='90px'; });
    await send(geometry()); await settled();
    assert((await box('reading')).width===434,'oversized text falls back within the scan budget');
    await setup(); await send(geometry([region,{x:376,y:130,width:90,height:110}])); await settled();
    assert((await box('reading')).right<=378 && (await box('reading')).y===24,'stacked status regions do not create vertical displacement');
    await setup(); await send(geometry([{x:8,y:20,width:450,height:150}])); await settled();
    assert((await box('reading')).width===434 && (await box('reading')).y===24,'full-width expanded island falls back instead of pushing text down');
    await setup(); await send(geometry([{x:0,y:20,width:80,height:120}])); await settled();
    assert((await box('reading')).x>=88 && (await box('reading')).y===24,'left-side occlusion fits text to the right');
    await setup(); await p.evaluate(()=>scrollTo(0,40)); await send(geometry()); await settled();
    assert((await box('reading')).right<=378 && (await box('reading')).y===-16, 'partly visible paragraph fits sideways without changing its reading offset');

    await setup();
    await p.locator('#reading').evaluate(n=>{n.innerHTML='Earlier words fill the lines above the visible reading position. '.repeat(4)+'<br><span id="keptWord">Keep</span> these words visible while the paragraph changes width.'});
    await send(geometry());await settled();
    await p.evaluate(()=>{dispatchEvent(new Event('pointerdown'));scrollTo(0,document.querySelector('#keptWord').getBoundingClientRect().top+scrollY)});
    const wordTop=(await box('keptWord')).y;
    for(const regions of [[],[region]]) {
      await p.evaluate(()=>{window.wordSamples=[];const until=performance.now()+1100;requestAnimationFrame(function sample(){wordSamples.push(document.querySelector('#keptWord').getBoundingClientRect().top);if(performance.now()<until)requestAnimationFrame(sample)});dispatchEvent(new Event('pointerup'))});
      await send(geometry(regions));await p.waitForTimeout(1200);
      assert(await p.evaluate(y=>wordSamples.every(top=>Math.abs(top-y)<1),wordTop), regions.length ? 'partly visible text stays anchored throughout refitting' : 'partly visible text stays anchored throughout width restoration');
    }
    await setup();
    await p.evaluate(()=>{
      dispatchEvent(new TouchEvent('touchstart',{touches:[new Touch({identifier:1,target:document.body,clientX:50,clientY:50})]}));
      dispatchEvent(new PointerEvent('pointercancel',{pointerType:'touch'}));
    });
    await send(geometry());await settled();
    assert((await box('reading')).width===434,'touch pointercancel does not release an ongoing finger gesture');
    await p.evaluate(()=>dispatchEvent(new TouchEvent('touchend',{touches:[]})));await settled();
    assert(await fitted(),'touchend releases the deferred fitting');

    await setup('main{position:relative}#following{opacity:0}', '<div id="absolute-follower"><button id="absolute-control" style="position:absolute;right:0;top:300px">Absolute</button></div>');
    const absolute=await box('absolute-control');
    await p.evaluate(()=>{
      window.safetySamples=[];const until=performance.now()+1100;
      requestAnimationFrame(function sample(){
        const a=document.querySelector('#reading').getBoundingClientRect(),b=document.querySelector('#following').getBoundingClientRect();
        safetySamples.push({gap:b.top-a.bottom,opacity:getComputedStyle(document.querySelector('#following')).opacity,
          control:document.querySelector('#absolute-control').getBoundingClientRect().top});
        if(performance.now()<until)requestAnimationFrame(sample);
      });
    });
    await send(geometry());await p.waitForTimeout(1200);
    assert(await p.evaluate(()=>safetySamples.every(s=>s.gap>=0)),'reflow followers never overlap the resized paragraph during animation');
    assert(await p.evaluate(()=>safetySamples.every(s=>Number(s.opacity)===0)),'authored hidden follower opacity is never exposed');
    assert(await p.evaluate(y=>safetySamples.every(s=>Math.abs(s.control-y)<1),absolute.y),'absolute descendant keeps its authored containing block during settling');

    await setup();await p.locator('#reading').evaluate(n=>n.innerHTML='<span style="white-space:nowrap">A nonwrapping span must never escape its newly narrowed paragraph</span> '+n.innerHTML);
    await send(geometry());await settled();
    assert((await box('reading')).width===434,'overflowing nonwrapping text rolls back the attempted fit');
    for (const shellCSS of ['body{overflow-x:hidden}', 'main{overflow-x:hidden}', 'main{overflow-x:clip}',
      'main{display:flex;flex-direction:column;gap:12px}']) {
      await setup(shellCSS);
      const initial = await box('reading'), following = await box('following');
      await send(geometry()); await settled();
      const fit = await box('reading'), next = await box('following');
      assert(fit.right <= 378 && Math.abs(fit.y-initial.y)<1,
        `normal article text fits inside ${shellCSS}`);
      assert(Math.abs((next.y-fit.y-fit.height)-(following.y-initial.y-initial.height))<1,
        `article flow spacing stays intact inside ${shellCSS}`);
      await send(geometry([], {enabled:false}));
      assert(JSON.stringify(await box('reading'))===JSON.stringify(initial),
        `original article geometry restores inside ${shellCSS}`);
    }
    await setup('main{height:140px;padding-bottom:0;overflow-x:hidden}');
    await send(geometry()); await settled();
    assert((await box('reading')).width===434, 'actual clipped or scrolling article shells remain unchanged');
    await setup();
    await p.locator('#reading').evaluate(n=>{
      const shell=document.createElement('section');
      shell.style.cssText='overflow-x:hidden;height:'+n.getBoundingClientRect().height+'px';
      n.style.marginBottom='0';n.before(shell);shell.append(n);
    });
    const bounded = await box('reading');
    await send(geometry()); await settled();
    assert(JSON.stringify(await box('reading'))===JSON.stringify(bounded),
      'fitting rolls back when new wrapping would clip a fixed-height shell');
    await setup('main{display:flex;flex-direction:column-reverse}');
    const reversed = await box('reading');
    await send(geometry([{...region, y:reversed.y+4, height:Math.min(120,reversed.height-8)}])); await settled();
    assert(JSON.stringify(await box('reading'))===JSON.stringify(reversed), 'reverse flex article order remains conservative');
    return {passed:results.length,tests:results};
  } finally { await p.close(); }
};
