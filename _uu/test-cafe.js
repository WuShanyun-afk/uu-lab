// 像素咖啡厅 · 无头模拟测试
// 用法：node test-cafe.js [天数]
// 把游戏脚本抠出来，在 Node 里用假 DOM 跑，然后让一个"机器人玩家"打几天，
// 看经济平衡、看有没有崩溃、看客人有没有卡死。
const fs = require('fs');

const GAME = 'D:\\小鲸鱼的文件夹\\x';   // 占位，下面会覆盖
const FILE = 'D:\\uu的办公室\\像素咖啡厅\\像素咖啡厅.html';
const DAYS = parseInt(process.argv[2] || '3', 10);

const html = fs.readFileSync(FILE, 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.log('找不到 script'); process.exit(1); }

/* ---------- 假 DOM ---------- */
function mkEl(tag) {
  const cls = new Set();
  const el = {
    tagName: tag || 'div', children: [], dataset: {}, disabled: false,
    _html: '', textContent: '', value: '', hidden: false,
    style: new Proxy({}, { get: () => '', set: () => true }),
    classList: {
      add: c => cls.add(c), remove: c => cls.delete(c),
      toggle: (c, v) => (v === undefined ? (cls.has(c) ? cls.delete(c) : cls.add(c)) : (v ? cls.add(c) : cls.delete(c))),
      contains: c => cls.has(c),
    },
    appendChild(c) { el.children.push(c); return c; },
    addEventListener() { },
    removeEventListener() { },
    querySelector: () => mkEl('div'),
    querySelectorAll: () => [],
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 320, height: 180 }),
    getContext: () => ctxStub,
  };
  Object.defineProperty(el, 'innerHTML', { get: () => el._html, set: v => { el._html = v; } });
  return el;
}
const ctxStub = new Proxy({}, {
  get: (t, k) => (k === 'canvas' ? { width: 320, height: 180 } : () => { }),
  set: () => true,
});

const byId = {};
['cv', 'toast', 'dayL', 'clockL', 'moneyL', 'repL', 'speedBtn', 'drinkRow',
  'sizeRow', 'tempRow', 'tray', 'stockRow', 'overlay', 'sheet',
  'menuBtn', 'menuOv', 'menuSheet'].forEach(id => { byId[id] = mkEl(); });

const store = {};
global.localStorage = {
  getItem: k => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: k => { delete store[k]; },
};
global.document = {
  getElementById: id => byId[id] || mkEl(),
  createElement: t => mkEl(t),
  querySelector: () => mkEl(),
  querySelectorAll: () => [],
  addEventListener() { },
};
global.window = { addEventListener() { }, innerWidth: 960, innerHeight: 540 };
global.requestAnimationFrame = () => 0;
global.performance = { now: () => 0 };

let api = null;
try {
  new Function('window', 'document', 'localStorage', 'requestAnimationFrame', 'performance',
    m[1] + '\n;return (typeof PixelCafe!=="undefined"?PixelCafe:window.PixelCafe);'
  )(global.window, global.document, global.localStorage, global.requestAnimationFrame, global.performance);
  api = global.window.PixelCafe;
} catch (e) {
  console.log('❌ 脚本抛异常：' + e.message);
  console.log(e.stack.split('\n').slice(0, 4).join('\n'));
  process.exit(1);
}
if (!api) { console.log('❌ 拿不到 PixelCafe 接口'); process.exit(1); }
console.log('✅ 脚本加载成功，接口齐全\n');

/* ---------- 机器人玩家 ---------- */
const DT = 1 / 60;
function playDay(api, style, autoShop) {
  const G = api.G;
  const before = { money: G.money, day: G.day };
  let guard = 0;
  while (G.phase !== 'shop' && guard < 60 * 60 * 20) {   // 最多 20 分钟真实时间
    guard++;
    // 1. 能送就送
    for (const g of G.guests.slice()) {
      if (g.state !== 'sit') continue;
      const has = G.cups.some(c => c.drink.id === g.drink.id && c.size === g.size && c.temp === g.temp);
      if (has) api.serveGuest(g);
    }
    // 2. 机器空着就补一杯（挑等最久的客人）
    if (style !== 'idle') {
      const waiting = G.guests.filter(g => g.state === 'sit')
        .sort((a, b) => a.patience - b.patience);
      for (const g of waiting) {
        const made = G.cups.some(c => c.drink.id === g.drink.id && c.size === g.size && c.temp === g.temp)
          || G.brewing.some(c => c.drink.id === g.drink.id && c.size === g.size && c.temp === g.temp);
        if (made) continue;
        if (api.startBrew(g.drink, g.size, g.temp, true)) break;
      }
    }
    api.tick(DT);
  }
  if (G.phase === 'shop') {
    const stats = {
      day: G.day, money: G.money, revenue: G.revenue, served: G.served,
      angry: G.angry, rep: G.rep, rent: G.rent, good: G.good,
    };
    if (autoShop) doShop(api);
    api.startDay();   // 直接进第二天（跳过商店界面）
    return stats;
  }
  return { day: before.day, money: G.money, revenue: G.revenue, served: G.served, angry: G.angry, rep: G.rep, rent: 0, good: 0 };
}

