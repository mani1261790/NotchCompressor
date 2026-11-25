const appearance = document.querySelector('#appearance');
const system = matchMedia('(prefers-color-scheme: dark)');
function draw(){
  const value = document.querySelector('.appearance-value');
  value.textContent = appearance.selectedOptions[0].textContent;
  value.hidden = false;
  const theme = appearance.value === 'auto' ? (system.matches ? 'dark' : 'light') : appearance.value;
  if(appearance.value==='auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme=theme;
  document.querySelector('.device-frame').src='assets/lunamo-laptop-'+theme+'-v2.png';
}
appearance.value=document.documentElement.dataset.theme||'auto';
appearance.addEventListener('change',()=>{
  try{localStorage.setItem('notchcompressor-appearance',appearance.value)}catch{}
  draw();
});
system.addEventListener('change',draw);
draw();

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
  demo.querySelector('.demo-card').hidden = progress === 100;
  demo.querySelector('.demo-gear').hidden = progress === 100;
  demo.querySelector('.demo-empty').hidden = progress !== 100;
  meter.hidden = progress === 100;
  const stateText = progress === 100
    ? (ja ? 'デモ完了 — 実際の動画は変更していません。' : 'Demo complete — no real video was changed.')
    : (ja ? (paused ? '一時停止中' : '圧縮中（デモ）') : (paused ? 'Paused' : 'Compressing (demo)'));
  // Announce state changes, not each 160 ms progress tick. The labeled native
  // progress element remains available when someone wants the current value.
  if(status.textContent !== stateText)status.textContent = stateText;
  percent.textContent = progress === 100 ? '' : progress + '%';
  demo.querySelector('.demo-phase').textContent = ja ? (paused ? '一時停止中' : '圧縮中') : (paused ? 'Paused' : 'Compressing');
  demo.querySelector('.demo-counts').textContent = ja ? `実行中 ${!paused && progress<100 ? 1:0}件 · 一時停止 ${paused ? 1:0}件 · 待機 0件` : `Running: ${!paused && progress<100 ? 1:0} · Paused: ${paused ? 1:0} · Waiting: 0`;
  demo.querySelector('.demo-remove').hidden = !paused || progress===100;
  demo.querySelector('.demo-paused-hint').hidden = !paused || progress===100;
  demo.querySelector('.demo-pin').textContent = paused ? '≡' : '⌖';
  pause.hidden = progress === 100;
  pause.textContent = paused ? '▶' : 'Ⅱ';
  pause.setAttribute('aria-label', ja ? (paused ? '再開' : '一時停止') : (paused ? 'Resume' : 'Pause'));
}
function start(mode) {
  const focusControls=zones.contains(document.activeElement);
  clearInterval(timer); expand(false); dragging=false; file.hidden=true; queue.hidden=false;
  demo.querySelector('.demo-mode').textContent = zones.querySelector(`[data-mode="${mode}"]`).getAttribute('aria-label') + ' · 430.3 MB';
  const settings=demo.querySelector('.demo-settings');
  settings.open=false;
  settings.querySelector('p').textContent=ja
    ? '標準 · ' + (mode==='audio' ? '映像はそのまま' : '映像 HEVC') + ' · ' + (mode==='video' ? '音声はそのまま' : '音声 AAC')
    : 'Balanced · ' + (mode==='audio' ? 'Keep video' : 'HEVC video') + ' · ' + (mode==='video' ? 'Keep audio' : 'AAC audio');
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
  const left=r.left+r.width*(1-480/1380)/2, top=r.top+r.width*(30/1380);
  const width=r.width*(480/1380), bottom=r.top+r.width*(178/1380);
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
  expand(Math.abs(event.clientX-(r.left+r.width/2))<=r.width*(240/1380) && event.clientY>=r.top && event.clientY<r.top+r.width*(178/1380));
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
function resetDemo(){clearInterval(timer);suppressClick=false;queue.hidden=true;file.hidden=false;expand(false);file.focus({preventScroll:true});}
demo.querySelector('.demo-reset').addEventListener('click',resetDemo);
demo.querySelector('.demo-remove').addEventListener('click',()=>{if(paused)resetDemo();});
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

demo.querySelector('.demo-gear').addEventListener('click',()=>{const details=demo.querySelector('.demo-settings');details.open=!details.open;if(!demo.querySelector('.demo-card').hidden)details.querySelector('summary').focus({preventScroll:true});});
