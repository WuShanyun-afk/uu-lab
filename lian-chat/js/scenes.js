/* Local scene illustrations for the daily report.
 *
 * The model only picks a scene id from this whitelist; the artwork itself is
 * hand-written SVG in this file, so a bad model response can never inject
 * markup, scripts or remote images into the report viewer.
 */

const svg = (body, extraClass = "") =>
  `<svg class="scene-svg ${extraClass}" viewBox="0 0 96 96" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">${body}</svg>`;

const SCENE_DEFS = {
  egg: {
    label: "煎蛋 / 鸡蛋",
    svg: svg(`
      <ellipse cx="48" cy="56" rx="31" ry="26" fill="#FFFDF7" stroke="#EFE6D5" stroke-width="1.6"/>
      <path d="M29 55c0-10 8.5-17 19-17s19 7 19 17-8 16-19 16-19-6-19-16Z" fill="#FFFDFB" stroke="#F2E8D6" stroke-width="1.2"/>
      <circle cx="48" cy="52" r="10.5" fill="#F7B33F"/>
      <circle cx="44.5" cy="48.5" r="3.4" fill="#FFD98A" opacity=".92"/>`),
  },
  coffee: {
    label: "咖啡 / 热饮",
    svg: svg(`
      <ellipse cx="47" cy="76" rx="24" ry="5" fill="#EFE8DB"/>
      <path d="M28 34h38v26c0 7-6 12-19 12s-19-5-19-12V34Z" fill="#FFFDF8" stroke="#E7DECD" stroke-width="1.6"/>
      <path d="M66 40h5c4 0 7 3 7 7s-3 7-7 7h-5" stroke="#E7DECD" stroke-width="1.8" stroke-linecap="round"/>
      <ellipse cx="47" cy="38" rx="17" ry="5" fill="#8A5B3C"/>
      <g class="s-steam" stroke="#D9CFC0" stroke-width="2" stroke-linecap="round">
        <path d="M39 27c-3-4 3-6 0-10"/><path d="M53 27c3-4-3-6 0-10"/>
      </g>`),
  },
  rice: {
    label: "米饭 / 便当",
    svg: svg(`
      <path d="M18 50h60c0 16-13 27-30 27S18 66 18 50Z" fill="#FFFDF7" stroke="#E7DECD" stroke-width="1.6"/>
      <ellipse cx="48" cy="50" rx="30" ry="7" fill="#FFFEF8"/>
      <g stroke="#D8C3A5" stroke-width="2" stroke-linecap="round"><path d="M60 40 78 26"/><path d="M64 44 82 30"/></g>`),
  },
  noodles: {
    label: "面 / 汤面",
    svg: svg(`
      <path d="M18 50h60c0 16-13 27-30 27S18 66 18 50Z" fill="#FFFDF7" stroke="#E7DECD" stroke-width="1.6"/>
      <g stroke="#E3B96B" stroke-width="2.4" stroke-linecap="round">
        <path d="M27 50c6-6 12 6 18 0s12 6 18 0"/>
        <path d="M29 56c6-6 12 6 18 0s12 6 16-2"/>
      </g>
      <g stroke="#D8C3A5" stroke-width="2" stroke-linecap="round"><path d="M62 36 80 22"/><path d="M66 40 84 26"/></g>`),
  },
  cake: {
    label: "甜点 / 蛋糕",
    svg: svg(`
      <ellipse cx="48" cy="76" rx="26" ry="5" fill="#EFE8DB"/>
      <path d="M30 42h36v26H30Z" fill="#FBEFE2" stroke="#EADCC8" stroke-width="1.6"/>
      <path d="M30 42h36v8H30Z" fill="#F6C9C0"/>
      <path d="M40 42v-8c0-3 3-5 8-5s8 2 8 5v8" fill="#F7D9D1" stroke="#EADCC8" stroke-width="1.6"/>
      <circle cx="48" cy="28" r="4" fill="#E4695E"/>`),
  },
  tea: {
    label: "茶 / 果茶",
    svg: svg(`
      <path d="M34 30h28l-3 34c-.4 4-4 6-11 6s-10.6-2-11-6L34 30Z" fill="#FFFDF8" stroke="#E7DECD" stroke-width="1.6"/>
      <path d="M36 42h24l-2 22c-.3 3-3 4-10 4s-9.7-1-10-4L36 42Z" fill="#C98A4B" opacity=".85"/>
      <circle cx="60" cy="36" r="6" fill="#F6E2A0" stroke="#E6CE86" stroke-width="1.2"/>`),
  },
  rain: {
    label: "雨 / 阴雨",
    svg: svg(`
      <rect x="20" y="18" width="56" height="60" rx="7" fill="#F2F6F7" stroke="#D7E0E3" stroke-width="1.6"/>
      <path d="M48 18v60M20 48h56" stroke="#D7E0E3" stroke-width="1.4"/>
      <g class="s-rain" stroke="#8FB3C4" stroke-width="2" stroke-linecap="round">
        <path d="M32 30v6"/><path d="M58 26v7"/><path d="M33 50v8"/><path d="M59 48v8"/><path d="M66 34v6"/>
      </g>`),
  },
  sun: {
    label: "晴天 / 阳光",
    svg: svg(`
      <circle cx="48" cy="46" r="16" fill="#F9C961"/>
      <g class="s-sun" stroke="#F6B93B" stroke-width="2.4" stroke-linecap="round">
        <path d="M48 16v8"/><path d="M48 68v8"/><path d="M18 46h8"/><path d="M70 46h8"/>
        <path d="M27 25l6 6"/><path d="M69 25l-6 6"/><path d="M27 67l6-6"/><path d="M69 67l-6-6"/>
      </g>`),
  },
  moon: {
    label: "夜晚 / 月亮",
    svg: svg(`
      <circle cx="48" cy="46" r="18" fill="#F5E3B0"/>
      <g fill="#E8D196"><circle cx="42" cy="40" r="3"/><circle cx="54" cy="50" r="4"/><circle cx="45" cy="55" r="2.2"/></g>
      <g class="s-twinkle" fill="#F7C961"><circle cx="24" cy="26" r="2"/><circle cx="70" cy="30" r="2.4"/><circle cx="64" cy="66" r="1.8"/></g>`),
  },
  cat: {
    label: "猫 / 小动物",
    svg: svg(`
      <path d="M32 72c0-13 7-20 16-20s16 7 16 20" fill="#8C7A68"/>
      <path d="M38 36l-3-9 10 4Z" fill="#9C8875"/>
      <path d="M58 36l3-9-10 4Z" fill="#9C8875"/>
      <circle cx="48" cy="44" r="13" fill="#9C8875"/>
      <g stroke="#4A4038" stroke-width="1.7" stroke-linecap="round"><path d="M42 44c1 1.7 3 1.7 4 0"/><path d="M50 44c1 1.7 3 1.7 4 0"/></g>
      <path d="M67 66c6 1 8 6 4 9" stroke="#8C7A68" stroke-width="5" stroke-linecap="round"/>`),
  },
  book: {
    label: "书 / 阅读",
    svg: svg(`
      <path d="M20 30h22c3 0 6 3 6 6v30c0-3-3-5-6-5H20V30Z" fill="#FFFDF8" stroke="#E4DACA" stroke-width="1.6"/>
      <path d="M76 30H54c-3 0-6 3-6 6v30c0-3 3-5 6-5h22V30Z" fill="#FFFDF8" stroke="#E4DACA" stroke-width="1.6"/>
      <g stroke="#EADFCC" stroke-width="1.4"><path d="M27 40h13"/><path d="M27 47h13"/><path d="M27 54h9"/><path d="M56 40h13"/><path d="M56 47h13"/></g>`),
  },
  phone: {
    label: "手机 / 消息",
    svg: svg(`
      <rect x="32" y="20" width="32" height="56" rx="9" fill="#FFFDF8" stroke="#E4DACA" stroke-width="1.6"/>
      <rect x="38" y="31" width="16" height="7" rx="3.5" fill="#DCEFE2"/>
      <rect x="42" y="43" width="16" height="7" rx="3.5" fill="#E9E3D6"/>
      <rect x="38" y="55" width="12" height="6" rx="3" fill="#DCEFE2"/>`),
  },
  bus: {
    label: "通勤 / 路上",
    svg: svg(`
      <rect x="22" y="30" width="52" height="34" rx="9" fill="#FFFDF8" stroke="#E4DACA" stroke-width="1.6"/>
      <g fill="#DCE9EE"><rect x="29" y="37" width="12" height="10" rx="2"/><rect x="45" y="37" width="12" height="10" rx="2"/><rect x="61" y="37" width="8" height="10" rx="2"/></g>
      <rect x="22" y="52" width="52" height="3" fill="#EFE7D8"/>
      <circle cx="34" cy="68" r="5" fill="#5A5148"/><circle cx="62" cy="68" r="5" fill="#5A5148"/>`),
  },
  bed: {
    label: "睡觉 / 躺下",
    svg: svg(`
      <rect x="22" y="46" width="52" height="20" rx="6" fill="#FFFDF8" stroke="#E4DACA" stroke-width="1.6"/>
      <rect x="26" y="35" width="18" height="12" rx="6" fill="#F3E6D6"/>
      <path d="M44 46h26v14H44Z" fill="#DCE7EA" opacity=".9"/>
      <path d="M24 66v6M72 66v6" stroke="#C9BFAE" stroke-width="2.4" stroke-linecap="round"/>`),
  },
  flower: {
    label: "花 / 植物",
    svg: svg(`
      <path d="M40 58h16l-2 18c-.2 2-2 3-6 3s-5.8-1-6-3l-2-18Z" fill="#E9C7A8"/>
      <path d="M48 58V38" stroke="#7E9B6B" stroke-width="2.4"/>
      <g fill="#F3B7C0"><circle cx="48" cy="32" r="5"/><circle cx="40" cy="38" r="5"/><circle cx="56" cy="38" r="5"/><circle cx="43" cy="45" r="5"/><circle cx="53" cy="45" r="5"/></g>
      <circle cx="48" cy="39" r="3" fill="#F7D98A"/>
      <path d="M48 50c6-6 12-4 12 0-4 4-9 4-12 0Z" fill="#8FB07A"/>`),
  },
  music: {
    label: "听歌 / 耳机",
    svg: svg(`
      <path d="M28 52V44c0-11 9-19 20-19s20 8 20 19v8" stroke="#8C7A68" stroke-width="3" stroke-linecap="round"/>
      <rect x="22" y="48" width="10" height="16" rx="5" fill="#8C7A68"/>
      <rect x="64" y="48" width="10" height="16" rx="5" fill="#8C7A68"/>
      <g class="s-twinkle" fill="#F0B45C"><circle cx="30" cy="26" r="2.2"/><circle cx="66" cy="22" r="1.8"/></g>`),
  },
  heart: {
    label: "想念 / 心意",
    svg: svg(`
      <g class="s-float" fill="#EFA6A6"><path d="M48 70c-12-9-20-16-20-25a11 11 0 0 1 20-5 11 11 0 0 1 20 5c0 9-8 16-20 25Z"/></g>
      <g class="s-float s-float-slow" fill="#F3C4C0"><path d="M70 34c-5-4-8-6-8-10a4.4 4.4 0 0 1 8-2 4.4 4.4 0 0 1 8 2c0 4-3 6-8 10Z"/></g>`),
  },
  cloud: {
    label: "阴天 / 云",
    svg: svg(`
      <path d="M30 60c-7 0-12-5-12-11s5-11 12-11c1-8 8-13 16-13 9 0 16 6 17 14 6 1 10 5 10 11 0 6-5 10-12 10H30Z" fill="#EDF1F3" stroke="#DCE4E8" stroke-width="1.6"/>`),
  },
  work: {
    label: "电脑 / 工作",
    svg: svg(`
      <rect x="28" y="36" width="40" height="27" rx="3" fill="#FFFDF8" stroke="#E4DACA" stroke-width="1.6"/>
      <rect x="32" y="40" width="32" height="19" fill="#DFEAEE"/>
      <path d="M20 69h56l-4 6H24l-4-6Z" fill="#EDE6D8" stroke="#E0D7C6" stroke-width="1.4"/>`),
  },
};

export const SCENE_IDS = Object.keys(SCENE_DEFS);

/** Human label used in the prompt so the model knows what fits. */
export const SCENE_LABELS = SCENE_DEFS;

/** id -> markup, or "" for unknown / none. */
export function sceneSvg(id) {
  return SCENE_DEFS[id]?.svg || "";
}

export function isScene(id) {
  return Object.prototype.hasOwnProperty.call(SCENE_DEFS, id);
}
