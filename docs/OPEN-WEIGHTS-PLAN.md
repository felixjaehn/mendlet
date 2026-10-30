# Open weights: Muse Glimmer im Proxy (Entscheidungsvorlage, 30.10.2026)

**Warum:** Die Jury-Runde 1 deckelt "Use of Meta tooling" unter 9, weil keine Open-Weight-Modelle genutzt werden. Das Briefing nennt Muse Glimmer und Muse Spark Open ausdrücklich, dazu gibt es den Bonus "Best Build on Meta Open Weight Models" ($10K).

**Fakten** ([Meta Research](https://research.meta.ai/blog/introducing-muse-glimmer-open-agentic-model), [Context Studios](https://www.contextstudios.ai/blog/muse-glimmer-metas-30b-open-agentic-model-that-runs-on-your-device)):
- 30B dense, Text und Bild rein, Text raus, Function Calling. Ausgelegt auf 32 GB Speicher. In 4-Bit unter 20 GB.
- Läuft auf Mac oder PC, nicht auf dem iPhone. ExecuTorch wird erwähnt, ein iPhone-Pfad ist bei 30B aber unrealistisch.
- Transformers-ID `meta-models/Muse-Glimmer-30B`.

**Bester Einsatz:** "Not working?" (`/step-help`) läuft lokal auf Glimmer im Proxy auf dem Mac. Der Mensch beschreibt das Problem mitten in der Reparatur, Glimmer sieht das Foto, den aktuellen Schritt und den Text und antwortet. Das ist privat, kostet keine API-Credits und funktioniert offline. Fallback ist Muse Spark über die API. Zweite Option: Die Sicherheitsvorprüfung läuft zuerst lokal und schickt gefährliche Gegenstände gar nicht erst hoch.

**Aufwand:** etwa 4 bis 6 Stunden, plus Download von rund 20 GB nach `/Volumes/Extreme SSD/signa-data/weights/`. Neue Abhängigkeit im Proxy: transformers oder MLX. Risiken: Latenz auf dem Mac, Speicher, Lizenz-Gate beim Download.

**Offen, Entscheidung beim Owner:** Download und Einbau freigeben? Ohne Freigabe wird nichts installiert (Memory-Regel: keine fremden Pipelines oder großen Downloads ohne Rückfrage).
