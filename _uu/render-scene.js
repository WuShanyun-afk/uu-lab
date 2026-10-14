// 把 像素咖啡厅.html 的画布在 Node 里"画"出来，存成 PNG，好让我亲眼看看像素画对不对
// 原理：实现一个只有 fillRect 的假 canvas + 一个手写 PNG 编码器（zlib 是 Node 自带的）
// 用法：node render-scene.js <分钟数> [输出路径]
const fs = require('fs');
const zlib = require('zlib');

const GAME = 'D:\\uu的办公室\\像素咖啡厅\\像素咖啡厅.html';
const W = 320, H = 180;

/* ---------- 假 canvas ---------- */
const noop = () => { };
function makeCtx(buf) {
  let fill = '#000000';
  return {
    set fillStyle(v) { fill = v; },
    get fillStyle() { return fill; },
    imageSmoothingEnabled: false,
    fillRect(x, y, w, h) {
      const r = parseInt(fill.slice(1, 3), 16);
      const g = parseInt(fill.slice(3, 5), 16);
      const b = parseInt(fill.slice(5, 7), 16);
      x = Math.round(x); y = Math.round(y);
      w = Math.round(w); h = Math.round(h);
      for (let j = y; j < y + h; j++) {
        if (j < 0 || j >= H) continue;
        for (let i = x; i < x + w; i++) {
          if (i < 0 || i >= W) continue;
          const p = (j * W + i) * 4;
          buf[p] = r; buf[p + 1] = g; buf[p + 2] = b; buf[p + 3] = 255;
        }
      }
    },
  };
}

/* ---------- PNG 编码（真·手搓） ---------- */
let CRC_T = null;
function crcTable() {
  if (CRC_T) return CRC_T;
  CRC_T = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    CRC_T[n] = c;
  }
  return CRC_T;
}
function crc32(buf) {
  const t = crcTable();
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) c = t[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const body = Buffer.concat([t, data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}
function encodePNG(rgba, w, h) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    Buffer.from(rgba.buffer, y * stride, stride).copy(raw, y * (stride + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
function scaleUp(rgba, w, h, k) {
  const out = new Uint8ClampedArray(w * k * h * k * 4);
  for (let y = 0; y < h * k; y++) {
    for (let x = 0; x < w * k; x++) {
      const sp = ((y / k | 0) * w + (x / k | 0)) * 4;
      const dp = (y * w * k + x) * 4;
      out[dp] = rgba[sp]; out[dp + 1] = rgba[sp + 1];
      out[dp + 2] = rgba[sp + 2]; out[dp + 3] = rgba[sp + 3];
    }
  }
  return out;
}

/* ---------- 跑起来 ---------- */
const html = fs.readFileSync(GAME, 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.log('找不到 script'); process.exit(1); }

const buf = new Uint8ClampedArray(W * H * 4);
const fakeCtx = makeCtx(buf);
const fakeCv = {
  width: W, height: H, getContext: () => fakeCtx,
  addEventListener: noop, style: new Proxy({}, { get: () => '', set: () => true }),
};

// 极简 DOM
const fakeEl = new Proxy({}, {
  get: (t, k) => {
    if (k === 'style') return new Proxy({}, { get: () => '', set: () => true });
    if (k === 'classList') return { add: noop, remove: noop, toggle: noop, contains: () => false };
    if (k === 'getContext') return () => fakeCtx;
    if (k === 'appendChild' || k === 'addEventListener' || k === 'setAttribute') return noop;
    if (k === 'children') return [];
    return () => {};
  },
  set: () => true,
});
global.document = {
  getElementById: (id) => (id === 'cv' ? fakeCv : fakeEl),
  createElement: () => fakeEl,
  querySelector: () => fakeEl,
  querySelectorAll: () => [],
  addEventListener: noop,
};
global.window = { addEventListener: noop, innerWidth: 960, innerHeight: 540 };
global.requestAnimationFrame = noop;
global.performance = { now: () => 0 };

const minutes = parseFloat(process.argv[2] || '540');
const outPath = process.argv[3] || require('path').join(require('os').tmpdir(), 'pixelcafe-scene.png');
const mode = process.argv[4] || 'scene';

try {
  new Function(m[1] + `
;globalThis.__probe = {
  drawScene, drawAll, drawCat, drawBubble, drawTables, drawMachine, drawTray, drawBarista,
  FURS, SPR, px, C, CFG, DRINKS, SIZES, TEMPS,
  setG: function(v){ G = v; }, getG: function(){ return G; },
  setSceneTime: function(v){ sceneTime = v; },
  freshGame: freshGame,
};`)();
} catch (e) {
  console.log('脚本抛异常：', e.message);
  process.exit(1);
}

// 先铺一层底色，避免透明
for (let i = 0; i < buf.length; i += 4) { buf[i] = 11; buf[i + 1] = 8; buf[i + 2] = 16; buf[i + 3] = 255; }

const P = globalThis.__probe;

if (mode === 'cats') {
  // 精灵表：每种配色 × 三种姿势，检查点阵有没有画歪
  P.px(0, 0, W, H, '#241a24');
  const poses = ['sit', 'walk1', 'walk2'];
  P.FURS.forEach((fur, i) => {
    poses.forEach((pose, j) => {
      const x = 8 + j * 40, y = 8 + i * 26;
      P.px(x - 2, y - 2, 18, 18, '#150f14');
      P.drawCat(x, y, fur, pose, false);
    });
  });
  // 顺便检查每行长度是否一致
  Object.keys(P.SPR).forEach(k => {
    const lens = [...new Set(P.SPR[k].map(r => r.length))];
    console.log(`  ${k}: ${P.SPR[k].length} 行, 行长 ${lens.join('/')} ${lens.length === 1 ? 'OK' : '<<< 行长不齐!'}`);
  });
} else if (mode === 'full') {
  // 完整一帧：场景 + 客人 + 气泡 + 机器 + 出杯口
  const g = P.freshGame();
  g.min = minutes;
  g.rep = 62;
  g.lv.machine = 2;
  const D = id => P.DRINKS.find(d => d.id === id);
  const mk = (slot, drink, size, temp, pat, fur) => ({
    id: slot, slot: slot, fur: fur, name: 'x', drink: drink, size: size, temp: temp,
    x: P.CFG.TABLE_X[slot], y: P.CFG.SEAT_Y, tx: P.CFG.TABLE_X[slot], seatY: P.CFG.SEAT_Y,
    state: 'sit', anim: 0, patience: pat, patienceMax: 34, wait: 0, pay: 0,
  });
  g.tables[0] = true; g.tables[1] = true; g.tables[2] = true;
  g.guests = [
    mk(0, D('latte'), 1, 0, 28, P.FURS[0]),
    mk(1, D('americano'), 2, 1, 14, P.FURS[1]),
    mk(2, D('cappuccino'), 0, 0, 7, P.FURS[4]),
  ];
  g.cups = [{ drink: D('latte'), size: 1, temp: 0 }, { drink: D('mocha'), size: 2, temp: 1 }];
  g.brewing = [{ drink: D('americano'), size: 2, temp: 1, left: 1.4, total: 3.4 }];
  P.setG(g);
  P.setSceneTime(0.3);
  P.drawAll();
} else {
  P.setSceneTime(0.3);
  P.drawScene(minutes);
}

const big = scaleUp(buf, W, H, parseInt(process.argv[5] || '3', 10));
fs.writeFileSync(outPath, encodePNG(big, W * parseInt(process.argv[5] || '3', 10), H * parseInt(process.argv[5] || '3', 10)));
console.log('已渲染 ' + minutes + ' 分钟时刻的画面 ->', outPath);
