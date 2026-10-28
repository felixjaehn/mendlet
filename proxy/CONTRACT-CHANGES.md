# Vertragserweiterungen vom 28.10.2026

Alle bisherigen Pflichtfelder und SSE-Ereignisse bleiben bestehen. Die folgenden Zusatzfelder müssen auf iOS optional dekodiert werden. Live-Verhalten aller neuen Modellpfade: **UNBESTÄTIGT**; Tests ausschließlich offline.

## Gemeinsame Antwortfelder

### Segment

Zusätzlich zu `id`, `label`, `kind`, `prompt`, `box`, `mask`, `score`:

```typescript
source?: "text" | "tap" | "grounding" | null
```

`text`: SAM-Konzeptsuche, auch beim Tracking. `tap`: manuelle Punkte/Box. `grounding`: Spark-Box plus tatsächlich erhaltene SAM-Maske. Alte Antworten ohne `source` bleiben gültig. Segment-IDs sind innerhalb einer Analyse eindeutig, nicht global. Mehrere Instanzen desselben Konzepts erhalten je eine ID; überlappende Boxen desselben Konzepts werden nicht mehr verworfen. Die Grenze von acht Segmenten entfällt. Bestehende Zusammenführung überlappender Synonyme (`tear`/`rip`) bleibt bestehen.

### Mask

`mask` bleibt nullable, `format` bleibt `"polygon"`, `points` bleibt unverändert der größte Außenring. Zusätzlich:

```typescript
rings?: Array<{
  points: Array<[number, number]>;
  hole: boolean;
}> | null
```

Alle Koordinaten beziehen sich normalisiert (0..1) auf das ganze orientierte Foto, nicht auf die Segmentbox. `hole: false` bedeutet Außenring oder Insel; `hole: true` ein auszuschneidendes Innenloch. Ringe sind geschlossene Polygone ohne wiederholten Endpunkt. Bei SAM-Rastern stehen sie nach absteigender Fläche; `rings[0].points` ist `points`. Zum Zeichnen alle Ringe gemeinsam mit Even-odd-Füllregel verwenden (auch Inseln in Löchern), nicht einfach sämtliche Löcher zuletzt übermalen. Alte Clients können weiterhin nur `points` zeichnen. Defekte Masken fallen wie bisher auf `mask: null` und die gültige Box zurück.

## POST /analyze

Unveränderter Request. Zusätzlich im JSON-Ergebnis und im SSE-`result`:

```json
{"instances": {"tear": 2, "hole": 1}}
```

Typ: `instances?: Record<string, number> | null`. Schlüssel = `prompt` der ausgegebenen Schadsegmente (`kind: "damage"`), Wert = nichtnegative Anzahl. Teile werden nicht mitgezählt. Konzepte ohne ausgegebene Schäden fehlen; bei einer abgeschlossenen Analyse ohne Schadsegmente `{}`, bei früh gesperrten Fällen derzeit `null`. Zählung nach der Synonym-Zusammenführung. Nicht als Gesamtzahl tatsächlich vorhandener Schäden interpretieren.

Wenn die erfolgreiche SAM-Textsuche keinen Schaden findet, folgt Spark-Grounding und danach SAM mit einer Box. Spark liefert `[x1,y1,x2,y2]` auf dem 0–1000-Raster; Werte außerhalb werden auf die Bildgrenze begrenzt, leere/verkehrte Boxen abgewiesen. Ohne sichtbaren Schaden (`box: null`) oder ohne SAM-Maske wird kein Schaden erfunden. Bestehende Teilsegmente bleiben erhalten. Budgetfehler werden weitergegeben, andere Grounding-Fehler erlauben die bisherige Textdiagnose.

Optionales SSE-Ereignis unmittelbar vor dem Fallback:

```text
event: grounding
data: {"label":"Schadstelle genauer lokalisieren"}
```

Reihenfolge im erfolgreichen Fallback: `progress(classify)`, `progress(segment)`, `grounding`, `progress(diagnose)`, `progress(plan)`, `result`. Ohne Fallback keine Änderung. `grounding` ist kein neuer Wert des bisherigen `stage`-Enums. `error` bleibt unverändert.

## POST /refine

```json
{
  "image_base64": "<Base64 oder Bild-Data-URL>",
  "points": [
    {"x": 0.5, "y": 0.5, "label": "positive"},
    {"x": 0.6, "y": 0.5, "label": "negative"}
  ],
  "box": [0.25, 0.25, 0.5, 0.5],
  "label": "Riss"
}
```

`image_base64`: String, höchstens 25.000.000 Zeichen. `points`: optional, Standard `[]`, höchstens 256 Punkte. `x`/`y`: endliche Zahlen in 0..1; `label` am Punkt exakt `positive` oder `negative`. `box`: optional/null, `[x,y,w,h]` in 0..1, positive Fläche, vollständig im Bild. Mindestens eine Box oder ein positiver Punkt ist nötig. Oberes `label`: nichtleerer String, höchstens 200 Zeichen.

