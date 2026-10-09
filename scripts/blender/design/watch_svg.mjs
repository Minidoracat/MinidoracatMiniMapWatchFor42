// 圖形層：六款手錶正面（viewBox 0 0 200 260）、模組圖示、手腕佩戴、像素尺寸示意。
let uidCounter = 0;
const uid = (p) => `${p}${++uidCounter}`;

// ---------- 七段液晶 ----------
const SEG = {
  0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd",
  6: "afgedc", 7: "abc", 8: "abcdefg", 9: "abcdfg",
};
function segDigit(x, y, w, h, d, on, off) {
  const t = 3.2, half = h / 2;
  const rects = {
    a: [x + 2, y, w - 4, t], d: [x + 2, y + h - t, w - 4, t], g: [x + 2, y + half - t / 2, w - 4, t],
    b: [x + w - t, y + 2, t, half - 3], c: [x + w - t, y + half + 1, t, half - 3],
    e: [x, y + half + 1, t, half - 3], f: [x, y + 2, t, half - 3],
  };
  const lit = SEG[d] || "";
  return Object.entries(rects).map(([k, r]) =>
    `<rect x="${r[0]}" y="${r[1]}" width="${r[2]}" height="${r[3]}" rx="1" fill="${lit.includes(k) ? on : off}"/>`).join("");
}
function segTime(x, y, str, { w = 13, h = 24, gap = 4, on = "#1E2A1A", off = "#AAB894" } = {}) {
  let out = "", cx = x;
  for (const ch of str) {
    if (ch === ":") {
      out += `<rect x="${cx + 1}" y="${y + h * 0.28}" width="3" height="3" fill="${on}"/><rect x="${cx + 1}" y="${y + h * 0.64}" width="3" height="3" fill="${on}"/>`;
      cx += 7;
    } else {
      out += segDigit(cx, y, w, h, Number(ch), on, off);
      cx += w + gap;
    }
  }
  return out;
}

// 嗶嗶腕機的兩種螢幕顏色（純外觀，玩家可切換）。
export const CRT_SCREENS = {
  green: { bg: "#08180B", scan: "#04120A", ink: "#6BFF5E", grid: "#1F6B2A", hi: "#B6FF9E", bar: "#12391A" },
  amber: { bg: "#1A0F03", scan: "#0E0700", ink: "#FFB642", grid: "#7A4A10", hi: "#FFDCA0", bar: "#3A2408" },
};

