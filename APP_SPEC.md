# Galt App Spec

> Galt is a macOS menu bar AI dictation app. This document is the product, UX, and desktop application specification for future implementation work. It follows Apple's macOS desktop conventions where they fit Galt's product model.

## 1. Product Positioning

Galt is a lightweight macOS speech input utility that stays out of the way during normal work.

Primary job:
- Hold or tap a global hotkey, speak, and insert polished text into the current app.
- Provide a control console for history, dictionary, usage insight, and settings.
- Keep sensitive data local unless the user chooses a cloud transcription or LLM provider.

Product category:
- Menu bar utility app.
- Single primary console window.
- Voice input, transcription, rewriting, translation, and personal vocabulary management.

Non-goals:
- Do not behave like a document editor.
- Do not open multiple main windows.
- Do not use a separate Settings window while the console window exists.
- Do not make the console a marketing or onboarding surface.

## 2. Platform Requirements

Minimum platform:
- macOS 14.0 or later.
- SwiftUI + AppKit hybrid implementation.
- `LSUIElement = true`; the app is primarily accessed from the menu bar.

Required permissions:
- Microphone: for recording speech.
- Accessibility: for global hotkey handling and text injection.
- Speech Recognition: for Apple on-device speech recognition.
- Keychain: for API keys and provider secrets.

Permission copy must be specific and task-oriented. Avoid vague prompts like "improve your experience".

## 3. Apple Desktop Principles

Galt follows these macOS desktop principles:

- Respect system window controls. Use standard close, minimize, and zoom controls; avoid duplicating close buttons inside the content area.
- Use a sidebar for persistent navigation when the window contains multiple destinations.
- Keep menus and menu bar commands focused on app-level actions.
- Use native controls where possible: buttons, menus, pickers, toggles, text fields, lists, and sheets.
- Support light and dark appearances unless a specific visual area has a functional reason to opt out.
- Preserve expected keyboard behavior for text fields, menus, and focus traversal.
- Prefer system dynamic colors or shared design tokens over one-off hardcoded colors.

Apple documentation reference points:
- Human Interface Guidelines: Windows, sidebars, menus, toolbars, settings, color, and feedback.
- SwiftUI: Windows, menu bar commands, Settings scene behavior, window style customization.
- AppKit: menu bar app behavior, NSWindow, NSStatusItem, NSPanel, dynamic system colors.

## 4. Application Architecture

Top-level runtime model:

```text
StatusBarController
  -> ConsoleWindowController
      -> ConsoleNavigation
          -> ConsoleView
              -> primary pages
              -> settings route
```

Core controllers:
- `StatusBarController`: menu bar item, menu commands, quick state toggles.
- `ConsoleWindowController`: owns the single console `NSWindow`.
- `ConsoleNavigation`: owns app route state for the console window.
- `DictationController`: coordinates hotkey-driven recording, transcription, polishing, and injection.
- `HUDController`: shows transient recording and completion feedback.

Core stores/providers:
- `SettingsStore`: user defaults backed app settings.
- `KeychainStore`: provider secrets and API keys.
- `HistoryStore`: local dictation history and statistics.
- `STTProvider`: transcription provider abstraction.
- `Polisher`: LLM polishing, translation, rewrite, and context adaptation.

## 5. Window Model

Galt uses one primary window: the console.

Console window:
- Default content size: `1200 x 800`.
- Minimum content size: `960 x 620`.
- Style: titled, closable, miniaturizable, resizable, full-size content view.
- Titlebar: hidden title and transparent titlebar.
- Window should center on first creation.
- Reopening the console should bring the existing window forward instead of creating another window.

Onboarding window:
- First-launch onboarding uses the same window controller, but an onboarding route-specific outer frame size.
- Outer frame size: `480 x 600`.
- Create the initial `NSWindow` content rect by converting this outer frame with `NSWindow.contentRect(forFrameRect:styleMask:)`, so the visible window height is exactly `600` including the titlebar/traffic-light area.

Settings:
- Settings is a second-level route inside the console window.
- Entering settings replaces the primary console layout; the primary sidebar is hidden.
- Settings has its own sidebar tabs.
- "返回应用" returns to the last primary page the user came from.

Do not add a second Settings `NSWindow` unless the product model changes.

## 6. Navigation Model

Use explicit route types:

```swift
enum ConsoleRoute {
    case primary(ConsolePrimaryPage)
    case settings
}

enum ConsolePrimaryPage {
    case overview
    case history
    case dictionary
}
```

Rules:
- Primary pages appear in the console's first-level sidebar.
- Secondary routes do not appear as primary pages.
- Settings is entered from the bottom settings row or menu bar command.
- Navigation state should preserve the last primary page for back navigation.
- Avoid placeholder route handling such as `EmptyView()` for real app destinations.

