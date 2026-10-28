# Live-Aufnahmen für den Demo-Modus

Echte Antworten des Proxys im Real-Modus (Meta Model API, 28.10.2026), unverändert gespeichert. Der Demo-Modus spielt sie ab, damit die App ohne Netz genau das zeigt, was die echten Modelle geliefert haben. Die Fotos sind KI-generiert (siehe `testdata/SOURCES.md`).

| Datei | Foto | Inhalt |
| --- | --- | --- |
| `jeans.json` | `jeans.jpg` | Prompt B v3, ohne Etikett: SAM `rip` 0,91, Annahme Denim, 5 Schritte |
| `jeans_label.json` | `jeans.jpg` + `jeans_label_photo.jpg` | Mit Etikettfoto: 98 % Baumwolle / 2 % Elasthan, dehnbarer Flicken |
| `pulli.json` | `pulli.jpg` | 3 Löcher als einzelne SAM-Instanzen, ein Stopf-Schritt pro Loch |
| `sneaker.json` | `sneaker.jpg` | `detached sole` 0,84, Kleber-Anleitung |
| `heizjacke.json` | `heizjacke.jpg` | Lithium-Akku, in 3 s gesperrt (warn_only) |
| `jeans_after.jpg` | – | Muse Image Nachher-Vorschau (Stopfen), 12 s |
| `pulli_after.jpg` | – | Muse Image Nachher-Vorschau, alle 3 Löcher gestopft, 11 s |
