# Demo video: cut script (3:00)

Story: *"My sweater has a hole. Again."* One real hero object (Felix's grey knit sweater with a small hole), one real repair, filmed end to end. App UI in English, voice-over in English. Only features built during the hackathon (Oct 27 – Nov 4) are shown, and the end card says so.

Numbers are sourced in `docs/impact.md`: EEA 2022 (≈16 kg of textiles per person per year in the EU) and the Ellen MacArthur Foundation (one garbage truck of clothing landfilled or burned every second).

## Shot list

| # | Time | Picture | Voice-over / on-screen text | Meta model on screen |
| --- | --- | --- | --- | --- |
| 1 | 0:00–0:08 | **Cold open.** Felix pulls the grey sweater out of the drawer, holds it up, freezes. Close-up push-in on the small hole. | VO (beat of silence, then): *"Seriously? Again?"* | – |
| 2 | 0:08–0:25 | **The thought.** Felix on the bed, sweater in hand, looking from the bin to the sweater. **Infographic on the side (right third):** a pile of clothes grows into a mountain, counter ticking up to **16 kg**. Caption: *"16 kg of textiles thrown away per person, every year in the EU"* (EEA, 2022). | *"My first thought: just toss it. That's what most of us do. Every person in the EU throws away about sixteen kilos of textiles a year. Most of it isn't worn out. It just has one small hole."* | – |
| 3 | 0:25–0:45 | **Open the app.** Hands open Mendlet: Home with "Repairs". Tap **Scan**, camera opens (corner brackets). Point at the hole, take the photo. | *"So instead I open Mendlet and point my phone at the hole."* | – |
| 4 | 0:45–1:10 | **The mark (hero shot, screen recording).** Analysis sheet ticks through *Looking at your photo → Finding the damage → Outlining it*. The outline draws around the hole, the photo zooms in, the label "Hole" appears. Finding sheet: *"Small hole in grey knit sweater."* | *"A hole is hard for an AI to find, because it's not an object, it's missing fabric. Muse Spark first points at the damage, and SAM 3.1 cuts out the exact pixels, even for a hole this small."* Lower third: **Muse Spark → SAM 3.1** | Muse Spark, SAM 3.1 |
| 5 | 1:10–1:25 | **The verdict.** "Repair it yourself." with *20 to 35 min · Low effort · €3–8*. Thumb flips **Marked → Repaired**: Muse Image shows Felix's own sweater, mended. | *"Then an honest verdict: repair it yourself, about half an hour, a few euros. And Muse Image shows me my own sweater, repaired, before I've even threaded a needle."* Lower third: **Muse Image** | Muse Spark, Muse Image |
| 6 | 1:25–1:45 | **Shopping (table top-down).** Overhead shot of a wooden table. Felix lays out the items from the shop bag: darning needle, grey wool, small scissors. Phone lies next to it with **"Gather these first"**. Each tap on a checkbox: item ticks, *pling* sound, quick cut. Progress "3 of 4 ready". | *"Mendlet tells me exactly what to get. Needle, matching yarn, scissors. I picked them up on the way home."* | – |
| 7 | 1:45–2:25 | **The repair (real hands, real sweater).** Tap **Start repair**: full-screen photo guide. The stitch rows draw themselves over the hole, needle glyph running along. Cut between phone (step 3 *"Weave lengthwise threads"*) and real hands doing exactly that. The yarn puckers: Felix taps **Not working?** and just says *"The yarn pulls the knit together"*: Muse Voice transcribes, Spark answers *"Keep the threads looser…"*. Swipe on, final step, tap **Finish**, the before/after slider on "Mended". | *"The guide is drawn on my own photo. The app computes the darning path from SAM's mask: where to go in, where to come out. And when something goes wrong, I just say what's happening."* Lower third: **Muse Voice → Muse Spark** | SAM 3.1 (mask → stitch path), Muse Voice, Muse Spark |
| 8 | 2:25–2:45 | **Outlook in three quick cuts.** (a) Leather sole worn through: *"Take it to a pro."* (b) White sneaker: glue band and timer, the Live Activity on the lock screen. (c) Cracked bike helmet: *"This needs a specialist."*, no instructions. | *"It works on shoes too, and it's honest when it's not a DIY job. And where a repair could hurt you, like a cracked helmet or a lithium battery, there are no instructions at all."* | Muse Spark (safety gate) |
| 9 | 2:45–3:00 | **Close.** Felix pulls the mended sweater over his head, smiles. End card: **Mendlet**, *"Built during the Meta Global AI Developer Hackathon 2026"*, *SAM 3.1 · Muse Spark · Muse Image · Muse Voice · Muse Wonder*, repo link. | *"One hole, half an hour, three euros. And one sweater less on the pile."* | All |

## Optional (if time allows, from 2:25)

- 4-second insert from **Settings → How Mendlet works**: the real trace (*Spark is locating… · SAM is segmenting… · Spark is checking the outline*). It proves the multi-step pipeline. Lower third: *"Real trace of this analysis"*.
- Precision mode with **Muse Wonder** as one line: *"In precision mode, a Muse Wonder agent double-checks every outline."*

## Filming notes

- **Live, not replay:** Film beats 3–5 and 7 on the real iPhone against the live proxy (proxy on the Mac, iPhone in the same Wi-Fi). Speed up the 20–30 s analysis wait to about 3 s with a visible time cut. Don't hide it, edit it.
- **Hero object:** The real sweater is in the benchmark (`testdata/real/02_pulli_kleines_loch.jpg`). Film in the same light so the result matches.
- **Overhead table (beat 6):** phone on a stand or tripod straight down, daylight, wooden table. The *pling* is a sound effect in the edit, timed on every tick.
- **Repair B-roll (beat 7):** at least 3 close-ups: needle going in at the dot, the yarn grid growing, final tug test. Cut on the stitch row the phone is showing.
- **Infographic (beat 2):** flat illustration, neutral colours, no AI imagery. Animate the counter 0 → 16 kg, small source line "EEA, 2022" at the bottom.
- **Don't show:** demo-mode launch arguments, Xcode, the simulator. Only the real phone.
- **Rules:** The end card names the build window. Everything shown was built Oct 27 – Nov 4.
