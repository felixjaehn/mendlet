"""Hand-made USB-board outlook fixture, aligned to testdata/electronics/01_kabel_platine.jpg.

Polygons are illustrative annotations, not live SAM output or electrical evidence.
"""

from .mock_data import _decision, _item, _plan, _step, seg
from .models import DiagnosePlan, Segment


def segments() -> list[Segment]:
    return [
        seg(
            "seg_1",
            "Rotes Kabel",
            "part",
            "red wire",
            0.88,
            [
                [0, 0.752],
                [0.061, 0.718],
                [0.119, 0.674],
                [0.169, 0.618],
                [0.187, 0.616],
                [0.198, 0.630],
                [0.153, 0.682],
                [0.084, 0.738],
                [0, 0.780],
            ],
        ),
        seg(
            "seg_2",
            "Schwarzes Kabel",
            "part",
            "black wire",
            0.95,
            [
                [0.746, 0.620],
                [0.761, 0.611],
                [0.801, 0.651],
                [0.868, 0.707],
                [0.941, 0.753],
                [1, 0.777],
                [1, 0.802],
                [0.932, 0.779],
                [0.849, 0.731],
                [0.781, 0.670],
            ],
        ),
        seg(
            "seg_3",
            "Abisoliertes Kabelende",
            "damage",
            "copper wire strands",
            0.61,
            [
                [0.175, 0.625],
                [0.197, 0.598],
                [0.224, 0.570],
                [0.193, 0.529],
                [0.222, 0.548],
                [0.245, 0.572],
                [0.258, 0.532],
                [0.256, 0.579],
                [0.288, 0.550],
                [0.274, 0.589],
                [0.303, 0.586],
                [0.271, 0.607],
                [0.296, 0.623],
                [0.238, 0.626],
                [0.217, 0.613],
                [0.190, 0.634],
            ],
        ),
        seg(
            "seg_4",
            "Abisoliertes Kabelende",
            "damage",
            "copper wire strands",
            0.57,
            [
                [0.744, 0.625],
                [0.727, 0.609],
                [0.676, 0.613],
                [0.718, 0.598],
                [0.687, 0.580],
                [0.709, 0.584],
                [0.701, 0.550],
                [0.721, 0.573],
                [0.737, 0.548],
                [0.732, 0.586],
                [0.756, 0.552],
                [0.744, 0.595],
                [0.760, 0.616],
            ],
        ),
        seg(
            "seg_5",
            "Platine",
            "part",
            "circuit board",
            0.79,
            [
                [0.420, 0.220],
                [0.647, 0.220],
                [0.654, 0.503],
                [0.630, 0.527],
                [0.630, 0.617],
                [0.353, 0.613],
                [0.363, 0.526],
                [0.354, 0.514],
            ],
        ),
        seg(
            "seg_6",
            "Lötpad +",
            "part",
            "solder pad",
            0.90,
            [
                [0.393, 0.447],
                [0.416, 0.440],
                [0.433, 0.449],
                [0.460, 0.442],
                [0.477, 0.452],
                [0.473, 0.477],
                [0.479, 0.491],
                [0.459, 0.503],
                [0.428, 0.501],
                [0.402, 0.500],
                [0.386, 0.485],
            ],
        ).model_copy(update={"source": "grounding", "polarity": "+"}),
        seg(
            "seg_7",
            "Lötpad −",
            "part",
            "solder pad",
            0.91,
            [
                [0.538, 0.448],
                [0.562, 0.441],
                [0.579, 0.452],
                [0.602, 0.443],
                [0.623, 0.452],
                [0.628, 0.478],
                [0.620, 0.497],
                [0.593, 0.504],
                [0.567, 0.503],
                [0.543, 0.495],
                [0.533, 0.473],
            ],
        ).model_copy(update={"source": "grounding", "polarity": "-"}),
    ]


