# Meta Model API: Notizen (Stand 2026-10-26)

Quellen (alle am 2026-10-26 abgerufen). Kürzel in Klammern werden unten als Beleg verwendet:
- [OV] https://dev.meta.ai/docs/models (ai.developer.meta.com/docs/models/ leitet per 302 auf dev.meta.ai/docs/models um)
- [AUTH] https://dev.meta.ai/docs/authentication
- [PRICE] https://dev.meta.ai/docs/pricing-rate-limits
- [IMG] https://dev.meta.ai/docs/image-understanding
- [FILE] https://dev.meta.ai/docs/file-handling
- [SO] https://dev.meta.ai/docs/structured-output
- [SAM] https://dev.meta.ai/docs/sam/overview, https://dev.meta.ai/docs/sam/segmenting, https://dev.meta.ai/docs/sam/reading-segmentation, https://dev.meta.ai/docs/sam/client-libraries, https://dev.meta.ai/docs/media-segmentation
- [STT] https://dev.meta.ai/docs/speech-to-text, https://dev.meta.ai/docs/api-reference/voice/transcribe, https://dev.meta.ai/docs/api-reference/voice/schemas
- [RS] https://reconscribe.com/meta-global-ai-developer-hackathon-2026/ (Drittquelle, nicht offiziell)
- [CV] https://cerebralvalley.ai/e/meta-ai-developer-hackathon

Hinweis: Alle Beispiele nutzen `https://api.meta.ai/v1` (Basis-URL) und `MODEL_API_KEY`. Ein GET auf die Basis-URL selbst liefert 404 (kein Index), das ist normal.

## 0. Gemeinsam

- Auth: Header `Authorization: Bearer $MODEL_API_KEY`. Key beginnt mit `LLM_`, Erstellung im Model-API-Dashboard (API keys). Key nie im Client-Code ausliefern, Server-Proxy nutzen. [AUTH]
- Kompatibel mit OpenAI-SDK, Anthropic-SDK, LangChain, LiteLLM; die Env-Variable wird von keinem SDK automatisch gelesen, Key explizit übergeben. [AUTH]
- Drei Protokolle für Textmodelle: Responses (`POST /v1/responses`), Chat Completions (`POST /v1/chat/completions`), Messages (`/v1/messages`). [OV][AUTH]
- Rate Limits gelten pro Team, nicht pro Key. [PRICE]
- Credits: $150 pro ausgewähltem Teilnehmer [RS][CV: Credits für Partner]. Ob eine Kreditkarte nötig ist: UNBESTÄTIGT.
- UNBESTÄTIGT: Der im PRD erwähnte "Proxy mit Tageslimit" steht in keiner der gelesenen Quellen. Nur die Rate Limits aus [PRICE] sind belegt.

## 1. Muse Spark

- Modell-IDs (Standard-Modus): `muse-spark-1.3` (neueste, laut Doku für neue Arbeit empfohlen und Default in den Doku-Beispielen), `muse-spark-1.2`, `muse-spark-1.1`. Contributor-Varianten `muse-spark-1.3-contributor`, `muse-spark-1.2-contributor` (Meta darf Inhalte zum Training nutzen; nicht verwenden). [OV][PRICE]
  - Abweichung zum PRD: Dort stehen nur 1.1 und 1.2. 1.3 existiert jetzt und ist Default.
- Eingabe: Text, Bild, Video, Audio, PDF; Ausgabe: Text; Kontext 1.048.576 Token. Audio-Verständnis in 1.3 laut Doku nicht voll unterstützt. [OV]
- Endpunkte/Methode: `POST /v1/responses`, `POST /v1/chat/completions`, `POST /v1/messages`, alle mit Bearer-Header. [OV][AUTH]
- Bildübergabe [IMG]:
  - Drei Wege: öffentliche http(s)-URL, Base64-Data-URL (`data:image/jpeg;base64,...`), oder `file_id` aus der Files API.
  - Responses API: Block `{"type":"input_image","image_url":"<url oder data-url>"}` (image_url ist ein einfacher String).
  - Chat Completions: Block `{"type":"image_url","image_url":{"url":"<url oder data-url>"}}`.
  - Bis zu 50 Bilder pro Request, mehr gibt HTTP 400. Bilder nur in User-Nachrichten.
  - Formate: image/png, image/jpeg (Alias image/jpg), image/gif, image/webp, image/x-icon. Inline-Limit 50 MB (50.000.000 Byte) pro Datei bei Base64/URL im Body. [FILE]
  - UNBESTÄTIGT: maximale Auflösung / Downscaling-Verhalten, HEIC-Support (nicht gelistet, also vor dem Senden zu JPEG konvertieren).
