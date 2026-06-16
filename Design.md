# Galt 色彩规范 v2.0 · 亮 / 暗双模式

> 主色 `#212121`（单色品牌，暗色反转为 `#F4F4F4`）· 青绿为唯一彩色点缀 · 可直接落地 CSS `data-theme` / Figma Variables 双 mode

---

## 0. 核心决策

`#212121` 是一个近黑的中性色。把它当主色，意味着 Galt 是**单色品牌（monochrome-primary）**：主按钮、关键强调、主文字都用近黑，青绿（Teal）退为**唯一**的彩色点缀，仅用于图表与高亮。

这带来一个亮暗必须解决的问题：**暗色模式下背景本身就在 `#212121` 附近，主色不能再用它**。所以品牌身份的本质不是「`#212121` 这个值」，而是「**与背景对比度最高的中性色**」：

| | 亮色 Light | 暗色 Dark |
|---|---|---|
| primary | `#212121`（深块 + 白字） | `#F4F4F4`（浅块 + 深字） |

三条贯穿全表的规则：

1. **primary 反转**：亮 `#212121` ↔ 暗 `#F4F4F4`，两种模式下主按钮都是「最高对比实心块」。
2. **暗色表面层级越高越亮**：画布 `#161616` → 面板 `#1E1E1E` → 卡片 `#262626` → 浮层 `#303030`。
3. **彩色在暗色下统一提亮一档**：青绿、语义色都比亮色更亮、更不易发灰。

---

## 1. 亮色模式 · Light

### Primary（近黑）

| Token | Hex | 用途 |
|---|---|---|
| `primary` | `#212121` | 主按钮填充、关键强调、选中文字 |
| `primary-hover` | `#383838` | 悬停（略提亮） |
| `primary-active` | `#0A0A0A` | 按下态 |
| `primary-subtle` | `#ECECEC` | 选中行 / 浅强调底 |
| `on-primary` | `#FFFFFF` | 主色块上的文字 |

### Neutrals（纯中性灰阶）

| Token | Hex | Token | Hex |
|---|---|---|---|
| `neutral-0` | `#FFFFFF` | `neutral-500` | `#757575` |
| `neutral-50` | `#FAFAFA` | `neutral-600` | `#5C5C5C` |
| `neutral-100` | `#F5F5F5` | `neutral-700` | `#424242` |
| `neutral-150` | `#EEEEEE` | `neutral-800` | `#303030` |
| `neutral-200` | `#E2E2E2` | `neutral-850` | `#262626` |
| `neutral-300` | `#CFCFCF` | `neutral-900` | `#212121` |
| `neutral-400` | `#9E9E9E` | `neutral-950` | `#161616` |

### Text · Surface · Border

| Token | Hex | 用途 |
|---|---|---|
| `text-primary` | `#212121` | 正文与标题（与主色同值） |
| `text-secondary` | `#757575` | 副标题、说明、时间戳 |
| `text-tertiary` | `#9E9E9E` | 占位符、最弱信息 |
| `text-on-primary` | `#FFFFFF` | 主色块上文字 |
| `surface-canvas` | `#ECECEC` | 窗口画布 |
| `surface-panel` | `#F5F5F5` | 主内容面板 |
| `surface-card` | `#FFFFFF` | 卡片、列表项 |
| `border-default` | `#E2E2E2` | 描边、分隔线 |
| `track` | `#F0F0F0` | 进度条底、侧栏激活底 |

### Accent · Semantic

| 角色 | 主色 | 浅底 | 用途 |
|---|---|---|---|
| `accent`（青绿） | `#16AAAC` | `#EAF8F7` | 图表高亮、数据强调（唯一彩色） |
| `success` | `#2BA86A` | `#E6F6EE` | 完成、正向增长 |
| `warning` | `#E8973B` | `#FBEBD5` | 提醒 |
| `danger` | `#E5484D` | `#FDE3E4` | 错误、删除 |
| `info` | `#2E8FE6` | `#E4ECF9` | 中性提示 |

### Soft Surfaces（KPI 柔色面）

| Token | Hex | 固定映射 |
|---|---|---|
| `soft-teal` | `#DAEFEA` | 总字数 / 输出 |
| `soft-amber` | `#FAE2CC` | 今日字数 |
| `soft-sky` | `#E4ECF9` | 使用时间 |
| `soft-rose` | `#F0DEDE` | 累计听写 |

### Category Tags

| Token | 背景 | 文字 |
|---|---|---|
| `tag-blue` | `#DCEBFC` | `#1E6FD0` |
| `tag-teal` | `#D3F1F0` | `#0B7074` |
| `tag-rose` | `#FBE0E6` | `#C23B58` |
| `tag-violet` | `#E9E4FB` | `#6B4FD0` |
| `tag-amber` | `#FBEBD5` | `#B5712A` |
| `tag-green` | `#E0F2E6` | `#2B7A4B` |

---

## 2. 暗色模式 · Dark

### Primary（反转为近白）

