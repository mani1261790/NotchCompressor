const appearance = document.querySelector('#appearance');
const system = matchMedia('(prefers-color-scheme: dark)');
const wide = matchMedia('(min-width: 960px) and (min-height: 630px)');
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const figure = document.querySelector('.showcase');
const tour = document.querySelector('.tour');
const scenes = [...document.querySelectorAll('[data-scene]')];
let active = 'open';
function draw(){
  const value = document.querySelector('.appearance-value');
  value.textContent = appearance.selectedOptions[0].textContent;
  value.hidden = false;
  const theme = appearance.value === 'auto' ? (system.matches ? 'dark' : 'light') : appearance.value;
  if(appearance.value==='auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme=theme;
  document.querySelector('.device-frame').src='assets/lunamo-laptop-'+theme+'-v2.png';
  scenes.forEach(a=>a.classList.toggle('current',a.dataset.scene===active));
}
function choose(view){active=view;draw()}
appearance.value=document.documentElement.dataset.theme||'auto';
appearance.addEventListener('change',()=>{
  try{localStorage.setItem('notchcompressor-appearance',appearance.value)}catch{}
  draw();
});
system.addEventListener('change',draw);
const slot = tour.querySelector('.screen-slot');
let geometry;
let needsMeasure = true;
let lastIntro = -1;
let frame = 0;
function measure() {
  const stacked = innerWidth < 960 && innerHeight >= 630 && figure.clientWidth * .6 + 270 < innerHeight;
  const follows = (wide.matches || stacked) && !reduce.matches;

  tour.classList.toggle('following', follows);
  const headerBottom = document.querySelector('header').getBoundingClientRect().bottom;
  const viewport = window.visualViewport;
  const usableTop = Math.max(headerBottom, viewport?.offsetTop || 0);
  const viewportBottom = (viewport?.offsetTop || 0) + (viewport?.height || innerHeight);
  const figureHeight = figure.offsetHeight;
  const center = (usableTop + viewportBottom) / 2;
  if (wide.matches && follows) {
    const pinTop = Math.max(usableTop + 12, center - figureHeight / 2);
    const last = scenes.at(-1).getBoundingClientRect();
    const tourTop = tour.getBoundingClientRect().top;
    figure.style.setProperty('--preview-pin-top', pinTop + 'px');
    // End the sticky containing block at the final explanation + half the Mac.
    // Native sticky scrolling now releases it; scroll events never change top.
    tour.style.setProperty('--tour-height',
      Math.max(figureHeight, last.top + last.height / 2 - tourTop + figureHeight / 2) + 'px');
  } else {
    figure.style.removeProperty('--preview-pin-top');
    tour.style.removeProperty('--tour-height');
  }
  const target = slot.getBoundingClientRect();
  const pinTop = parseFloat(getComputedStyle(figure).top) || 80;
  const viewportWidth = document.documentElement.clientWidth;
  const openingWidth = viewportWidth >= 960
    ? Math.min(viewportWidth * .8, 1152)
    : Math.min(viewportWidth * .94, target.width * 1.15);
  geometry = {
    follows, stacked, center,
    distance: Math.max(1, scrollY + tour.getBoundingClientRect().top - pinTop),
    scale: Math.max(1, openingWidth / Math.max(1, target.width)),
    x: (viewportWidth - target.width) / 2 - target.left,
    sceneY: stacked ? Math.max(innerHeight * .68, pinTop + figureHeight + 90) : center,
    scenes: scenes.map(el => {
      const r = el.getBoundingClientRect();
      return {el, center: scrollY + r.top + r.height / 2};
    })
  };
  lastIntro = -1;
  needsMeasure = false;
}
function update() {
  frame = 0;
  if (needsMeasure) measure();
  const y = scrollY;
  const t = reduce.matches ? 1 : Math.min(1, Math.max(0, y / geometry.distance));
  // Once docked, no animation styles or layout properties are touched on scroll.
  if (t !== lastIntro) {
    const landed = t * t * (3 - 2 * t);
    const remaining = 1 - landed;
    tour.style.setProperty('--intro-x', geometry.x * remaining + 'px');
    tour.style.setProperty('--intro-scale', 1 + remaining * (geometry.scale - 1));
    tour.style.setProperty('--shell-y', remaining * 54 + 'px');
    tour.style.setProperty('--shell-opacity', landed);
    tour.style.setProperty('--copy-opacity', Math.max(0, (landed - .45) / .55));
    lastIntro = t;
  }
  if (geometry.follows) {
    const focus = y + geometry.sceneY;
    const scene = geometry.scenes.reduce((best, item) =>
      Math.abs(item.center - focus) < Math.abs(best.center - focus) ? item : best);
    if (scene.el.dataset.scene !== active) choose(scene.el.dataset.scene);
  }
}
const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
const invalidate = () => { needsMeasure = true; schedule(); };
addEventListener('scroll', schedule, {passive:true});
addEventListener('resize', invalidate, {passive:true});
window.visualViewport?.addEventListener('resize', invalidate, {passive:true});
for (const q of [wide, reduce]) q.addEventListener('change', invalidate);

draw(); update(); document.fonts.ready.then(invalidate);

// Local interaction simulation. Never read or upload a visitor's files.
const demo = document.querySelector('.demo-screen');
const file = demo.querySelector('.demo-file');
const island = demo.querySelector('.demo-notch');
const zones = demo.querySelector('.demo-zones');
const queue = demo.querySelector('.demo-queue');
const status = demo.querySelector('.demo-state');
const percent = demo.querySelector('.demo-percent');
const pause = demo.querySelector('.demo-pause');
const meter = demo.querySelector('progress');
const ja = document.documentElement.lang === 'ja';
let gesture = null;
let suppressClick = false;
let dragging = false, progress = 0, paused = false, timer;
function expand(open) {
  island.classList.toggle('expanded', open); zones.hidden = !open;
  file.setAttribute('aria-expanded', String(open));
  if (!open) zones.querySelectorAll('button').forEach(b=>b.setAttribute('data-active','false'));
}
function updateProgress() {
  if(progress===100 && document.activeElement===pause)demo.querySelector('.demo-reset').focus({preventScroll:true});
  meter.value = progress;
  demo.querySelector('.demo-job').hidden = progress === 100;
  demo.querySelector('.demo-empty').hidden = progress !== 100;
  meter.hidden = progress === 100;
  const stateText = progress === 100
    ? (ja ? 'デモ完了 — 実際の動画は変更していません。' : 'Demo complete — no real video was changed.')
    : (ja ? (paused ? '一時停止中' : '圧縮中（デモ）') : (paused ? 'Paused' : 'Compressing (demo)'));
  // Announce state changes, not each 160 ms progress tick. The labeled native
  // progress element remains available when someone wants the current value.
  if(status.textContent !== stateText)status.textContent = stateText;
  percent.textContent = progress === 100 ? '' : ' · ' + progress + '%';
  pause.hidden = progress === 100;
  pause.textContent = paused ? '▶' : 'Ⅱ';
  pause.setAttribute('aria-label', ja ? (paused ? '再開' : '一時停止') : (paused ? 'Resume' : 'Pause'));
}
function start(mode) {
  const focusControls=zones.contains(document.activeElement);
  clearInterval(timer); expand(false); dragging=false; file.hidden=true; queue.hidden=false;
  demo.querySelector('.demo-mode').textContent = zones.querySelector(`[data-mode="${mode}"]`).textContent;
  progress=0;paused=false;updateProgress();
  if(focusControls)pause.focus({preventScroll:true});
  timer=setInterval(()=>{if(paused)return;progress=Math.min(100,progress+2);updateProgress();if(progress===100)clearInterval(timer);},160);
}
file.addEventListener('click',()=>{
  if(suppressClick){suppressClick=false;return;}
  const open=!island.classList.contains('expanded');
  expand(open);
  if(open)zones.querySelector('[data-mode="both"]').focus({preventScroll:true});
});
// A pointer gesture keeps the sample under the finger/mouse and works on touch
// devices too. It never accepts a real file or relies on browser drag ghosts.
file.draggable=false;
file.addEventListener('pointerdown',event=>{
  if(!event.isPrimary || event.button!==0)return;
  suppressClick=false;
  gesture={id:event.pointerId,x:event.clientX,y:event.clientY,moved:false,
    scale:file.getBoundingClientRect().width/file.offsetWidth};
  file.setPointerCapture(event.pointerId);
});
function zoneAt(x,y){
  if(zones.hidden)return null;
  // Hit targets use the expanded geometry immediately. A fast drop must not
  // miss just because the visual width transition has not finished yet.
  const r=demo.getBoundingClientRect();
  const left=r.left+r.width*.12, top=r.top+r.width*.045;
  const width=r.width*.76, bottom=r.top+r.width*.21;
  if(x<left || x>left+width || y<top || y>bottom)return null;
  return zones.querySelectorAll('button')[Math.min(2,Math.floor((x-left)/width*3))];
}
file.addEventListener('pointermove',event=>{
  if(!gesture || gesture.id!==event.pointerId)return;
  const dx=event.clientX-gesture.x,dy=event.clientY-gesture.y;
  if(!gesture.moved && Math.hypot(dx,dy)<5)return;
  gesture.moved=true;dragging=true;
  file.classList.add('dragging');
  file.style.transform=`translate(${dx/gesture.scale}px,${dy/gesture.scale}px)`;
  const r=demo.getBoundingClientRect();
  expand(event.clientX>=r.left && event.clientX<=r.right && event.clientY>=r.top && event.clientY<r.top+r.height*.36);
  const zone=zoneAt(event.clientX,event.clientY);
  zones.querySelectorAll('button').forEach(b=>b.setAttribute('data-active',String(b===zone)));
});
function endGesture(event,cancelled=false){
  if(!gesture || gesture.id!==event.pointerId)return;
  const moved=gesture.moved;
  const zone=moved && !cancelled ? zoneAt(event.clientX,event.clientY) : null;
  gesture=null;dragging=false;file.style.transform='';file.classList.remove('dragging');
  if(file.hasPointerCapture(event.pointerId))file.releasePointerCapture(event.pointerId);
  if(moved){suppressClick=true;if(zone)start(zone.dataset.mode);else expand(false);}
}
file.addEventListener('pointerup',event=>endGesture(event));
file.addEventListener('pointercancel',event=>endGesture(event,true));
file.addEventListener('lostpointercapture',event=>endGesture(event,true));
file.addEventListener('dragstart',event=>event.preventDefault());
demo.addEventListener('dragover',event=>{event.preventDefault();event.dataTransfer.dropEffect='none';});
demo.addEventListener('drop',event=>event.preventDefault());
zones.querySelectorAll('button').forEach(button=>button.addEventListener('click',()=>start(button.dataset.mode)));
pause.addEventListener('click',()=>{paused=!paused;updateProgress();});
demo.querySelector('.demo-reset').addEventListener('click',()=>{clearInterval(timer);suppressClick=false;queue.hidden=true;file.hidden=false;expand(false);file.focus();});
demo.addEventListener('keydown',event=>{
  if(event.key==='Escape' && !file.hidden){
    event.preventDefault();
    if(gesture)endGesture({pointerId:gesture.id},true);
    expand(false);file.focus({preventScroll:true});
  }
});
zones.addEventListener('keydown',event=>{
  if(!['ArrowLeft','ArrowRight'].includes(event.key))return;
  const buttons=[...zones.querySelectorAll('button')];
  const index=buttons.indexOf(document.activeElement);
  if(index<0)return;
  event.preventDefault();
  buttons[(index+(event.key==='ArrowRight'?1:-1)+buttons.length)%buttons.length].focus({preventScroll:true});
});