- Perception Grounding (optional): Das Modell kann Objektpositionen auf einem normalisierten 0-1000-Raster liefern, (0,0) oben links; Umrechnung in Pixel mit Bildgröße. Werte können leicht außerhalb (z. B. 1001) liegen. [IMG]
- Structured Output [SO]:
  - Chat Completions: `response_format: {"type":"json_schema","json_schema":{"name":"...","schema":{...}}}`. Decoding wird auf das Schema eingeschränkt (garantiert konformes JSON).
  - Responses API: Parameter heißt `text.format` (Gegenstück zu `response_format`). Das genaue JSON von `text.format` habe ich nicht im Wortlaut gesehen: UNBESTÄTIGT, vor Nutzung auf https://dev.meta.ai/docs/structured-output prüfen. Empfehlung: für JSON Chat Completions nehmen.
  - Rekursive Schemas gehen nicht (HTTP 400). `strict` ist standardmäßig false; Ausgabe ist trotzdem schemakonform.
  - Ein simples `json_object`-Modus ist in der Doku nicht beschrieben: UNBESTÄTIGT.
- Preise (Standard, pro 1 Mio. Token): Input $1,25; gecachter Input $0,15; Output $4,25. Web-Search-Grounding $2,50 pro 1.000 Queries extra. [PRICE]
- Rate Limit: 3.000 RPM, 4.000.000 TPM (Standard). [PRICE]
- Minimales curl (Chat Completions, Text; aus [AUTH]):
```
curl https://api.meta.ai/v1/chat/completions \
  -H "Authorization: Bearer $MODEL_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"muse-spark-1.3","messages":[{"role":"user","content":"Hello"}]}'
```
- Minimales curl mit Bild (Responses; Schema aus [IMG], dort mit URL):
```
curl https://api.meta.ai/v1/responses \
  -H "Authorization: Bearer $MODEL_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"muse-spark-1.3","input":[{"type":"message","role":"user","content":[
        {"type":"input_text","text":"What is in this image?"},
        {"type":"input_image","image_url":"data:image/jpeg;base64,<BASE64>"}]}]}'
```
  (Die Data-URL-Variante ist im Text von [IMG] beschrieben; das vollständige curl dort nutzt eine https-URL. Ein Live-Aufruf wurde nicht ausgeführt, kein Key.)

## 2. SAM 3.1

- Modell-ID: `sam-3.1`. Ein Modell für Bild und Video. [SAM][OV]
- Endpunkt: `POST /v1/responses` (Responses API, kein eigener Segmentierungs-Endpunkt). Header `Authorization: Bearer ...`, `Content-Type: application/json`; für Streaming `Accept: text/event-stream`. [SAM]
- Request: eine User-Message mit genau einem `input_text` (Prompt) und einem Medienteil. Bild: `{"type":"input_image","image_url":"<öffentliche URL oder data:image/png;base64,...>"}`. Video: `input_video` mit `video_url` oder `file_id`. [SAM segmenting]
  - Streaming wird empfohlen (`"stream": true`), ist aber nicht Pflicht; nicht-streamend kommt das komplette Ergebnis in einer Response. Das exakte JSON-Feld des nicht-streamenden Ergebnisses (vermutlich `output_text`) ist nicht im Wortlaut gezeigt: UNBESTÄTIGT. Im Stream: Events `response.output_text.delta` (je Delta eine Zeile = ein Frame), Ende mit `response.completed`.
  - Bildformate/Größenlimit speziell für SAM: UNBESTÄTIGT. Nur belegt: PNG-Beispiele, Data-URL erlaubt, Inline-Limit 50 MB allgemein [FILE]. Video: MP4/MOV (H.264/H.265/MPEG-4), bis 15.000 Frames.
