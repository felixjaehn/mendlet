# Proxy

FastAPI-Proxy zwischen iOS-App und Meta Model API. Er hält den API-Key, setzt das Tageslimit durch, validiert jede Modellantwort gegen den Vertrag (PRD §8) und erzwingt die Sicherheitsregeln (PRD §7). Bilder und Audio werden nie gespeichert oder geloggt.

## Starten

```bash
cd repair-assistant/proxy
cp .env.example .env          # META_API_KEY eintragen; leer = Mock-Modus
uv run uvicorn app.main:app --host 0.0.0.0 --port 8787
uv run pytest -q              # alle Tests offline
```

## Modi

- **Mock** (Standard ohne Key oder mit `MOCK_MODE=1`): deterministische deutsche Fixtures mit realistischen Verzögerungen. Szenario über das Request-Feld `mock_scenario` oder Schlüsselwörter in `user_note`: `textile_tear_needs_label` (Standard, fragt nach dem Etikett), `textile_tear`, `textile_hole`, `textile_open_seam`, `textile_button`, `shoe_sole`, `battery_jacket`, `helmet`, `unsupported`.
- **Real** (Key gesetzt): Muse Spark `muse-spark-1.3` über `/v1/chat/completions` mit `response_format: json_schema`; SAM 3.1 über `/v1/responses`, ein Begriff pro Aufruf, parallel, PNG und SSE bis `response.completed`, mit String-Metadata `include_confidence=true` und `mask_encoding=one_bit`; Muse Voice Transcribe über `/v1/asr/transcribe` (Multipart-Teile `request` als JSON und `audio` als WAV). Mit `CACHE_MODEL_CALLS=1` werden erfolgreiche Spark-, SAM- und Voice-Antworten unter `.cache/` gecacht. SDK-Retries sind aus; nur ungültiges Spark-JSON wird in der normalen Pipeline einmal wiederholt.

## Endpunkte

| Methode | Pfad | Zweck |
| --- | --- | --- |
| GET | `/health` | Modus, heutige Kosten, Tageslimit |
| POST | `/analyze` | SSE: `progress` (classify, segment, diagnose, plan), dann `result` oder `error`. Mit `?stream=false` reines JSON |
| POST | `/step-help` | Hilfe zu genau einem Schritt |
| POST | `/transcribe` | Multipart `file` (WAV) → `{"text": …}` |

## Maskenformat (intern)

SAM 3.1 liefert Boxen und Masken als Special-Token-Text. Der Proxy parst ihn mit `meta-sam-parser` und gibt der App normalisierte Koordinaten (0..1):

```json
{ "box": [x, y, w, h], "mask": { "format": "polygon", "points": [[x, y], ...] } }
```

Fehlt die Maske oder ist ihr Payload defekt, nutzt die App die gültige Box. Ungültige Boxen werden verworfen. Der offizielle Parser bestätigt offline Box-lokale, halb offene Maskengrenzen. Die Übereinstimmung auf echten Fotos bleibt **UNBESTÄTIGT**. Ein Polygon enthält den größten äußeren Ring; Innenlöcher und kleinere getrennte Inseln sind im bestehenden App-Vertrag nicht darstellbar. Ein-Pixel-Risse bleiben ohne Downsampling erhalten.

## Erster echter Aufruf am 27.10.2026

Zuerst nur den begrenzten Smoke-Test ausführen. Er macht bei frischem Cache genau einen Versuch je Modell, ohne Retry. Ein erneuter identischer Aufruf liest die Ergebnisse aus dem Cache. Ohne **exportiertes** `META_API_KEY` endet er mit `SKIP`, bevor Bild, Audio oder Cache gelesen/geschrieben werden; `.env` wird vom Smoke-Script absichtlich nicht geladen.

```zsh
cd '/Users/felixjaehn/Desktop/Meta AI Hackathon/repair-assistant/proxy'
export UV_CACHE_DIR=/private/tmp/repair-assistant-uv-cache
uv run pytest -q
read -rs 'META_API_KEY?Meta API key: '
export META_API_KEY
printf '\n'
uv run python scripts/smoke_real.py '/absolute/path/repair-photo.jpg'
```

Für einen deutschen Sprachtest kann der **erste** Smoke-Aufruf stattdessen eine eigene WAV-Aufnahme von maximal fünf Sekunden verwenden:

```zsh
uv run python scripts/smoke_real.py '/absolute/path/repair-photo.jpg' --audio '/absolute/path/german-sample.wav'
```

Ohne `--audio` entsteht eine Sekunde Stille nur im Speicher: Das prüft den Voice-Vertrag, keine Sprachqualität. Das Bild wird für SAM orientiert, auf maximal 1536 Pixel verkleinert und als PNG gesendet. Für SAM gibt es optional `--concept hole` oder `--concept 'open seam'`, weiterhin genau ein Begriff/ein Aufruf.

