# PRD: Reparatur-Assistent (Meta AI Hackathon, Swift-Prototyp)

Oct 26, 2026 · @Felix

## 1. Überblick und Ziel

Der Reparatur-Assistent erkennt auf einem Foto, was an einem kaputten Kleidungsstück oder Schuh defekt ist, empfiehlt ehrlich zwischen Selbstreparatur, Profi und Ersatz und führt Schritt für Schritt durch die Reparatur.

Ziel ist die Abgabe beim Meta Global AI Developer Hackathon im Indie-Track, Theme "Build for Your World". Abgabeschluss ist der 4. November 2026, 21:00 Uhr ET, das entspricht dem 5. November, 3:00 Uhr MEZ. Der Swift-Prototyp (iOS) entsteht in der Bauphase vom 27. Oktober bis 4. November.

Die Bewertungsgewichte stammen aus einer Drittquelle, die den Waiver zusammenfasst. Die Official Rules gehen vor.

| Kriterium | Gewicht | Unser Beitrag |
| --- | --- | --- |
| Impact | 30 % | belegte Zahlen zu Reparatur und Abfall, klarer Alltagsnutzen |
| Nutzung der Meta-Tools | 25 % | SAM 3.1 und Muse Spark mit je eigener, unverzichtbarer Rolle |
| Demo | 25 % | Textil-Demo mit Stichpfad, Schuh-Demo, Demo-Video |
| Technische Tiefe | 20 % | strukturierte Ausgaben, Sicherheitslogik, eigener Benchmark |

Erfolgsdefinition: Der Heldenfall Textil liefert in unter 30 Sekunden vom Foto eine Einkaufsliste und führt danach Schritt für Schritt durch die Reparatur, und jede Aussage zur Genauigkeit stützt sich auf den eigenen Benchmark.

PRD 2 (ASL-Gesprächshilfe) ruht bis nach der Abgabe. Beide Projekte liegen im selben Repo in eigenen Unterordnern: repair-assistant/ und gebaerden-app/.

## 2. Nutzer und Problem

Zielnutzer sind Privatpersonen, die Kleidung und Schuhe lieber reparieren würden, aber nicht wissen, ob es sich lohnt, wie es geht und was sie dafür brauchen.

Kernversprechen: Foto aufnehmen, die Schadstelle auf dem eigenen Foto markiert sehen, eine ehrliche Empfehlung bekommen und eine Anleitung, die sich auf genau dieses Objekt bezieht.

Demo 1 ist ein Textil-Fall (Riss, offene Naht oder Loch): Die App zeigt auf dem Foto, wo die Nadel entlanggeführt wird. Demo 2 sind Lieblingsschuhe mit Schaden an Sohle, Naht oder Absatz. Elektronik (Niedervolt, ohne Akku) bleibt Backup, falls Zeit übrig ist.

Differenzierung gegenüber allgemeinen Reparaturanleitungen im Netz: Die Anleitung liegt auf dem eigenen Foto, und die App rät auch dann vom Selbstreparieren ab, wenn es unsicher ist. Ob es dafür schon vergleichbare Apps gibt, ist nicht geprüft und bleibt eine Annahme.

Die Impact-Zahlen (Textilabfall, Schuhmüll, EU-Recht auf Reparatur) werden vor der Abgabe recherchiert und mit Quelle eingetragen. Bis dahin steht hier keine Zahl.

## 3. Scope

Der iOS-Prototyp deckt zuerst Textil (Demo 1) und dann Schuhe (Demo 2) Ende zu Ende ab. Unterstützt werden nur diese beiden Kategorien, Elektronik ist nur Backup. Alles andere kommt später oder gar nicht.

**Prototyp (Must)**

- Foto aufnehmen oder aus der Galerie wählen, optional mit Kurzbeschreibung
- Segmentierung der Schadstelle und der Bauteile mit SAM 3.1, als Overlay auf dem Foto. Bei Textil zusätzlich ein berechneter, animierter Stichpfad entlang der Schadstelle
- Diagnose und Entscheidung mit Muse Spark als strukturiertes JSON, mit gezielten Rückfragen (zum Beispiel Foto vom Etikett)
- Sicherheitsprüfung vor jeder Anleitung
- Einkaufsliste mit Material und Werkzeug zum Abhaken, danach geführte Reparatur mit einem Schritt pro Screen

**Bis zur Abgabe (Should)**

- Elektronik als Backup-Fall, nur mit Verdachtsdiagnose und Wackeltest-Anleitung
- Anleitungsschritte mit Bezug auf die markierten Bereiche
- Spracheingabe per Muse Voice Transcribe für Beschreibung und Antworten auf Rückfragen
- Lokaler Verlauf der letzten Analysen
- Mini-Benchmark mit eigenen Fällen

**Nicht im Scope (Non-Goals)**

- Accounts, Cloud-Speicherung, Bezahlfunktion, Shop-Anbindung
- Android und native Offline-Modelle
- Alle Kategorien außer Textil und Schuhen (kein Fahrrad, keine Möbel), Elektronik nur als Backup, nie mit Akku oder Netzanschluss und ohne Platinenanalyse auf Bauteilebene
- Muse Image, solange Zeit fehlt (Spracheingabe ist Should nach FR-27 und entfällt als Erstes)

## 4. User Flow

Der Flow hat acht Schritte mit zwei Abzweigungen: Die Sicherheitsprüfung kann die Anleitung sperren, und niedrige Konfidenz oder fehlende Angaben lösen eine Rückfrage aus.