## 7. Information Architecture

Primary console pages:
- 首页: current productivity summary, dictation status, usage stats, recent activity.
- 历史: local dictation history, filtering, search, copy, retry, deletion, details.
- 词典: user vocabulary, automatic/manual term groups, add/search/edit/delete.

Secondary pages:
- 设置: app configuration, grouped by settings tabs.

Settings tabs:
- 通用: appearance, launch at login, Dock behavior, app-level behavior.
- 键盘快捷键: dictation, translation, ask-anything shortcuts.
- 语言: UI language, translation target, local recognition locale.
- 音频: microphone, sound feedback, mute behavior.
- 语音引擎: active selection only — engine mode (cloud/local/auto), active STT provider, active local engine, polish on/off, active LLM provider. Credentials and model strings live in 模型库, not here.
- 模型库: resource inventory — local models (Apple device status; full Whisper model list with per-model download/progress/delete/default) and provider models (per-provider API keys; STT provider model shown read-only, LLM provider model editable).

Do not add account, help center, changelog, or about pages unless they have real implemented content and clear product value.

Home page layout:
- The home route uses the same `1200 x 800` console window, `8px` outer inset, and `#EDEDEF` root background.
- The primary sidebar is `232px` wide; the content panel begins at `x=240`, measures `952 x 784`, uses `#F8F9FB`, `#E7E8EB` border, and `16px` corner radius. Primary selected row fill is `#DFE0E3`; bottom settings entry is a separate `24px` footer row with `14px` text (color `rgba(0,0,0,0.85)`) and a `16px` two-track sliders icon (Figma node 610:680), matching the Figma settings entry.
- Home content is centered in the panel with max width `904px` and starts `24px` from the top.
- Header title is `Galt`, `20px` semibold, color `#3C3D40`; subtitle is `Speak. The mind does the rest.`, `14px`, color `#8E8F90`.
- Metric cards: four cards, each `214 x 108`, `12px` radius, `16px` horizontal gap, top offset aligned to Figma. Use soft fills `#DAEFEA`, `#FAD8BC`, `#E4ECF9`, `#DAEFEA`.
- Middle row: two white cards, each `444 x 167`, `16px` radius, `16px` gap. Left is productivity trend; right is personalization status.
- Recent transcription card: white `904 x 358`, `16px` radius, placed below the middle row with `15px` gap.

History page layout:
- The history route uses the same `1200 x 800` console window, `232px` primary sidebar, `8px` outer inset, and `#F8F9FB` right content panel.
- Content uses an explicit `24px` horizontal inset inside the right panel with max width `904px`; title starts `24px` from the panel top and uses `20px` semibold text, color `#3C3D40`, line height `28px`.
- The history settings block starts `19px` below the title and has two rows, each `48px` high, with `16px` vertical gap.
- Setting row title uses `14px` semibold `#1A1C1F`; helper text uses `14px` regular `#8E8F90` and stays on one line at the default window size.
- Retention picker is `128 x 28`, right-aligned in the first row, `8px` radius, white fill, `#EDEDED` border, `12px` label.
- Filter segmented control sits `16px` below the settings block, uses `#F1F1F1` background, `10px` radius, `2px` padding, `4px` item gap, and `12px` labels.
- Selected filter item uses white fill, `#EDEDED` border, and `8px` radius; item widths are fixed (`48px`, `48px`, `84px`) so switching tabs never changes the segmented control size.
- The record area starts `23px` below the filter. It renders date-grouped records when data exists; group titles use `12px` regular `#8E8F90`, `16px` line height, and sit `11px` above their card.
- Record groups do not use a white card background or outer border. Single records render as transparent `52px` rows on the panel background; multi-record groups stack `52px` rows with `#EDEDED` separators.
- History rows use `52px` minimum height, `16px` horizontal padding, `15px` vertical padding, time column width `54px`, `16px` gap, time text `14px` regular `#8E8F90`, and content text `14px` regular black.
- The resting row stays pure text (no retry, flag, more, copy, search, or large empty-state controls), matching the Figma. Per-row actions are revealed on hover at the trailing edge — copy 成稿文本 and delete — and the same actions (plus 复制原始转写 when raw differs) are available via right-click; the reserved trailing action width keeps text from reflowing on hover.
- Clicking a row toggles an expanded view of the original transcription when it differs from the polished text, respecting Reduce Motion.
- The 保存历史 retention picker is functional: 永久保留 / 30 天 / 14 天 / 7 天, persisted to `historyRetentionDays`; choosing a finite window (and entering the page) prunes records older than the cutoff.
- The empty state is quiet text only (a `15px` semibold title plus a `13px` `#8E8F90` line), varying by filter/search context; no illustrated card.
- Only the record timeline area scrolls when grouped records exceed the visible panel height; the title, history settings block, and filter segmented control remain fixed at the top of the right panel.
- Empty states below the filter should remain visually quiet; avoid large illustrated cards in this layout.

