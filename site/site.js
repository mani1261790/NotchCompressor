const appearance = document.querySelector('#appearance');
const system = matchMedia('(prefers-color-scheme: dark)');
const wide = matchMedia('(min-width: 960px) and (min-height: 630px)');
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const figure = document.querySelector('.showcase');
const switcher = document.querySelector('.switcher');
const tour = document.querySelector('.tour');
const buttons = [...document.querySelectorAll('[data-view]')];
const scenes = [...document.querySelectorAll('[data-scene]')];
const notebook = document.querySelector('#notebook');
const settings = document.querySelector('#settings-shot');
let active = 'open';
let lastPath = '';
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
buttons.forEach(b=>b.addEventListener('click',()=>choose(b.dataset.view)));
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
const status = demo.querySelector('.demo-status');
const pause = demo.querySelector('.demo-pause');
const meter = demo.querySelector('progress');
const ja = document.documentElement.lang === 'ja';
const mime = 'application/x-notchcompressor-demo';
let dragging = false, progress = 0, paused = false, timer;
function expand(open) {
  island.classList.toggle('expanded', open); zones.hidden = !open;
  file.setAttribute('aria-expanded', String(open));
  if (!open) zones.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed','false'));
}
function updateProgress() {
  meter.value = progress;
  status.textContent = progress === 100
    ? (ja ? 'デモ完了 — 実際の動画は変更していません。' : 'Demo complete — no real video was changed.')
    : (ja ? (paused ? '一時停止中' : '圧縮中（デモ）') : (paused ? 'Paused' : 'Compressing (demo)')) + ' · ' + progress + '%';
  pause.hidden = progress === 100;
  pause.textContent = paused ? '▶' : 'Ⅱ';
  pause.setAttribute('aria-label', ja ? (paused ? '再開' : '一時停止') : (paused ? 'Resume' : 'Pause'));
}
function start(mode) {
  clearInterval(timer); expand(false); dragging=false; file.hidden=true; queue.hidden=false;
  demo.querySelector('.demo-mode').textContent = zones.querySelector(`[data-mode="${mode}"]`).textContent;
  progress=0;paused=false;updateProgress();
  timer=setInterval(()=>{if(paused)return;progress=Math.min(100,progress+2);updateProgress();if(progress===100)clearInterval(timer);},160);
}
file.addEventListener('click',()=>expand(!island.classList.contains('expanded')));
file.addEventListener('dragstart',event=>{dragging=true;event.dataTransfer.setData(mime,'sample');event.dataTransfer.effectAllowed='copy';});
file.addEventListener('dragend',()=>{dragging=false;expand(false);});
demo.addEventListener('dragover',event=>{
  event.preventDefault();
  if(!dragging){event.dataTransfer.dropEffect='none';return;}
  const r=demo.getBoundingClientRect();
  const near=event.clientY-r.top<r.height*.36;
  expand(near);const zone=event.target.closest('[data-mode]');
  event.dataTransfer.dropEffect=zone?'copy':'none';
  zones.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b===zone)));
});
demo.addEventListener('drop',event=>{
  event.preventDefault();const zone=event.target.closest('[data-mode]');
  if(dragging && zone && event.dataTransfer.getData(mime)==='sample')start(zone.dataset.mode);
  else expand(false);
});
zones.querySelectorAll('button').forEach(button=>button.addEventListener('click',()=>start(button.dataset.mode)));
pause.addEventListener('click',()=>{paused=!paused;updateProgress();});
demo.querySelector('.demo-reset').addEventListener('click',()=>{clearInterval(timer);queue.hidden=true;file.hidden=false;expand(false);file.focus();});
demo.addEventListener('keydown',event=>{if(event.key==='Escape'){expand(false);file.focus();}});
