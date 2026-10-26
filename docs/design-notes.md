# Design-Notes: Reparatur-Assistent

Stand 26. Okt. 2026. Alle Referenzen stammen aus dem Mobbin MCP und dienen nur als Inspiration. Kein Screen, keine Grafik und kein Asset wird 1:1 übernommen (PRD §13, §15). Alle Icons sind SF Symbols, alle Bilder sind eigene Fotos.

## Designrichtung: "Werkbank"

Die App soll sich anfühlen wie ein ruhiger, kompetenter Handwerker neben dir, nicht wie ein Chatbot. Drei Prinzipien:

1. **Das eigene Foto ist die Bühne.** Jeder Screen nach der Aufnahme zeigt das Foto groß, Overlays liegen direkt darauf. Text erklärt, das Foto zeigt.
2. **Ein Faden als Leitmotiv.** Die Akzentfarbe "Garn" (Orange) erscheint nur dort, wo die App handelt oder führt: Stichpfad, primäre Buttons, Fortschritt. Dadurch wird der animierte Stichpfad zum Signature-Moment der Demo.
3. **Ehrlichkeit sichtbar machen.** Konfidenz, "Schätzung, keine Garantie" und Sperren sind gestaltete Elemente, keine Fußnoten.

### Tokens (`Theme.swift`)

| Token | Light | Dark | Verwendung |
| --- | --- | --- | --- |
| `paper` | #F6F3EE | #121110 | Hintergrund |
| `card` | #FFFFFF | #1E1C1A | Karten, Sheets |
| `ink` | #1C1A17 | #F2EFEA | Primärtext |
| `inkSecondary` | #6B655D | #A39D94 | Sekundärtext |
| `hairline` | #E6E0D7 | #2E2B27 | Trennlinien, Kartenrand |
| `thread` (Akzent) | #E2552B | #FF6A3D | Stichpfad, Primärbutton, Fortschritt |
| `threadSoft` | thread 12 % | thread 18 % | Chips, ausgewählte Zeilen |
| `safe` | #2F7D5B | #4CC38A | erledigt, "habe ich", repair_self |
| `caution` | #C98A00 | #F5B83D | warn_only, sicherheitsrelevanter Schritt, Konfidenz mittel |
| `stop` | #C2372B | #FF5A4E | professional, Sperre, Fehler |
| Segment-Paletten | damage = thread, part = #3A7BD5 / #8E5BD9 / #2BA39A | | Overlays (Füllung 25 %, Kontur 100 %, 2 pt) |

Typografie: SF Pro. Titel `.largeTitle.bold()`, Schritttext `.title2` (groß wie im Kochmodus, lesbar mit Nadel in der Hand), Zahlen `.rounded` und `monospacedDigit()`. Radius: Karten 20, Buttons 16 (Kapsel für Primär-CTA). Abstände: 8er-Raster, Seitenrand 20.

Bewegung: `spring(response: 0.45, dampingFraction: 0.85)` als Standard. Haptik: `.success` bei "Erledigt" und Abschluss, `.warning` bei Sperre, `.selection` beim Abhaken. `reduceMotion` respektieren (Stichpfad dann statisch mit nummerierten Punkten).

Barrierefreiheit: Dynamic Type bis XXL ohne Abschneiden, VoiceOver-Labels für Overlays ("Schadstelle: Riss, 6 cm"), Kontrast AA, Trefferflächen ≥ 44 pt.

## Screens und Referenzen