// ---------- 七款錶（回傳 <g>，供不同場合重用） ----------
const WATCHES = {
  valutech() {
    const g = uid("vt");
    const ridges = [10, 20, 30, 40, 50, 60].map((y) => `<rect x="66" y="${y}" width="68" height="2" fill="#2C2D31"/>`).join("")
      + [196, 206, 216, 226, 236, 246].map((y) => `<rect x="66" y="${y}" width="68" height="2" fill="#2C2D31"/>`).join("");
    return `<defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E7EAEE"/><stop offset="1" stop-color="#A9AEB5"/></linearGradient></defs>
    <rect x="66" y="0" width="68" height="84" fill="#1E1F22"/><rect x="66" y="176" width="68" height="84" fill="#1E1F22"/>${ridges}
    <rect x="62" y="186" width="76" height="8" rx="2" fill="#2C2D31"/>
    <rect x="27" y="88" width="9" height="18" rx="2" fill="#B4B8BE"/><rect x="164" y="88" width="9" height="18" rx="2" fill="#B4B8BE"/><rect x="164" y="152" width="9" height="18" rx="2" fill="#B4B8BE"/>
    <rect x="34" y="62" width="132" height="136" rx="18" fill="#1E1F22" stroke="#34363B" stroke-width="2"/>
    <rect x="44" y="72" width="112" height="116" rx="10" fill="url(#${g})"/>
    <text x="100" y="88" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="10.5" font-weight="700" fill="#1E1F22" letter-spacing=".5">ValuTech</text>
    <rect x="52" y="95" width="96" height="58" rx="4" fill="#B9C6A3" stroke="#6F7A63" stroke-width="1.5"/>
    <rect x="58" y="100" width="18" height="6" rx="1" fill="#1E2A1A" opacity=".85"/><rect x="80" y="100" width="10" height="6" rx="1" fill="#1E2A1A" opacity=".85"/>
    <path d="M126 101h14v6h-14z M140 103h2v2h-2z" fill="#1E2A1A"/>
    ${segTime(60, 116, "12:34")}
    <text x="58" y="174" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="8" font-weight="700" fill="#2C2D31">MODE</text>
    <text x="142" y="174" text-anchor="end" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="8" font-weight="700" fill="#E0592B">LIGHT</text>`;
  },
  paws() {
    const heart = (x, y, s = 1) => `<path transform="translate(${x} ${y}) scale(${s})" d="M0 2.4C0-.6 4-1.4 5 1.4 6-1.4 10-.6 10 2.4 10 5.8 5 8.6 5 8.6S0 5.8 0 2.4z" fill="#FFF6EC"/>`;
    return `<rect x="72" y="0" width="56" height="84" rx="10" fill="#8FDDC2"/><rect x="72" y="176" width="56" height="84" rx="10" fill="#8FDDC2"/>
    ${heart(95, 18)}${heart(95, 40)}${heart(95, 200)}${heart(95, 222)}${heart(95, 244)}
    <path d="M50 96 L57 44 L94 74 Z" fill="#F59BBE" stroke="#F59BBE" stroke-width="8" stroke-linejoin="round"/>
    <path d="M150 96 L143 44 L106 74 Z" fill="#F59BBE" stroke="#F59BBE" stroke-width="8" stroke-linejoin="round"/>
    <path d="M60 84 L63 60 L81 74 Z" fill="#FFD3E2"/><path d="M140 84 L137 60 L119 74 Z" fill="#FFD3E2"/>
    <circle cx="100" cy="132" r="58" fill="#F59BBE" stroke="#E0719E" stroke-width="2"/>
    <circle cx="160" cy="132" r="6" fill="#E0719E"/>
    <circle cx="100" cy="132" r="47" fill="#FFF6EC"/>
    <path d="M62 120 C80 112 92 128 112 118 S136 110 140 116" stroke="#F9C7DA" stroke-width="4" fill="none" stroke-linecap="round"/>
    <path d="M74 98 L92 150" stroke="#F9C7DA" stroke-width="3" fill="none" stroke-linecap="round"/>
    <g stroke="#E0719E" stroke-width="1.6" stroke-linecap="round"><path d="M58 128h10M58 134h10M60 140l8-2"/><path d="M142 128h-10M142 134h-10M140 140l-8-2"/></g>
    <g fill="#F59BBE"><ellipse cx="100" cy="160" rx="9" ry="7"/><circle cx="90" cy="149" r="3.6"/><circle cx="100" cy="146" r="3.6"/><circle cx="110" cy="149" r="3.6"/></g>
    <path d="M100 132 L86 118" stroke="#6B3A4C" stroke-width="4.5" stroke-linecap="round"/><path d="M100 132 L100 99" stroke="#6B3A4C" stroke-width="3" stroke-linecap="round"/>
    <circle cx="100" cy="132" r="4.5" fill="#6B3A4C"/>`;
  },
  nexus() {
    const g = uid("nx"), p = uid("nxh"), c = uid("nxc");
    const vents = (y0) => [0, 10, 20, 30, 40, 50].map((d) => `<rect x="85" y="${y0 + d}" width="30" height="4" rx="2" fill="#11161C"/>`).join("");
    return `<defs><linearGradient id="${g}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#232A33"/><stop offset="1" stop-color="#0E1217"/></linearGradient>
      <pattern id="${p}" width="12" height="10.4" patternUnits="userSpaceOnUse"><path d="M3 0h6l3 5.2-3 5.2H3L0 5.2z" fill="none" stroke="#123E42" stroke-width=".9"/></pattern>
      <clipPath id="${c}"><rect x="54" y="78" width="92" height="104" rx="20"/></clipPath></defs>
    <rect x="70" y="0" width="60" height="84" fill="#1D232B"/><rect x="70" y="176" width="60" height="84" fill="#1D232B"/>${vents(12)}${vents(194)}
    <rect x="160" y="108" width="8" height="28" rx="3" fill="#2B3540"/><rect x="160" y="146" width="8" height="16" rx="3" fill="#2B3540"/>
    <rect x="40" y="62" width="120" height="136" rx="34" fill="url(#${g})" stroke="#2B3540" stroke-width="3"/>
    <rect x="46" y="68" width="108" height="124" rx="29" fill="none" stroke="#3EE6E0" stroke-width="6" opacity=".18"/>
    <rect x="46" y="68" width="108" height="124" rx="29" fill="none" stroke="#3EE6E0" stroke-width="2"/>
    <rect x="54" y="78" width="92" height="104" rx="20" fill="#05080B"/>
    <g clip-path="url(#${c})"><rect x="54" y="78" width="92" height="104" fill="url(#${p})"/>
      <path d="M40 150 L160 128 M92 70 L110 200 M40 118 C80 126 110 108 160 112" stroke="#1C6E6B" stroke-width="3" fill="none"/>
      <path d="M70 168 C84 150 96 152 102 140 S120 120 132 112" stroke="#3EE6E0" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-dasharray="0"/>
      <circle cx="132" cy="112" r="4" fill="none" stroke="#3EE6E0" stroke-width="2"/></g>
    <path d="M100 152 l-6 10 6-3 6 3z" fill="#E6FFFE"/>
    <text x="100" y="104" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="17" fill="#9FF7F3" font-variant-numeric="tabular-nums">21:47</text>
    <rect x="122" y="86" width="14" height="6" rx="1.5" fill="none" stroke="#3EE6E0" stroke-width="1"/><rect x="123.5" y="87.5" width="8" height="3" fill="#3EE6E0"/>`;
  },
  spiffo() {
    const bands = (y0, n) => Array.from({ length: n }, (_, i) =>
      `<rect x="72" y="${y0 + i * 12}" width="56" height="12" fill="${i % 2 ? "#3A3C41" : "#8C8F96"}"/>`).join("");
    return `<g>${bands(0, 7)}${bands(176, 7)}</g>
    <circle cx="62" cy="82" r="17" fill="#8C8F96"/><circle cx="62" cy="82" r="8.5" fill="#5A5D63"/>
    <circle cx="138" cy="82" r="17" fill="#8C8F96"/><circle cx="138" cy="82" r="8.5" fill="#5A5D63"/>
    <circle cx="100" cy="134" r="58" fill="#8C8F96" stroke="#6E7178" stroke-width="2"/>
    <circle cx="160" cy="134" r="5.5" fill="#D9443A"/>
    <circle cx="100" cy="134" r="50" fill="none" stroke="#D9443A" stroke-width="4.5"/>
    <circle cx="100" cy="134" r="45" fill="#F3F0E8"/>
    <path d="M56 121 Q100 96 144 121 Q100 140 56 121 Z" fill="#2E2F33"/>
    <ellipse cx="83" cy="120" rx="7.5" ry="6" fill="#FFFFFF"/><ellipse cx="117" cy="120" rx="7.5" ry="6" fill="#FFFFFF"/>
    <circle cx="84" cy="121" r="2.8" fill="#2E2F33"/><circle cx="116" cy="121" r="2.8" fill="#2E2F33"/>
    <ellipse cx="100" cy="135" rx="4.5" ry="3.2" fill="#2E2F33"/>
    <path d="M90 143 Q100 151 110 143" stroke="#2E2F33" stroke-width="2.2" fill="none" stroke-linecap="round"/>
    <text x="100" y="168" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="9.5" font-weight="700" fill="#C33A31" letter-spacing=".6">SP-3</text>`;
  },
  ranger() {
    const strap = (y) => `<rect x="68" y="${y}" width="64" height="84" fill="#5B6340"/><rect x="86" y="${y}" width="4" height="84" fill="#B9A77A"/><rect x="98" y="${y}" width="4" height="84" fill="#B9A77A"/><rect x="110" y="${y}" width="4" height="84" fill="#B9A77A"/>`;
    const screw = (x, y) => `<circle cx="${x}" cy="${y}" r="4.2" fill="#2A2E1C"/><path d="M${x - 2.4} ${y}h4.8M${x} ${y - 2.4}v4.8" stroke="#6B7449" stroke-width="1.2"/>`;
    const grid = [100, 116, 132, 148, 164].map((y) => `<path d="M52 ${y}h96" stroke="#F2B33D" stroke-width=".7" opacity=".28"/>`).join("")
      + [68, 84, 100, 116, 132].map((x) => `<path d="M${x} 88v88" stroke="#F2B33D" stroke-width=".7" opacity=".28"/>`).join("");
    return `${strap(0)}${strap(176)}<rect x="64" y="194" width="72" height="9" rx="2" fill="#9AA0A6"/>
    <rect x="20" y="98" width="12" height="20" rx="2" fill="#3B4126"/><rect x="20" y="146" width="12" height="20" rx="2" fill="#3B4126"/>
    <rect x="168" y="98" width="12" height="20" rx="2" fill="#3B4126"/><rect x="168" y="146" width="12" height="20" rx="2" fill="#3B4126"/>
    <path d="M52 60 H148 L172 84 V180 L148 204 H52 L28 180 V84 Z" fill="#4F5732" stroke="#3B4126" stroke-width="3"/>
    <path d="M28 84 L52 60 H66 L38 90 Z M172 84 L148 60 H134 L162 90 Z M28 180 L52 204 H66 L38 174 Z M172 180 L148 204 H134 L162 174 Z" fill="#3B4126"/>
    ${screw(46, 78)}${screw(154, 78)}${screw(46, 186)}${screw(154, 186)}
    <text x="100" y="78" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="10" font-weight="700" fill="#B9A77A" letter-spacing="2">US</text>
    <rect x="50" y="86" width="100" height="92" rx="6" fill="#11140C" stroke="#2A2E1C" stroke-width="2"/>
    ${grid}
    <text x="100" y="112" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="15" fill="#F2B33D" font-variant-numeric="tabular-nums">N 012°</text>
    <path d="M70 160 C84 148 96 154 108 140 S126 128 134 122" stroke="#F2B33D" stroke-width="2.4" fill="none" stroke-linecap="round"/>
    <circle cx="70" cy="160" r="3" fill="#F2B33D"/><path d="M130 118 l8 2 -6 6z" fill="#F2B33D"/>`;
  },
  crt(p = CRT_SCREENS.green) {
    const g = uid("pb"), t = uid("pbt"), c = uid("pbc");
    const ribs = (y0) => [0, 9, 18, 27, 36, 45].map((d) => `<rect x="46" y="${y0 + d}" width="108" height="4" rx="2" fill="#23271A"/>`).join("");
    const scan = Array.from({ length: 24 }, (_, i) => `<rect x="44" y="${70 + i * 4}" width="86" height="1.3" fill="${p.scan}" opacity=".55"/>`).join("");
    const knurl = (cx, cy, r, n) => Array.from({ length: n }, (_, i) => {
      const a = (i / n) * Math.PI * 2;
      return `<path d="M${(cx + (r - 3.5) * Math.cos(a)).toFixed(1)} ${(cy + (r - 3.5) * Math.sin(a)).toFixed(1)}L${(cx + r * Math.cos(a)).toFixed(1)} ${(cy + r * Math.sin(a)).toFixed(1)}"/>`;
    }).join("");
    const mono = `font-family="Consolas, 'Courier New', monospace"`;
    const tabs = [["STAT", 48], ["ITEM", 64], ["DATA", 80], ["MAP", 97.5], ["RADIO", 111]].map(([w, x]) => `<text x="${x}" y="80" ${mono} font-size="6.2" fill="${p.ink}">${w}</text>`).join("");
    const button = (x, label) => `<rect x="${x}" y="178" width="27" height="15" rx="3" fill="#3A3A28"/><rect x="${x + 2}" y="179.5" width="23" height="3" rx="1.5" fill="#55553A"/><text x="${x + 13.5}" y="189.5" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="5.6" font-weight="700" fill="#D8D0A0">${label}</text>`;
    return `<defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8E8E62"/><stop offset=".55" stop-color="#76764F"/><stop offset="1" stop-color="#5A5A3B"/></linearGradient>
      <linearGradient id="${t}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5E5C40"/><stop offset=".45" stop-color="#9A9870"/><stop offset="1" stop-color="#5E5C40"/></linearGradient>
      <clipPath id="${c}"><rect x="44" y="68" width="86" height="94" rx="8"/></clipPath></defs>
    <rect x="42" y="0" width="116" height="58" fill="#2F3324"/><rect x="42" y="204" width="116" height="56" fill="#2F3324"/>${ribs(6)}${ribs(208)}
    <rect x="24" y="48" width="162" height="162" rx="20" fill="url(#${g})" stroke="#3E3E28" stroke-width="2"/>
    <rect x="14" y="76" width="18" height="104" rx="8" fill="url(#${t})" stroke="#3E3E28" stroke-width="1.5"/>
    <g fill="#3A3926"><rect x="14" y="92" width="18" height="4"/><rect x="14" y="114" width="18" height="4"/><rect x="14" y="136" width="18" height="4"/><rect x="14" y="158" width="18" height="4"/></g>
    <g fill="#4A4A30"><rect x="144" y="55" width="30" height="2.6" rx="1.3"/><rect x="144" y="60" width="30" height="2.6" rx="1.3"/></g>
    <rect x="36" y="60" width="102" height="110" rx="12" fill="#23261A"/>
    <rect x="44" y="68" width="86" height="94" rx="8" fill="${p.bg}"/>
    <g clip-path="url(#${c})">${scan}${tabs}
      <path d="M46 84 H95.5 V73.5 H110 V84 H128" stroke="${p.ink}" stroke-width=".9" fill="none"/>
      <path d="M44 132 L130 114 M88 86 V146 M44 102 C70 110 96 94 130 98" stroke="${p.grid}" stroke-width="2.2" fill="none"/>
      <path d="M58 140 C70 128 80 130 88 120 S104 104 114 100" stroke="${p.ink}" stroke-width="2.4" fill="none" stroke-linecap="round"/>
      <circle cx="114" cy="100" r="3.6" fill="none" stroke="${p.ink}" stroke-width="1.8"/>
      <path d="M88 116 l-4.5 8 4.5 -2.6 4.5 2.6z" fill="${p.hi}"/>
      <rect x="46" y="148" width="82" height="9" fill="${p.bar}"/>
      <text x="49" y="154.6" ${mono} font-size="5.8" fill="${p.ink}">BAT 72%</text><text x="125" y="154.6" text-anchor="end" ${mono} font-size="5.8" fill="${p.ink}">N 012°</text></g>
    <rect x="44" y="68" width="86" height="94" rx="8" fill="none" stroke="${p.ink}" stroke-width="1" opacity=".3"/>
    <circle cx="149" cy="72" r="4" fill="#FFB000"/><circle cx="149" cy="72" r="7.5" fill="#FFB000" opacity=".2"/>
    <circle cx="164" cy="100" r="19" fill="#3A3A28"/><g stroke="#5E5E40" stroke-width="1.6">${knurl(164, 100, 19, 24)}</g>
    <circle cx="164" cy="100" r="11" fill="#55553A"/><path d="M164 91 V98" stroke="#D8D0A0" stroke-width="2.6" stroke-linecap="round"/>
    <circle cx="164" cy="146" r="11" fill="#3A3A28"/><g stroke="#5E5E40" stroke-width="1.4">${knurl(164, 146, 11, 16)}</g><path d="M157 146 H162" stroke="#D8D0A0" stroke-width="2.4" stroke-linecap="round"/>
    ${button(42, "STATS")}${button(74, "ITEMS")}${button(106, "DATA")}
    <text x="164" y="178" text-anchor="middle" font-family="Bahnschrift, 'Arial Narrow', sans-serif" font-size="7.5" font-weight="700" fill="#2E2E1E" letter-spacing=".6">BB-3000</text>
    <g fill="#3E3E28"><circle cx="34" cy="200" r="2.4"/><circle cx="176" cy="200" r="2.4"/></g>`;
  },
  // 嗶嗶腕機的琥珀螢幕：同一支錶，玩家在右鍵選單切換螢幕顏色。
  "crt-amber"() { return WATCHES.crt(CRT_SCREENS.amber); },
  luthex() {
    const g = uid("lx");
    const flutes = Array.from({ length: 48 }, (_, i) => {
      const a = (i / 48) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
      return `<path d="M${(100 + 50 * c).toFixed(1)} ${(132 + 50 * s).toFixed(1)}L${(100 + 58 * c).toFixed(1)} ${(132 + 58 * s).toFixed(1)}"/>`;
    }).join("");
    const ticks = Array.from({ length: 12 }, (_, i) => {
      const a = (i / 12) * Math.PI * 2 - Math.PI / 2, c = Math.cos(a), s = Math.sin(a), big = i % 3 === 0;
      const r1 = big ? 35 : 38;
      return `<path d="M${(100 + r1 * c).toFixed(1)} ${(132 + r1 * s).toFixed(1)}L${(100 + 44 * c).toFixed(1)} ${(132 + 44 * s).toFixed(1)}" stroke-width="${big ? 3 : 1.6}"/>`;
    }).join("");
    const strap = (y) => `<rect x="74" y="${y}" width="52" height="84" rx="6" fill="#4A2C20"/><path d="M80 ${y + 4}V${y + 80}M120 ${y + 4}V${y + 80}" stroke="#C9A46A" stroke-width="1.2" stroke-dasharray="4 3"/>`;
    return `<defs><radialGradient id="${g}" cx=".38" cy=".32" r=".8"><stop offset="0" stop-color="#F6DC86"/><stop offset=".55" stop-color="#D4AF37"/><stop offset="1" stop-color="#A67C22"/></radialGradient></defs>
    ${strap(0)}${strap(176)}<g fill="#2B1912"><circle cx="100" cy="212" r="2.4"/><circle cx="100" cy="226" r="2.4"/><circle cx="100" cy="240" r="2.4"/></g>
    <rect x="157" y="125" width="11" height="14" rx="2.5" fill="#C9A046"/>
    <circle cx="100" cy="132" r="60" fill="url(#${g})"/>
    <g stroke="#9C7425" stroke-width="1.6">${flutes}</g>
    <circle cx="100" cy="132" r="47" fill="#111111" stroke="#7A5C1E" stroke-width="1.5"/>
    <g stroke="#D9B45A" stroke-linecap="round">${ticks}</g>
    <text x="100" y="114" text-anchor="middle" font-family="Georgia, 'Times New Roman', serif" font-size="7.5" fill="#D9B45A" letter-spacing="1.6">LUTHEX</text>
    <rect x="85" y="146" width="30" height="19" rx="4" fill="#1E1A12" stroke="#D9B45A" stroke-width="1"/>
    <path d="M89 160 C95 154 101 158 106 151 L111 150" stroke="#D9B45A" stroke-width="1.4" fill="none" stroke-linecap="round"/>
    <path d="M100 132 L85 118" stroke="#D9B45A" stroke-width="4" stroke-linecap="round"/><path d="M100 132 L100 97" stroke="#D9B45A" stroke-width="2.6" stroke-linecap="round"/>
    <circle cx="100" cy="132" r="3.6" fill="#D9B45A"/>`;
  },
};