| Token | Hex | 用途 |
|---|---|---|
| `primary` | `#F4F4F4` | 主按钮填充 + 深字 |
| `primary-hover` | `#FFFFFF` | 悬停 |
| `primary-active` | `#D4D4D4` | 按下态 |
| `primary-subtle` | `#2A2A2A` | 选中行 / 浅强调底 |
| `on-primary` | `#212121` | 主色块上的文字 |

### Neutrals（暗色阶 · 数值越小越亮）

| Token | Hex | Token | Hex |
|---|---|---|---|
| `neutral-1000` | `#0A0A0A` | `neutral-500` | `#757575` |
| `neutral-950` | `#161616` | `neutral-400` | `#9E9E9E` |
| `neutral-900` | `#1E1E1E` | `neutral-300` | `#CFCFCF` |
| `neutral-850` | `#262626` | `neutral-200` | `#E2E2E2` |
| `neutral-800` | `#303030` | `neutral-100` | `#F4F4F4` |
| `neutral-700` | `#424242` | | |
| `neutral-600` | `#5C5C5C` | | |

### Text · Surface · Border

| Token | Hex | 用途 |
|---|---|---|
| `text-primary` | `#F4F4F4` | 正文与标题（近白不刺眼） |
| `text-secondary` | `#A8A8A8` | 副标题、说明 |
| `text-tertiary` | `#7A7A7A` | 最弱信息 |
| `text-on-primary` | `#212121` | 主色块（浅）上文字 |
| `surface-canvas` | `#161616` | 窗口画布（最深） |
| `surface-panel` | `#1E1E1E` | 主内容面板 |
| `surface-card` | `#262626` | 卡片、列表项 |
| `surface-raised` | `#303030` | 浮层、弹窗 |
| `border-default` | `#383838` | 描边、分隔线 |

### Accent · Semantic（提亮以适应深底）

| 角色 | 主色 | 暗底 | 文字 |
|---|---|---|---|
| `accent`（青绿） | `#45BDBC` | `#103B3C` | `#7DCFCB` |
| `success` | `#3FBE7E` | `#14301F` | `#6FD79B` |
| `warning` | `#F0A94E` | `#322713` | `#F4C07E` |
| `danger` | `#F0595E` | `#3A1718` | `#F58A8E` |
| `info` | `#4FA0EE` | `#14243A` | `#80B6F2` |

### Soft Surfaces（深色 KPI 面 · 深底 + 浅字）

> 注意：浅色 pastel **不可**直接照搬到暗色（会糊成亮斑）。改为深色调底配浅色字。

| Token | 底色 | 文字 | 固定映射 |
|---|---|---|---|
| `soft-teal` | `#16312C` | `#7DCFCB` | 总字数 / 输出 |
| `soft-amber` | `#322713` | `#F0C079` | 今日字数 |
| `soft-sky` | `#16243A` | `#80B6F2` | 使用时间 |
| `soft-rose` | `#331E22` | `#E68BA0` | 累计听写 |

### Category Tags

| Token | 背景 | 文字 |
|---|---|---|
| `tag-blue` | `#16263D` | `#7FB4F0` |
| `tag-teal` | `#103B3C` | `#5FD0CE` |
| `tag-rose` | `#3A1E26` | `#E68BA0` |
| `tag-violet` | `#241E3D` | `#A892F0` |
| `tag-amber` | `#322713` | `#E0A961` |
| `tag-green` | `#16301F` | `#6FCF8F` |

---

## 3. 亮 / 暗 关键 Token 对照

| 角色 Token | 亮色 Light | 暗色 Dark | 说明 |
|---|---|---|---|
| `primary` | `#212121` | `#F4F4F4` | 核心反转：最高对比中性 |
| `on-primary` | `#FFFFFF` | `#212121` | 主按钮上的文字 |
| `text-primary` | `#212121` | `#F4F4F4` | 正文主色 |
| `text-secondary` | `#757575` | `#A8A8A8` | 次要文字 |
| `surface-canvas` | `#ECECEC` | `#161616` | 窗口画布 |
| `surface-panel` | `#F5F5F5` | `#1E1E1E` | 主面板 |
| `surface-card` | `#FFFFFF` | `#262626` | 卡片（暗色越高越亮） |
| `border-default` | `#E2E2E2` | `#383838` | 描边 |
| `accent`（青绿） | `#16AAAC` | `#45BDBC` | 暗色提亮一档 |
| `success` | `#2BA86A` | `#3FBE7E` | 语义色均提亮 |
| `danger` | `#E5484D` | `#F0595E` | 语义色均提亮 |

---

## 4. 系统色 · System（两模式共用，保留不动）

| 用途 | Hex |
|---|---|
| 关闭 Close | `#FF736A` |
| 最小化 Minimize | `#FEBC2E` |
| 缩放 Zoom | `#19C332` |

---

## 5. CSS 变量

