# Blocker

| Blocker | Seit | Auswirkung | Workaround | Wer löst |
| --- | --- | --- | --- | --- |
| Meta-API-Key fehlt | 26. Okt. | Kein echter Aufruf von Muse Spark, SAM 3.1 oder Voice Transcribe | Proxy läuft im Mock-Modus (`MOCK_MODE=1`), die App hat einen Demo-Modus mit eingebauten Fixtures | Felix: Key in `proxy/.env` |
| Testfotos fehlen (`testdata/`) | 26. Okt. | SAM-Fototest, Benchmark und Etikett-Test stehen aus | Prozedural erzeugte Demo-Bilder in der App, Benchmark-Runner läuft mit Mock | Felix: Fotos am 27. Okt. (mind. 10 Textil, 5 Schuh, 3 Etiketten, 4 Sicherheitsfälle) |
| SAM-3.1-Maskenformat unbestätigt | 26. Okt. | Der Adapter im Proxy wandelt in das interne Polygonformat, ist aber noch nicht gegen die echte API getestet | Polygon-Vertrag (normalisiert) ist fest, Boxen als Fallback | Erster Echt-Test mit Key |
| Discord-Fragen offen (Live-Produkt, Vorarbeit) | 26. Okt. | Unklar, ob Juroren die App selbst starten | Demo-Modus funktioniert ohne Server | Felix |