1. **Start:** Button für Kamera oder Galerie, optionales Textfeld "Was ist kaputt?" mit Mikrofon-Button für Spracheingabe.
2. **Objekt- und Risikoprüfung:** Die App bestimmt die Kategorie (Textil oder Schuh, als Backup Niedervolt-Elektronik) und die Risikostufe. Alle anderen Objekte lehnt sie freundlich ab. Bei "nur Warnung" oder "Profi" geht es direkt zu Schritt 8a.
3. **Analyse:** Ladeansicht mit den echten Zwischenschritten (Segmentierung, Diagnose, Entscheidung).
4. **Diagnose:** Das Foto zeigt die SAM-Overlays, darunter Diagnosetext und Konfidenz. Fehlen Angaben oder liegt die Konfidenz unter dem Schwellwert, stellt die App gezielte Rückfragen, zum Beispiel nach einem Foto vom Etikett oder einer besseren Aufnahme (Makro, anderer Winkel). Du antwortest per Foto, Sprache oder Text, danach startet die Analyse bei Schritt 3 neu.
5. **Entscheidung:** Empfehlung Selbst reparieren, Profi oder Ersetzen mit Begründung, Aufwand, Zeitspanne und grober Kostenspanne.
6. **Einkaufsliste:** Die App erzeugt aus der Diagnose eine Liste mit Material und Werkzeug. Jeder Eintrag zeigt Menge, Pflicht oder optional, einen Suchbegriff für den Laden und, wenn möglich, eine Haushaltsalternative. Pro Eintrag hakst du "habe ich" oder "muss ich kaufen" ab. Die App fasst die offenen Käufe zusammen, die Liste lässt sich als Text teilen, und der Stand bleibt gespeichert. "Reparatur starten" wird aktiv, sobald alle Pflichteinträge vorhanden sind.
7. **Geführte Reparatur:** Ein Schritt pro Screen mit Titel, kurzem Text, typischem Fehler und Fortschrittsanzeige. Bei Textil läuft ein animierter Stichpfad entlang der Schadstelle und zeigt, wo die Nadel ein- und ausgeht. Sonst markiert das Foto den betroffenen Bereich. Du bestätigst jeden Schritt mit "Erledigt", kannst zurückgehen und bei Problemen "Hilft nicht" tippen oder ein neues Foto schicken. Sicherheitsrelevante Schritte (scharfe Werkzeuge, Hitze, Klebstoffdämpfe, beim Backup Elektronik: Gerät stromlos machen) müssen bestätigt sein, bevor "Weiter" aktiv wird.
8. **Abschluss:** a) Warnscreen mit Begründung und Hinweis auf Fachbetrieb, ohne Anleitung. b) Reparatur abgeschlossen mit optionalem Ergebnisfoto, Zusammenfassung speichern (Should).

## 5. Funktionale Anforderungen

Die App braucht 27 Anforderungen, davon 19 Must für den Prototyp.

| ID | Anforderung | Prio |
| --- | --- | --- |
| FR-01 | Foto per Kamera oder Galerie wählen, Bild vor dem Upload auf maximal 1536 px Kantenlänge verkleinern | Must |
| FR-02 | Optionaler Freitext zum Schaden | Must |
| FR-03 | Kategorie und Risikostufe (erlaubt, nur Warnung, Profi) bestimmen, bevor eine Anleitung entsteht. Unterstützt werden Textil und Schuhe, als Backup Niedervolt-Elektronik. Alle anderen Objekte lehnt die App ab | Must |
| FR-04 | Bei Risikostufe "nur Warnung" oder "Profi" keine Anleitung ausgeben, sondern Warnscreen mit Begründung | Must |
| FR-05 | Bauteile und Schadstelle per SAM 3.1 über Textprompts segmentieren | Must |
| FR-06 | Segmente als farbige Overlays auf dem Foto zeichnen, einzeln ein- und ausblendbar | Must |
| FR-07 | Diagnose mit Ursachen, Konfidenz und Verweis auf Segmente ausgeben | Must |
| FR-08 | Entscheidung Selbst reparieren, Profi oder Ersetzen mit Begründung, Aufwand, Zeit und Kostenspanne | Must |
| FR-09 | Einkaufsliste aus der Diagnose erzeugen: Material und Werkzeug mit Menge, Pflicht oder optional, Suchbegriff und, wenn möglich, Haushaltsalternative | Must |
| FR-10 | Bei Konfidenz unter 0,6 eine bessere Aufnahme anfordern statt zu raten | Should |
| FR-11 | Schritte verweisen auf Segment-IDs und heben den Bereich auf dem Foto hervor | Should |
| FR-12 | Fehlerzustände sichtbar machen: API-Fehler, Timeout, leeres Ergebnis, Retry-Button | Should |
| FR-13 | Lokaler Verlauf der letzten 20 Analysen auf dem Gerät | Could |
| FR-14 | Hinweis "Schätzung, keine Garantie" bei Kosten und Zeit | Must |
| FR-15 | Elektronik (Backup-Fall): bei losen Kontakten "Verdacht, nicht bestätigt" ausgeben und erst nach Wackel- oder Durchgangstest zur Reparatur führen | Could |
| FR-16 | Anfragen laufen über den Proxy, der ein Tageslimit für API-Kosten durchsetzt | Must |
| FR-17 | Einkaufsliste abhaken: je Eintrag "habe ich" oder "muss ich kaufen", offene Käufe zusammenfassen, Liste als Text teilen, Stand lokal speichern. "Reparatur starten" ist aktiv, sobald alle Pflichteinträge vorhanden sind | Must |
| FR-18 | Geführte Reparatur: ein Schritt pro Screen, Fortschrittsanzeige, Zurück und Weiter, Abbruch jederzeit mit gespeichertem Stand | Must |
| FR-19 | Jeder Schritt zeigt Titel, kurzen Text, typischen Fehler und den Button "Erledigt" | Must |
| FR-20 | Bei "Hilft nicht" oder neuem Foto antwortet die App nur zu diesem einen Schritt und ändert den Rest der Anleitung nicht | Should |
| FR-21 | Sicherheitsrelevante Schritte (scharfe Werkzeuge, Hitze, Klebstoffdämpfe, beim Backup Elektronik: Gerät stromlos machen und Testschritte) müssen bestätigt sein, bevor "Weiter" aktiv wird | Must |
| FR-22 | Abschlussscreen mit optionalem Ergebnisfoto | Could |
| FR-23 | Stichpfad (Textil): aus der Maske der Schadstelle Kontur und Mittellinie berechnen, Stichpunkte in gleichmäßigem Abstand setzen und als animiertes Overlay zeichnen. Der Abstand richtet sich nach der Länge der Schadstelle, nicht nach Millimetern. Bei einem Loch legt die App statt der Mittellinie ein Stopfgitter über die Kontur | Must |
| FR-24 | Muse Spark wählt die Stichart (zum Beispiel Leiterstich, Vorstich, Stopfen) und erklärt jeden Stichschritt, ohne Koordinaten zu liefern | Must |
| FR-25 | Rückfragen: Fehlen Angaben, die Material oder Vorgehen bestimmen, stellt die App höchstens 3 gezielte Rückfragen, zum Beispiel nach einem Foto vom Etikett. Antwort per Foto, Sprache oder Text, danach läuft die Analyse mit allen Angaben neu | Must |
| FR-26 | Etikett lesen: Muse Spark entnimmt dem Etikettfoto Materialzusammensetzung und Pflegehinweise und nutzt sie für Stichart, Nadel, Faden und Warnhinweise | Must |
| FR-27 | Spracheingabe: Mikrofon-Button für Beschreibung und Antworten auf Rückfragen. Muse Voice Transcribe wandelt Audio in Text, den der Nutzer vor dem Senden sieht und korrigieren kann | Should |

