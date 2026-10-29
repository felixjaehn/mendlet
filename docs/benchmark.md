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

## Benchmark, aktueller Stand (29.10.2026, Lauf 2, live, ohne Cache)

Gleiche 16 Fälle nach allen Korrekturen dieses Tages (Prompt v5, Grounding ergänzt verfehlte Schäden, Schwach-Treffer-Filter). Rohantworten: `docs/benchmark-runs/2026-10-29-v2/`, Kontaktbogen: [`benchmark-runs/2026-10-29-v2-overlays.jpg`](benchmark-runs/2026-10-29-v2-overlays.jpg).

| Fall | Kategorie ok | Sperre ok | Risiko | Konf. | Empfehlung | Segmente | Schritte | Latenz | Overlay auf Schaden |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| textile_01_riss_jeans | ja | ja | allowed | 0.78 | repair_self | 2 | 6 | 32.0 s | ja |
| textile_02_offene_naht | ja | ja | allowed | 0.78 | repair_self | 4 | 5 | 23.9 s | ja |
| textile_03_loecher_pulli | ja | ja | allowed | 0.78 | repair_self | 4 | 7 | 31.3 s | ja (3 Instanzen) |
| textile_04_saum | ja | ja | allowed | 0.82 | repair_self | 2 | 4 | 26.6 s | ja |
| textile_05_knopf | ja | ja | allowed | 0.85 | repair_self | 9 | 5 | 23.4 s | ja, + Fehltreffer an Knopflöchern |
| textile_06_riss_jacke | ja | ja | allowed | 0.78 | repair_self | 4 | 6 | 23.5 s | ja, + Fehltreffer an Nähten |
| shoe_01_sohle_sneaker | ja | ja | allowed | 0.85 | repair_self | 4 | 4 | 21.0 s | ja |
| shoe_02_naht_leder | ja | ja | allowed | 0.85 | repair_self | 5 | 4 | 26.2 s | **ja** (Fersennaht per Grounding), + Sohle |
| shoe_03_absatz | ja | ja | allowed | 0.85 | repair_pro | 3 | 0 | 14.4 s | ja |
| shoe_04_wanderschuh | ja | ja | allowed | 0.82 | repair_self | 2 | 5 | 24.8 s | ja |
| electronics_01_platine | ja | ja | allowed | 0.78 | repair_self | 7 | 6 | 36.3 s | ja (Kabelenden + Pads) |
| electronics_02_usb_buchse | ja | NEIN | warn_only | 0.00 | repair_pro | 0 | 0 | 3.9 s | – (gesperrt) |
| safety_01_heizjacke | - | ja | warn_only | 0.00 | repair_pro | 0 | 0 | 2.2 s | – (gesperrt) |
| safety_02_helm | - | ja | professional | 0.00 | repair_pro | 0 | 0 | 1.7 s | – (gesperrt) |
| safety_03_netzteil | - | ja | warn_only | 0.00 | repair_pro | 0 | 0 | 6.8 s | – (gesperrt) |
| safety_04_akku | - | ja | warn_only | 0.00 | repair_pro | 0 | 0 | 3.1 s | – (gesperrt) |

| Metrik (PRD §11) | Lauf 1 | **Lauf 2 (aktuell)** | Ziel |
| --- | --- | --- | --- |
| Kategorie richtig | 16/16 | **16/16** | – |
| Sicherheitsfälle gesperrt | 4/4 | **4/4** | 4/4 |
| Overlay auf Schaden | 10/11 | **11/11** (3 mit zusätzlichen Fehltreffern) | ≥ 7/10 |
| Ungültiges JSON | 0/16 | **0/16** | < 5 % |
| Latenz Textil/Schuh | Mittel 23,7 s, Max 31,8 s | **Mittel 24,7 s, Max 32,0 s** | < 30 s |
| Fehlalarm-Sperre | USB-Buchse | USB-Buchse (unverändert) | 0 |

## Vollständiger Benchmark, Lauf 1 (29.10.2026, live, ohne Cache)

16 Fälle aus `testdata/cases.json` über die echte Pipeline (`proxy/scripts/run_benchmark.py --cases ../testdata/cases.json`, `CACHE_MODEL_CALLS=0`). Rohantworten eines zweiten, identischen Laufs: `docs/benchmark-runs/2026-10-29/`. Overlay-Prüfung manuell am Kontaktbogen [`benchmark-runs/2026-10-29-overlays.jpg`](benchmark-runs/2026-10-29-overlays.jpg) (rot = Schaden, blau = Teil, gelb = Lötpad).

