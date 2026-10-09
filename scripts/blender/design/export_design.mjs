// 設計稿 → JSON（stdout）：七款錶正面 <g>、模組圖示路徑。build_watch_art.py 用 node 執行後交給 resvg 算圖。
// watch_svg.mjs 是主 MOD temp/design-minimap-watch-1005/svg.mjs 的原樣複本（設計稿更新時直接覆蓋）。
import { watchGroup, icon } from "./watch_svg.mjs";

const watches = ["valutech", "paws", "nexus", "spiffo", "ranger", "luthex", "crt", "crt-amber"];
const icons = ["ledger", "gps", "comm", "scan", "detect", "mildetect", "longcomm", "relay", "eco", "light", "card"];
process.stdout.write(JSON.stringify({
  watches: Object.fromEntries(watches.map((id) => [id, watchGroup(id)])),
  icons: Object.fromEntries(icons.map((id) => [id, icon(id, { size: 24 })])),
}));