- Prompt: kurze Nominalphrase für genau ein Konzept ("glasses", "yellow school bus"). Befehle/Fragen, Listen ("a, b"), "and", Negation, ODER unzuverlässig oder 0 Treffer. Plural, Groß-/Kleinschreibung, Satzzeichen egal. Mehrere Konzepte = mehrere Requests (nicht in einem Call möglich). Attribute ("red square") filtern. Kein Treffer = leerer Output, kein Fehler. [SAM segmenting]
  - Für den Fotottest relevant: ob "tear", "open seam", "hole" brauchbar sind, ist nicht dokumentiert. Doku sagt "concrete nouns match best". UNBESTÄTIGT, per Fototest klären.
- Alternativ: Box-/Punkt-Prompts im selben `input_text`, z. B. `<0f>1<|box;x1=444;y1=626;x2=675;y2=849;w=1800;h=1200|>,2<|point;x=1430;y=700;w=1800;h=1200|>-<|point;x=1300;y=450;w=1800;h=1200|>`. Bis 16 Objekte, Koordinaten in Medienpixeln (nach EXIF-Rotation), w/h muss Seitenverhältnis des Bilds haben, sonst 400. Nicht mit Textphrase kombinierbar. Masken kommen dabei immer als one_bit. [SAM segmenting]
- Optionale Request-Felder (Top-Level `metadata`, Werte sind Strings): `"mask_encoding": "lossless"` (Default, Marker `~`) oder `"one_bit"` (Marker `!`, kleiner); `"include_confidence": "true"` (Score je Box/Maske); `"propagation_direction"` (nur Video). [SAM segmenting]
- Antwortformat (WICHTIG): kein JSON, kein RLE, keine Polygone auf dem Draht, sondern Special-Token-Text im `output_text`, eine Zeile pro Frame (Bild = Frame `<0f>`). [SAM reading]
  - Zeile: `<0f>` dann Records, durch Komma getrennt. Record = Objekt-ID (Ganzzahl, nicht zwingend dicht) + ein Box-Token + ein Mask-Token.
  - Box: `<|box;x1=353;y1=382;x2=453;y2=427;w=537;h=561[;c=0.96]|>`. x1,y1 oben links, x2,y2 unten rechts (inklusiv), in Quellpixeln; w,h = Bildgröße.
  - Maske: `<|mask;x=0;y=0[;c=0.96];data=<H>,<W>,<enc><payload>|>`. H,W = Zeilen,Spalten der Maske (Höhe zuerst), kleiner als das Bild. enc `~` lossless, `!` one_bit. Payload ist Base85 (nicht Base64).
  - Score: Feld `c` (0 bis 1) nur wenn `metadata.include_confidence = "true"`; sonst gibt es keinen Score. Box und Maske eines Records tragen denselben Wert.
  - Mehrere Treffer pro Prompt: ja, jeder Treffer ein Record mit eigener ID. Mehrere Prompts pro Call: nein (ein Konzept pro Request).
  - Platzierung der Maske im Bild: die Doku nennt `x=0;y=0` ("Maskenursprung, immer 0") und sagt nur, die Maske sei kleiner als das Bild. In allen Doku-Beispielen entspricht Maskengröße exakt der Box (Box x 353..453, y 382..427 inklusiv = 101x46, Maske `data=46,101`; zweites Beispiel 81 Spalten bei x 260..340). Schluss: Maske = Ausschnitt der Box, an (x1,y1) ins Bild zu legen. Das ist eine Ableitung aus den Beispielen, im Text nicht ausdrücklich bestätigt: UNBESTÄTIGT, im ersten Live-Test gegenprüfen.