## 6. Meta-Modell-Pipeline

Jedes Modell bekommt einen Job, den ein anderes nicht übernehmen kann. Mehr Modelle zählen nur, wenn sie eine echte Rolle haben.

| Rolle | Modell | Eingabe | Ausgabe | Fallback | Prio |
| --- | --- | --- | --- | --- | --- |
| Kategorie und Risikostufe | Muse Spark | Foto, Freitext | JSON mit category, risk\_level, reason | Bei Unsicherheit risk\_level = warn\_only | Must |
| Schadstelle und Bauteile markieren | SAM 3.1 | Foto, Textprompts je Kategorie (Textil: tear, open seam, hole; Schuh: shoe sole, seam, detached sole; immer kurze englische Begriffe) | Masken oder Boxen mit Score je Prompt | Boxen statt Masken, sonst Antippen durch Nutzer | Must |
| Diagnose und Entscheidung | Muse Spark | Foto, Segment-Metadaten, Freitext | JSON mit diagnosis und decision | Konfidenz unter 0,6 führt zur Rückfrage | Must |
| Einkaufsliste und Anleitung | Muse Spark | Diagnose-JSON, Segment-IDs | Einkaufsliste und Schrittliste mit Segmentbezug | Reine Textanleitung ohne Overlay | Must |
| Anleitungsskizzen | Muse Image | Zielzustand als Prompt | Skizze je Schritt | Weglassen | Could |
| Spracheingabe | Muse Voice Transcribe | Audio | Text für Freitextfeld und Antworten auf Rückfragen | Tastatur | Should |

**Stichpfad (Textil):** Ihn berechnet App-Code, kein Modell. SAM 3.1 liefert die Maske der Schadstelle, die App leitet daraus Kontur und Mittellinie ab und setzt die Stichpunkte. Muse Spark wählt nur die Stichart und beschreibt die Schritte. Ob SAM 3.1 Risse und offene Nähte per Textprompt sauber findet, entscheidet der Fototest.

**Rückfragen und Etikett:** Fehlen Angaben, die Material oder Vorgehen bestimmen, gibt Muse Spark gezielte Rückfragen zurück, höchstens drei. Bei Textil ist das Foto vom Etikett die wichtigste, weil Stoffzusammensetzung und Pflegehinweise Nadel, Faden und Stich bestimmen. Muse Spark liest das Etikett direkt aus dem Foto. Ob die Texterkennung auf kleinen oder verwaschenen Etiketten zuverlässig genug ist, zeigt der Fototest.

