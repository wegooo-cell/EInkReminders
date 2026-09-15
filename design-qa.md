# Design QA — NOTE4 四视图选择页

## Evidence

- Source visual truth: `/var/folders/4k/thzswf395k70hfzmrvtvhfph0000gn/T/codex-clipboard-8eaeaccf-9ee9-424d-bda0-d63fdb51ae07.png`
- Implementation screenshot: `/Users/weihongli/Documents/New project/EInkReminders/previews/note4-view-picker.png`
- Side-by-side comparison: `/Users/weihongli/Documents/New project/EInkReminders/previews/view-picker-comparison.png`
- Source pixels: 538 × 286. Implementation pixels and physical viewport: 400 × 300 at 1×, matching the NOTE4 panel. Comparison canvas: 840 × 340.
- State: “今天” selected; representative counts 3 / 6 / 8 / 12. Counts are drawn dynamically by firmware from the Mac snapshot.

## Full-view comparison

The implementation preserves the source's 2 × 2 smart-list hierarchy, reading order, rounded-card proportions, icon/title/count placement, and clearly distinct selected state. Color has intentionally been translated to one-bit black and white: selection uses a sparse e-ink-safe dither plus a heavier outline. A compact title and hardware-control footer are intentional additions required by the physical device's settings navigation.

## Required fidelity surfaces

- Fonts and typography: PingFang-derived CJK rasterization keeps the hierarchy legible at 400 × 300. Labels and counts retain the source's bold emphasis; the footer is intentionally smaller secondary text.
- Spacing and layout rhythm: two equal columns and two equal rows align consistently, with balanced gutters and enough separation from the title and footer.
- Colors and visual tokens: the colorful source cards are correctly reduced to pure black/white and a dither selection token for the monochrome panel.
- Image and icon quality: all four icons come from macOS SF Symbols rather than hand-drawn approximations. They remain recognizable after one-bit conversion.
- Copy and content: exactly four modules are present—今天、计划、全部、完成—with live numeric counts and explicit key guidance.

## Focused-region comparison

No separate crop was needed because the native 400 × 300 implementation and every card label, symbol, count, border, and footer remain readable in the side-by-side comparison.

## Findings

- No actionable P0, P1, or P2 differences remain.
- P3: the “计划” symbol contains finer pixels than the other three SF Symbols, but it is still recognizable on the native panel and does not affect navigation.

## Comparison history

- First pass: SF Symbols were absent from the rendered bitmap. Fixed by rasterizing the system-symbol CGImage directly into the one-bit frame.
- Second pass: all icons, labels, counts, card borders, and the selected state are visible in the post-fix comparison.

## Implementation checklist

- [x] 2 × 2 layout
- [x] Four required smart views
- [x] SF Symbols icons
- [x] Dynamic counts
- [x] Monochrome selected state
- [x] Hardware navigation footer

final result: passed
