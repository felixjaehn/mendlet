# Benchmark und Live-Messungen

Alle Zahlen stammen aus echten Aufrufen der Meta Model API (Standard-Modus). Die Testfotos sind KI-generiert und gekennzeichnet (`testdata/SOURCES.md`). Fehlschläge stehen hier genauso wie Treffer.

## Live-Sondierung 1 (28.10.2026)

Skript: `proxy/scripts/probe_live.py`. Bild auf 1024 px verkleinert.

### SAM 3.1 mit Textprompt (ein Konzept pro Aufruf)

| Foto | Konzept | Treffer | Score | Latenz |
| --- | --- | --- | --- | --- |
| Jeans mit Riss (`textile/01_riss_jeans.jpg`) | `tear` | 0 | – | 3,8 s |
| | `hole` | 0 | – | 4,6 s |
| | `ripped fabric` | 0 | – | 3,0 s |
| | `torn denim` | 0 | – | 4,4 s |
| | `frayed threads` | 0 | – | 3,5 s |
| | `jeans` | 1 | 0,86 | 5,7 s |
| | `seam` | 2 | 0,81 / 0,83 | 3,9 s |
| Strickpulli mit 3 Löchern (`textile/03_loch_pulli.jpg`) | `hole` | **3** | 0,80 / 0,80 / 0,76 | 2,3 s |
| | `moth hole` | 3 | 0,52 / 0,51 / 0,53 | 4,2 s |
| Sneaker, Sohle vorne gelöst (`shoes/01_sohle_sneaker.jpg`) | `shoe sole` | 1 | 0,92 | 3,4 s |
| | `gap` | 0 | – | 2,4 s |

**Befund:** SAM findet Objekte und Bauteile (Jeans, Naht, Sohle) und klar umrandete Löcher, aber keinen Riss als Konzept. Ein Riss ist eine Lücke im Stoff, kein Objekt.

### Muse Spark Grounding → SAM-Box-Prompt

| Foto | Spark-Box (0–1000) | Spark-Latenz | SAM-Maske | Score | SAM-Latenz |
| --- | --- | --- | --- | --- | --- |
| Jeans mit Riss | [375, 165, 690, 840] | 5,0 s | pixelgenau entlang der ausgefransten Ränder, Naht ausgespart ([Overlay](live-probes/2026-10-28_jeans_spark-box_sam.png)) | 0,94 | 3,7 s |
| Sneaker | [212, 469, 702, 605] | ~5 s | Sohlenkante im Ablösebereich, also die Klebezone; Spalt selbst nicht isoliert ([Overlay](live-probes/2026-10-28_sneaker_spark-box_sam.png)) | 0,55 | 2,7 s |

**Konsequenz für die Architektur:** Spark lokalisiert und SAM segmentiert. Das ist jetzt der Hauptpfad für Schäden, nicht mehr der Rückfall. Grounding läuft parallel zur SAM-Textsuche (`proxy/app/pipeline.py`). Beim Schuh braucht es zusätzliche Punkt-Prompts (`/refine`), um den Spalt selbst zu isolieren.

### Muse Spark

- Bild plus JSON-Schema funktioniert. Mit `max_completion_tokens=2048` kamen 862 Output-Token, davon **820 Reasoning-Token**. Mit 256 Token (erster Smoke-Test) blieb die Antwort leer. Das Limit im Smoke-Test ist korrigiert.
- Kategorie und Schaden auf Englisch erkannt: Jeans "rip", Sneaker "sole separation at toe".

### Kosten bisher

Smoke-Test plus Sondierung: etwa 0,06 $ (geschätzt aus Token und Bildzahl, Rechnung UNBESTÄTIGT).

## Vollständiger Benchmark

Ausstehend: alle Fälle aus `testdata/` über `/analyze` (Ziele aus PRD §11).