Dictionary page layout (Figma node 610:634):
- Same `1200 x 800` console window, `232px` primary sidebar, `8px` outer inset, `#F8F9FB` right content panel, `24px` horizontal inset, `904px` max content width.
- Title "词典" starts `24px` from the panel top, `20px` semibold, color `#3C3D40`, line height `28px`.
- "添加词语" button is right-aligned on the title row: `28px` high, `12px` horizontal padding, `8px` radius, fill `#1A1C1F`, `12px` white label. Opens the add-term sheet.
- A toolbar row sits `16px` below the title: filter segmented control on the left, search control on the right, row height `32px`.
- Filter segmented control: `#F1F1F1` background, `10px` radius, `2px` padding, `4px` item gap, items `28px` high with `12px` horizontal padding and `12px` labels. Tabs are 全部 / 自动添加 / 手动添加; 自动添加 and 手动添加 carry a small `16px` leading icon. Selected item uses white fill + `#EDEDED` border + `8px` radius.
- Search starts as a `32 x 32`, `10px` radius, `#F1F1F1` icon button; activating it expands a `240 x 32` inline search field (same fill) with a clear button.
- Terms render as a left-aligned wrapping grid of `214 x 32` chips with `16px` row/column gaps (four columns fill the `904px` width). Each chip is transparent with an `#EDEDED` border, `8px` radius, a `16px` leading icon, and a `12px` `#3C3D40` label; delete is revealed on hover and via right-click menu — the resting chip stays clean per the Figma.
- Only the chip grid scrolls; title and toolbar stay fixed. Empty state is quiet: `20px` semibold title plus a `13px` `#8E8F90` helper line, centered, no large card.

## 8. Menu Bar Behavior

The menu bar is the always-available control surface.

Required menu items:
- Short usage hint.
- Current stats summary.
- Open console.
- Toggle AI polishing.
- Translation mode submenu.
- Settings.
- Open dictation history file/folder if needed.
- Quit Galt.

Menu rules:
- Menu state must refresh when the menu opens.
- Toggle items should show accurate checked state.
- Translation submenu should show the current target.
- Menu commands should route to existing windows where possible.
- Do not open duplicate windows from menu commands.

## 9. Interaction Model

Dictation:
- Hold the configured hotkey to record; release to transcribe and insert.
- Tap the configured hotkey to lock recording; tap again to stop.
- HUD appears during recording and communicates current state.
- Completion, failure, and empty-audio states should be visible but transient.

Voice editing:
- If text is selected, spoken instructions may rewrite the selected content.
- Replacement should preserve the user's current app context when possible.

Translation:
- Translation mode converts spoken input into the selected target language.
- Translation mode is reachable from both menu bar and settings.

Settings:
- Changing settings should apply immediately when technically safe.
- Dangerous or irreversible actions should require confirmation.
- API keys should never be shown in plain text by default.

## 10. Visual System

Shared console/sidebar tokens live in code as `ConsoleDesign`.

Current canonical tokens:
- Primary console sidebar width: `232`.
- Primary sidebar row height: `32`.
- Primary sidebar row radius: `8`.
- Primary sidebar icon size: `14`.
- Primary sidebar icon width: `18`.
- Primary sidebar text size: `14`.
- Primary sidebar horizontal padding: `10`.
- Settings sidebar width: `232`.
- Settings sidebar row height: `32`.
- Settings sidebar row radius: `8`.
- Settings sidebar icon width: `18`.
- Settings sidebar text size: `14`.
- Console panel background: near-system off-white.
- Sidebar background: macOS sidebar-style light gray.
- Primary control color: `#23221F`.

Rules:
- Primary sidebar and settings sidebar should share interaction rhythm, but settings uses its own second-level dimensions from `SettingsDesign`.
- Do not duplicate colors or row dimensions outside shared tokens.
- Content panels may use cards only for grouped controls, records, and repeated items.
- Avoid nested cards.
- Use rounded rectangles conservatively; default card radius should stay modest.
- Text must fit at the minimum supported window size.

## 11. Settings UI Rules

Settings is a task-oriented configuration surface, not a marketing page.

