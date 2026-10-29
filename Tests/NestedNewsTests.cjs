const fs = require('node:fs');
module.exports = async function (page, source) {
  const p=await page.context().newPage(), tests=[];
  const check=(v,n)=>{if(!v)throw Error(n);tests.push(n)};
  const html=fs.readFileSync(__dirname+'/Fixtures/nested-news.html','utf8');
  await p.setViewportSize({width:466,height:678});
  await p.route('**/*',r=>r.fulfill({contentType:'text/html',body:html}));
  const box=id=>p.locator('#'+id).evaluate(n=>{const r=n.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,width:r.width,height:r.height}});
  const send=(enabled=true)=>p.evaluate(enabled=>__duoCamera.update({enabled,width:466,height:678,regions:[{x:382,y:0,width:84,height:220}]}),enabled);
  try {
    await p.goto('https://nested.example/');await p.evaluate(source);
    const before=await box('reading'),sign=await box('signin'),drawer=await box('closed-menu'),widget=await box('fixed-widget');
    await send();await p.waitForTimeout(900);
    check((await box('signin')).right<=374 && (await box('signin')).y===sign.y,'sticky header control moves sideways without moving its header');
    check((await box('reading')).right<=374 && Math.abs((await box('reading')).y-before.y)<1,'deep article inside grid shells fits without lifting text');
    check(JSON.stringify(await box('fixed-widget'))===JSON.stringify(widget),'complex following content preserves its fixed descendant while text fits');
    check(JSON.stringify(await box('closed-menu'))===JSON.stringify(drawer),'closed offcanvas navigation retains its original geometry');
    for(let i=0;i<3;i++){await p.evaluate(()=>dispatchEvent(new Event('scroll')));await p.waitForTimeout(850)}
    check((await box('signin')).right<=374,'sticky header stays fitted across repeated settling passes');
    await p.locator('#signin').click();check(new URL(p.url()).hash==='#signin-result','adapted sticky header action remains clickable');
    await p.locator('#article-link').click();check(new URL(p.url()).hash==='#link-result','adapted nested article link remains clickable');
    await p.evaluate(()=>{dispatchEvent(new Event('pointerdown'));scrollTo(0,document.getElementById('following').getBoundingClientRect().top+scrollY-90)});
    const top=(await box('following')).y;
    await p.evaluate(()=>dispatchEvent(new Event('pointerup')));await p.waitForTimeout(1000);
    check(Math.abs((await box('following')).y-top)<1 && (await box('following')).right<=374,'nested article retains visible reading position after another scroll');
    check((await box('signin')).right<=374,'sticky header remains fitted after article scrolling');
    await p.evaluate(()=>__duoCamera.update({enabled:true,width:466,height:678,regions:[]}));await p.waitForTimeout(950);
    check(await p.evaluate(()=>![...document.querySelector('.toolbar').attributes].some(a=>a.name.startsWith('data-duo-camera-'))),'removing the island releases owned header sizing');
    await send(false);check((await box('reading')).width===before.width && (await box('signin')).x===sign.x,'original layout restores nested article and sticky header');
    await p.evaluate(()=>scrollTo(0,document.getElementById('reading').getBoundingClientRect().bottom+scrollY-45));
    const followingTop=(await box('following')).y;
    await send();await p.waitForTimeout(950);
    check((await box('following')).right<=374 && Math.abs((await box('following')).y-followingTop)<1 && (await box('reading')).width===before.width,'a paragraph hidden by sticky chrome cannot roll back the visible paragraph fit');
    await send(false);
    await p.evaluate(()=>{
      const n=document.getElementById('reading');
      n.innerHTML='Earlier words fill the lines above the visible reading position. '.repeat(3)+'<br><span id="keptWord">Keep</span> these visible words while the earlier lines rewrap beside the camera.';
      scrollTo(0,document.getElementById('keptWord').getBoundingClientRect().top+scrollY-56);
    });
    const wordTop=(await box('keptWord')).y;
    await send();await p.waitForTimeout(950);
    check((await box('reading')).right<=374 && Math.abs((await box('keptWord')).y-wordTop)<1,'visible word stays anchored below site sticky chrome during refitting');
    return {passed:tests.length,tests};
  } finally {await p.close()}
};