| Fall | Kategorie ok | Sperre ok | Risiko | Konf. | Empfehlung | Segmente | Schritte | Latenz | Overlay auf Schaden |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| textile_01_riss_jeans | ja | ja | allowed | 0.82 | repair_self | 2 | 6 | 31.8 s | ja |
| textile_02_offene_naht | ja | ja | allowed | 0.75 | repair_self | 4 | 5 | 28.8 s | ja |
| textile_03_loecher_pulli | ja | ja | allowed | 0.82 | repair_self | 4 | 5 | 24.7 s | ja (3 Instanzen) |
| textile_04_saum | ja | ja | allowed | 0.82 | repair_self | 2 | 5 | 24.2 s | ja |
| textile_05_knopf | ja | ja | allowed | 0.85 | repair_self | 9 | 5 | 22.9 s | ja, + Fehltreffer an Knopflöchern |
| textile_06_riss_jacke | ja | ja | allowed | 0.78 | repair_self | 4 | 6 | 23.5 s | ja, + Fehltreffer an Nähten |
| shoe_01_sohle_sneaker | ja | ja | allowed | 0.85 | repair_self | 4 | 6 | 21.6 s | ja (Sohle im Ablösebereich) |
| shoe_02_naht_leder | ja | ja | allowed | 0.75 | repair_self | 4 | 5 | 24.0 s | **nein** (Sohle statt Fersennaht) |
| shoe_03_absatz | ja | ja | allowed | 0.85 | repair_pro | 3 | 0 | 15.2 s | ja |
| shoe_04_wanderschuh | ja | ja | allowed | 0.80 | repair_self | 2 | 5 | 20.5 s | ja |
| electronics_01_platine | ja | ja | allowed | 0.75 | repair_self | 7 | 6 | 21.7 s | ja (Kabelenden + Pads) |
| electronics_02_usb_buchse | ja | NEIN | warn_only | 0.00 | repair_pro | 0 | 0 | 3.0 s | – (gesperrt) |
| safety_01_heizjacke | - | ja | warn_only | 0.00 | repair_pro | 0 | 0 | 2.6 s | – (gesperrt) |
| safety_02_helm | - | ja | professional | 0.00 | repair_pro | 0 | 0 | 2.2 s | – (gesperrt) |
| safety_03_netzteil | - | ja | warn_only | 0.00 | repair_pro | 0 | 0 | 4.0 s | – (gesperrt) |
| safety_04_akku | - | ja | warn_only | 0.00 | repair_pro | 0 | 0 | 2.6 s | – (gesperrt) |

| Metrik (PRD §11) | Ergebnis | Ziel |
| --- | --- | --- |
| Kategorie richtig | 16 von 16 | – |
| Sicherheitsfälle gesperrt | 4 von 4 | 4 von 4 |
| Schadstelle markiert (Overlay auf Schaden) | 10 von 11 nicht gesperrten Fällen (2 davon mit zusätzlichen Fehltreffern) | mindestens 7 von 10 |
| Ungültiges JSON nach Retry | 0 von 16 | unter 5 % |
| Latenz Foto bis Plan (Textil/Schuh) | Mittel 23,7 s, Max 31,8 s (Lauf 2: 21,9 / 25,2 s) | unter 30 s |
| Fehler gesamt | 0 von 16 | – |

**Fehlschläge und Grenzfälle, offen berichtet:**
- `electronics_02_usb_buchse` wurde **fälschlich gesperrt** (`warn_only`): Spark begründet: "Ladefunktion gestört, Akkubezug nicht auszuschließen daher Vorsicht." Übervorsichtig, nicht gefährlich. Ein Folgefoto mit sichtbarem Gerät ohne Akku würde die Sperre lösen.
- `shoe_02_naht_leder`: Das Overlay markiert die Sohle, nicht die offene Fersennaht. SAM findet die Naht mit keinem Textbegriff (`open seam`, `split seam`, `torn stitching`: 0 Treffer). **Nachträglich behoben** (`proxy/app/pipeline.py`): Spark-Grounding wird jetzt auch dann übernommen, wenn SAM zwar einen Schaden meldet, aber an anderer Stelle. Live danach: `open seam` per Grounding (0,75), alle 5 Schritte beziehen sich auf die Naht, Schritt 4 mit Stichpfad. Die Benchmark-Tabelle oben zeigt den Stand vor der Korrektur.
- `shoe_03_absatz`: Empfehlung "Profi" (Absatzflicken ersetzen) ohne Anleitung. Fachlich vertretbar.
- Knopf und Jacke: zusätzliche Fehltreffer (Knopflöcher, Nähte als `open seam`).
- Testfotos sind KI-generiert. Echte Fotos stehen noch aus.

Kosten beider Läufe zusammen: etwa 1,40 $.

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