/* 模拟一个还算会玩的店主：先补货，再买最便宜的升级 */
function doShop(api) {
  const G = api.G;
  // 补货到 45
  Object.keys(api.GOODS).forEach(k => {
    while (G.stock[k] < 45 && G.money >= api.GOODS[k].p) { G.money -= api.GOODS[k].p; G.stock[k]++; }
  });
  // 买个升级
  for (let round = 0; round < 3; round++) {
    const cands = [];
    api.UPGRADES.forEach(u => {
      if (G.lv[u.id] < u.max) cands.push({ t: 'upg', id: u.id, cost: u.cost[G.lv[u.id]] });
    });
    api.DRINKS.forEach(d => { if (!G.unlocked[d.id]) cands.push({ t: 'menu', id: d.id, cost: d.unlock }); });
    cands.sort((a, b) => a.cost - b.cost);
    const pickOne = cands.find(c => c.cost <= G.money * 0.7);
    if (!pickOne) break;
    G.money -= pickOne.cost;
    if (pickOne.t === 'upg') G.lv[pickOne.id]++; else G.unlocked[pickOne.id] = true;
  }
}

/* ---------- 跑 ---------- */
console.log('  === 正常玩家：' + DAYS + ' 天 ===');
for (let i = 0; i < DAYS; i++) {
  const r = playDay(api, 'normal', true);
  console.log(`  第 ${r.day} 天  售 ${String(r.served).padStart(2)} 杯  好评 ${String(r.good).padStart(2)}  ` +
    `气走 ${String(r.angry).padStart(2)} 位  营业额 ${String(Math.round(r.revenue)).padStart(4)}  ` +
    `房租 ${String(r.rent).padStart(3)}  口碑 ${String(Math.round(r.rep)).padStart(3)}  ` +
    `手上现金 ${String(Math.round(r.money)).padStart(5)}`);
}

/* ---------- 摆烂玩家 ---------- */
console.log('\n  === 摆烂玩家（一杯不做）：2 天 ===');
api.G = api.freshGame();
for (let i = 0; i < 2; i++) {
  const r = playDay(api, 'idle');
  console.log(`  第 ${r.day} 天  售 ${r.served} 杯  气走 ${r.angry} 位  口碑 ${Math.round(r.rep)}  现金 ${Math.round(api.G.money)}`);
}

/* ---------- 断言 ---------- */
console.log('\n  === 一致性检查 ===');
let pass = 0, fail = 0;
function check(label, cond, extra) {
  if (cond) { pass++; console.log('  ✅ ' + label); }
  else { fail++; console.log('  ❌ ' + label + (extra !== undefined ? '  -> ' + extra : '')); }
}
api.G = api.freshGame();
const G = api.G;
check('开局 3 个座位', api.tableCount() === 3, api.tableCount());
check('开局 3 款咖啡解锁', Object.values(G.unlocked).filter(Boolean).length === 3);
check('开局现金 ' + api.CFG.START_MONEY, G.money === 200, G.money);
check('库存够做几杯', G.stock.bean > 0 && G.stock.cup > 0);

// 做一杯拿铁：应该扣 1 豆 1 奶 1 杯
const b0 = G.stock.bean, m0 = G.stock.milk, c0 = G.stock.cup;
const latte = api.DRINKS.find(d => d.id === 'latte');
api.startBrew(latte, 1, 0, true);
check('做拿铁扣原料', G.stock.bean === b0 - 1 && G.stock.milk === m0 - 1 && G.stock.cup === c0 - 1,
  `豆${G.stock.bean} 奶${G.stock.milk} 杯${G.stock.cup}`);
check('咖啡机开始工作', G.brewing.length === 1);
check('一台机器只能同时一杯', api.startBrew(latte, 1, 0, true) === false);

// 没解锁的应该做不了
const mocha = api.DRINKS.find(d => d.id === 'mocha');
check('未解锁的菜单做不了', api.startBrew(mocha, 1, 0, true) === false);

// 把豆子掏空，应该做不了
G.stock.bean = 0; G.brewing = []; G.cups = [];
check('原料不够就做不了', api.startBrew(latte, 1, 0, true) === false);

// 送到对的客人手里
G.stock.bean = 10; G.stock.milk = 10; G.stock.cup = 10;
G.cups = [{ drink: latte, size: 1, temp: 0 }];
G.guests = [{ id: 1, slot: 0, fur: api.G.constructor ? null : null, name: 't', drink: latte, size: 1, temp: 0,
  x: 30, y: api.CFG.SEAT_Y, seatY: api.CFG.SEAT_Y, state: 'sit', anim: 0,
  patience: 30, patienceMax: 30, wait: 0, pay: 0 }];