Der Smoke-Test nutzt Spark **nur mit Text und JSON-Schema**. Die Notizen enthalten keine sichere Obergrenze für Spark-Bildtokens; deshalb wird im gedeckelten Test kein Spark-Bildaufruf ausgelöst. Spark-Bildeingabe, Diagnose-Prompt B und Materialerkennung bleiben live **UNBESTÄTIGT**. Die normale Proxy-Pipeline sendet die Fotos weiterhin an Spark; ihre Request-Serialisierung wird offline getestet.

Der feste lokale Kostendeckel beträgt **0,10 USD**, konservativ vorab reserviert werden **0,085758 USD**: Spark 65.536 Input-/256 Output-Token, ein SAM-Bild und maximal fünf Sekunden Voice. Der Spark-Text samt Schema ist auf 8 KiB begrenzt. Modell-IDs, Preise, Endpoint und Limit sind im Script fest; Umgebungsvariablen können sie nicht überschreiben. Ein Prozess-Lock und ein vor dem Aufruf atomar gespeichertes Journal verhindern doppelte Versuche. Auch Fehler, Timeout und Abbruch behalten ihre Reservierung. Journal beschädigt/fehlend bei vorhandenem Usage-Cache = Abbruch. Exitcodes: 0 = PASS/SKIP, 1 = FAIL.

**UNBESTÄTIGT:** Meta-seitige Annahme/Durchsetzung von `max_completion_tokens`, tatsächliche Tokenabrechnung und Endrechnung. Der lokale Deckel ist kein nachgewiesenes serverseitiges Kontolimit. Die dokumentierten Preise und die begrenzten Text-/Audioeingaben liegen der Reservierung zugrunde. Bei einem Fehler Cache und `.cache/smoke_real/attempts.json` zur Prüfung behalten; nicht löschen oder mit neuem `--cache-dir` erneut ausführen. Geändertes Bild/Audio/Konzept wird für ein bereits versuchtes Modell abgewiesen.

Nach Prüfung des Reports kann der normale Proxy gestartet werden; dessen mehrstufige Analyse ist ein separater Lauf und fällt **nicht** unter den Smoke-Deckel:

```zsh
MOCK_MODE=0 CACHE_MODEL_CALLS=1 DAILY_BUDGET_USD=5 uv run uvicorn app.main:app --host 0.0.0.0 --port 8787
```

Das normale Tagesbudget erfasst Kosten nach erfolgreichen Antworten und kann bei parallelen Aufrufen überschritten werden. Es ist kein harter Reservierungsdeckel wie im Smoke-Test. Den mehrteiligen Benchmark erst nach dem ersten Fototest starten.

## Offline-Verifikation

`uv run pytest -q` blockiert echte HTTP-Transports auch in Real-Client-Tests. Die Tests prüfen die tatsächlich vom SDK serialisierten Requests, SSE einschließlich geteilter Token und unvollständiger Streams, WAV-Multipart, Caching, Sicherheitsregeln und die komplette Real-Client-Pipeline über `httpx.MockTransport`.

Synthetische SAM-Wire-Fixtures liegen in `tests/fixtures/sam/`: dünner Riss, Loch, Innenloch, mehrere Treffer, kein Treffer und defekte Zeilen/Masken. Sie sind keine Live-Antworten. Base85-One-Bit-Masken wurden mit dem installierten offiziellen Codec erzeugt. Zum deterministischen Neuerzeugen: `uv run python scripts/build_sam_fixtures.py` (verwendet dessen derzeit privaten Encoder). Textil-Diagnose verwendet `../prompts/prompt_b_diagnose.v2.txt`; v1 bleibt unverändert. Promptqualität und die tatsächliche Änderung von Nadel/Garn/Stich nach einem Etikettfoto müssen live bewertet werden.

## Beispiele

```bash
curl -s localhost:8787/health
curl -sN -X POST localhost:8787/analyze -H 'Content-Type: application/json' \
  -d '{"image_base64":"<base64>","user_note":"Riss an der Naht","locale":"de"}'
curl -s -X POST 'localhost:8787/analyze?stream=false' -H 'Content-Type: application/json' \
  -d '{"image_base64":"<base64>","mock_scenario":"battery_jacket","locale":"de"}'
uv run python scripts/run_benchmark.py --fast   # Benchmark-Tabelle (Mock oder Real)
```

## Entscheidungen

- Gesperrte Antworten haben leere `segments`, `shopping_list` und `guide.steps`. `diagnosis` und `decision` tragen Platzhalter, damit die App nie `null` dekodieren muss.
- Die Schlüsselwort-Vorprüfung auf `user_note` macht das Risiko nur strenger, nie lockerer. Sie versteht keine Verneinung ("ohne Akku" sperrt trotzdem). Das ist bewusst vorsichtig.
- Ist die Klassifikation auch nach einem Retry ungültig, gilt `warn_only`.
