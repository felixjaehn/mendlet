# Demo-Skript (3:00)

Heldenfall: Lieblingsshirt oder -jeans mit Riss an der Naht. Gedreht wird mit echtem Kleidungsstück und echtem iPhone, dazu Bildschirmaufnahmen. Jede Zahl im Video stammt aus `impact.md` (belegt) oder aus `benchmark.md` (gemessen).

| Zeit | Bild | Ton (Sprechertext, Deutsch oder Englisch mit Untertitel) | Bewertungskriterium |
| --- | --- | --- | --- |
| 0:00–0:12 | Nahaufnahme: Hände halten ein Shirt mit Riss. Schnitt auf Mülltonne. Texteinblendung "1 Lkw-Ladung pro Sekunde" mit Quelle Ellen MacArthur Foundation | "Jede Sekunde landet weltweit eine Lkw-Ladung Kleidung auf der Deponie oder in der Verbrennung. Oft wegen eines Risses, den man in 20 Minuten nähen könnte." | Impact |
| 0:12–0:20 | Titelkarte: App-Name und "Built with Muse Spark + SAM 3.1" | "Ich habe einen Reparatur-Assistenten gebaut, der dir genau das zeigt: auf deinem eigenen Foto." | Meta-Tools |
| 0:20–0:40 | Screen: Foto aufnehmen, "Riss an der Naht" diktieren (Mikro). Analyse-Screen: die vier Stufen haken sich ab, die SAM-Masken blenden auf dem Foto ein | "Muse Spark prüft zuerst Objekt und Sicherheit. SAM 3.1 markiert den Riss pixelgenau. Dann stellt Muse Spark die Diagnose." | Tech-Tiefe, Meta-Tools |
| 0:40–1:00 | Rückfrage-Sheet: "Zeig mir das Etikett". Etikett fotografieren. Banner "98 % Baumwolle, 2 % Elasthan erkannt". Diagnose aktualisiert sich: dehnbarer Stich, Rundspitz-Nadel | "Statt zu raten, fragt die App nach. Das Etikett verändert das Ergebnis: Elasthan braucht einen elastischeren Stich." | Demo, Tech-Tiefe |
| 1:00–1:15 | Entscheidungs-Screen: "Selbst reparieren", 20–40 Min., 3–8 €, Pille "Schätzung, keine Garantie" | "Ehrliche Empfehlung: selbst reparieren, Profi oder ersetzen, mit Zeit und Kosten als Spanne." | Impact |
| 1:15–1:30 | Einkaufsliste: zwei Einträge auf "Habe ich", einer auf "Kaufen", Haushaltsalternative sichtbar, Teilen | "Die Einkaufsliste enthält genau das, was die Schritte brauchen, mit Alternativen aus dem Haushalt." | Demo |
| 1:30–2:10 | Geführte Reparatur: **Stichpfad zeichnet sich über den echten Riss** (3 s Close-up). Sicherheitsschritt "Schere" mit Bestätigung. Schnitt auf echte Hände, die den Leiterstich nähen. "Hilft nicht" → Schritthilfe antwortet zu diesem einen Schritt | "Den Stichpfad berechnet die App selbst aus der SAM-Maske: Skelett, Mittellinie, Stiche im gleichen Abstand. Das Modell wählt nur die Stichart." | Demo, Tech-Tiefe (Signature-Moment) |
| 2:10–2:22 | Abschluss-Screen: Häkchen, Vorher-Nachher, "≈ 0,25 kg Textil vor Deponie oder Verbrennung bewahrt" | "Repariert. Ein Kleidungsstück weniger auf der Deponie." | Impact |
| 2:22–2:37 | Neues Foto: beheizbare Jacke mit Akku → Sperr-Screen | "Und wo es gefährlich wird, gibt es keine Anleitung. Akkus, Helme, Netzteile sperrt die App, bevor eine Diagnose entsteht." | Tech-Tiefe, Verantwortung |
| 2:37–2:52 | Grafik der Pipeline (Muse Spark → SAM 3.1 → App-Geometrie → Muse Spark), danach die Benchmark-Tabelle mit echten Zahlen inklusive Fehlerquote | "Getestet an X eigenen Fällen: Schadstelle in X von Y korrekt markiert, alle Sicherheitsfälle gesperrt. Auch die Fehler stehen im Repo." | Tech-Tiefe |
| 2:52–3:00 | Shirt wird angezogen, Endkarte mit Repo-Link | "Reparieren statt wegwerfen. Mit deinem eigenen Foto." | Impact |

## Drehhinweise

- Erst den echten Riss fotografieren, die Analyse laufen lassen und das Ergebnis aufzeichnen. Danach wirklich nähen, so entsteht echte B-Roll. Nichts faken: Die Platzhalter X und Y kommen aus dem echten Benchmark.
- Bildschirmaufnahme auf dem iPhone (Kontrollzentrum), Hochformat, danach in 9:16 oder 16:9 mit Rand schneiden.
- Den Stichpfad 2 bis 3 Sekunden ungeschnitten zeigen, er ist der stärkste Moment.
- Video und README müssen kennzeichnen, dass alles in der Bauphase entstand (PRD §13).
