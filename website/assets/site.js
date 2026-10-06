const root = document.documentElement;
const preference = matchMedia('(prefers-reduced-motion: reduce)');
const mobile = matchMedia('(max-width: 760px), (max-width: 960px) and (orientation: portrait)');
const compact = matchMedia('(max-height: 619px)');
const sections = {
  hero: document.querySelector('.hero'),
  desktop: document.querySelector('.desktop-section'),
  editor: document.querySelector('.editor-section'),
  quick: document.querySelector('.quick-section'),
  ending: document.querySelector('.continue-section')
};
const parts = {
  masthead: document.querySelector('.hero-masthead'),
  heroLines: [...document.querySelectorAll('.hero-line')],
  heroCopy: document.querySelector('.hero-copy'),
  words: [...document.querySelectorAll('.display-stack span')],
  editor: document.querySelector('.editor-interface'),
  editorCopy: document.querySelector('.editor-copy > p'),
  editorCaption: document.querySelector('.section-caption'),
  laptop: document.querySelector('.physical-laptop'),
  desktopCopy: document.querySelector('.desktop-copy'),
  desktopIndex: document.querySelector('.desktop-index'),
  platform: document.querySelector('.platform-strip'),
  quick: document.querySelector('.quick-interface'),
  quickLines: [...document.querySelectorAll('.quick-copy h2 .line-mask > span')],
  shortcut: document.querySelector('.shortcut-key'),
  quickCaption: document.querySelector('.quick-copy > p'),
  ending: document.querySelector('.continue-row'),
  letters: [...document.querySelectorAll('.continue-word > .letter')]
};
let motionOverride = null;
let metrics = {};
let framePending = false;
let renderedScroll = scrollY;
let keyboardNavigation = false;
const values = new WeakMap();
const clamp = value => Math.min(1, Math.max(0, value));
const ease = value => { const t = clamp(value); return t * t * (3 - 2 * t); };
const phase = (value, start, end) => ease((value - start) / (end - start));
const mix = (from, to, progress) => from + (to - from) * progress;
const isReduced = () => root.dataset.motion === 'reduced';
const isImmersive = () => root.dataset.story === 'immersive';
function set(element, properties) {
  const previous = values.get(element) || {};
  for (const [name, value] of Object.entries(properties)) {
    const next = typeof value === 'number' ? String(Math.round(value * 1000) / 1000) : value;
    if (previous[name] === next) continue;
    element.style.setProperty('--' + name, next);
    previous[name] = next;
  }
  values.set(element, previous);
}
const px = value => Math.round(value * 10) / 10 + 'px';
const typeMeasure = document.createElement('canvas').getContext('2d');
function fitHeroType() {
  for (const line of parts.heroLines) {
    const word = line.querySelector('.hero-word');
    const style = getComputedStyle(word);
    const size = parseFloat(style.fontSize);
    typeMeasure.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const bounds = typeMeasure.measureText(word.textContent);
    const tracking = parseFloat(style.letterSpacing) || 0;
    const width = bounds.actualBoundingBoxLeft + bounds.actualBoundingBoxRight + tracking * (word.textContent.length - 1);
    const height = bounds.actualBoundingBoxAscent + bounds.actualBoundingBoxDescent;
    const sx = line.clientWidth / width;
    const sy = (line.clientHeight - 5) / height;
    const ascent = bounds.fontBoundingBoxAscent ?? size * .88;
    const descent = bounds.fontBoundingBoxDescent ?? size * .12;
    const baseline = (size - ascent - descent) / 2 + ascent;
    set(word, { 'fit-x': sx, 'fit-y': sy, 'ink-x': px(bounds.actualBoundingBoxLeft * sx), 'ink-y': px((bounds.actualBoundingBoxAscent - baseline) * sy) });
  }
}
function measure() {
  for (const [name, element] of Object.entries(sections)) {
    const bounds = element.getBoundingClientRect();
    metrics[name] = { top: bounds.top + scrollY, height: bounds.height, run: Math.max(1, bounds.height - innerHeight) };
  }
  metrics.laptopWidth = parts.laptop.offsetWidth;
  metrics.laptopHeight = parts.laptop.offsetHeight;
  metrics.gutter = parseFloat(getComputedStyle(parts.editor.closest('.scene')).paddingLeft) || 0;
  fitHeroType();
  requestFrame();
}
function locate() {
  const entries = Object.entries(sections);
  const name = entries.findLast(([key]) => metrics[key] && scrollY >= metrics[key].top - innerHeight * .25)?.[0] || 'hero';
  const metric = metrics[name];
  return metric ? { name, progress: clamp((scrollY - metric.top) / (isImmersive() ? metric.run : metric.height)) } : null;
}
function render() {
  framePending = false;
  const still = isReduced();
  renderedScroll = still ? scrollY : mix(renderedScroll, scrollY, .2);
  if (Math.abs(renderedScroll - scrollY) < .2) renderedScroll = scrollY;
  const w = innerWidth;
  const h = innerHeight;
  const small = mobile.matches;
  const pinned = isImmersive();
  const entering = name => clamp((renderedScroll + h * .75 - metrics[name].top) / (metrics[name].run + h * .75));
  const flowing = name => phase((renderedScroll + h - metrics[name].top) / (h + metrics[name].height), .1, .65);
  for (const [name, section] of Object.entries(sections)) {
    section.querySelector('.scene').classList.toggle('is-near', scrollY + h > metrics[name].top && scrollY < metrics[name].top + metrics[name].height);
  }
  if (!pinned) {
    parts.desktopIndex.inert = false;
    const editor = still ? 1 : flowing('editor');
    const desktop = still ? 1 : flowing('desktop');
    const quick = still ? 1 : flowing('quick');
    set(parts.editor, { tx: px((1 - editor) * w * .16), ty: px((1 - editor) * 90), rot: (1 - editor) * 5 + 'deg', scale: mix(.91, 1, editor), alpha: mix(.5, 1, editor) });
    set(parts.laptop, { ty: px((1 - desktop) * 85), scale: mix(.85, 1, desktop) });
    set(parts.quick, { tx: '0px', ty: px((1 - quick) * 120), rot: (1 - quick) * 4 + 'deg', scale: mix(.65, 1, quick), alpha: quick });
    parts.letters.forEach((letter, index) => {
      const t = still ? 1 : phase(flowing('ending'), .03 + index * .025, .4 + index * .025);
      set(letter, { ty: (1 - t) * 125 + '%', alpha: t });
    });
  } else {
    const hero = clamp((renderedScroll - metrics.hero.top) / h);
    const exit = phase(hero, .05, .9);
    set(parts.masthead, { tx: '0px', ty: px(-h * .08 * exit), alpha: 1 - phase(hero, .35, 1) });
    set(parts.heroCopy, { ty: px(-h * .04 * exit), alpha: 1 - phase(hero, .35, 1) });

    const editor = entering('editor');
    parts.words.forEach((word, index) => {
      const t = phase(editor, .025 + index * .075, .22 + index * .075);
      set(word, { tx: px(-w * .055 * index * (1 - t)), ty: px(h * .24 * (1 - t) - 25 * phase(editor, .85, 1)), alpha: t });
    });
    const editorIn = phase(editor, .15, .65);
    const editorTop = small ? Math.min(h * .48, 395) : h * .035;
    set(parts.editor, {
      tx: px(small ? mix(w * .4, w * .03 - metrics.gutter, editorIn) : mix(w * 1.08, w * .355 - metrics.gutter, editorIn)),
      ty: px(mix(h * .48, editorTop, editorIn)),
      scale: mix(.8, 1, editorIn), rot: mix(8, 0, editorIn) + 'deg'
    });
    const editorCopy = phase(editor, .25, .55);
    set(parts.editorCopy, { ty: px((1 - editorCopy) * 40), alpha: editorCopy });
    const caption = phase(editor, .4, .7);
    set(parts.editorCaption, { ty: px((1 - caption) * 25), alpha: caption });

    const desktop = entering('desktop');
    const camera = phase(desktop, small ? .38 : .2, .94);
    const bw = metrics.laptopWidth;
    const bh = metrics.laptopHeight;
    const finalScale = small ? 2.1 : Math.min(w * .94 / (bw * .7023), h * .88 / (bh * .6251));
    const finalX = (w - bw * .7023 * finalScale) / 2 - bw * .1492 * finalScale;
    const finalY = (h - bh * .6251 * finalScale) / 2 - bh * .1197 * finalScale;
    set(parts.laptop, { tx: px(mix(small ? -w * .02 : w * .32, finalX, camera)), ty: px(mix(small ? h * .34 : h * .30, finalY, camera)), scale: mix(small ? .88 : .66, finalScale, camera), rot: mix(small ? -3 : -5, 0, camera) + 'deg' });
    const desktopOut = phase(desktop, .38, .65);
    parts.desktopIndex.inert = desktopOut > .98;
    set(parts.desktopCopy, { ty: px(-100 * desktopOut), alpha: 1 - desktopOut });
    set(parts.desktopIndex, { ty: px(70 * desktopOut), alpha: 1 - desktopOut });
    set(parts.platform, { alpha: 1 - phase(desktop, .5, .8) });

    const quick = entering('quick');
    parts.quickLines.forEach((line, index) => {
      const t = phase(quick, .02 + index * .09, .27 + index * .09);
      set(line, { ty: px((1 - t) * 100), alpha: t });
    });
    const popup = phase(quick, .2, .76);
    set(parts.quick, { tx: px(small ? mix(w * .18, w * .075, popup) : mix(w * .76, w * .49, popup)), ty: px(small ? mix(h * .8, h * .53, popup) : mix(h * .7, h * .16, popup)), scale: mix(.52, 1, popup), rot: mix(9, 0, popup) + 'deg', alpha: phase(quick, .18, .39) });
    const pulse = Math.sin(phase(quick, .23, .60) * Math.PI);
    set(parts.shortcut, { scale: 1 + pulse * .07, halo: px(pulse * 13) });
    const quickCopy = phase(quick, .25, .52);
    set(parts.quickCaption, { ty: px((1 - quickCopy) * 25), alpha: quickCopy });

    const ending = clamp((renderedScroll + h * .28 - metrics.ending.top) / (metrics.ending.run + h * .28));
    parts.letters.forEach((letter, index) => {
      const t = phase(ending, .03 + index * .035, .34 + index * .035);
      set(letter, { ty: (1 - t) * 130 + '%', rot: (1 - t) * 9 + 'deg', alpha: t });
    });
    const endCopy = phase(ending, .4, .72);
    set(parts.ending, { ty: px((1 - endCopy) * 50), alpha: endCopy });
  }
  if (renderedScroll !== scrollY) requestFrame();
}
function requestFrame() {
  if (framePending) return;
  framePending = true;
  requestAnimationFrame(render);
}
function applyMotion(preserve = false) {
  const previous = preserve ? locate() : null;
  root.dataset.motion = (motionOverride ?? !preference.matches) ? 'full' : 'reduced';
  root.dataset.story = !isReduced() && !compact.matches ? 'immersive' : 'flow';
  const toggle = document.querySelector('.motion-toggle');
  toggle.setAttribute('aria-pressed', String(isReduced()));
  toggle.textContent = isReduced() ? '开启动效' : '减少动效';
  measure();
  if (previous) {
    const next = metrics[previous.name];
    scrollTo({ top: next.top + previous.progress * (isImmersive() ? next.run : Math.max(0, next.height - innerHeight)), behavior: 'instant' });
  }
  renderedScroll = scrollY;
  requestFrame();
}
function jump(hash, behavior = 'smooth') {
  const id = hash.replace('#', '');
  const key = id === 'main' || id === 'library' ? 'hero' : id;
  if (!sections[key]) return;
  const metric = metrics[key];
  const anchorPhase = key === 'ending' ? .8 : key === 'desktop' ? .08 : .52;
  const position = isImmersive() && key !== 'hero' ? metric.top + metric.run * anchorPhase : metric.top;
  scrollTo({ top: position, behavior: isReduced() ? 'instant' : behavior });
  if (behavior === 'instant') renderedScroll = scrollY;
  requestFrame();
}
document.querySelectorAll('a[href^="#"]').forEach(link => link.addEventListener('click', event => {
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const hash = link.getAttribute('href');
  if (!document.querySelector(hash)) return;
  event.preventDefault();
  jump(hash, 'smooth');
}));
document.querySelector('.motion-toggle').addEventListener('click', () => { motionOverride = isReduced(); applyMotion(true); });
preference.addEventListener('change', () => { if (motionOverride === null) applyMotion(true); });
compact.addEventListener('change', () => applyMotion(true));
addEventListener('scroll', requestFrame, { passive: true });
addEventListener('resize', measure, { passive: true });
addEventListener('pageshow', () => {
  measure();
  const initialSection = location.hash || '#main';
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
  requestAnimationFrame(() => jump(initialSection, 'instant'));
});
addEventListener('keydown', event => { if (event.key === 'Tab') keyboardNavigation = true; });
addEventListener('pointerdown', () => { keyboardNavigation = false; }, { passive: true });
addEventListener('focusin', event => {
  if (!keyboardNavigation || !isImmersive()) return;
  const section = event.target.closest('.story-track');
  const entry = Object.entries(sections).find(([, element]) => element === section);
  if (!entry) return;
  const metric = metrics[entry[0]];
  const p = (scrollY - metric.top) / metric.run;
  if (entry[0] === 'desktop' ? p > .25 || p < 0 : p < .3 || p > .9) jump('#' + section.id, 'instant');
});
document.fonts.ready.then(measure);
document.querySelectorAll('img').forEach(img => { if (!img.complete) img.addEventListener('load', measure, { once: true }); });
applyMotion();
requestAnimationFrame(() => { root.dataset.ready = 'true'; });