- Dekodierung: Offizielle Libraries `@meta-sam/parser` (npm) und `meta-sam-parser` (pip, Python >= 3.10, ohne Abhängigkeiten): `decodeMaskToRaster` (Uint8Array 0/1, zeilenweise, H*W), `decodeMaskToRLE` (COCO-RLE `{size:[h,w], counts}`), `decodeMaskToSVGPath` (M/L/Z-Pfad); Python: `decode_mask_to_raster`, `decode_mask_to_rle`, `decode_mask_to_svg_path`, `build_object_prompt`. So lassen sich Konturen/Polygone ableiten. Eigenes Parsing ohne Library: Base85-Alphabet der Library nicht dokumentiert, daher Library nutzen (genaues Base85-Alphabet UNBESTÄTIGT). [SAM client-libraries]
- Preis: $2,50 pro 1.000 Bilder; Video $0,20 pro 1.000 Frames (min. 50 Frames/Request). Rate Limit 3.000 RPM, kein TPM. [PRICE]
- Fehler: ungültiger Prompt/Metadata = 400 (permanent); unbekanntes/nicht freigeschaltetes Modell = 404 mit `code: model_not_found`. [SAM segmenting]
- Minimales curl (wörtlich aus [SAM media-segmentation]; URL durch eigene ersetzen):
```
curl -N -X POST "https://api.meta.ai/v1/responses" \
  -H "Authorization: Bearer $MODEL_API_KEY" -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"model":"sam-3.1","input":[{"type":"message","role":"user","content":[
        {"type":"input_text","text":"glasses"},
        {"type":"input_image","image_url":"https://example.com/photo.png"}]}],
       "stream":true,"metadata":{"mask_encoding":"one_bit","include_confidence":"true"}}'
```
  (`metadata` ergänzt aus [SAM segmenting]; die Basisform ohne metadata ist wörtlich dokumentiert.) Antwort-Zeilen kommen als `data: {"type":"response.output_text.delta","delta":"<0f>0<|box;...|>..."}`.

## 3. Muse Voice Transcribe

- Modell-ID: `muse-voice-transcribe-1.0`. Eingabe Audio, Ausgabe Transkript-Text (keine Wort-Zeitstempel, keine Sprachsynthese). 25 evaluierte Sprachen mit Code-Switching. [OV][STT]
- Datei-Endpunkt: `POST /v1/asr/transcribe` (multipart/form-data) mit Auth-Header. Realtime: WebSocket `wss://api.meta.ai/v1/asr/realtime` (Details nicht gelesen). [OV][STT]
- Request: Teil `request` (JSON, Content-Type application/json) und Teil `audio` (Datei). Felder in `request`: `model` (Pflicht), `audioEncoding` (Pflicht, nur `"WAV"`), `mode` (`PUSH_TO_TALK` Default, `ENDPOINTING`, `DIARIZATION`), `keywords` (Array), `languageBias` (Array von Sprachnamen, z. B. ["German"]), `partialMode`, `emitAudioProgress` (nur Event-Stream). Optional Query `sessionId`. [STT schemas]
- Audioformat: ausschließlich WAV (RIFF/WAVE), mono, 16-bit Integer PCM, 16 kHz oder 24 kHz. Andere Formate vorher konvertieren: `ffmpeg -i input.m4a -ac 1 -ar 24000 -c:a pcm_s16le -map_metadata -1 output.wav`. Limits: max. 10 Minuten Audio (sonst 400), Body max. 32 MB (sonst 413). Realtime nutzt rohes PCM 16-bit LE mono (PCM_24KHZ oder PCM_16KHZ). [STT]
  - Für die PWA: Browser-Aufnahme (webm/mp4) muss clientseitig oder im Proxy nach WAV 16/24 kHz mono konvertiert werden. Wie, ist nicht Teil der Doku.
