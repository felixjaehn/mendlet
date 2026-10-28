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

## Erste Ende-zu-Ende-Läufe über `/analyze` (28.10.2026, live)

Foto `textile/01_riss_jeans.jpg`, Notiz "Riss an der Naht am Hosenbein".

| Lauf | Prompt B | Ergebnis | Latenz | Kosten kumuliert |
| --- | --- | --- | --- | --- |
| 1 | v2 | SAM per Text: `rip` 0,91, `frayed edge` 0,59, `garment` 0,90. Diagnose korrekt (Riss neben intakter Seitennaht), Konfidenz 0,5, fragt nach Etikett, keine Anleitung | 30 s | 0,047 $ |
| 2 | v2 + Etikettfoto | **Fehler**: Antwort bei 4096 Output-Token abgeschnitten (`finish_reason=length`). Limit auf 16.000 erhöht | 25 s | 0,073 $ |
| 2b | v2 + Etikettfoto, 16k | Etikett gelesen (98 % Baumwolle, 2 % Elasthan, Pflege). Konfidenz 0,82. Einkaufsliste mit **dehnbarem** Flickstoff, Denim-Nadel. 5 Schritte mit Heften (Vorstich) und Stopfen. Aber: alle 5 Schritte als sicherheitskritisch markiert | 9 s (Cache) | – |
| 3 | v3 | Fragt **nicht** nach dem Etikett ("Vermutlich Denim … Annahme"), Konfidenz 0,8, vollständige Anleitung. Nur 2 von 5 Schritten sicherheitskritisch (Schere) | 35 s | 0,176 $ |

Prompt B v3 (`prompts/prompt_b_diagnose.v3.txt`): Etikett nur noch, wenn das Material nicht sichtbar ist und das Vorgehen entscheidend ändert. Sicherheitsbestätigung nur für Schneiden, Hitze, Kleber, Strom.

Offen: Latenz über dem Ziel von 30 s.

## Latenz (28.10.2026, live, ohne Cache, Jeans)

| Konfiguration | Klassifizieren | SAM + Grounding (parallel) | Diagnose + Plan | Gesamt |
| --- | --- | --- | --- | --- |
| Spark Standard-Reasoning, SAM 1536 px, 7 Konzepte | 3,8 s | 16,6 s | 26,1 s | 46,5 s |
| Spark `reasoning_effort=low` | 2,5 s | 15,7 s | 12,6 s | 30,8 s |
| `low` + SAM 1024 px + 6 Konzepte (ohne `tear`) | 3,0 s | 10,5 s | 16,4 s | **29,9 s** |

Parallel gestartete SAM-Aufrufe brauchen einzeln 6 bis 14 s statt 3 bis 5 s. Meta reiht parallele Streams offenbar ein. Qualität mit `low`: Konfidenz 0,78 bis 0,82, 5 Schritte, 1 bis 2 Sicherheitsschritte, also vergleichbar mit dem Standard. Kosten der Messläufe: etwa 0,15 $.

## Weitere Live-Fälle über `/analyze` (28.10.2026)

| Fall | SAM | Spark | Latenz |
| --- | --- | --- | --- |
| Strickpulli, 3 Löcher | `hole` ×3 (0,78/0,78/0,77), `garment` 0,97; Fehltreffer `rip` ×2 (0,52) | "Vermutlich Wollstrick", Konfidenz 0,78, Stopfgarn und stumpfe Stopfnadel, **ein Stopf-Schritt pro Loch** | 30 s |
| Sneaker, Sohle vorne gelöst | `detached sole` 0,84, `shoe sole` 0,91; 4 schwache `seam`-Treffer (0,51–0,63) | Konfidenz 0,85, Reiniger, Handschuhe, flexibler Schuhkleber, Krepp; nur der Kleberschritt sicherheitskritisch | 29 s |
| Heizjacke mit Akku | – (vorher gesperrt) | `warn_only`, Lithium-Risiko, keine Anleitung | **3 s** |

Muse Image Nachher-Vorschau (`/after-preview`, `reasoning_strength=low`): Jeans 12 s, Pulli 11 s. Bildausschnitt, Licht und Material bleiben gleich, nur der Schaden ist repariert ([Jeans](live-probes/2026-10-28_jeans_muse-image_after.jpg)). Kosten gesamt bis hier: 0,47 $.

Offene Qualitätspunkte: schwache Fehltreffer (Score < 0,6), die einen stärkeren Schaden überlappen oder nur Teile sind, sollten gefiltert werden.

## Elektronik-Ausblick: SAM auf der USB-Platine (28.10.2026, live)

Foto `electronics/01_kabel_platine.jpg` (Muse Image generiert).

| Konzept | Treffer | Score | Latenz |
| --- | --- | --- | --- |
| `red wire` | 1 | 0,88 | 2,4 s |
| `black wire` | 1 | 0,95 | 3,8 s |
| `copper wire strands` | 2 (beide Kabelenden) | 0,61 / 0,57 | 2,3 s |
| `circuit board` | 1 | 0,79 | 2,7 s |
| `solder pad` | 0 | – | 1,8 s |

Folgerung für das Löt-Overlay: Kabel und blanke Enden liefert SAM per Text. Die Ziel-Pads mit Polarität (+/− im Siebdruck) lokalisiert Spark, SAM segmentiert sie per Box, wie beim Riss.
