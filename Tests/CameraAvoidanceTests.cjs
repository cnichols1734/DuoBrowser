async function runCameraTests(page, source) {
  const p = await page.context().newPage();
  let html = '', results=[];
  await p.setViewportSize({width:466,height:678});
  await p.route('**/*', r => r.fulfill({contentType:'text/html',body:html}));
  const assert=(ok,name)=>{if(!ok)throw Error(name);results.push(name)};
  async function setup(extra='',content='') {
    html=`<!doctype html><style>body{margin:0}header{height:120px;background:#eee}button{position:absolute;right:10px;top:30px;width:44px;height:44px}${extra}</style><header><button id="target" onclick="window.clicked=true">Go</button>${content}</header><main><input value="kept"></main>`;
    await p.goto('https://fixture.example/');await p.evaluate(source);
  }
  async function update(enabled=true,regions=[{x:390,y:20,width:66,height:70}],width=466) {
    await p.evaluate(({enabled,regions,width})=>globalThis.__duoCamera.update({enabled,regions,width,height:678}),{enabled,regions,width});
    await p.waitForTimeout(240);
  }
  const position=()=>p.locator('#target').evaluate(n=>({x:n.getBoundingClientRect().x,y:n.getBoundingClientRect().y}));
  try {
    await setup();await update();
    assert((await position()).x<390-44,'collision moves to verified free space');
    await p.locator('#target').click();assert(await p.evaluate(()=>window.clicked)===true,'moved action remains clickable');
    assert(await p.locator('input').inputValue()==='kept','unrelated form is preserved');
    await update(false);assert((await position()).x===412,'disable restores original geometry');
    await setup('button{transform:rotate(2deg)}');const before=await position();await update();assert((await position()).x===before.x,'author transform is preserved');
    await setup();await p.locator('input').focus();await update();assert((await position()).x===412,'editing defers adjustment');
    await setup();await p.evaluate(()=>{const e=document.createElement('div');e.contentEditable='true';document.body.append(e);e.focus()});await update();assert((await position()).x===412,'contenteditable defers adjustment');
    await setup();await p.evaluate(()=>Object.defineProperty(visualViewport,'scale',{value:2}));await update();assert((await position()).x===412,'pinch scale defers adjustment');
    await setup();await update();await update(true,[]);assert((await position()).x===412,'unfold removes obsolete correction');
    await setup('button{width:220px}');await update();assert((await position()).x===236,'wide control falls back');
    await setup('', '<button style="right:90px;top:30px">Other</button><button style="right:10px;top:100px">Below</button>');await update();assert((await position()).x===412,'occupied destinations are not covered');
    await setup();await update();await p.evaluate(()=>document.querySelector('#target').style.color='red');await update(false);
    assert(await p.locator('#target').evaluate(n=>n.style.color)==='red','rollback retains author edits');
    await setup();await update();await p.evaluate(()=>{window.mutations=0;new MutationObserver(r=>window.mutations+=r.length).observe(document.documentElement,{subtree:true,attributes:true,childList:true,characterData:true})});
    await p.waitForTimeout(600);assert(await p.evaluate(()=>window.mutations)===0,'settled camera adapter has no mutation loop');
    await setup();await update(true,[{x:195,y:10,width:33,height:35}],233);
    assert((await position()).x<346,'native point to CSS scale conversion');
    return {passed:results.length,tests:results};
  } finally {await p.close()}
}
if(typeof module!=='undefined')module.exports=runCameraTests;