- Antwort (Accept: application/json): `{"sessionId":..., "transcript":"...", "audioDurationMs":..., "turns":[...]}` (turns leer bei PUSH_TO_TALK). `Accept: text/plain` liefert Text, `text/event-stream` Events. [STT schemas]
- Preis: $0,18 pro Stunde Audio, sekundengenau. Limits: 256 gleichzeitige Streams, 16.000 Streams pro Stunde (Realtime und Datei teilen sich das Budget); bei Überschreitung HTTP 429. Keine Contributor-Variante. [PRICE]
- Minimales curl (wörtlich aus [STT transcribe]):
```
curl -X POST "https://api.meta.ai/v1/asr/transcribe" \
  -H "Authorization: Bearer $MODEL_API_KEY" -H "Accept: application/json" \
  -F 'request={"model":"muse-voice-transcribe-1.0","audioEncoding":"WAV","mode":"PUSH_TO_TALK"};type=application/json' \
  -F "audio=@recording.wav;type=audio/wav"
```
- UNBESTÄTIGT: Unterstützt Deutsch gut? Die Liste der 25 Sprachen steht nicht in den gelesenen Seiten; per `languageBias: ["German"]` und Test klären.

## 4. Hackathon

Quellen: [CV] (offiziell) und [RS] (Drittquelle, stützt sich auf Waiver). Die Official Rules lagen laut [RS] am 17.10. noch nicht vor und haben Vorrang.

- Zeitraum: Start 26.10.2026 (Kickoff-Livestream), Abgabe bis 4.11.2026, 21:00 Uhr ET (= 5.11., 02:00 UTC, also 03:00 Uhr MEZ am 5.11.), Jurierung 4.-8.11., Finale und Gewinner am 9.11. [CV][RS]
- Tracks: Indie (Einzelpersonen, Studierende; laut [RS] bis 4 Personen), Startup. Pro Projekt genau ein Track. Indie-Lens: Kreativität, technischer Anspruch, "funktioniert es". [CV]
- Themen: "Build for Your World" und "Push the Frontier". [CV]
- Gewichtung (laut Waiver, wiedergegeben in [RS]): Impact 30 %, Use of Meta AI Tooling 25 %, Demo 25 %, Technical Depth and Execution 20 %. [RS]
  - Tipp aus [RS] (deren Einschätzung, nicht offiziell): mindestens zwei Meta-Produkte kombinieren, z. B. SAM 3.1 plus Muse Spark.
- Preise Indie: gesamt $400.000, 1. Platz $150.000 [RS]. Bonuspreise bis $50.000. [RS]
- Abgabe: über das Cerebral-Valley-Portal; "working demo" und Demo-Video. Videolänge: UNBESTÄTIGT (nicht genannt). Was "live product" konkret heißt: UNBESTÄTIGT; die Demo-Kategorie bewertet, ob die Demo "live standhält" ([RS]). Ob Repo-Link, öffentliche Demo-URL, Testzugang oder Beschreibung Pflicht sind: UNBESTÄTIGT, Official Rules abwarten.
- Rechte: Einreichung bleibt dein Eigentum, Veranstalter bekommen eine unbefristete, weltweite, einfache Nutzungslizenz. Nichts ist vertraulich. [RS]
- Meta-API-Geografie: Zugriff aus mehreren Ländern gesperrt (Liste in [RS], Quelle Geographic Use Policy); Deutschland nicht genannt.

## 5. Offene Punkte (UNBESTÄTIGT)

1. SAM: Platzierung der Maske relativ zur Box (abgeleitet: Box-Ausschnitt), Base85-Alphabet, JSON-Feld im nicht-streamenden Fall, Bildgrößen-/Auflösungslimit, Eignung der Prompts "tear / open seam / hole / shoe sole / seam / detached sole".
2. Muse Spark: Auflösungslimit, HEIC, exakte Syntax von `text.format` (Responses), json_object-Modus, Zahl/Größe von Bildern bei Payload-Limit außer 50 MB inline.
3. Voice: Deutsch-Qualität, Sprachliste, Browser-Aufnahme nach WAV konvertieren.
4. Hackathon: Videolänge, Repo-/Demo-URL-Pflicht, Bedeutung von "live product", finale Official Rules, Kreditkarte für die $150, der im PRD genannte Proxy mit Tageslimit.
5. Keine Live-Aufrufe ausgeführt (kein API-Key vorhanden); alle curl-Beispiele stammen aus der Doku, die Data-URL-Variante für Muse Spark und `metadata` bei SAM sind aus Textbeschreibungen zusammengesetzt.

