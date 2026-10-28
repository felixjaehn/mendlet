# Tool-Calling für den Reparatur-Agenten (Primärquelle, 28.10.2026)

Quellen: https://dev.meta.ai/docs/tool-calling und https://dev.meta.ai/docs/models (gelesen am 28.10.2026 in Chrome).

- Empfohlen ist die **Responses API** (`POST /v1/responses`). Sie behält das Reasoning über mehrere Tool-Runden. Modell `muse-wonder-1.0` (Preview, nur Standard-Modus) oder `muse-spark-1.3`. Beide nehmen dieselben Requests an, der Wechsel ist nur eine andere Modell-ID.
- Tool-Definition im flachen Format: `{"type":"function","name":"segment_damage","description":"…","parameters":{JSON-Schema}}`. Namen müssen `^[a-zA-Z0-9_.-]+$` erfüllen, höchstens ein Punkt.
- Ein Tool-Aufruf kommt als Output-Item `{"type":"function_call","name","arguments","call_id","status"}`. Die Antwort geht zurück als Input-Item `{"type":"function_call_output","call_id","output":"<json-string>"}` mit `previous_response_id`.
- Es sind mehrere parallele Aufrufe pro Runde möglich (`parallel_tool_calls` steht standardmäßig auf true). Jeder Aufruf braucht eine eigene Antwort. `call_id` hat 1–64 Zeichen.
- `tool_choice` erlaubt nur `"auto"`. Die App muss deshalb mit Tool-Aufruf und Textantwort umgehen können.
- `max_tool_calls` begrenzt nur eingebaute Tools. Für eigene Tools müssen wir die Runden selbst deckeln.
- Argumente werden nicht garantiert schemakonform geliefert, deshalb immer selbst validieren. `strict: true` prüft nur das Schema selbst.
- Eingebaute Tools: `web_search` (Search Grounding) und `tool_search`.
- Streaming: Ereignisse `response.function_call_arguments.delta` / `.done`.
- Wonder laut Doku: plant, delegiert an Sub-Agenten, ruft Tools parallel auf und erholt sich von Fehlern. `reasoning_effort` reicht von minimal bis max.

## Geplante Agenten-Tools

| Tool | Führt aus | Zweck |
| --- | --- | --- |
| `segment(concept)` | SAM 3.1, Textprompt | Schaden und Bauteile finden |
| `segment_at(box\|points)` | SAM 3.1, Geometrie-Prompt | gezielt nachsegmentieren |
| `locate(description)` | Muse Spark Perception Grounding | Box für SAM liefern, wenn der Textprompt nichts findet |
| `verify_mask(segment_id)` | Muse Spark mit Overlay-Bild | prüfen, ob die Maske auf dem Schaden liegt |
| `read_label(image)` | Muse Spark | Material und Pflege |
| `preview_repair(instruction)` | Muse Image Edit | Nachher-Vorschau |
| `finish(plan)` | – | Diagnose, Entscheidung, Liste und Schritte (Vertrag) |

Der Agent darf höchstens 8 Runden drehen. Die Sicherheitsprüfung (Prompt A plus Keyword-Gate) läuft **vorher** und deterministisch, nie durch den Agenten. Jeder Agentenschritt geht als SSE-Ereignis `agent_step` an die App (Live-Trace).

## Umsetzung im Proxy (29.10.2026)

- `AGENT_MODE=wonder` (Standard aus). Code: `proxy/app/agent.py`, Einstieg `RealMetaClient.agent_run`, Mock `MockClient.agent_run`. Tools wie in der Tabelle, ohne `read_label` und `preview_repair` (gibt es als eigene Endpunkte). Rundenlimit 8; Sicherheit läuft vorher in `pipeline.analyze`.
- Jede Tool-Ausführung sendet `event: agent_step` (`n`, `tool`, `label`, `model`, `status`, `ms`). Vertrag: `proxy/CONTRACT-CHANGES.md`.
- `finish` wird mit `DiagnosePlan` validiert; ungültig, Rundenlimit oder keine Tool-Antwort ergibt den normalen Diagnoseaufruf. Upstream-Fehler ergeben die klassische Pipeline.
- **Preise Muse Wonder 1.0 (Standard)**, Primärquelle https://dev.meta.ai/docs/pricing-rate-limits (gelesen 28.10.2026): 4,00 $ Input, 20,00 $ Output, 0,20 $ gecachter Input je 1 Mio. Token; Contributor-Modus nicht verfügbar. Konstanten in `proxy/app/budget.py` (`WONDER_*`).
- **UNBESTÄTIGT:** Live-Verhalten der Schleife (Latenz, Rundenzahl, ob `previous_response_id` mit unseren Bild-Inputs akzeptiert wird), Token-Zählung inkl. Reasoning, Wirkung von `reasoning`-Parametern (nicht gesendet).