G.tables[0] = true;
const money0 = G.money;
check('送对杯能收到钱', api.serveGuest(G.guests[0]) === true && G.money > money0, G.money - money0);
check('送完变开心状态', G.guests[0].state === 'happy');
check('桌子被释放', G.tables[0] === false);
check('出杯口清空了', G.cups.length === 0);

// 送错的应该被拒
G.cups = [{ drink: api.DRINKS[0], size: 0, temp: 1 }];
G.guests = [{ id: 2, slot: 1, drink: latte, size: 1, temp: 0, x: 74, y: api.CFG.SEAT_Y,
  seatY: api.CFG.SEAT_Y, state: 'sit', anim: 0, patience: 30, patienceMax: 30, wait: 0, pay: 0 }];
G.tables[1] = true;
check('送错杯会被拒收', api.serveGuest(G.guests[0]) === false);
check('被拒后客人还在等', G.guests[0].state === 'sit' && G.cups.length === 1);

// 耐心归零会走人
G.guests[0].patience = 0.01;
const rep0 = G.rep;
api.tick(0.5);
check('耐心归零会气走', G.guests[0].state === 'leaving' && G.rep < rep0, G.rep);

// 升级有效
const t0 = api.brewTime(latte, 1, 0);
G.lv.machine = 3;
const t1 = api.brewTime(latte, 1, 0);
check('咖啡机升级出杯更快', t1 < t0, `${t0.toFixed(2)}s -> ${t1.toFixed(2)}s`);
G.lv.seat = 3;
check('座位升级到 6 桌', api.tableCount() === 6, api.tableCount());
G.lv.sign = 3; G.rep = 80;
check('招牌 + 口碑拉高客流', api.spawnInterval() < 8, api.spawnInterval().toFixed(1) + 's');
G.lv.sofa = 0;
const p0 = api.patienceMax();
G.lv.sofa = 3;
check('沙发加耐心', api.patienceMax() > p0, `${p0} -> ${api.patienceMax()}`);

// 打烊流程
api.G = api.freshGame();
api.G.phase = 'open';
api.G.min = api.CFG.DAY_END - 1;
api.tick(1);
check('到点自动打烊', api.G.phase === 'closing' || api.G.phase === 'shop', api.G.phase);

// 菜单 / 配方页
console.log('\n  === 菜单页 ===');
api.G = api.freshGame();
const gg = api.G;
const amer = api.DRINKS.find(d => d.id === 'americano');
const latt = api.DRINKS.find(d => d.id === 'latte');
const moch = api.DRINKS.find(d => d.id === 'mocha');
check('美式只要豆和杯', Object.keys(amer.need).join() === 'bean,cup', Object.keys(amer.need).join());
check('拿铁要豆奶杯', Object.keys(latt.need).join() === 'bean,milk,cup', Object.keys(latt.need).join());
check('摩卡要豆奶糖杯', Object.keys(moch.need).join() === 'bean,milk,syrup,cup', Object.keys(moch.need).join());
check('每款都有配方', api.DRINKS.every(d => Object.keys(d.need).length >= 2));

// 「还能做几杯」取原料里最紧的那个
gg.stock = { bean: 10, milk: 3, syrup: 100, cup: 50 };
check('还能做几杯 = 取最紧的原料', api.canMake(latt) === 3, api.canMake(latt));
check('  豆子够 10 杯但奶只够 3 杯', api.canMake(amer) === 10, api.canMake(amer));
gg.stock.milk = 0;
check('缺料时算 0 杯', api.canMake(latt) === 0, api.canMake(latt));

// 打开菜单会暂停游戏
gg.stock = { bean: 30, milk: 30, syrup: 20, cup: 40 };
const clockBefore = gg.min;
api.openMenu();
api.tick(1);
check('打开菜单时游戏暂停', gg.min === clockBefore, `${clockBefore} -> ${gg.min}`);
api.closeMenu();
api.tick(1);
check('关掉菜单后继续走', gg.min > clockBefore, gg.min);
check('菜单页渲染没崩', byId.menuSheet.innerHTML.indexOf('菜单 · 配方') >= 0);
check('菜单页列出了全部 ' + api.DRINKS.length + ' 款', (byId.menuSheet.innerHTML.match(/class="rec/g) || []).length === api.DRINKS.length,
  (byId.menuSheet.innerHTML.match(/class="rec/g) || []).length);
check('菜单页标了锁', byId.menuSheet.innerHTML.indexOf('🔒') >= 0);

if (process.env.DUMP_MENU) {
  console.log('\n  --- 菜单页 HTML ---');
  console.log(byId.menuSheet.innerHTML.replace(/></g, '>\n<'));
  console.log('  --- 完 ---\n');
}

console.log(`\n  结果：${pass} 通过 / ${fail} 失败`);
process.exit(fail ? 1 : 0);