def plan() -> DiagnosePlan:
    items = [
        _item(
            1,
            "Lötkolben 25–40 W mit feiner Spitze und sicherer Ablage",
            "tool",
            "1 Set",
            True,
            "Elektronik Lötkolben 25–40 W feine Spitze Ablage",
        ),
        _item(
            2,
            "Bleifreies Lötzinn 0,5–0,8 mm",
            "material",
            "1 kleine Rolle",
            True,
            "Elektronik Lötzinn bleifrei 0,5–0,8 mm",
        ),
        _item(3, "Flussmittelstift für Elektronik", "material", "1 Stift", True, "Elektronik Flussmittelstift"),
        _item(4, "Helfende Hände", "tool", "1 Halter", True, "Helfende Hände Platinenhalter"),
        _item(
            5, "Passender Schrumpfschlauch", "material", "2 kurze Stücke", True, "Schrumpfschlauch dünne USB Leitung"
        ),
        _item(6, "Multimeter mit Durchgangsprüfung", "tool", "1 Stück", True, "Multimeter Durchgangsprüfer"),
    ]
    steps = [
        _step(
            "USB abziehen und Versorgung bestätigen",
            "Ziehe den USB-Stecker ab und trenne jede Versorgung. Bestätige ausdrücklich: Das Gerät hat keine "
            "Batterie, keinen Akku und keinen Netzanschluss. Nur dann weiterarbeiten. Bei Unklarheit abbrechen "
            "und einen Fachbetrieb fragen. Die Platine bleibt während Prüfung und Löten vollständig stromlos.",
            "Nur ausschalten reicht nicht: Die USB-Verbindung muss getrennt sein.",
            segs=[],
            items=[],
            critical=True,
        ),
        _step(
            "Verdacht mit Durchgangs- und Wackeltest prüfen",
            "Verdacht, nicht bestätigt: Die beiden sichtbaren losen Kabelenden könnten die Unterbrechung erklären. "
            "Prüfe am stromlosen Gerät anhand Beschriftung/Schaltplan und Durchgangsmessung, welches Kabel wohin "
            "gehört. Halte je eine Messspitze an die beiden zugänglichen Enden derselben Leitung und bewege "
            "sie sanft: Der Durchgang soll stabil sein. Rot gehört nur bei bestätigter Zuordnung an +, Schwarz an −. "
            "Bei unklarer Polung, beschädigtem Pad oder Kurzschlussverdacht nicht löten; Fachhilfe holen.",
            "Kabelfarben allein sind kein Nachweis. Nie am versorgten Gerät Durchgang messen.",
            segs=["seg_3", "seg_4", "seg_6", "seg_7"],
            items=["item_6"],
            critical=True,
        ),
        _step(
            "Leitungen und Platine fixieren",
            "Nur nach eindeutiger Prüfung fortfahren. Schiebe passenden Schrumpfschlauch auf jede Leitung und "
            "parke ihn fern der Lötstelle. Fixiere Platine und Kabel in den helfenden Händen. Ordne die Litzen "
            "so, dass keine seitlich absteht. Trage wenig Elektronik-Flussmittel auf die Pads auf; vermeide "
            "Hautkontakt und beachte die Herstellerhinweise. Die Kabel sollen ohne Zug zum zugehörigen Pad reichen.",
            "Schrumpfschlauch erst nach dem Löten aufschieben wollen: Er passt dann nicht über die Verbindung.",
            segs=["seg_3", "seg_4", "seg_6", "seg_7"],
            items=["item_3", "item_4", "item_5"],
        ),
    ]
    for end, pad, wire, symbol, duration in [
        ("seg_3", "seg_6", "Rotes", "+", 2),
        ("seg_4", "seg_7", "Schwarzes", "−", 3),
    ]:
        step = _step(
            f"{wire} Kabel an {symbol} löten",
            f"Lege das geprüfte blanke Ende an das Pad {symbol}. Berühre Litze und Pad gleichzeitig mit "
            "der feinen Spitze, als Richtwert 2–3 s erhitzen und wenig Zinn an die Kontaktstelle zuführen. "
            "Nimm erst Zinn, dann Spitze weg und halte die Leitung ruhig, bis die Verbindung abgekühlt ist. "
            "Ziel: benetzte, feste Verbindung ohne lose Litzen oder Brücke zum Nachbarpad. Fließt das Lot "
            "nicht, absetzen und abkühlen lassen, nicht länger erhitzen. Lötkolben nur auf hitzefester "
            "Ablage ablegen, heiße Spitze nicht berühren; gut lüften/absaugen und Flussmitteldämpfe nicht einatmen.",
            "Nur Zinn auf der Spitze schmelzen: Pad und Litze müssen gemeinsam benetzt werden.",
            segs=[end, pad],
            items=["item_1", "item_2", "item_3", "item_4"],
            critical=True,
        )
        step["overlay"] = {"type": "solder", "from_segment_id": end, "to_segment_id": pad, "hold_seconds": duration}
        steps.append(step)
    steps += [
        _step(
            "Abkühlen lassen und stromlos kontrollieren",
            "Lege den Lötkolben sicher ab und schalte ihn aus. Lass die Lötstellen vollständig abkühlen. Prüfe "
            "mit sanftem Zug auf festen Halt und mit dem Multimeter den Durchgang jeder Verbindung sowie "
            "einen möglichen Kurzschluss zwischen + und −. Bei unklarem Messwert, loser Litze oder Lötbrücke "
            "nicht einschalten; Fachhilfe holen. Der Timer allein bestätigt keine gute Lötstelle.",
            "Eine noch warme Verbindung bewegen: Das kann die Lötstelle schwächen.",
            segs=["seg_6", "seg_7"],
            items=["item_1", "item_6"],
            critical=True,
        ),
        _step(
            "Isolierung prüfen und kurz testen",
            "Prüfe, ob der vorbereitete Schrumpfschlauch die Verbindung sicher abdecken kann. Nur mit geeigneter "
            "Wärmequelle nach Herstellerangabe schrumpfen, keine offene Flamme; Nachbarbauteile nicht erhitzen. "
            "Fehlt das passende Werkzeug oder ist die Padgeometrie ungeeignet, Fachhilfe für die Isolierung "
            "holen und hier stoppen. Erst nach eindeutiger Prüfung, vollständiger Isolierung und geschlossenem "
            "Gehäuse kurz an der vorgesehenen USB-Kleinspannungsquelle testen. Bei Wärme, Geruch oder "
            "Fehlfunktion sofort trennen und Fachhilfe holen.",
            "Die offene Platine zum Test auf Metall ablegen: Kurzschlussgefahr.",
            segs=[],
            items=["item_5"],
            critical=True,
        ),
    ]
    return _plan(
        {
            "summary": "USB-LED-Platine mit zwei losen Kabelenden und sichtbaren +/−-Pads. "
            "Kontaktunterbrechung: Verdacht, nicht bestätigt; erst stromloser Durchgangs-/Wackeltest.",
            "likely_causes": ["Möglicherweise mechanisch abgerissene Leitungen; elektrische Ursache noch ungeprüft"],
            "confidence": 0.78,
            "evidence_segment_ids": ["seg_3", "seg_4", "seg_6", "seg_7"],
            "needs_more_info": False,
        },
        _decision(
            "repair_self",
            "Bedingter Ablauf nur für die stromlose USB-Kleinspannung ohne Batterie und "
            "Netzanschluss, nach bestätigter Zuordnung und intakten Pads. Bei Unsicherheit Fachhilfe.",
            "medium",
            [25, 45],
            [30, 65],
        ),
        items,
        steps,
    )
