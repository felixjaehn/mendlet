# Demo script (3:00)

The video decides the final round: the top 5 per track are ranked on their videos alone ("Is the demo video genuinely cool to watch?"). It shows only what was built during the hackathon and says so.

Seven beats, one hero object (real jeans with a real tear), app UI in **English**, voice-over in English. Every number comes from `docs/impact.md` (sourced) or `docs/benchmark.md` (measured).

| Time | Picture | Voice-over | Criterion |
| --- | --- | --- | --- |
| 0:00–0:12 | **Hook.** Hands hold jeans with a tear next to the seam. Cut to a bin. Caption "1 truckload of clothing every second" (Ellen MacArthur Foundation) | "Every second, a truckload of clothing is landfilled or burned. Often because of one tear you could fix in twenty minutes." | Impact |
| 0:12–0:40 | **Live scan on a real iPhone.** Camera moves over the jeans, brackets search, frame turns orange: "Tear detected – hold still". The mask sticks to the fabric while the phone moves. Auto capture | "Point your phone at it. The app finds the damage live with SAM 3.1, and the outline stays on the fabric while you move." | Meta tools, Demo |
| 0:40–1:10 | **Agent log** (screen recording, fast replay). Scan beam, then the log: Spark checks safety, SAM searches "rip", server error, agent re-routes, Spark locates, SAM segments the box, Spark verifies the mask. Mask appears exactly along the frayed edges | "SAM can't find a tear by name, because a tear is a gap, not an object. So Muse Spark points at it and SAM cuts out the exact pixels. A Muse Wonder agent checks its own masks and recovers when a call fails." | Meta tools (surprise), Tech |
| 1:10–1:30 | **Before/after.** Divider sits on the tear; thumb drags it: left the tear, right the darned jeans (Muse Image). "Repair it yourself · 40–70 min · €5–12" | "Before you thread a needle, Muse Image shows your own jeans repaired. Then an honest call: repair it yourself, go to a pro, or replace it." | Meta tools, Demo |
| 1:30–2:15 | **Signature moment: the stitch path.** Darning path draws over the real tear (3 s uncut). Then "Live on the fabric": the same path on the camera image of the jeans. Cut to real hands darning along it. Voice command "next" (Muse Voice) | "The darning path is computed by the app itself from SAM's mask, warp first, then weft, anchored on intact fabric. Then it lies on the real fabric. Hands busy? Just say 'next'." | Demo (signature), Tech |
| 2:15–2:40 | **Breadth in three cuts.** Sweater: "3 holes" with three masks. Sneaker: glue zone, press arrows, 3-minute timer. USB board: red wire → "+" pad. Heated jacket: blocked in 3 seconds | "Three moth holes, three masks. Shoes: where to glue and which way to press. Electronics: which wire goes to which pad. And where it gets dangerous, like lithium batteries, there are no instructions." | Impact, Tech |
| 2:40–3:00 | **Proof and close.** Benchmark card: 16 live cases, 4/4 hazards blocked, 10/11 masks on the damage, 0 invalid JSON, failures listed. End card "Built during the Meta Global AI Developer Hackathon · repo link" | "Tested live on our own cases, failures included. Repair instead of replace." | Tech, Impact |

## Filming notes

- Real jeans, real iPhone, live proxy for beats 2 and 5. Analyse first, then actually darn: that gives honest B-roll.
- Beat 3 can use the recorded agent run (Settings → "Show agent run with error recovery"); label it on screen "recorded real API responses".
- Settings → "Fast (for video recording)" shortens the replay. State the real latency honestly once (about 24 s).
- Portrait screen recording via Control Center; cut to 16:9 with a frame. English subtitles.
- Do not show anything that was not built during the hackathon; the end card says so.
- For the "Most Viral" bonus: a 30-s cut of beat 5 as an X post.
