# Übergabe (Stand 30.10.2026, früh)

Ziel: Eine unabhängige Jury bewertet 10/10 (Briefing: `docs/JUDGING-BRIEF.md`).

Jury-Verlauf in der Nacht (jede Runde ein frischer Agent, alle v8-Screenshots, README, Briefing):

| Runde | Gesamt | "Wirkt KI-generiert?" |
| --- | --- | --- |
| 1 | 7,6 | ja, leicht |
| 2 | 7,4 | ja, leicht |
| 3 | 7,0 | ja, leicht |
| 4 | 7,4 | **nein** |
| 5 | 7,2 | **nein** |
| 6 | 7,2 | **nein** (nach Live Activity, Übergängen, Haptik) |

Die Werte schwanken je nach Juror um etwa ±0,3. Gedeckelt sind sie durch zwei Punkte, die kein Design-Fix löst:

1. **Impact (30 %) liegt bei 6–7.** Echte Nutzer und eine echte, gefilmte Reparatur fehlen. Nutzergeschichten werden bewusst nicht erfunden.
2. **Use of Meta tooling bleibt unter 9.** Open-Weight-Modelle sind nicht eingebaut. Die Entscheidungsvorlage liegt in `docs/OPEN-WEIGHTS-PLAN.md`: Muse Glimmer lokal im Proxy für "Not working?", etwa 20 GB Download auf die SSD, Aufwand 4–6 Stunden. **Freigabe offen.**

## Stand
- Redesign nach `docs/design/REDESIGN-SPEC.md`: 28 Mobbin-Suchen, 69 Referenzbilder in `docs/design/refs/`. Home mit Projekten, Scan, Markierung, Befund, Urteil, "Before you start", Anleitung, Projekt, Abschluss, Sicherheitsstopp, Einstellungen. Name **Mendlet**, Icon `docs/branding/icon-b.png`.
- Nur Englisch, auch auf einem deutschen iPhone. Akzent System-Blau, kein Orange. Der PDF-Export ist entfernt.
- Diagnose-Prompt v7 sorgt für natürliche, kurze Texte mit "Done when". Live neu aufgenommen: Pulli (echtes Foto), Ledersohle (echtes Foto), verschlissenes Shirt (Replace mit "second life"), Sneaker, Pulli mit 3 Löchern, Jeans mit Etikett, Heizjacke, Helm.
- Tests: iOS 91 grün, Proxy 254 grün. Screenshots `docs/screenshots/v8-en-*.png` (32 Stück, frisch).
- Proxy-Fix: Eine präzise Spark-Box schlägt eine breite SAM-Schadensbox (Sohlenloch).

## Bekannte Lücken
- **Codex-Login:** Der Status meldet "aktiv", das Token lässt sich aber nicht erneuern, und Jobs scheitern sofort. Bitte `codex login` ausführen. Codex nie für Design einsetzen.
- **Muse Image:** Lieferte um ca. 05:00 HTTP 400 auf jede Anfrage, auch eine schlichte. Die Pulli-Vorschau zeigt deshalb noch die X-förmige Stopfstelle. Später neu erzeugen (Skript-Muster: `after_preview` mit `stitch_type=darning`).
- **Platine:** Die Aufnahme mit v7 hat die Polarität verloren. Die alte Aufnahme mit längeren Texten bleibt drin.
- **Shirt:** SAM markiert nur 1 von vielen Löchern. Beim Urteil "Replace" wird deshalb kein Label gezeigt.

## Nur durch den Menschen
Video drehen: ein echtes, unbekanntes Teil am echten iPhone gegen den Live-Proxy. Das bringt laut Jury den größten Gewinn bei "Demo". Außerdem: Live-Scan auf dem Gerät testen, Repo veröffentlichen (vorher Subtree-Split nach `~/Desktop/repair-assistant` erneuern), Discord-Fragen klären, Open Weights freigeben oder ablehnen, `codex login`.
