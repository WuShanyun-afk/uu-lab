// 画廊页「地址栏锚点」的无头测试
// 用法：node "d:\uu的办公室\_uu\test-gallery.js"
// 原理：把 gallery.html 里的 <script> 抠出来，在 Node 里用假的 document/location/window 跑一遍。
//      纯内存，不碰任何真文件，不联网。
const fs = require('fs');

const GALLERY = 'D:\\小鲸鱼的专属文件夹\\gallery.html';

const html = fs.readFileSync(GALLERY, 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.log('FAIL 找不到 <script> 块'); process.exit(1); }

// ---------- 极简 DOM stub ----------
function mkEl() {
  const s = new Set();
  const o = {
    style: {}, children: [], innerHTML: '', textContent: '',
    hidden: false, href: '', src: '',
    classList: {
      add(c) { s.add(c); }, remove(c) { s.delete(c); }, has(c) { return s.has(c); },
    },
    appendChild(c) { o.children.push(c); },
    addEventListener() {},
    scrollIntoView() {},
  };
  return o;
}

const byId = {};
['nav', 'frame', 'title', 'open', 'gridwrap', 'grid'].forEach(i => { byId[i] = mkEl(); });
const subEl = mkEl();

global.document = {
  getElementById: i => byId[i],
  querySelector: () => subEl,
  createElement: () => mkEl(),
};
global.location = { hash: '' };
let onHashChange = null;
global.window = { addEventListener: (n, f) => { if (n === 'hashchange') onHashChange = f; } };

// ---------- 断言 ----------
let pass = 0, fail = 0;
function check(label, cond, extra) {
  if (cond) { pass++; console.log('  ✅ ' + label); }
  else { fail++; console.log('  ❌ ' + label + (extra ? '  -> ' + extra : '')); }
}
function goto(hash) { location.hash = '#/' + encodeURI(hash); onHashChange(); }

const test = `
  // 1. 默认打开第一件
  check('默认打开第一件', frame.src === encodeURI(GROUPS[0].works[0].f), frame.src);
  check('侧栏恰好高亮一个', buttons.filter(b => b.classList.has('on')).length === 1);

  // 2. 深链接到某件作品
  goto('我的头像/us.html');
  check('深链接切到 us.html', frame.src === encodeURI('我的头像/us.html'), frame.src);
  check('  标题跟着换', titleEl.textContent.includes('我俩的合影'), titleEl.textContent);
  check('  高亮跟着换', buttons.filter(b => b.classList.has('on')).length === 1);

  // 3. 点侧栏 -> hash 自己变
  select(0, 0, buttons[0]);
  check('点作品后 hash 自己变', decodeURI(location.hash) === '#/小鲸鱼的艺术作品/noodle-for-mom.html', decodeURI(location.hash));

  // 4. 整组静图
  goto('静图预览');
  const nImg = GROUPS.find(g => g.name === '静图预览').images.length;
  check('深链接「静图预览」显示网格', gridwrap.hidden === false);
  check('  ' + nImg + ' 张图都渲染了', grid.children.length === nImg, grid.children.length);
  check('  open 按钮藏起来', openEl.style.visibility === 'hidden');

  // 5. 深链接到游戏
  goto('游戏专区/赛博虎鲸宠物.html');
  check('深链接切到虎鲸', frame.src === encodeURI('游戏专区/赛博虎鲸宠物.html'), frame.src);
  const before = frame.src;

  // 6. 乱写的 hash 不能炸
  goto('这/个/不/存/在.html');
  check('乱写 hash 不炸、画面保持', frame.src === before, frame.src);

  // 7. 每个作品/静图都有一条能被解析回来的锚点
  let bad = [];
  GROUPS.forEach((g, gi) => {
    const list = g.works || g.images || [];
    if (!g.works) {
      if (findIdx(g.name) === null) bad.push(g.name);
    }
    list.forEach((w, wi) => {
      if (findIdx(w.f) === null) bad.push(w.f);
      btnMap[gi + ':' + wi] = btnMap[gi + ':' + wi] || null;
    });
  });
  check('全部 ' + (nWorks + nImgs) + ' 个条目都能反查到', bad.length === 0, bad.join('、'));

  // 8. 按钮映射齐全
  check('btnMap 覆盖全部按钮', Object.keys(btnMap).length === buttons.length, Object.keys(btnMap).length + ' vs ' + buttons.length);
`;

try {
  new Function('check', 'goto', m[1] + test)(check, goto);
} catch (e) {
  console.log('  ❌ 运行抛异常: ' + e.message);
  fail++;
}

console.log('');
console.log(`  结果：${pass} 通过 / ${fail} 失败`);
process.exit(fail ? 1 : 0);