export function watchGroup(id) { return WATCHES[id](); }

// 頁面有 sprite 時（globalThis.__WATCH_SPRITES）用 <use> 引用，避免同一支錶重複內嵌幾十次。
const useSprites = () => globalThis.__WATCH_SPRITES === true;
const watchBody = (id) => (useSprites() ? `<use href="#w-${id}"/>` : watchGroup(id));

// 完整錶（正面）。label 為空字串時當裝飾處理。
export function watchSVG(id, { width = 200, label = "" } = {}) {
  const a11y = label ? `role="img" aria-label="${label}"` : `aria-hidden="true" focusable="false"`;
  const h = Math.round(width * 1.3);
  return `<svg class="watch-svg" viewBox="0 0 200 260" width="${width}" height="${h}" ${a11y}>${watchBody(id)}</svg>`;
}

// 物品欄圖示：裁成正方形，只看錶殼。
export function watchIcon(id, px, label = "") {
  const a11y = label ? `role="img" aria-label="${label}"` : `aria-hidden="true" focusable="false"`;
  return `<svg class="watch-icon" viewBox="14 38 172 172" width="${px}" height="${px}" ${a11y}>${watchBody(id)}</svg>`;
}

// 手腕佩戴：袖口、前臂、手；錶身只裁掉錶帶末端，留一小段錶帶繞過手腕的感覺。
export function wristSVG(id, label) {
  const clip = uid("wr"), s = 0.47;
  const tx = (196 - 100 * s).toFixed(1), ty = (74 - 130 * s).toFixed(1);
  return `<svg class="wrist-svg" viewBox="0 0 320 150" role="img" aria-label="${label}">
    <path d="M250 46 C276 40 304 46 316 62 C322 72 320 86 310 92 C296 102 272 106 250 104 Z" fill="#C9967A"/>
    <path d="M262 48 C276 34 294 32 302 38 C306 44 298 52 284 56 Z" fill="#D2A285"/>
    <path d="M276 92 C288 90 300 86 308 80" stroke="#A9775B" stroke-width="2" fill="none" stroke-linecap="round"/>
    <path d="M92 38 C150 34 210 42 250 48 L252 102 C210 108 150 116 92 112 Z" fill="#C9967A"/>
    <path d="M92 100 C150 106 210 100 252 94 L252 102 C210 108 150 116 92 112 Z" fill="#B98466"/>
    <path d="M0 26 H94 Q104 75 94 124 H0 Z" fill="#56616C"/><path d="M88 24 Q100 75 88 126" stroke="#46505A" stroke-width="10" fill="none"/>
    <g transform="translate(${tx} ${ty}) scale(${s})"><clipPath id="${clip}"><rect x="14" y="40" width="172" height="168"/></clipPath><g clip-path="url(#${clip})">${watchBody(id)}</g></g>
  </svg>`;
}

