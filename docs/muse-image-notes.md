# Muse Image: Notizen (Primärquelle, 28.10.2026)

Quelle: https://dev.meta.ai/docs/image-generation (gelesen am 28.10.2026 in Chrome).

- Modell `muse-image-1.0`: ein Modell für Generierung und Bearbeitung. Agentisch: Es sucht selbst nach Bild- und Webreferenzen und rechnet Layouts per Shell. Diese Werkzeuge sind standardmäßig an.
- **Bearbeitung in einem Schuss:** `POST /v1/images/edits`, JSON-Body (Meta-spezifisch, Content-Type `application/json`):
  ```json
  {"model":"muse-image-1.0","prompt":"…","images":[{"image_url":"data:image/jpeg;base64,…"}],"n":1,
   "reasoning_strength":"low","tool_enablement":{"enable_web_search":false,"enable_shell":false,"enable_image_search":false}}
  ```
  Alternativ Multipart über `client.images.edit(image=…)` im OpenAI-SDK. `mask`, `input_fidelity` und `partial_images` lösen 400 aus. Unbekannte Top-Level-Felder (z. B. `seed`) ebenfalls 400. `moderation` darf nicht gesetzt werden (400 bei muse-image-1.0).
- **Antwort:** `{"created":…, "data":[{"b64_json":"…"}], "output_format":"webp", "usage":{…}}`. Standardformat ist webp, `output_format` kann `png` oder `jpeg` sein. `size` als "WxH" legt nur das Seitenverhältnis fest.
- **Mehrere Runden:** Responses API (`model: muse-image-1.0`, `previous_response_id`). Das Bild steht im Output-Item `image_generation_call.result` (Base64). Einziges erlaubtes Tool ist `image_generation` (mit `reasoning_strength`, `size`, `output_format`, Tool-Schaltern).
- **Streaming:** `stream: true` → Ereignis `image_edit.completed` mit `b64_json`.
- **Preis:** pauschal 0,01 $ pro erfolgreich zurückgegebenem Bild, unabhängig von `reasoning_strength` und Werkzeugen.
- **Fehler:** 503 = wiederholbar (Backoff), 400 `content_policy_violation` = Sicherheitsfilter.
- Für die Nachher-Vorschau: `reasoning_strength: "low"` und alle Werkzeuge aus, denn wir brauchen keine Webreferenzen und wollen es schnell.
