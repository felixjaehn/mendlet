# Übergabe (Stand 29.10.2026, abends)

Ziel: unabhängige Jury bewertet 10/10 (Briefing: `docs/JUDGING-BRIEF.md`). Letzte Gesamt-Jury 7,1/10, letzte Demo-Jury 8/10. Beide noch vor dem iOS-27-Umbau und dem PDF-Export.

## Stand
- Proxy (252 Tests offline grün) und iOS (82 Tests grün), letzter Commit `6dc3cd7`.
- Live verifiziert: SAM 3.1, Muse Spark (Grounding → SAM-Box), Muse Image (Vorher/Nachher), Muse Wonder (Präzisionsmodus), Muse Voice. Benchmark mit 16 Fällen in `docs/benchmark.md`.
- App ist nur noch Englisch, iOS-27-Design (Systemfarben, Liquid Glass, kein Orange, weiße Visual-Intelligence-Masken). Bebilderter PDF-Export der Anleitung ist eingebaut, aber **noch nicht angesehen**.
- Abgabe-Repo: `~/Desktop/repair-assistant` (Subtree-Split, MIT). Vor der Abgabe neu splitten und dorthin pullen (siehe Memory `standalone-submission-repo`).
- Proxy starten: `cd proxy && uv run uvicorn app.main:app --port 8787` (Key in `proxy/.env`). Screenshots: `./scripts/screenshots.sh`. Demo für Juroren: `./scripts/run-demo.sh`.

## Nächste Schritte (Reihenfolge)
1. **Echte Fotos live analysieren** und in den Benchmark aufnehmen: `testdata/real/01_ledersohle_loch.jpg` (Sohle bis zum Loch durchgelaufen, eher "Profi/neu besohlen") und `testdata/real/02_pulli_kleines_loch.jpg` (kleines, schwer sichtbares Loch). Wenn SAM/Grounding das Pulli-Loch nicht findet: Grounding-Prompt für kleine Löcher schärfen, Tap-to-refine (`/refine`) in der Diagnose sichtbar anbieten.
2. **Demo-Fix "schwer zu erkennen":** Bei kleinen Schäden auf dem Foto automatisch auf die Schadstelle zoomen (Diagnose und Anleitung: Ausschnitt um die Damage-Box mit Rand, Pinch-to-zoom), Maske kräftiger zeichnen. Die echten Fotos als Demo-Aufnahmen speichern (`ios/RepairAssistant/Resources/LiveRecordings/`, inkl. `.en.json`).
3. ~~PDF-Export~~ entfällt (Owner 29.10.: "PDF brauche ich nicht. raus damit"), wird im Redesign entfernt.
4. Screenshots neu aufnehmen und alle Screens gegen die Mobbin-Collection prüfen (`https://mobbin.com/collections/175c3475-f7b6-41b6-af7c-3dc3a68df769`).
5. Bei Empfehlung "Replace": Upcycling-, Recycling- und Spendehinweise (Spark, optional Muse-Image-Vorschau der Upcycling-Idee).
6. Schlanke Jury-Runde (nur Demo bzw. Kerndokumente, kurzer Bericht).

## Nur durch den Menschen
Video nach `docs/demo-script.md` drehen, Live-Scan auf echtem iPhone testen, GitHub-Repo veröffentlichen, Discord-Fragen (Arbeit nach Kickoff 26.10., starten Juroren die App?).