## 6. Proxy-Readiness: Offline-Prüfung am 26.10.2026

Keine Meta-API-Aufrufe ausgeführt, keine Credits verbraucht. Geprüft wurden PRD §§6–11, diese Notizen, Proxy-Code und die lokal installierten SDKs. Die folgenden Punkte sind Offline-Befunde, keine Bestätigung durch den Modelldienst:

- Muse Spark bleibt bei `chat.completions` und `response_format.json_schema`, mit Bildblöcken `image_url.url` in der User-Nachricht. Schema-Generator korrigiert: Die Schema-Annotation `title` darf entfernt werden, das echte Schritt-Feld `properties.title` nicht. Diagnose verwendet Prompt B v2; v1 unverändert. v2 verlangt belegte Etikettangaben, passende Handnadel/Garn/Stich, ausführbare Stichtechnik und nur vorhandene Segment-/Artikel-IDs. Wirkung und Qualität live **UNBESTÄTIGT**.
- SAM nutzt jetzt die hier dokumentierte Streaming-Variante: ein `input_text`, ein PNG-`input_image`, String-Metadata `include_confidence: "true"`, `mask_encoding: "one_bit"`, `Accept: text/event-stream`; Textdeltas werden bis `response.completed` zusammengesetzt. Incomplete/Fehler/Stream ohne Abschluss sind keine erfolgreichen Nulltreffer und werden nicht gecacht. Damit ist der unbestätigte nicht-streamende Ergebnis-Envelope keine Voraussetzung des Proxys mehr.
- Der Quelltext der installierten offiziellen Python-Library bezeichnet `SegmentationMaskBounds` ausdrücklich als halb offene Quellbild-Grenzen für eine Box-lokale Maske und konvertiert inklusive x2/y2 nach right/bottom +1. Das stützt die Ableitung in §2 offline. Ausrichtung/Skalierung auf echten Bildern sowie Erkennung von `tear`, `hole`, `open seam` bleiben **UNBESTÄTIGT**.
- Synthetische Raw-Wire-Fixtures in `proxy/tests/fixtures/sam/` verwenden den offiziellen privaten `_encode_raster`-Helper, inklusive Base85-`!`-Payloads. Abgedeckt: ein Pixel dünner gebogener Riss, Loch, Innenloch, nicht dichte Objekt-IDs/mehrere Treffer, Nulltreffer, defekte Zeilen/Masken und ungültige Koordinaten. Parser → Polygon → Segment sowie die komplette Real-Client-Pipeline laufen offline über MockTransport. Diese Daten sind ausdrücklich keine aufgezeichneten API-Antworten.
- Polygon-Konvertierung ohne verlustreiches Downsampling; diagonale dünne Risse bleiben zusammenhängend. Der unveränderte App-Vertrag hat nur einen äußeren Polygonring: Innenlöcher und kleinere getrennte Inseln werden nicht wiedergegeben. Defekte Masken fallen auf gültige Boxen zurück, ungültige Boxen werden verworfen.
- Voice sendet ausschließlich Multipart `request` (application/json, model/audioEncoding=WAV/mode/languageBias) plus `audio` (audio/wav). WAV wird am Client-Rand erneut geprüft und auf kanonisches RIFF/PCM normalisiert; leere/abgeschnittene Dateien, falsche Samplebreite und >600 Sekunden werden vor dem Aufruf abgewiesen. Transkript-Envelope wird geprüft, erfolgreiche Transkripte werden bei aktiviertem Cache ebenfalls gecacht. Deutsche Erkennungsqualität bleibt **UNBESTÄTIGT**.
- SDK-eigene HTTP-Retries ausgeschaltet; normale Spark-JSON-Validierung hat weiter genau einen Retry. Sicherheitsprüfung berücksichtigt auch Antworten der Rückfragerunde. Ungeklärte Materialfragen nach dieser Runde, repair_pro/replace und gesperrte Fälle liefern keine Anleitung. SAM-Ausfall kann in der normalen Pipeline auf Text ohne erfundene Segmente zurückfallen; Budgetfehler werden weitergegeben.
- `proxy/scripts/smoke_real.py` macht ohne exportiertes `META_API_KEY` nichts außer SKIP (kein dotenv, keine Eingabedatei-/Cache-I/O, keine Requests). Mit Key genau ein Versuch je Modell bei frischem Cache, danach Replay ohne API; keine Retries. Ein über Prozess-Lock und persistentes Write-ahead-Journal geschützter lokaler Deckel reserviert maximal 0,093374 USD unter dem fest codierten Limit 0,10 USD: Spark 65.536 Input-/2.048 Output-Token (256 reichten live nicht, siehe benchmark.md), SAM ein Bild, Voice maximal fünf Sekunden. Fehler/Abbruch behalten die Reservierung; beschädigtes Journal führt zum Abbruch.
- Bewusste Smoke-Grenze für den Deckel: Spark wird nur mit <=8 KiB Text/Schema geprüft, da diese Notizen keine harte Obergrenze für Bildtokens liefern. SAM bekommt das angegebene Foto. Voice bekommt optional eigene Sprache (WAV <=5 Sekunden), sonst eine Sekunde Stille im RAM. Spark-Fotopfad/Prompt B und Voice-Sprachqualität sind dadurch live weiterhin **UNBESTÄTIGT**. Der normale Proxy behält Spark-Bildeingabe.
- **UNBESTÄTIGT:** Annahme und Durchsetzung des OpenAI-kompatiblen `max_completion_tokens` durch Meta (neu: 4096 im normalen Proxy, 256 im Smoke), tatsächliche Tokenzählung und Rechnungsbeträge. Der Smoke hat einen harten lokalen Reservierungsdeckel; ein serverseitig garantiertes Kontolimit ist weiterhin nicht belegt. Das normale Tagesbudget bilanziert nach Antworten und kann durch parallele Requests überschritten werden; es ist kein harter Vorabdeckel. Morgen zuerst den begrenzten Smoke nach `proxy/README.md` ausführen, nicht den Benchmark.