// 遊戲內尺寸示意：一格一單位的像素角色，錶只有一格（第 1 欄、第 14 列）。
const PIX = [
  "....HHHHHH....", "...HHHHHHHH...", "...HSSSSSSH...", "...SSSSSSSS...", "...SSSSSSSS...",
  "....SSSSSS....", ".....SSSS.....", "...TTTTTTTT...", "..TTTTTTTTTT..", ".TTTTTTTTTTTT.",
  ".TT.TTTTTT.TT.", ".TT.TTTTTT.TT.", ".TT.TTTTTT.TT.", ".SS.TTTTTT.SS.", ".SS.TTTTTT.SS.",
  ".SS.PPPPPP.SS.", "....PPPPPP....", "....PPPPPP....", "....PP..PP....", "....PP..PP....",
  "....PP..PP....", "....PP..PP....", "....PP..PP....", "....PP..PP....", "...BBB..BBB...", "...BBB..BBB...",
];
const PIX_COL = { H: "#3A2A20", S: "#C9967A", T: "#5E7A8C", P: "#3D4652", B: "#2A2A2A" };
function pixBody() {
  let out = "";
  PIX.forEach((row, y) => {
    for (let x = 0; x < row.length;) {
      const ch = row[x];
      let n = 1;
      while (row[x + n] === ch) n++;
      if (PIX_COL[ch]) out += `<rect x="${x}" y="${y}" width="${n}" height="1" fill="${PIX_COL[ch]}"/>`;
      x += n;
    }
  });
  return out;
}
export function pixelChar(style, cell = 4, label = "") {
  const w = 14 * cell, h = PIX.length * cell;
  const a11y = label ? `role="img" aria-label="${label}"` : `aria-hidden="true" focusable="false"`;
  const body = useSprites() ? `<use href="#pix-body"/>` : pixBody();
  const cells = style.pixelCells === 2
    ? `<rect x="1" y="13" width="1" height="1" fill="${style.wristColor}"/><rect x="1" y="14" width="1" height="1" fill="${style.wristAccent}"/>`
    : `<rect x="1" y="14" width="1" height="1" fill="${style.wristColor}"/>`;
  return `<svg class="pix" viewBox="0 0 14 ${PIX.length}" width="${w}" height="${h}" shape-rendering="crispEdges" ${a11y}>${body}${cells}</svg>`;
}