### 1. Start / Aufnahme
Referenzen: [Lovi Kamera](https://mobbin.com/screens/fb588f6f-6692-4a3f-ac84-2eba98d8df69), [CapWords Rahmen + Hinweis](https://mobbin.com/screens/026d84ee-1718-4afd-82e0-f7ad839a8181), [MacroFactor Snap/Describe-Umschalter](https://mobbin.com/screens/2f2e5b74-cb4c-41bb-93ba-22e5962b6b78), [Lifesum Bottom-Sheet mit Claim](https://mobbin.com/screens/1aeee107-a9ef-4770-91a4-827bb3c62ffd).

Übernommene Muster: Home auf hellem `paper` mit großem Hero-CTA "Foto aufnehmen" (Kapsel, `thread`) und sekundär "Aus Galerie". Darüber ein kurzer Claim ("Was ist kaputt? Zeig's mir."). Darunter die Kategorie-Chips "Kleidung · Schuhe" als Erwartungssetzung und der Verlauf der letzten Analysen als horizontale Fotokarten (Could). Nach der Auswahl folgt ein Review-Sheet mit Foto, dem Feld "Was ist kaputt? (optional)" und einem Mikrofon-Button rechts im Feld (wie in den Chat-Eingaben bei Mindvalley/Perplexity). Primär: "Analysieren". Die Kamera nutzt das System-UI (UIImagePickerController). Ein Hinweis-Overlay im Review-Sheet: "Tipp: Schaden mittig, gutes Licht".

### 2. Analyse (Laden mit echten Zwischenschritten)
Referenzen: [Calm Sleep Checkliste](https://mobbin.com/screens/52e0bf63-158b-49be-a8d6-fd6bab9c17af), [Hers Schritt-Pills](https://mobbin.com/screens/44f7a26e-46b8-4512-a432-598171fb7885), [yope Häkchen + Spinner](https://mobbin.com/screens/339bdee5-6672-44ca-82b3-75c0f64fd5ca).

Übernommene Muster: Oben das eigene Foto (abgedunkelt, mit langsamem Scan-Schimmer). Darunter eine Liste mit vier Stufen aus den SSE-Events: "Objekt und Sicherheit prüfen" → "Schaden markieren (SAM 3.1)" → "Diagnose stellen (Muse Spark)" → "Reparatur planen". Erledigte Stufen bekommen ein animiertes Häkchen, die aktive einen Spinner, kommende sind ausgegraut. Sobald das Segment-Event kommt, blenden die Masken schon auf dem Foto ein. Die Wartezeit wird so zum Beweis, dass echte Arbeit passiert (Technische Tiefe). Die Modellnamen stehen klein als Untertitel und zeigen den Juroren die Meta-Tools.

### 3. Diagnose mit Overlays
Referenzen: [Lovi Skin-Analysis mit Filter-Chips über dem Foto](https://mobbin.com/screens/e6316517-0b99-428f-a07c-93cf5e8be244), [pliability Werte auf dem Körper](https://mobbin.com/screens/7fcf70e5-690c-4979-8c97-d0e69aa569d8), [Redfin Risiko-Liste](https://mobbin.com/screens/5a1cbf33-2ba5-46d6-af23-c87d154483da).

Übernommene Muster: Das Foto füllt die obere Hälfte, die Segmente liegen als Masken darauf. Darunter eine horizontale Chip-Leiste ("Alle", "Riss", "Naht", "Stoff"), mit der man jedes Segment ein- und ausblendet (FR-06). Darunter ein Sheet mit der Diagnose-Zusammenfassung, wahrscheinlichen Ursachen als Liste und einem Konfidenz-Meter (Ring oder Balken, Farbe nach Stufe: ≥ 0,75 safe, 0,6–0,75 caution, < 0,6 stop) samt Klartext ("ziemlich sicher"). Tippt man eine Ursache an, pulsiert ihr Segment (evidence_segment_ids).

### 4. Rückfrage
Referenzen: [Cleo AI Antwort-Chips](https://mobbin.com/screens/81550181-2282-4421-97d6-0d93e2d86349), [Perplexity Follow-ups](https://mobbin.com/screens/fe1aa2bb-e46b-45b2-ac6f-e2cb4916cbf1), [Mindvalley Eingabe mit Mikro](https://mobbin.com/screens/9d0010dc-0b64-4abb-b525-e99901fbdb26).

Übernommene Muster: Ein Assistenten-Blatt im Chat-Stil, das über der Diagnose aufgeht: eine Sprechblase der App ("Damit ich Nadel und Faden richtig wähle: Zeig mir das Etikett innen am Kragen."). Darunter die Antwortoptionen passend zum Fragetyp: großer Button "Etikett fotografieren" (photo), Antwort-Chips (choice), Textfeld mit Mikro (voice_or_text). Daneben "Überspringen" (dann entscheidet das Modell mit den vorhandenen Angaben). Höchstens 3 Fragen, angezeigt als "1 von 2". Nach der Antwort zurück zu Screen 2, dabei leuchtet die neue Information auf: "Etikett erkannt: 98 % Baumwolle, 2 % Elasthan".

### 5. Entscheidung
Referenzen: [Kit Vergleich zweier Optionen](https://mobbin.com/screens/c5bbe885-3e44-43c5-ab99-a4ef6c9407f9), [Expedia Vergleichsspalten](https://mobbin.com/screens/2feecb06-ae6a-4429-b43a-11ed7e7b6ecc), [Uxcel Kennzahl-Zeilen](https://mobbin.com/screens/b133afa4-f09c-4997-8dee-4cb2114f9b58).

Übernommene Muster: Eine große Empfehlungskarte ("Selbst reparieren", Icon `scissors`, Farbe `safe`) mit einer Begründung in 1–2 Sätzen. Darunter drei Kennzahl-Kacheln in einer Reihe: Aufwand (1–3 Punkte), Zeit ("20–40 Min."), Kosten ("3–8 €"). Direkt darunter das Estimate-Label "Schätzung, keine Garantie" als eigene Pille (FR-14). Unten ein kompakter Vergleich der drei Optionen (Selbst / Profi / Ersetzen). Die gewählte ist hervorgehoben, die anderen sind gedimmt, je mit einer Zeile Begründung. CTA: "Einkaufsliste ansehen".

### 6. Einkaufsliste
Referenzen: [Kitchen Stories Einkaufsliste](https://mobbin.com/screens/7f3f5aa5-c32f-424f-a9bc-972f2520205b), [Centr gruppierte Liste](https://mobbin.com/screens/6351ae26-084e-441c-8391-109fa8be5175), [Recime Sticky-CTA mit Zähler](https://mobbin.com/screens/c0365bb5-38c0-43f6-a5ff-3c1cbe61b229), [Crouton Abhak-Zustand](https://mobbin.com/screens/f19b0219-6d7d-400c-8dac-1de17f3811bc).

Übernommene Muster: Zwei Gruppen, "Material" und "Werkzeug". Jede Zeile zeigt Name, Menge, das Badge "Pflicht" oder "optional" und darunter die Haushaltsalternative ("oder: Sicherheitsnadel"). Rechts ein Segmented-Toggle "Habe ich" (safe) / "Kaufen" (thread). Ein Druck auf die Zeile klappt den Suchbegriff mit einem Kopieren-Button auf. Oben eine Zusammenfassung ("2 Dinge kaufen · ca. 4 €"), in der Toolbar ein Teilen-Button (ShareLink mit Text). Der Sticky-CTA unten heißt "Reparatur starten" und ist deaktiviert, bis alle Pflichteinträge den Status "Habe ich" haben. Dabei steht der Hinweis "Noch 2 Pflichtteile offen". Der Stand bleibt lokal gespeichert.

### 7. Geführte Reparatur
Referenzen: [Kitchen Stories Kochmodus (Foto oben, großer Text, Segment-Fortschritt)](https://mobbin.com/screens/c0dbae93-8b94-436d-b8fe-789c02841d43), [Recime "Step 1 of 4" + Next](https://mobbin.com/screens/4439d48a-0f3c-443c-8249-fd951894e316), [HelloFresh Step-Dots + Werkzeug-Leiste](https://mobbin.com/screens/a8ce2bb8-cecc-423b-aaaf-53e3e00e333a), [OKX/Uniswap Bestätigungs-Checkbox vor Weiter](https://mobbin.com/screens/4ed71f4a-555f-47b9-81ca-cb78505e11e6).

Übernommene Muster: Oben ein segmentierter Fortschrittsbalken (ein Segment pro Schritt, `thread`) und daneben "Schritt 3 von 7", rechts "Schließen" (Stand bleibt gespeichert). Das Foto mit Overlay füllt etwa 45 % des Screens. Bei Textil läuft dort der **animierte Stichpfad**: eine Linie zeichnet sich entlang der Schadstelle, nummerierte Ein- und Ausstichpunkte erscheinen abwechselnd links und rechts, eine Nadel-Markierung wandert mit, Wiederholung als Loop. Sonst ist das Segment hervorgehoben. Darunter die Leiste "Du brauchst" mit Mini-Chips der benutzten Items (uses_items), dann der Titel (`.title2.bold`), der Text und eine Karte "Typischer Fehler" (Icon `exclamationmark.bubble`, caution-soft). Sicherheitsrelevante Schritte zeigen ein caution-Banner mit Checkbox "Verstanden, ich passe auf". Bis sie gesetzt ist, bleibt "Erledigt" deaktiviert (FR-21). Unten links Zurück, mittig groß "Erledigt", rechts "Hilft nicht" (öffnet ein Sheet für Schritthilfe mit Text, Mikro und Foto). Wischen zwischen erledigten Schritten ist erlaubt.

### 8a. Sperre / Warnung
Referenzen: [OKX Risikowarnung](https://mobbin.com/screens/d4d6ac31-b40e-479d-b27e-f78f9dc99ffd), [Revolut "Keep … safe"](https://mobbin.com/screens/3becd9c6-c512-4fc6-96da-f54e6c99ebac), [Uniswap Warn-Sheet](https://mobbin.com/screens/4ed71f4a-555f-47b9-81ca-cb78505e11e6).

Übernommene Muster: Ein Vollbild-Screen, ruhig und nicht alarmistisch. Oben das eigene Foto klein mit `stop`- oder `caution`-Rand, darunter ein großes Symbol (`bolt.trianglebadge.exclamationmark` bei Akku, `shield.lefthalf.filled` bei professional). Dann der Titel ("Hier reparieren wir lieber nicht selbst"), die Begründung aus `safety.reason` und eine Info-Box "Was du stattdessen tun kannst" (Fachbetrieb, Hersteller, Reparaturcafé). Primär-CTA "Neues Foto", sekundär "Verstanden". Keine Schritte, keine Einkaufsliste.

### 8b. Abschluss
Referenzen: [Uxcel Lesson complete mit Kennzahlen](https://mobbin.com/screens/b133afa4-f09c-4997-8dee-4cb2114f9b58), [Apple News Done/Share](https://mobbin.com/screens/9d6d2b9e-e1dc-4cd6-8b0e-8c15b51e7727), [Brick Zusammenfassung](https://mobbin.com/screens/eb2562e9-5f2c-4e6a-87da-8ca18fdc29eb).

Übernommene Muster: Ein großes Häkchen mit dezenter Faden-Animation (eine Linie schließt sich zum Kreis), darunter "Repariert!". Daneben eine Vorher-Nachher-Karte, wenn ein Ergebnisfoto da ist (Button "Ergebnisfoto aufnehmen"). Die Kennzahlen: benötigte Zeit, ausgegeben ca. €, und "1 Kleidungsstück gerettet". Primär "Fertig", sekundär Teilen.

### Fehlerzustände (FR-12)
Ein Inline-Fehlerkarte im jeweiligen Screen statt eines Alerts: Icon, Klartext ("Der Server antwortet nicht. Läuft der Proxy?"), "Erneut versuchen". Leeres SAM-Ergebnis: "Ich finde die Stelle nicht sicher. Tipp sie an." (Fallback: Antippen).

## Signature-Momente für das Demo-Video
1. Die Masken blenden während des Ladens schon auf dem Foto ein.
2. Die Etikett-Rückfrage, danach aktualisiert sich die Diagnose sichtbar ("Elasthan erkannt → dehnbarer Stich").
3. Der Stichpfad zeichnet sich Stich für Stich über den echten Riss.
4. Die Sperre bei der beheizbaren Jacke mit Akku.
