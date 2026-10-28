# Demo-Skript (3:00)

Das Video ist im Finale das wichtigste Artefakt: Die Top 5 je Track werden nur noch anhand der Videos gerankt ("Is the demo video genuinely cool to watch?"). Es zeigt ausschließlich, was in der Bauphase entstanden ist, und sagt das auch.

Heldenfall: eine echte Jeans mit Riss neben der Seitennaht. Gedreht wird mit echtem Kleidungsstück, echtem iPhone und Live-Proxy. Jede Zahl stammt aus `impact.md` (belegt) oder `benchmark.md` (gemessen).

| Zeit | Bild | Ton (Englisch, deutsche UI mit Untertiteln) | Kriterium |
| --- | --- | --- | --- |
| 0:00–0:10 | Hände halten die Jeans mit Riss. Schnitt auf eine Mülltonne. Einblendung "1 truck of clothing per second" (Ellen MacArthur Foundation) | "Every second, a truckload of clothing is landfilled or burned. Often because of a tear you could fix in 20 minutes." | Impact |
| 0:10–0:28 | **Live-Scan:** Kamera fährt über die Jeans, Eckklammern suchen, der Rahmen wird orange: "Riss erkannt – halt still". Die Maske klebt am Stoff, während die Kamera sich bewegt. Badge "SAM 3.1 · live 790 ms". Auto-Aufnahme | "Point your phone at it. SAM 3.1 finds the damage live, and the overlay sticks to the fabric while you move." | Meta-Tools, Demo |
| 0:28–0:50 | **Analyse mit Agenten-Trace:** Scan-Strahl läuft über das Foto, darunter die Schritte live: "Muse Spark prüft Objekt und Sicherheit", "SAM 3.1 sucht „rip“", "Muse Spark lokalisiert Schaden", "SAM 3.1 segmentiert", "Muse Spark prüft Maske ✓". Die Masken erscheinen pixelgenau entlang der ausgefransten Ränder | "SAM can't find a tear by name, because a tear is a gap, not an object. So Muse Spark locates it and hands SAM a box, and SAM returns a pixel-accurate mask. A Muse Wonder agent checks its own masks and re-segments if they're off." | Meta-Tools (überrascht), Tech |
| 0:50–1:05 | **Diagnose:** Label-Pins mit Score, "Vermutlich Denim". Optionale Karte "Etikett fotografieren" → Etikett → Banner "98 % Baumwolle · 2 % Elasthan", Einkaufsliste wechselt animiert auf dehnbaren Flicken | "It doesn't interrogate you. It assumes denim and tells you so. Add the label if you want, and the plan changes: elastane needs a stretchy patch." | Demo, Tech |
| 1:05–1:22 | **Entscheidung mit Muse Image:** Vorher/Nachher-Slider auf dem eigenen Foto. Daumen zieht den Slider, der Riss ist gestopft. "Selbst reparieren · 40–70 Min · 5–12 €" | "Honest recommendation, and Muse Image shows your own jeans repaired, before you thread a needle." | Meta-Tools, Demo |
| 1:22–1:32 | Einkaufsliste: abhaken, teilen | "Exactly what the steps need. Nothing else." | Impact |
| 1:32–2:05 | **Stichpfad, Signature-Moment:** Der Stichpfad zeichnet sich über den echten Riss (3 s ungeschnitten). Dann "Live auf dem Stoff": derselbe Pfad liegt auf dem Kamerabild der echten Jeans. Schnitt auf echte Hände, die nach dem Pfad nähen. Sprachbefehl "weiter" (Muse Voice) | "The app computes the stitch path itself from SAM's mask: skeleton, centerline, evenly spaced stitches. Then it projects it onto the real fabric. Hands busy? Just say 'next'." | Demo (Signature), Tech |
| 2:05–2:15 | **Pulli:** drei Mottenlöcher, drei Masken, drei Stopf-Schritte. Muse-Image-Vorschau: alle drei gestopft | "Three holes, three masks, three darning steps." | Meta-Tools |
| 2:15–2:27 | **Sneaker:** Klebezone als schraffiertes Band entlang der gelösten Sohle, Pressrichtungspfeile, Countdown-Ring | "Shoes too: where to glue, which way to press, how long to wait." | Demo |
| 2:27–2:37 | **Heizjacke mit Akku:** Sperre nach 3 s | "And where it gets dangerous, there are no instructions. Batteries, helmets, mains power are blocked before any diagnosis." | Tech, Verantwortung |
| 2:37–2:47 | **Ausblick Elektronik:** USB-Platine, SAM markiert rotes und schwarzes Kabel, Spark liest +/− und verbindet Kabelende und Pad | "Next: low-voltage electronics. Which wire goes where, and where to solder." | Impact |
| 2:47–3:00 | Pipeline-Grafik (Spark → SAM → App-Geometrie → Wonder → Image), Benchmark-Zahlen mit Fehlern, Endkarte "Built during the hackathon · repo link" | "Five Meta models, each with a job only it can do. Tested on our own cases, failures included. Repair instead of replace." | Tech, Impact |

## Drehhinweise

- Erst die echte Jeans live analysieren und die Bildschirmaufnahme laufen lassen, dann wirklich nähen. So entsteht echte B-Roll. Nichts faken: Benchmark-Zahlen nur aus `benchmark.md`.
- Live-Scan und "Live auf dem Stoff" auf dem echten iPhone drehen, denn der Simulator hat keine Kamera.
- Für ruhige Takes in der Analyse: Einstellung "schnell" im Demo-Modus. Im Video die echte Latenz ehrlich nennen (etwa 30 s).
- Bildschirmaufnahme im Hochformat, für 16:9 mit Rand schneiden. Untertitel auf Englisch.
- Video und README kennzeichnen, dass alles in der Bauphase entstand (Official Rules, sonst Disqualifikation).
- Für den Bonus "Most Viral": 30-s-Schnitt von 1:32–2:05 als X-Post.