Koordinaten beziehen sich auf das ganze Foto **nach EXIF-Orientierung**, ohne UI-Ränder oder Ausschnitt. Der Proxy orientiert/verkleinert auf maximal 1536 Pixel und rechnet in die tatsächlich gesendete PNG-Größe um. Punkte werden abgerundet und auf gültige Pixel begrenzt; rechte/untere Boxkante wird aufgerundet und für SAM in inklusive x2/y2 umgerechnet. Beispiel für ein 640×480-Bild: `<0f>1<|box;x1=160;y1=120;x2=479;y2=359;w=640;h=480|><|point;x=320;y=240;w=640;h=480|>-<|point;x=384;y=240;w=640;h=480|>`. Positive Punkte direkt aneinanderhängen; Kommas trennen Objekte, keine Punkte. `label` wird nicht als zusätzliche Textphrase an SAM geschickt. Metadata: `mask_encoding: "one_bit"`.

Antwort HTTP 200: **ein Segment direkt**, kein Envelope/Array. `id: "seg_1"`, `source: "tap"`, `kind: "damage"`, `label` und `prompt` = Request-Label; übriger Segmentvertrag unverändert. Die ID gilt für diesen einzelnen Refinement-Response und ersetzt keine Analyse-ID automatisch. Bei Nulltreffer HTTP 422 mit `error.code: "no_segment"`.

## POST /track

```json
{"video_base64":"<MP4-Base64>","concept":"tear"}
```

`video_base64`: String, auch `data:video/mp4;base64,...`; maximal 50.000.000 dekodierte Bytes (Feldlimit 66.666.700 Zeichen). Der Proxy prüft Base64 und ISO-BMFF-Header, keine Codecs. `concept`: nichtleerer String, höchstens 200 Zeichen; genau eine kurze Nominalphrase senden.

```typescript
{
  frames: Array<{
    index: number;
    segments: Array<Segment & { object_id: string }>;
  }>;
  fps?: number | null;
}
```

Frame-Index ist der ursprüngliche nullbasierte Quellframe (0..14999), Frames aufsteigend. `object_id` ist die von SAM gelieferte dezimale ID als **String**, nicht notwendigerweise fortlaufend. `id` lautet `seg_<object_id>` und bleibt über Frames stabil, unabhängig von Score/Reihenfolge. Boxen/Masken sind je Frame normalisiert. Explizit leere Frames haben `segments: []`; fehlende Frames werden nicht erfunden. Vollständig leerer SAM-Output ergibt `frames: []`. Der HTTP-Endpunkt liefert JSON nach abgeschlossenem Upstream-SSE (`response.completed`); ein unvollständiger Stream ergibt einen Fehler und wird nicht gecacht.

`fps` wird im Real-Modus derzeit weggelassen, da keine verlässliche Bildrate vorliegt. Sonstige null-Felder werden in `/track` ebenfalls weggelassen. Mock: zehn deterministische bewegte Frames, `object_id: "7"`, `fps: 10`. Videokosten lokal: $0,20/1000 Frames, mindestens 50, derzeit geschätzt über höchsten ausgegebenen Frame-Index + 1. Fehlende Endframes und Live-Abrechnung **UNBESTÄTIGT**.

## POST /after-preview

```json
{
  "image_base64": "<Base64 oder Bild-Data-URL>",
  "diagnosis_summary": "Riss entlang der Seitennaht",
  "stitch_type": "ladder_stitch"
}
```

`image_base64`: wie `/refine`. `diagnosis_summary`: nichtleerer String, höchstens 2000 Zeichen; dafür `diagnosis.summary` der Analyse verwenden. `stitch_type`: exakt `ladder_stitch`, `running_stitch`, `darning` oder `whip_stitch` (wie im Overlay-Vertrag).

```json
{"image_base64":"<reines Base64-Bild, keine Data-URL>","model":"muse-image-1.0"}
```

Bildtyp aus den dekodierten Bytes erkennen; der Modellpfad kann PNG/JPEG/WebP liefern. Muse Image bekommt ein orientiertes PNG, eine kurze englische Edit-Anweisung aus Diagnose und Stichart, `n=1`, `response_format=b64_json` über Multipart `POST /v1/images/edits`. Das Modell soll Foto, Material, Perspektive, Beleuchtung und Hintergrund beibehalten. Modellname folgt der Serverkonfiguration `IMAGE_MODEL`, Standard `muse-image-1.0`.

Erfolgreiche HTTP-Antworten buchen lokal $0,01 pro Bild, auch wenn der zurückgegebene Bildinhalt ungültig ist. Erfolgreiche validierte Bilder werden bei `CACHE_MODEL_CALLS=1` anhand von Modell, Prompt und Bildinhalt gecacht; Cache-Treffer buchen keine weiteren Kosten. URLs als Ersatzantwort werden nicht heruntergeladen. Mock gibt das orientierte/verkleinerte Foto als PNG mit einer kleinen deterministischen Pixeländerung zurück und verbraucht kein Budget. Bildqualität und Live-Preis bleiben **UNBESTÄTIGT**.

## Fehler

Bestehender AppError-Envelope: `{"error":{"code":"...","message":"..."}}`, deutsche Meldung. Bild-/Video-Dekodierungsfehler HTTP 422 (`invalid_image`/`invalid_video`), zu große dekodierte Videos 413, Tageslimit 429 (`budget_exceeded`), Modellfehler 502 (`model_output_invalid`/`upstream_error`), Timeout 504 (`timeout`). Pydantic-Requestvalidierung liefert weiterhin FastAPI-422 mit `detail`. Die Endpunkte prüfen das vorhandene Tagesbudget vor dem Modellaufruf; es bleibt eine nachträgliche Kostenbilanz und kann bei parallelen Aufrufen überschritten werden.
