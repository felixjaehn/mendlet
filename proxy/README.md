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
- **Real** (Key gesetzt): Muse Spark `muse-spark-1.3` über `/v1/chat/completions` mit `response_format: json_schema`; SAM 3.1 über `/v1/responses`, ein Begriff pro Aufruf, parallel; Muse Voice Transcribe über `/v1/asr/transcribe` (WAV). Aufrufe werden mit `CACHE_MODEL_CALLS=1` unter `.cache/` gecacht, damit Tests und Benchmark keine Credits doppelt verbrauchen.

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

Fehlt die Maske, nutzt die App die Box. Die Platzierung der Maske (Box-Ausschnitt an x1,y1) ist aus den Doku-Beispielen abgeleitet und wird im ersten Echttest geprüft (`app/sam.py`, TODO).

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