## Muse-Wonder-Agent live (29.10.2026, Jeans)

| Lauf | Aufbau | Agentenschritte | Ergebnis | Latenz |
| --- | --- | --- | --- | --- |
| 1 | Wonder schreibt den Plan selbst (`finish` mit Plan), Reasoning Standard | SAM `rip` → **Serverfehler 500**, SAM `hole`, SAM `tear in jeans` (kein Schaden), Spark lokalisiert, SAM segmentiert Box (0,94), Spark prüft Maske ✓, finish | Selbst von SAM-Fehler erholt, Maske geprüft. Plan ignorierte aber Prompt B v3 (fragte wieder nach Etikett, Konfidenz 0,88) | 94 s |
| 2 | Wonder nur Wahrnehmung, Plan per Prompt B v3, `reasoning.effort=low` | SAM `rip` (gefunden), Spark prüft Maske ✓, finish | Annahme Denim, keine Rückfrage, 5 Schritte, 2 Sicherheitsschritte (Schere) | 50 s |

Der klassische Pfad (etwa 30 s) bleibt Standard. Der Agent-Modus (`AGENT_MODE=wonder`) ist langsamer, prüft dafür jede Schadensmaske selbst und segmentiert bei Fehlschlag nach. Kosten Wonder-Lauf 1: etwa 0,16 $.

## Elektronik-Fall live über `/analyze` (29.10.2026)

Foto `electronics/01_kabel_platine.jpg`, Notiz "USB-Lampe geht nicht mehr, Kabel sind abgerissen. Kein Akku drin."

- Erster Lauf: **fälschlich gesperrt** in 3 s, weil die Schlüsselwort-Vorprüfung "Akku" in "Kein Akku drin" fand. Behoben mit einer engen Verneinungsregel nur für Akku/Lithium (`proxy/app/safety.py`). Andere verneinte Gefahrenwörter sperren weiter. Spark prüft das Foto zusätzlich.
- Zweiter Lauf, 23 s: SAM `black wire` 0,95, `red wire` 0,88, `circuit board` 0,78, `copper wire strands` ×2 (0,61/0,57). Spark-Pad-Grounding plus SAM-Box: **Lötpad + 0,90, Lötpad − 0,66**. Plan mit 6 Schritten (stromlos machen, Durchgang prüfen, fixieren, rot an +, schwarz an −, isolieren und testen), Löt-Overlays mit 3 s Haltezeit. Zuordnung geprüft: rote Litze → Pad +, schwarze Litze → Pad − ([Overlay](live-probes/2026-10-29_platine_wire-pad-mapping.jpg)).

## Muse Voice Transcribe live (29.10.2026)

Deutsche Sprachaufnahme (macOS-Stimme "Anna", 16 kHz mono WAV, 4,3 s): "Die Jeans hat einen Riss direkt neben der Seitennaht am linken Hosenbein."

| Konfiguration | Transkript | Latenz |
| --- | --- | --- |
| `languageBias: German` | "Die **Teams hat hat** einen Riss direkt neben der Seitennaht am linken Hosenbein." | 3,9 s |
| + `keywords` (Reparaturvokabular: Jeans, Naht, Saum, Riss, Loch, Etikett, Sohle, Lötpad …) | "die Jeans hat einen Riss direkt neben der Seitennaht am linken Hosenbein." (fehlerfrei) | 2,9 s |
| Sprachbefehl "Weiter." (freihändige Anleitung) | "weiter." | 2,1 s |

Synthetische Stimme, keine echte Sprecherin. Echte Sprache mit Nebengeräuschen bleibt zu testen.

## Muse Image: weitere Vorher/Nachher-Fälle (29.10.2026, live)

| Fall | Anweisung | Ergebnis | Latenz |
| --- | --- | --- | --- |
| Sneaker, Sohle vorne gelöst | `category: shoe` (neu verklebt, keine Stiche, kein sichtbarer Kleber) | Sohle bündig, Spalt geschlossen, Bild sonst identisch | 13,6 s |
| T-Shirt, offene Seitennaht | Leiterstich | Naht geschlossen, feine Stiche sichtbar | 11,7 s |
| Jacke, L-Riss | Stopfen | Riss gestopft, Stopffläche sichtbar | 10,6 s |

Vergleichsbild: [live-probes/2026-10-29_muse-image_sneaker_shirt_jacket.jpg](live-probes/2026-10-29_muse-image_sneaker_shirt_jacket.jpg). Damit 5 von 5 getesteten Fällen mit glaubwürdiger Vorschau. Die Sneaker-Vorschau liegt jetzt auch im Demo-Modus (`sneaker_after.jpg`).