```css
/* ===== 亮色模式（默认） ===== */
:root {
  /* Primary */
  --primary:#212121; --primary-hover:#383838; --primary-active:#0A0A0A;
  --primary-subtle:#ECECEC; --on-primary:#FFFFFF;
  /* Neutrals */
  --neutral-0:#FFFFFF; --neutral-50:#FAFAFA; --neutral-100:#F5F5F5; --neutral-150:#EEEEEE;
  --neutral-200:#E2E2E2;--neutral-300:#CFCFCF;--neutral-400:#9E9E9E;--neutral-500:#757575;
  --neutral-600:#5C5C5C;--neutral-700:#424242;--neutral-800:#303030;--neutral-850:#262626;
  --neutral-900:#212121;--neutral-950:#161616;--neutral-1000:#0A0A0A;
  /* Text · Surface · Border */
  --text-primary:#212121; --text-secondary:#757575; --text-tertiary:#9E9E9E; --text-on-primary:#FFFFFF;
  --surface-canvas:#ECECEC; --surface-panel:#F5F5F5; --surface-card:#FFFFFF; --surface-raised:#FFFFFF;
  --border-default:#E2E2E2; --track:#F0F0F0;
  /* Accent · Semantic */
  --accent:#16AAAC; --accent-subtle:#EAF8F7; --accent-fg:#0B7074;
  --success:#2BA86A; --success-subtle:#E6F6EE; --success-fg:#1C7A4B;
  --warning:#E8973B; --warning-subtle:#FBEBD5; --warning-fg:#B5712A;
  --danger:#E5484D;  --danger-subtle:#FDE3E4;  --danger-fg:#B5363A;
  --info:#2E8FE6;    --info-subtle:#E4ECF9;    --info-fg:#1E6FD0;
  /* Soft surfaces (KPI) */
  --soft-teal:#DAEFEA; --soft-amber:#FAE2CC; --soft-sky:#E4ECF9; --soft-rose:#F0DEDE;
  --soft-teal-fg:#0B7074; --soft-amber-fg:#B5712A; --soft-sky-fg:#1E6FD0; --soft-rose-fg:#C23B58;
  /* Tags */
  --tag-blue-bg:#DCEBFC;   --tag-blue-fg:#1E6FD0;
  --tag-teal-bg:#D3F1F0;   --tag-teal-fg:#0B7074;
  --tag-rose-bg:#FBE0E6;   --tag-rose-fg:#C23B58;
  --tag-violet-bg:#E9E4FB; --tag-violet-fg:#6B4FD0;
  --tag-amber-bg:#FBEBD5;  --tag-amber-fg:#B5712A;
  --tag-green-bg:#E0F2E6;  --tag-green-fg:#2B7A4B;
}
/* ===== 暗色模式 ===== */
[data-theme="dark"] {
  /* Primary（反转） */
  --primary:#F4F4F4; --primary-hover:#FFFFFF; --primary-active:#D4D4D4;
  --primary-subtle:#2A2A2A; --on-primary:#212121;
  /* Text · Surface · Border */
  --text-primary:#F4F4F4; --text-secondary:#A8A8A8; --text-tertiary:#7A7A7A; --text-on-primary:#212121;
  --surface-canvas:#161616; --surface-panel:#1E1E1E; --surface-card:#262626; --surface-raised:#303030;
  --border-default:#383838; --track:#2A2A2A;
  /* Accent · Semantic（提亮） */
  --accent:#45BDBC; --accent-subtle:#103B3C; --accent-fg:#7DCFCB;
  --success:#3FBE7E; --success-subtle:#14301F; --success-fg:#6FD79B;
  --warning:#F0A94E; --warning-subtle:#322713; --warning-fg:#F4C07E;
  --danger:#F0595E;  --danger-subtle:#3A1718;  --danger-fg:#F58A8E;
  --info:#4FA0EE;    --info-subtle:#14243A;    --info-fg:#80B6F2;
  /* Soft surfaces（深底 + 浅字） */
  --soft-teal:#16312C; --soft-amber:#322713; --soft-sky:#16243A; --soft-rose:#331E22;
  --soft-teal-fg:#7DCFCB; --soft-amber-fg:#F0C079; --soft-sky-fg:#80B6F2; --soft-rose-fg:#E68BA0;
  /* Tags */
  --tag-blue-bg:#16263D;   --tag-blue-fg:#7FB4F0;
  --tag-teal-bg:#103B3C;   --tag-teal-fg:#5FD0CE;
  --tag-rose-bg:#3A1E26;   --tag-rose-fg:#E68BA0;
  --tag-violet-bg:#241E3D; --tag-violet-fg:#A892F0;
  --tag-amber-bg:#322713;  --tag-amber-fg:#E0A961;
  --tag-green-bg:#16301F;  --tag-green-fg:#6FCF8F;
}
```

---

## 6. 落地要点

1. **token 名两模式一致，只换值**——这是亮暗系统的铁律，组件里只引用语义 token（如 `var(--primary)`），不写死 hex。
2. **暗色 KPI 不可照搬浅色 pastel**——必须用深色调底 + 浅字（已在 §2 处理）。
3. **进 Figma**：建一个 collection，挂 Light / Dark 两个 mode，token 名与本表逐行对应，值随 mode 切换。
4. **系统红绿灯不纳入主题**，两模式共用原值。

---

*Galt 色彩规范 v2.0 · 单色品牌锚定 #212121 · 暗色主色反转 #F4F4F4 · 青绿为唯一彩色点缀 · 适用 macOS 客户端亮 / 暗双模式。*
