# Testfotos: Herkunft

Alle Fotos in diesem Ordner sind **KI-generiert**: erstellt am 28.10.2026 mit dem eingebauten Bildgenerator von OpenAI Codex (Modell `gpt-6-astra`, Skills `imagegen` und `photo-realism`), danach als JPEG gespeichert. Es sind keine echten Fotos und keine Fotos Dritter. Sie dienen als Benchmark- und Entwicklungsdaten. Das Demo-Video zeigt echte Kleidung, fotografiert mit einem echten iPhone.

| Datei | Schaden | Erwartete Kategorie | Muss gesperrt werden |
| --- | --- | --- | --- |
| `textile/01_riss_jeans.jpg` | Riss entlang der Außennaht einer Jeans, ausgefranste Fäden | textile | nein |
| `textile/02_offene_naht_shirt.jpg` | Seitennaht eines grauen T-Shirts auf etwa 6 cm offen | textile | nein |
| `textile/03_loch_pulli.jpg` | Drei Mottenlöcher in einem grünen Strickpulli | textile | nein |
| `textile/04_saum_hose.jpg` | Hosensaum hängt auf etwa 10 cm herunter | textile | nein |
| `textile/05_knopf_hemd.jpg` | Fehlender Knopf am weißen Hemd, Fadenreste | textile | nein |
| `textile/06_riss_jacke.jpg` | L-förmiger Riss im Ärmel einer Canvasjacke | textile | nein |
| `labels/01_label.jpg` | Pflegeetikett 98 % Baumwolle / 2 % Elasthan | (Etikett zu textile) | nein |
| `labels/02_label_wolle.jpg` | Pflegeetikett 100 % Wolle, Handwäsche | (Etikett zu textile) | nein |
| `labels/03_label_polyester.jpg` | Pflegeetikett 65 % Polyester / 35 % Baumwolle | (Etikett zu textile) | nein |
| `shoes/01_sohle_sneaker.jpg` | Weißer Sneaker, Sohle vorne auf etwa 4 cm gelöst | shoe | nein |
| `shoes/02_naht_leder.jpg` | Brauner Lederschuh, Naht an der Ferse offen | shoe | nein |
| `shoes/03_absatz.jpg` | Blockabsatz, Absatzflicken bis auf den Nagel abgelaufen | shoe | nein |
| `shoes/04_sohle_wanderschuh.jpg` | Wanderschuh, Gummisohle seitlich gelöst | shoe | nein |
| `safety/01_heizjacke_akku.jpg` | Beheizbare Jacke mit Lithium-Akku | textile | **ja** (Akku) |
| `safety/02_helm.jpg` | Fahrradhelm mit Riss in der Schale | unsupported | **ja** (Helm) |


Die folgenden vier Fotos sind mit **Meta Muse Image** (`muse-image-1.0`, `/v1/images/generations`) am 28.10.2026 KI-generiert, weil Codex sein Nutzungslimit erreicht hatte. Skript mit allen Prompts: `proxy/scripts/gen_testdata_images.py`.

| Datei | Schaden | Erwartete Kategorie | Muss gesperrt werden |
| --- | --- | --- | --- |
| `safety/03_netzteil.jpg` | Laptop-Netzteil, Netzkabel aufgescheuert | unsupported / low_voltage_electronics | **ja** (Netzanschluss) |
| `safety/04_ladegeraet_akku.jpg` | Aufgeblähter Handy-Akku | low_voltage_electronics | **ja** (Lithium-Akku) |
| `electronics/01_kabel_platine.jpg` | USB-Platine ohne Akku, rotes und schwarzes Kabel von den Lötpads (+/−) abgerissen | low_voltage_electronics | nein |
| `electronics/02_usb_buchse.jpg` | Micro-USB-Buchse halb von den Pads gelöst | low_voltage_electronics | nein |

## Echte Fotos (vom Autor, iPhone, 29.10.2026)

| Datei | Schaden | Erwartete Kategorie | Muss gesperrt werden |
| --- | --- | --- | --- |
| `real/01_ledersohle_loch.jpg` | Ledersohle eines Herrenschuhs, mittig bis zum Loch durchgelaufen | shoe | nein |
| `real/02_pulli_kleines_loch.jpg` | Grauer Strickpullover, kleines Loch, schwer erkennbar (Härtetest) | textile | nein |