// 頁首的隱藏 sprite：每款錶與像素角色各定義一次。
export function spriteDefs(ids) {
  return `<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false"><defs>${ids.map((id) => `<g id="w-${id}">${watchGroup(id)}</g>`).join("")}<g id="pix-body">${pixBody()}</g></defs></svg>`;
}

// ---------- 模組與狀態圖示（24×24，currentColor） ----------
const ICON_PATHS = {
  ledger: `<path d="M5 4h10.5A2.5 2.5 0 0 1 18 6.5V20H7.5A2.5 2.5 0 0 1 5 17.5z"/><path d="M8.5 8.5h6M8.5 11.5h6M8.5 14.5h4"/>`,
  gps: `<path d="M12 21s-6.5-6.4-6.5-11.2a6.5 6.5 0 0 1 13 0C18.5 14.6 12 21 12 21z"/><circle cx="12" cy="9.8" r="2.3"/>`,
  comm: `<path d="M12 21V11.5"/><circle cx="12" cy="9.5" r="1.6" fill="currentColor"/><path d="M8.6 6.2a4.8 4.8 0 0 0 0 6.6M15.4 6.2a4.8 4.8 0 0 1 0 6.6"/>`,
  longcomm: `<path d="M12 21V11.5"/><circle cx="12" cy="9.5" r="1.6" fill="currentColor"/><path d="M8.6 6.2a4.8 4.8 0 0 0 0 6.6M15.4 6.2a4.8 4.8 0 0 1 0 6.6M5.8 3.4a8.8 8.8 0 0 0 0 12.2M18.2 3.4a8.8 8.8 0 0 1 0 12.2"/>`,
  scan: `<circle cx="7.5" cy="15.5" r="3.6"/><circle cx="16.5" cy="15.5" r="3.6"/><path d="M11 15h2M4.6 13.4 6.6 6.5h3l.9 6.4M19.4 13.4 17.4 6.5h-3l-.9 6.4"/>`,
  detect: `<circle cx="12" cy="12" r="2" fill="currentColor"/><path d="M8.2 8.2a5.4 5.4 0 0 0 0 7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6M5.2 5.2a9.6 9.6 0 0 0 0 13.6M18.8 5.2a9.6 9.6 0 0 1 0 13.6"/>`,
  mildetect: `<circle cx="12" cy="13" r="2" fill="currentColor"/><path d="M8.2 9.2a5.4 5.4 0 0 0 0 7.6M15.8 9.2a5.4 5.4 0 0 1 0 7.6M5.2 6.2a9.6 9.6 0 0 0 0 13.6M18.8 6.2a9.6 9.6 0 0 1 0 13.6M9.4 4.2 12 2.6l2.6 1.6"/>`,
  relay: `<path d="M12 9.5 8 21M12 9.5 16 21M9.2 17.5h5.6M10.3 13.6h3.4"/><circle cx="12" cy="7.6" r="1.6" fill="currentColor"/><path d="M8.4 4.4a5 5 0 0 0 0 6.4M15.6 4.4a5 5 0 0 1 0 6.4"/>`,
  eco: `<rect x="3" y="7" width="16" height="10" rx="2"/><path d="M21 10.5v3"/><path d="M11.6 8.8 9 12.4h3.2l-1.8 3" />`,
  lock: `<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>`,
  plus: `<path d="M12 6v12M6 12h12"/>`,
  check: `<path d="M5 12.5 9.5 17 19 7"/>`,
  none: `<path d="M7 7l10 10M17 7 7 17"/>`,
  pause: `<path d="M9 6.5v11M15 6.5v11"/>`,
  clock: `<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>`,
  warn: `<path d="M12 3.5 21.5 20h-19z"/><path d="M12 10v4.5"/><circle cx="12" cy="17.2" r=".9" fill="currentColor"/>`,
  card: `<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 10h18"/><rect x="6" y="13" width="4" height="2.5" rx=".6" fill="currentColor"/>`,
  watch: `<rect x="7" y="6.5" width="10" height="11" rx="3"/><path d="M9 6.5V3h6v3.5M9 17.5V21h6v-3.5M12 9.5V12l1.6 1"/>`,
  close: `<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>`,
  battery: `<rect x="2.5" y="7" width="17" height="10" rx="2"/><path d="M21.5 10.5v3"/>`,
  infinity: `<path d="M8 9.5c-2.5-2-5.5-.5-5.5 2.5s3 4.5 5.5 2.5l8-5c2.5-2 5.5-.5 5.5 2.5s-3 4.5-5.5 2.5z"/>`,
  light: `<path d="M4 9.5h6.5l3-2.5v10l-3-2.5H4z"/><path d="M16.5 8.5 20 7M16.5 12h4M16.5 15.5 20 17"/>`,
  cloud: `<path d="M7.5 18.5h9.5a4 4 0 0 0 .4-8 5.5 5.5 0 0 0-10.6 1.4A3.3 3.3 0 0 0 7.5 18.5z"/>`,
};

export function icon(name, { size = 20, cls = "" } = {}) {
  return `<svg class="ico ${cls}" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${ICON_PATHS[name]}</svg>`;
}

// 電量圖示：電量格寬度隨百分比變化。
export function batteryIcon(pct, size = 22) {
  const w = Math.max(0, Math.min(1, pct / 100)) * 13;
  return `<svg class="ico" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${ICON_PATHS.battery}<rect x="4.5" y="9" width="${w.toFixed(1)}" height="6" rx=".8" fill="currentColor" stroke="none"/></svg>`;
}