Bestätigt: Muse Spark nimmt laut [Meta-Dokumentation](https://ai.developer.meta.com/docs/models/) Bild und Video entgegen und gibt Text zurück. Die Modell-IDs sind muse-spark-1.1 und muse-spark-1.2 im Standard-Tier, die Contributor-Variante wird nicht genutzt. Offen bleibt, in welchem Format SAM 3.1 Masken liefert (siehe Annahmen in Abschnitt 14).

Laut ReconScribe-Guide ist die Model API unter https://api.meta.ai/v1 mit dem OpenAI- und Anthropic-SDK kompatibel. Standard-Preise: Muse Spark 1,25 $ je 1 Mio. Input-Token und 4,25 $ je 1 Mio. Output-Token, SAM 3.1 2,50 $ je 1.000 Bilder. Jeder Teilnehmer erhält 150 $ Credits. Der Proxy führt ein Tageslimit.

## 7. Sicherheitsregeln

Die App gibt nur dort Anleitungen, wo ein Fehler harmlos bleibt. Im Zweifel wählt sie die vorsichtigere Stufe. Die Stufen sind ein Produktvorschlag und lassen sich anpassen.

| Stufe | Beispiele | Verhalten |
| --- | --- | --- |
| allowed | Textilien (Riss, offene Naht, Loch, Saum, Knopf) und Schuhe (Sohle, Naht, Absatz). Backup: Niedervolt-Geräte ohne Akku und ohne Netzanschluss (Kabelbruch, USB-Buchse) | Anleitung. Bei Elektronik zuerst Hinweis, dass das Gerät komplett stromlos sein muss |
| warn\_only | Lithium-Akkus (auch in beheizbarer Kleidung oder LED-Schuhen), Netzteile, netzbetriebene Geräte, Kondensatoren in Blitz- und Röhrengeräten, Gasgeräte | Warnscreen mit Begründung, keine Schritte |
| professional | Helme, Kindersitze, Bremsen, alles, was bei Versagen Personen gefährdet | Empfehlung für Fachbetrieb, keine Schritte |

Regeln für die Umsetzung:

- Das Risiko wird vor der Diagnose bestimmt. Eine Anleitung entsteht nie ohne Risikostufe allowed.
- Bei unklarem Objekt gilt warn\_only. Bei category unsupported entsteht nie eine Anleitung, egal welche Risikostufe gesetzt ist.
- Nur Backup Elektronik: Lose Kontakte auf Platinen sind oft nicht sichtbar. Die App meldet "Verdacht, nicht bestätigt" und verlangt zuerst einen Wackel- oder Durchgangstest.
- Kosten und Zeit sind Schätzungen und werden so beschriftet.
- Warnungen und Sperren werden im Benchmark gesondert getestet (Abschnitt 11).

## 8. Datenmodelle und JSON-Verträge

App und Proxy sprechen über die Endpunkte POST /analyze, POST /step-help und POST /transcribe und tauschen Codable-taugliches JSON aus. Das Maskenformat hängt vom SAM-3.1-Ergebnis ab und wird nach dem ersten Test festgelegt.

POST /analyze meldet den Fortschritt per Server-Sent Events (classify, segment, diagnose, plan), damit die Ladeansicht aus Schritt 3 echte Zwischenschritte zeigt. Das letzte Ereignis trägt die Response unten.

```json
// Request
{
  "image_base64": "...",
  "user_note": "Sohle löst sich vorne",
  "extra_images": [{ "purpose": "label | closeup | other", "image_base64": "..." }],
  "answers": [{ "question_id": "q1", "text": "..." }],
  "locale": "de"
}
```

```json
// Response von /analyze
{
  "case_id": "uuid",
  "category": "textile | shoe | low_voltage_electronics | unsupported",
  "risk_level": "allowed | warn_only | professional",
  "safety": { "blocked": false, "reason": null },
  "segments": [
    {
      "id": "seg_1",
      "label": "Sohle",
      "kind": "part | damage",
      "prompt": "shoe sole",
      "box": [x, y, w, h],
      "mask": "<format nach SAM-Test>",
      "score": 0.0
    }
  ],
  "diagnosis": {
    "summary": "...",
    "likely_causes": ["..."],
    "confidence": 0.0,
    "evidence_segment_ids": ["seg_1"],
    "needs_more_info": false,
    "follow_up_questions": [
      { "id": "q1", "type": "photo | voice_or_text | choice", "prompt": "Mach ein Foto vom Etikett mit der Materialangabe", "purpose": "label | closeup | other" }
    ],
    "label_info": { "materials": ["..."], "care": ["..."] }
  },
  "decision": {
    "recommendation": "repair_self | repair_pro | replace",
    "reasoning": "...",
    "effort": "low | medium | high",
    "time_minutes": [30, 60],
    "cost_eur": [5, 15],
    "estimate_note": "Schätzung, keine Garantie"
  },
  "shopping_list": [
    {
      "id": "item_1",
      "name": "Kontaktkleber für Schuhe",
      "kind": "material | tool",
      "quantity": "1 Tube",
      "required": true,
      "search_term": "Schuhkleber Kontaktkleber",
      "household_alternative": null
    }
  ],
  "guide": {
    "steps": [
      {
        "n": 1,
        "title": "...",
        "text": "...",
        "common_mistake": "...",
        "safety_critical": false,
        "requires_confirmation": false,
        "segment_ids": ["seg_1"],
        "uses_items": ["item_1"],
        "overlay": { "type": "stitch_path | highlight", "stitch_type": "ladder_stitch | running_stitch | darning | whip_stitch", "segment_id": "seg_2" }
      }
    ]
  }
}
```

Der Proxy speichert nichts, auch keine Audioaufnahmen. POST /transcribe nimmt eine Audiodatei und liefert Text (Muse Voice Transcribe, Format nach Docs). Die App hält Einkaufsliste, Schrittstand und Abhak-Zustand lokal und schickt bei Schritthilfe den nötigen Kontext mit.

```json
// Request an /step-help
{
  "step": { "n": 3, "title": "...", "text": "..." },
  "diagnosis_summary": "...",
  "risk_level": "allowed",
  "issue_text": "Der Kleber haftet nicht",
  "image_base64": "... (optional)"
}
```

```json
// Response von /step-help
{
  "answer": "...",
  "retry_hint": null,
  "escalate": false
}
```

Regeln: Ist risk\_level nicht allowed, bleiben shopping\_list und guide leer. Das gilt auch bei category unsupported und bei needs\_more\_info true. Pro Analyse gibt es höchstens eine Rückfrage-Runde, danach entscheidet das Modell mit den vorhandenen Angaben oder empfiehlt repair\_pro. Das Feld confidence liegt zwischen 0 und 1. Die App wertet nur Felder aus diesem Vertrag aus und zeigt nie rohen Modelltext.

## 9. Technische Architektur

Die iOS-App spricht nur mit einem schlanken Proxy auf dem eigenen Rechner. Der Proxy hält den API-Key und ruft die Meta Model API auf. So landet kein Key in der App oder im öffentlichen Repo. Das Teilnehmerdokument verlangt kein Hosting. Es nennt neben Video und Code auch ein "Live-Produkt", und ob Juroren es selbst aufrufen, ist offen und gehört als Frage in den Discord.

**iOS-App**

- SwiftUI, Ziel iOS 17 oder neuer, MVVM mit async/await
- Bildauswahl über PhotosPicker, Kamera über UIImagePickerController, Audioaufnahme über AVAudioRecorder (Mikrofonberechtigung nötig)
- APIClient mit URLSession, Codable-Modelle nach Abschnitt 8
- OverlayRenderer zeichnet Masken oder Boxen mit Canvas über das Foto, StitchPathPlanner berechnet aus der Maske Mittellinie und Stichpunkte
- Basis-URL des Proxys kommt aus einer lokalen Konfigurationsdatei, die nicht eingecheckt wird. Info.plist braucht NSAllowsLocalNetworking (HTTP zum Proxy im WLAN), NSLocalNetworkUsageDescription, NSCameraUsageDescription und NSMicrophoneUsageDescription

**Proxy**

- Python mit FastAPI, Endpunkte POST /analyze, POST /step-help, POST /transcribe und GET /health
- Meta Model API über den OpenAI-kompatiblen Client mit Basis-URL https://api.meta.ai/v1, Modell muse-spark-1.2 im Standard-Tier
- Key aus der Umgebungsvariable, Tageslimit für Kosten, kein Speichern von Bildern oder Audio, kein Logging von Bildinhalten
- Läuft lokal auf dem Mac, das iPhone erreicht ihn im selben WLAN

**Projektstruktur**

```text
repair-assistant/
  proxy/        FastAPI-App, .env.example, tests/
  ios/          Xcode-Projekt RepairAssistant
    Models/     Codable-Typen
    Services/   APIClient
    Views/      Start, Analyse, Diagnose, Entscheidung, Anleitung
    Rendering/  OverlayRenderer
  docs/         api-notes.md, benchmark.md
  README.md
```

Falls die Zeit knapp wird, darf die App die Meta API direkt aufrufen, solange der Key nur lokal liegt, die App nicht verteilt wird und der Key nie in Git landet.

## 10. Prompt-Entwürfe

Drei Prompts tragen die Pipeline: Der erste bestimmt Kategorie und Risiko vor jeder Anleitung, der zweite liefert Diagnose, Entscheidung, Einkaufsliste und Anleitung, der dritte beantwortet Rückfragen zu einem einzelnen Schritt. Alle erzwingen JSON ohne Fließtext drumherum.

```text
# Prompt A: Kategorie und Risiko (System)
Du bist ein vorsichtiger Reparatur-Assistent. Antworte ausschließlich mit JSON nach dem Schema.
Aufgabe: Bestimme anhand des Fotos und des Nutzertexts die Kategorie und die Risikostufe.
Risikostufen:
- allowed: Textilien und Schuhe. Backup: Niedervolt-Geräte ohne Akku und ohne Netzanschluss.
- warn_only: Lithium-Akkus (auch in beheizbarer Kleidung oder LED-Schuhen), Netzteile, netzbetriebene Geräte, Kondensatoren in Blitz- und Röhrengeräten, Gasgeräte.
- professional: Helme, Kindersitze, Bremsen und alles, was bei Versagen Personen gefährdet.
Alle Objekte, die weder Textil noch Schuh noch Niedervolt-Elektronik sind, bekommen category unsupported. Wenn du unsicher bist, wähle warn_only. Gib immer eine kurze Begründung.
Schema: {"category": string, "risk_level": string, "reason": string}
```

```text
# Prompt B: Diagnose, Entscheidung, Einkaufsliste, Anleitung (System)
Du bist ein ehrlicher Reparatur-Assistent. Antworte ausschließlich mit JSON nach dem Schema aus dem Vertrag.
Du bekommst das Foto, den Nutzertext und eine Liste markierter Segmente mit IDs und Labels.
Regeln:
- Verweise bei Diagnose und Schritten nur auf vorhandene Segment-IDs.
- Setze confidence zwischen 0 und 1. Unter 0,6 oder bei fehlenden Angaben setze needs_more_info auf true und stelle in follow_up_questions gezielte Rückfragen (höchstens 3) statt zu raten. Lass shopping_list und guide dann leer.
- Frage bei Textil nach dem Etikett, wenn kein Etikettfoto vorliegt. Lies mit Etikettfoto Materialzusammensetzung und Pflegehinweise in label_info und nutze sie für Stichart, Nadel, Faden und Warnhinweise.
- Erfinde keine Teile, Maße oder Preise. Kosten und Zeit sind Schätzungen als Spanne.
- Empfiehl repair_pro oder replace, wenn die Reparatur unrealistisch oder riskant ist.
- Erstelle shopping_list mit allem, was die Schritte brauchen: Name, Menge, Pflicht oder optional, Suchbegriff für den Laden und, wenn sinnvoll, eine Haushaltsalternative. Führe nur Dinge auf, die in einem Schritt vorkommen.
- Jeder Schritt ist eine einzelne, prüfbare Handlung mit title, text, common_mistake und uses_items (IDs aus shopping_list).
- Setze safety_critical und requires_confirmation auf true bei Schritten zu Strom, Hitze, Klebstoffdämpfen, scharfen Werkzeugen und Funktionstests.
- Nur Backup, bei Elektronik: lose Kontakte sind nur ein Verdacht, solange kein Wackel- oder Durchgangstest vorliegt. Schreibe zuerst den Test als Schritt 1.
- Bei Textil: Gib je Schritt ein overlay-Objekt mit type und stitch_type an (zum Beispiel ladder_stitch, running_stitch, darning, whip_stitch), aber keine Koordinaten. Den Stichpfad berechnet die App aus der Maske.
- Schreibe alle Texte auf Deutsch, kurz und konkret.
```

```text
# Prompt C: Schritthilfe (System)
Du bekommst einen einzelnen Reparaturschritt, die Diagnose-Zusammenfassung, die Beschreibung des Problems und optional ein neues Foto.
Antworte ausschließlich mit JSON: {"answer": string, "retry_hint": string oder null, "escalate": boolean}.
Ändere die übrigen Schritte nicht und bleibe bei der Risikostufe des Falls.
Wenn das Problem sicherheitsrelevant wird (Rauch, starke Hitze, Akku wird warm), setze escalate auf true und rate zum Abbruch.
Schreibe auf Deutsch, kurz und konkret.
```

Alle Prompts werden in der Pipeline als Dateien im Repo geführt und beim Benchmark mit festen Ständen versioniert.

## 11. Benchmark und Akzeptanzkriterien

Der Benchmark umfasst mindestens 10 eigene Fälle und wird in der Abgabe offen mit Fehlerquote berichtet. Die Zielwerte sind ein Vorschlag.

Fallmix: 5 Textilien (Riss, offene Naht, Loch, Saum, Knopf), 4 Schuhe mit unterschiedlichen Schäden, 1 Elektronik-Backupfall. Dazu 4 Sicherheitsfälle mit Fotos von Gegenständen, die gesperrt werden müssen (zum Beispiel Netzteil, Akku, Helm, beheizbare Jacke mit Akku). Alle Fotos sind eigene oder frei lizenzierte Aufnahmen.

| Metrik | Messung | Zielwert |
| --- | --- | --- |
| Schadstelle markiert | manuell: Overlay liegt auf dem realen Schaden, ja oder nein | mindestens 7 von 10 |
| Diagnose plausibel | manuell, Skala 0 bis 2 | Mittelwert mindestens 1,3 |
| Entscheidung nachvollziehbar | manuell, ja oder nein | mindestens 8 von 10 |
| Sicherheitsfälle gesperrt | automatisch: risk\_level ist nicht allowed oder category ist unsupported | 4 von 4 |
| Latenz Foto bis Einkaufsliste | Stoppuhr im Demo-Fall, ohne die Zeit, die der Nutzer für eine Rückfrage braucht | unter 30 Sekunden |
| Ungültiges JSON | Anteil der Antworten, die den Vertrag verletzen | unter 5 % nach einem Retry |

**Abnahme des Prototyps:** Der Textil-Fall läuft vom Foto über die Einkaufsliste bis zum letzten Reparaturschritt ohne Absturz, zeigt mindestens ein SAM-Overlay auf der Schadstelle, liefert eine Entscheidung mit Begründung und sperrt einen Testfall mit Akku. Die Einkaufsliste enthält jedes Material und Werkzeug, das ein Schritt braucht. Der Stichpfad folgt sichtbar der Kontur der Schadstelle. Die App stellt im Textil-Fall eine sinnvolle Rückfrage (Etikett), und die Antwort verändert das Ergebnis.

## 12. Meilensteine

Der Plan rechnet mit etwa 52 bis 67 Stunden bis zur Abgabe, verteilt auf Abende und das Wochenende. Die Gesamtschätzung für die volle Version lag bei 55 bis 75 Stunden, deshalb gilt der Scope aus Abschnitt 3. Einkaufsliste, geführter Reparaturmodus und Stichpfad-Overlay sind Must und kosten etwa 10 bis 16 Stunden zusätzlich, Rückfragen mit Etikettfoto etwa 4 bis 6 und Spracheingabe etwa 3 bis 5 (alles Schätzungen). Wenn die Zeit nicht reicht, entfallen zuerst Spracheingabe, Elektronik und der lokale Verlauf.

1. **Mo, 26. Okt:** Teilnehmerdokument lesen, Credit-Formular ausfüllen und Kreditkarte hinterlegen, im Discord (#questions) fragen, ob Code vor dem 27. Okt. zählt. Docs und Cookbook lesen, SAM-3.1-Test mit 10 bis 15 eigenen Textil- und Schuhfotos. Noch kein Repo.
2. **Di, 27. Okt:** Öffentliches Repo anlegen, Proxy mit /health und /analyze, Pipeline Kategorie, Segmentierung, Diagnose. Ergebnisse in docs/api-notes.md festhalten.
3. **Mi, 28. Okt:** Entscheidung, Einkaufsliste und Rückfragen mit Etikettfoto. Swift-App mit Start, Analyse und Diagnose-Screen samt Overlay.
4. **Do und Fr, 29. und 30. Okt:** Geführte Reparatur und Stichpfad-Overlay für Textil (Demo 1), Sicherheitslogik, Rückfrage bei niedriger Konfidenz.
5. **Sa und So, 31. Okt und 1. Nov:** Schuh-Fall (Demo 2), Benchmark mit allen Fällen, Impact-Zahlen mit Quellen recherchieren, Oberfläche glätten. Spracheingabe und Elektronik nur bei freier Zeit.
6. **Mo, 2. Nov:** Feature-Stopp. Fehler beheben, README mit Kennzeichnung des in der Bauphase Neuen, Beschreibung schreiben.
7. **Di, 3. Nov:** Demo-Video (3 Minuten) aufnehmen und schneiden, Abgabetext fertigstellen. Letzter Tag für Fragen im Discord.
8. **Mi, 4. Nov:** Puffer. Abgabe bis spätestens 18:00 Uhr MEZ, das sind 12:00 Uhr ET. Die Credits müssen bis 21:00 Uhr ET beantragt sein.

Fällt SAM 3.1 am ersten Tag bei den Testfotos durch, wird der Schritt auf Boxen oder Antippen umgestellt, und der Plan bleibt bestehen.

## 13. Hackathon-Compliance

Das Teilnehmerdokument des Hackathons (Stand 26. Oktober) geht allem vor, was hier steht. Seine Tabellen zu Bewertung und Preisen liegen uns nicht vor, die gewichteten Kriterien aus Abschnitt 1 sind daher unbestätigt. Die folgende Liste stützt sich auf die [Eventseite](https://cerebralvalley.ai/e/meta-ai-developer-hackathon) und den [ReconScribe-Guide](https://reconscribe.com/meta-global-ai-developer-hackathon-2026/), der den Waiver zusammenfasst.

- [ ] Teilnehmerdokument und später veröffentlichte Official Rules gelesen
- [ ] Credit-Formular ausgefüllt, Kreditkarte hinterlegt, Spend-Limit gesetzt, vor dem 4. Nov., 21:00 Uhr ET
- [ ] Discord-Frage gestellt: Zählt Code vor dem 27. Okt. als erlaubte Vorarbeit? Ohne Antwort erst ab 27. Okt. entwickeln
- [ ] Indie-Track gewählt, ein Projekt, du als Einziger in der Abgabe eingetragen
- [ ] Repo öffentlich, ohne Keys und VW-Daten, .env in .gitignore
- [ ] Demo zeigt nur in der Bauphase Neues, und Video und README kennzeichnen das klar (sonst droht Disqualifikation)
- [ ] Kein Altcode aus eigenen Apps oder dem Negotiation-Trainer-MVP
- [ ] Nur eigene oder frei lizenzierte Fotos und Assets, Mobbin-Screens nur als Inspiration und nie 1:1 kopiert
- [ ] Meta Model API sinnvoll genutzt (Stage 1 ist Pass/Fail), pro Modell dokumentiert, welche Aufgabe es hat
- [ ] Nicht als "Simple Image Analyzer" wirken: Einkaufsliste, geführte Reparatur und Stichpfad im Video zeigen
- [ ] Keine medizinischen Ratschläge, nichts Politisches
- [ ] Nebentätigkeit und mögliche Interessenkonflikte mit dem Arbeitgeber geklärt (keine Rechtsberatung)
- [ ] Meta Model API im Standard-Modus, nicht im Contributor-Modus (laut ReconScribe-Guide)
- [ ] 3-Minuten-Demo-Video, Link öffentlich erreichbar
- [ ] Abgabe auf der Cerebral-Valley-Plattform vor dem 4. Nov., 18:00 Uhr MEZ

**Quellen:** [Eventseite Cerebral Valley](https://cerebralvalley.ai/e/meta-ai-developer-hackathon) · [ReconScribe-Guide](https://reconscribe.com/meta-global-ai-developer-hackathon-2026/), Teilnehmerdokument des Hackathons (vom Nutzer bereitgestellt), Stand 26. Oktober 2026.

## 14. Risiken, Annahmen und offene Fragen

Das größte Risiko ist die Qualität von SAM 3.1 auf Stoff und Schuhen (als Backup auf Platinen), denn sie ist ungetestet. Für Demo 1 muss SAM Risse und offene Nähte per Textprompt finden, sonst entfällt der Stichpfad. Der Fototest entscheidet darüber.

| Risiko oder Annahme | Folge | Gegenmaßnahme |
| --- | --- | --- |
| Muse Spark nimmt Bilder entgegen (laut Meta-Dokumentation bestätigt) | Restrisiko: Die Qualität der Bilddiagnose ist ungetestet | Fototest am ersten Tag. Bei schwacher Qualität Rückfragen und Etikettfoto stärker nutzen und die Konfidenzschwelle erhöhen |
| Maskenformat von SAM 3.1 unbekannt | Overlay-Rendering verzögert sich | Docs lesen, Format in api-notes.md festhalten, Boxen als Fallback |
| SAM 3.1 trennt Platinenbereiche nicht zuverlässig | Elektronik-Fall schwach | Elektronik auf Gehäuse- und Kabelschäden begrenzen |
| Halluzinierte Reparaturschritte | Fehlerhafte oder riskante Anleitung | Risikostufen, Konfidenzschwelle, Rückfrage, Pflicht zum Test vor Elektronikreparatur |
| Zeitbudget unter dem Bedarf der vollen Version | Prototyp bleibt unfertig | Scope aus Abschnitt 3, Feature-Stopp am 2. November |
| 150 $ Credits reichen nicht | Tests brechen ab | Tageslimit im Proxy, Bilder verkleinern, Ergebnisse beim Entwickeln cachen |
| Official Rules ändern Vorgaben | Plan muss angepasst werden | Heute lesen, Compliance-Liste prüfen |
| Impact-Zahlen fehlen | Schwächerer Impact-Score | Zahlen mit Quellen vor dem 1. November recherchieren |

**Offene Fragen**

- Welches Elektronikgerät dient als Fall, und hat es Akku oder Netzanschluss?
- Wie viele Stunden stehen realistisch zur Verfügung, und gibt es freie Tage? Enthalten die 52 bis 67 Stunden aus Abschnitt 12 die Zusatzposten (Einkaufsliste, Reparaturmodus, Stichpfad, Rückfragen, Sprache) schon? Der Abstand zur vollen Version (55 bis 75) ist klein.
- Entschieden: Gebaut wird mit Claude Code, Muse Code ist optional.

## 15. Arbeitsanweisung für Claude Code

Baue in dieser Reihenfolge und arbeite autonom nach den Regeln in Abschnitt 16. Rate nicht: Unklares klärst du mit einem kleinen Test und hältst das Ergebnis fest.

1. Lies die Meta-Model-API-Dokumentation unter dev.meta.ai/docs. Halte Modell-IDs, Endpunkte, Bildformat und Größenlimit für Muse Spark, das Maskenformat von SAM 3.1 und das Audioformat von Muse Voice Transcribe in docs/api-notes.md fest. Erfinde keine Endpunkte oder Parameter.
2. Lege das Repo nach der Struktur aus Abschnitt 9 an, mit .gitignore und .env.example.
3. Baue den Proxy mit /health, /analyze und /step-help. Teste jeden Modellaufruf zuerst per curl oder Skript.
4. Teste SAM 3.1 mit den Beispielfotos und schreibe die Ergebnisse in docs/benchmark.md.
5. Setze die Pipeline aus Abschnitt 6 um, mit den Prompts aus Abschnitt 10 und dem Vertrag aus Abschnitt 8. Validiere jede Modellantwort gegen das Schema und wiederhole genau einmal bei ungültigem JSON.
6. Baue die SwiftUI-App Screen für Screen nach Abschnitt 4 und hole vor jedem Screen Design-Referenzen über den Mobbin MCP (siehe unten). Beginne mit Start, Analyse und Diagnose samt Overlay.
7. Ergänze Entscheidung, Einkaufsliste, geführten Reparaturmodus mit Stichpfad-Overlay für Textil, Sicherheitsscreen und Fehlerzustände.

**Regeln**

- Keine API-Keys im Code oder in Git. Der Key liegt nur im Proxy.
- Kleine Commits, ein Thema pro Commit.
- Schreibe Tests für den Schema-Parser und für die Sicherheitslogik. Die Sicherheitsfälle aus Abschnitt 11 müssen bestehen.
- Zeige in der App nie rohen Modelltext, nur Felder aus dem Vertrag.
- Speichere keine Nutzerbilder oder Audioaufnahmen auf dem Proxy.
- Nutze nur eigene oder frei lizenzierte Testfotos. Das Repo ist öffentlich: keine Keys, keine VW-Daten, und das README listet, was in der Bauphase entstand.

**Design (Pflicht): Mobbin MCP**

Nutze für jedes UI-Element den Mobbin MCP (https://api.mobbin.com/mcp) als Design-Referenz. Suche vor jedem Screen passende Screens und Flows, zum Beispiel für Kamera und Aufnahme, Checklisten, Schritt-für-Schritt-Anleitungen, Rückfragen im Chat-Stil, Spracheingabe und Fortschrittsanzeigen. Halte in docs/design-notes.md fest, welche Referenzen du je Screen genutzt hast.

Mobbin-Screens sind nur Inspiration. Kopiere keine Screens, Grafiken oder Assets 1:1, denn das Repo ist öffentlich und der Hackathon verbietet Assets ohne Rechte. Ist der Mobbin MCP nicht verbunden, trägst du das in docs/blockers.md ein und arbeitest an Proxy und Pipeline weiter (Abschnitt 16), statt Screens frei zu erfinden.

**Definition of Done für den Prototyp:** Die Abnahme aus Abschnitt 11 ist erfüllt, und api-notes.md enthält alle bestätigten API-Fakten.

## 16. Autonomer Betrieb

Claude Code arbeitet ohne Rückfragen und meldet sich nur über Statusdateien. Dieser Abschnitt hat Vorrang vor Abschnitt 15.

**Voraussetzungen, die der Mensch vor dem Start erfüllt**

- [ ] Meta-Model-API-Key liegt im Proxy-.env, Credits sind beantragt, Spend-Limit ist gesetzt
- [ ] Mobbin MCP ist in Claude Code verbunden
- [ ] Eigene Testfotos liegen in testdata/: mindestens 10 Textil-, 5 Schuh- und 3 Etikettfotos
- [ ] Xcode, Simulator oder iPhone und das Signing-Team sind eingerichtet
- [ ] Erster Commit frühestens am 27. Okt. (Bauphase), außer die Discord-Antwort erlaubt früher

**Arbeitsregeln**

1. Nicht anhalten und nicht zurückfragen. Bei Unklarheit baust du den kleinsten Test, hältst das Ergebnis in docs/api-notes.md fest und machst mit dem Fallback aus der Tabelle unten weiter.
2. Blocker (fehlender Key, nicht verbundener MCP, fehlende Testfotos, widersprüchliche Docs) trägst du in docs/blockers.md ein und arbeitest an etwas Unabhängigem weiter. Bleibt nichts Unabhängiges, schreibst du den Status und stoppst.
3. Arbeite streng nach Priorität: alle Must in der Reihenfolge Kernpipeline, Textil-Demo, Schuh-Demo, dann Should, dann Could. Beginne nie ein Could, solange ein Must offen ist.
4. Nach jedem Meilenstein laufen die Tests, dann Commit, dann docs/STATUS.md aktualisieren.
5. Die Tests für Schema-Parser und Sicherheitsfälle müssen vor jedem Commit grün sein.
6. Modellaufrufe in Tests werden gecacht und laufen nie in Schleifen. Die 150 $ Credits dürfen nicht überschritten werden.
7. Keine destruktiven Befehle außerhalb des Repos, kein Force-Push, keine Pakete ohne klaren Grund.
8. Stoppe sofort, wenn ein Schritt gegen Abschnitt 13 verstoßen würde, zum Beispiel Keys im Repo oder Assets ohne Rechte.

**Fallbacks, wenn eine Annahme nicht stimmt**

| Annahme | Prüfung | Fallback |
| --- | --- | --- |
| Muse Spark liefert brauchbare Bilddiagnosen (Bildeingabe ist laut Doku bestätigt) | Test mit allen Textil- und Schuhfotos aus testdata/ | Rückfragen verstärken (Etikett, Makroaufnahmen) und die Konfidenzschwelle erhöhen. Material notfalls per Auswahl-Chips abfragen |
| SAM 3.1 findet Risse und Nähte per Textprompt | Test mit allen Textilfotos in testdata/ | Bei mehr als der Hälfte Fehlschlägen: Schadstelle durch Antippen des Nutzers markieren lassen, in STATUS.md als Demo-Risiko vermerken |
| Maskenformat ist nutzbar | Test auf einem Foto | Boxen statt Masken, Stichpfad dann entlang der Boxdiagonale |
| Etikett-Texterkennung ist zuverlässig | Test mit den 3 Etikettfotos | Nutzer wählt Material per Chips, Etikettfoto bleibt optional |
| Muse Voice Transcribe läuft | Test mit einer Aufnahme | Spracheingabe streichen (Should) |

**Stichpfad: Algorithmus-Vorschlag**

Maske binarisieren, auf ein Skelett ausdünnen (zum Beispiel Zhang-Suen), den längsten Pfad als Mittellinie wählen und gleichmäßig nach Länge resamplen. Die Stichmarker liegen abwechselnd links und rechts der Linie, die Animation läuft entlang der Linie. Teste den Algorithmus zuerst mit Beispielmasken ohne Modellaufruf. Das passt für längliche Schäden (Riss, offene Naht). Bei einem Loch (Stopfen) legt die App ein Gitter aus parallelen Linien über die Kontur, erst in einer Richtung, dann quer dazu.

**Berichtspflicht**

docs/STATUS.md ist die einzige Stelle, an der der Mensch nachliest. Sie enthält: was läuft, was fehlt, offene Blocker, bisherige API-Kosten, Ergebnis des Benchmarks sowie je ein Ja oder Nein für "Textil-Demo läuft" und "Schuh-Demo läuft".

**Abgabevorbereitung durch Claude Code**

- README: was in der Bauphase entstand, welches Meta-Modell welche Aufgabe hat, wie man die App startet
- docs/demo-script.md: Skript für das 3-Minuten-Video mit Zeitmarken (Textil-Demo mit Rückfrage und Stichpfad, Schuh-Demo, Sicherheitssperre, Benchmark-Zahlen)
- Entwurf des Abgabetexts

Das Video nimmt der Mensch auf.
