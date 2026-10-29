# HIG review (iOS app, iPhone 17 Pro, light + dark)

Checked against Apple HIG: Layout, Typography, Color, Materials, Buttons, Toolbars/Navigation, Camera patterns, Accessibility.

| Screen | Guideline | Result |
|---|---|---|
| Home (camera) | Camera: full-bleed preview, shutter centred, gallery thumbnail left, secondary mode right | pass |
| Home | Layout: controls respect safe areas, preview extends under status bar | fixed (preview was wider than the screen and pushed controls off-screen) |
| Home | Hit targets >= 44 pt (shutter 76, thumb 48, Live 48, top buttons 44) | pass |
| Home | Permissions: camera asked in context, denied state explains and links to Settings | pass |
| Home | Materials: controls on photo use dark scrim + glass, white symbols, contrast > 4.5:1 | pass |
| Home | VoiceOver: all icon buttons labelled (Photos, Take photo, Scan damage, History, Settings) | pass |
| Home | Reduce Motion: only a fade of the hint, no looping motion | pass |
| Analysis | Typography: text styles only (Dynamic Type), progress with text + colour (not colour alone) | pass |
| Diagnosis | Zoom/Refine controls on photo were 38 pt | fixed (44 pt, labelled, dark scrim) |
| Diagnosis | Zoom badge unreadable on light photos | fixed (dark scrim circle) |
| Decision | Cards on grouped background, one primary CTA in the bottom bar | pass |
| Shopping | Status buttons 36-40 pt | fixed (44 pt) |
| Shopping | Selection is not colour-only (icon + text) | pass |
| Guide | Step progress, one primary action, back/close in toolbar | pass |
| Completion / Block | One title, one CTA; block screen unchanged (safety gate) | pass |
| Settings | Standard grouped Form, destructive action in red | pass |
| All | Colour: system colours, accent system blue, no orange | pass |
| All | Dark Mode: system colours adapt; "All" chip was white-on-white | fixed (accent fill); home is always dark (camera) |
| All | No visible German, no demo wording | pass |
| All | Accessibility labels on interactive icons | pass; a few German VoiceOver-only hints remain (open, low risk) |
