# Live-Aufnahmen für den Demo-Modus

Echte Antworten des Proxys im Real-Modus (Meta Model API, 28.10.2026), unverändert gespeichert. Der Demo-Modus spielt sie ab, damit die App ohne Netz genau das zeigt, was die echten Modelle geliefert haben. Die Fotos sind KI-generiert (siehe `testdata/SOURCES.md`).

| Datei | Foto | Inhalt |
| --- | --- | --- |
| `jeans.json` | `jeans.jpg` | Prompt B v3, ohne Etikett: SAM `rip` 0,91, Annahme Denim, 5 Schritte |
| `jeans_label.json` | `jeans.jpg` + `jeans_label_photo.jpg` | Mit Etikettfoto: 98 % Baumwolle / 2 % Elasthan, dehnbarer Flicken |
| `pulli.json` | `pulli.jpg` | Neu aufgenommen am 29.10. mit dem Schwachsegment-Filter des Proxys: Kleidungsstück 0,97 und 3 Löcher (0,78 / 0,78 / 0,77), keine Schein-Risse |
| `sneaker.json` | `sneaker.jpg` | `detached sole` 0,84, Kleber-Anleitung |
| `heizjacke.json` | `heizjacke.jpg` | Lithium-Akku, in 3 s gesperrt (warn_only) |
| `jeans_after.jpg` | – | Muse Image Nachher-Vorschau (Stopfen), 12 s |
| `pulli_after.jpg` | – | Muse Image Nachher-Vorschau, alle 3 Löcher gestopft, 11 s |
| `jeans_agent.json` | `jeans.jpg` | 29.10., AGENT_MODE=wonder: `{recorded, agent_steps (3 echte Schritte), result}`. Der Demo-Modus spielt diese Schritte ab (davor der Classify-Schritt der Pipeline) und nutzt `result` als Analyse |
| `jeans_agent_recovery_trace.json` | – | 29.10., erste Agentenversion, 94 s: 7 echte Schritte, SAM meldet HTTP 500, der Agent weicht über Spark-Lokalisierung plus SAM-Box aus. Einstellungen: "Agenten-Lauf mit Fehlerbehebung zeigen". Enthält kein Ergebnis, es wird `jeans_agent.json` → `result` verwendet |

Für Pulli, Sneaker und Heizjacke gibt es keine aufgezeichneten Agentenschritte; die App zeigt dort nur den Classify-Schritt und die Phasen, keine erfundenen Schritte.
| `platine.json` | `platine.jpg` | Elektronik live 29.10.: Kabel, blanke Enden, Lötpads +/− (Spark liest Siebdruck, SAM segmentiert), Löt-Overlays rot→+, schwarz→− |