## 7. Neue Endpunkte (28.10.)

Keine Live-Aufrufe an `api.meta.ai`, keine Credits verbraucht. Neue Endpunkte und Verträge wurden ausschließlich mit synthetischen Fixtures und `httpx.MockTransport` geprüft. Vollständiger iOS-Vertrag: `proxy/CONTRACT-CHANGES.md`.

- `/refine`: `{image_base64, points:[{x,y,label:"positive"|"negative"}], box?:[x,y,w,h], label}` → ein Segment mit `source:"tap"`. Koordinaten 0..1 im EXIF-orientierten Foto; Umrechnung nach der bestehenden Verkleinerung in die tatsächlich gesendeten PNG-Pixel. Offizieller `build_object_prompt`: ein Objekt `1`, Box zuerst, positive Punkt-Tokens direkt aneinander, negative mit `-`; **Kommas trennen Objekte, nicht positive Punkte desselben Objekts**. Inklusive x2/y2, w/h = tatsächliche Bildgröße, `mask_encoding:"one_bit"`. Syntax durch [SAM-Doku](https://dev.meta.ai/docs/sam/segmenting) und lokale Library gestützt; Modellannahme/Maskenqualität live **UNBESTÄTIGT**.
- `/analyze`: Nach erfolgreicher SAM-Textsuche ohne Schadsegmente liefert Spark strukturiert `{concept, box:[x1,y1,x2,y2] | null}` auf dem 0–1000-Raster. Leicht überstehende Werte werden begrenzt; ungültige/entartete Boxen abgewiesen. Danach SAM-Boxprompt; nur eine tatsächliche SAM-Maske wird als `source:"grounding"` ergänzt. Textsegmente haben `source:"text"`. Optionales SSE `grounding` mit `{"label":"Schadstelle genauer lokalisieren"}` zwischen `progress(segment)` und `progress(diagnose)`; bestehende Ereignisse unverändert. Grounding und Erkennungsqualität live **UNBESTÄTIGT**.
- Multi-Instance und Masken: alle akzeptierten Treffer desselben Konzepts bleiben erhalten, eigene Segment-IDs, keine Acht-Segmente-Grenze; bestehende Synonym-Zusammenführung bleibt. Optionales Top-Level `instances` zählt ausgegebene Schadsegmente pro `prompt`. Optionales `mask.rings:[{points:[[x,y],...],hole:bool}]` enthält Außenringe, mehrere Innenlöcher und Inseln. `mask.points` bleibt der bisherige größte Außenring. Synthetische One-Bit-Fixtures prüfen Platzierung und verschachtelte Ringe; Verhalten auf echten Fotos **UNBESTÄTIGT**.
- `/track`: `{video_base64,concept}` → `{frames:[{index,segments:[Segment + object_id:string]}],fps?}`. SAM `input_video.video_url` als MP4-Data-URL, Streaming bis `response.completed`, offizieller Video-Parser für Box-lokale Masken, stabile Objekt-IDs. Im Real-Modus derzeit kein `fps`; leere Quellframes bleiben leer. Nur Base64/Größe/MP4-Header lokal geprüft, keine Codec-Prüfung. Videokosten lokal geschätzt als $0,20/1000 Frames (mindestens 50), aus höchstem ausgegebenem Index + 1; nicht ausgegebene Endframes werden nicht erfasst. Videoannahme, Vollständigkeit und tatsächliche Abrechnung **UNBESTÄTIGT**.
- `/after-preview`: `{image_base64,diagnosis_summary,stitch_type}` → `{image_base64,model}`. `muse-image-1.0` über Multipart `POST /v1/images/edits`: PNG-Teil `image`, `model`, `prompt` aus Diagnose/Stichart, `n=1`, `response_format=b64_json`; Antwort `data[0].b64_json`. Das ist inzwischen in der [offiziellen Edit-Referenz](https://dev.meta.ai/docs/api-reference/images/edit-image) und den [Schemas](https://dev.meta.ai/docs/api-reference/images/schemas) dokumentiert, kein bloß angenommener OpenAI-Shape. Live-Annahme, Reparaturqualität und der vorgegebene lokale Preis **UNBESTÄTIGT**. Gebucht werden $0,01 je erfolgreicher HTTP-Antwort, auch bei ungültigem Bildpayload; validierte Bildantworten werden bei aktiviertem Modellcache gecacht, Replay kostet lokal nichts. Keine Bild-URL-Folgeabrufe. Das Tagesbudget bleibt eine nachträgliche Bilanz ohne harte Reservierung.
- Mock-Modus: Refinement aus Punkten/Box inklusive negativer Innenlöcher, `textile_grounding`, `textile_multi`, `textile_rings`, zehn bewegte Tracking-Frames (Objekt 7, 10 fps), Vorschau mit kleiner deterministischer Pixeländerung. Keine Modellkosten. Neue Wire-Tests prüfen EXIF/Downscaling, exakte Geometrie-Tokens, Grounding, Multi-Instance, Löcher/Inseln, geteilte Video-SSE-Deltas, unvollständige Streams, Multipart-Edit, Cache und Kosten. Diese Offline-Ergebnisse ersetzen keine Live-Verifikation; alle neuen Modellpfade bleiben **UNBESTÄTIGT**.

## Proxy-Ergänzungen 29.10.2026

- `/detect`: `{image_base64,concept}` → `{segments}`; ein SAM-Textprompt auf 768 px, bei Nulltreffer `[]` ohne Spark-Grounding. Live **UNBESTÄTIGT**.
- `/analyze` sendet zusätzlich `event: segments` (früh, identisch mit `result.segments`) und im Agent-Modus `event: agent_step`. Weak-Segment-Filter (Score < 0,6, überlappend bzw. Teile, höchstens 3 Teile).
- `/after-preview`: optional `category` (`textile`|`shoe`), `repair_hint` (≤ 200), `stitch_type` jetzt optional.
- Muse Wonder (`muse-wonder-1.0`, Responses API): Preise 4,00 / 20,00 / 0,20 $ je 1 Mio. Token (Input / Output / gecachter Input), Quelle https://dev.meta.ai/docs/pricing-rate-limits. Details: agent-notes.md.