Layout:
- The settings route uses the same `1200 x 800` console window, with an `8px` outer inset and background `#EDEDEF`.
- The left settings sidebar is `232px` wide and contains only second-level settings navigation.
- Sidebar top reserves `32px` for the titlebar/traffic-light area, then shows `返回应用` as the first row.
- Sidebar groups are `个人` and `引擎`; do not show account, about, help center, changelog, or settings search in this route.
- Sidebar rows are `32px` high, `8px` corner radius, `14px` text, `18px` icon column, and selected row fill `#DFE0E3`.
- The right content panel starts after the sidebar at `x=240`, fills the remaining `952 x 784`, uses background `#F8F9FB`, border `#E7E8EB`, and `16px` corner radius.
- Content inside the right panel is centered with max width `904px`.
- Page title starts at `24px` top inset, uses `20px` semibold text and `28px` line height.
- Setting rows use `14px` semibold title `#1A1C1F`, `14px` regular helper text `#8E8F90`, and a minimum height of `48px`.

Control choices:
- Toggles for boolean settings.
- Menus or pickers for exclusive choices.
- Buttons for explicit commands.
- Secure fields for secrets.
- Progress indicators for model downloads.
- Hotkey recorder for shortcuts.

Search:
- Settings search is intentionally omitted from the current Figma-derived layout.
- Add search only when setting volume justifies it and it can search individual rows, not only tabs.

## 12. Data and Privacy

Local data:
- History stays local under Application Support.
- Dictionary terms are stored locally and used in transcription/polishing prompts.
- Settings are stored in UserDefaults via `SettingsStore`.

Secrets:
- API keys belong in Keychain.
- Debug-only development storage may bypass Keychain prompts, but must stay behind `#if DEBUG`.
- Never log API keys, full provider authorization headers, or unredacted secrets.

Cloud behavior:
- Cloud STT and LLM providers require user-provided credentials.
- Auto mode may fall back from cloud to local recognition when configured.
- UI copy should make clear when data leaves the device.

## 13. Error and Feedback Rules

Use the least disruptive feedback that still helps the user act.

Examples:
- HUD for recording state and transient transcription result.
- Inline setting row error for missing API key or failed model download.
- Menu state for high-level on/off modes.
- System permission prompt only when the user action requires it.

Do not show modal alerts for routine transcription failures unless the user must make a decision.

## 14. Accessibility and Localization

Accessibility:
- All icon-only controls need help text or accessible labels.
- Focus order must follow visual order.
- Text fields, menus, and buttons must be keyboard reachable.
- Color should not be the only status indicator.

Localization:
- Current primary UI language is Simplified Chinese.
- User-facing strings should be written so they can later move to localized resources.
- Language settings must distinguish UI language, transcription locale, and translation target.

## 15. Implementation Rules

Architecture:
- Keep route state in `ConsoleNavigation`.
- Keep window ownership in `ConsoleWindowController`.
- Keep menu bar actions in `StatusBarController`.
- Keep settings persistence in `SettingsStore`.
- Keep secrets in `KeychainStore`.

SwiftUI:
- Use `@State private var` for view-local state.
- Use `@AppStorage` only when the setting is genuinely app-level and already has a stable key.
- Avoid placing unrelated business logic inside views.
- Prefer small subviews when a view grows past a single responsibility.

AppKit:
- Use AppKit for menu bar, global window ownership, panels, and low-level integration.
- Keep AppKit calls isolated at the edges of the SwiftUI view tree.

Testing and validation:
- Run Xcode diagnostics for changed Swift files.
- Run a full Xcode build after structural changes.
- Keep snapshot sizes aligned with real default window sizes.

## 16. Current Defaults

Window:
- Console default size: `1200 x 800`.
- Console minimum size: `960 x 620`.

Primary navigation:
- 首页
- 历史
- 词典
- 设置 entry at bottom, routes to secondary settings page.

Settings navigation:
- 返回应用
- Search settings
- 通用
- 键盘快捷键
- 语言
- 音频
- 语音引擎（合并自原「转写引擎」+「AI」，仅保留激活选择与开关）
- 模型库（本地模型下载管理 + 供应商凭证/模型目录）

Hotkeys:
- Dictation default: `fn`.
- Translation default: none.
- Ask default: none.

## 17. Change Control

Any future UI change should answer these questions before implementation:

1. Is this a primary page, secondary page, transient HUD, sheet, popover, or menu action?
2. Does it preserve the single-window console model?
3. Does it reuse `ConsoleDesign` tokens or intentionally introduce a new token?
4. Does it respect macOS-native controls and behaviors?
5. Does it expose data or secrets outside the local device?
6. Does it work at `960 x 620` and look correct at `1200 x 800`?

If a change violates this spec, update the spec first and explain the product reason.
