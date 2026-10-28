"""Deterministic German mock fixtures. Textile scenarios are the richest (demo focus)."""

import math
from typing import Any

from .models import ClassifyResult, DiagnosePlan, Mask, MaskRing, Segment, TrackFrame, TrackedSegment, TrackResponse

# ---- geometry helpers (normalized coordinates, polygon masks) ----------------------


def ribbon(p0: tuple[float, float], p1: tuple[float, float], width: float, seed: float = 1.0, n: int = 16) -> list[list[float]]:
    """Thin, elongated, irregular, pointed-at-both-ends shape (a tear)."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy)
    nx, ny = -dy / length, dx / length
    upper, lower = [], []
    for i in range(n + 1):
        t = i / n
        wob = 0.006 * math.sin(t * 9 + seed) + 0.003 * math.sin(t * 23 + 2 * seed)
        half = width / 2 * (math.sin(math.pi * t) ** 0.6) * (0.75 + 0.25 * math.sin(t * 17 + seed))
        cx, cy = p0[0] + dx * t + nx * wob, p0[1] + dy * t + ny * wob
        upper.append([round(cx + nx * half, 4), round(cy + ny * half, 4)])
        lower.append([round(cx - nx * half, 4), round(cy - ny * half, 4)])
    return upper + lower[::-1]


def blob(cx: float, cy: float, r: float, n: int = 28) -> list[list[float]]:
    """Roughly round, slightly irregular blob (a hole)."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        rr = r * (1 + 0.12 * math.sin(3 * a) + 0.07 * math.sin(5 * a + 1))
        pts.append([round(cx + rr * math.cos(a), 4), round(cy + rr * math.sin(a), 4)])
    return pts


def rect(x: float, y: float, w: float, h: float, cut: float = 0.02) -> list[list[float]]:
    return [[x + cut, y], [x + w - cut, y], [x + w, y + cut], [x + w, y + h - cut], [x + w - cut, y + h],
            [x + cut, y + h], [x, y + h - cut], [x, y + cut]]


def seg(sid: str, label: str, kind: str, prompt: str, score: float, poly: list[list[float]]) -> Segment:
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    box = [round(min(xs), 4), round(min(ys), 4), round(max(xs) - min(xs), 4), round(max(ys) - min(ys), 4)]
    return Segment(id=sid, label=label, kind=kind, prompt=prompt, box=box,
                   mask=Mask(points=poly, rings=[MaskRing(points=poly, hole=False)]), score=score, source="text")  # type: ignore[arg-type]


# ---- builders ----------------------------------------------------------------------


def _item(i: int, name: str, kind: str, qty: str, required: bool, term: str, alt: str | None = None) -> dict[str, Any]:
    return {"id": f"item_{i}", "name": name, "kind": kind, "quantity": qty, "required": required,
            "search_term": term, "household_alternative": alt}


def _step(title: str, text: str, mistake: str, *, segs: list[str], items: list[str], critical: bool = False,
          overlay: tuple[str, str | None] | None = None, seg_id: str = "seg_2") -> dict[str, Any]:
    return {
        "n": 0, "title": title, "text": text, "common_mistake": mistake,
        "safety_critical": critical, "requires_confirmation": critical,
        "segment_ids": segs, "uses_items": items,
        "overlay": {"type": overlay[0], "stitch_type": overlay[1], "segment_id": seg_id} if overlay else None,
    }


def _plan(diagnosis: dict, decision: dict, items: list[dict], steps: list[dict]) -> DiagnosePlan:
    for n, s in enumerate(steps, start=1):
        s["n"] = n
    return DiagnosePlan.model_validate(
        {"diagnosis": diagnosis, "decision": decision, "shopping_list": items, "guide": {"steps": steps}}
    )


def _decision(rec: str, why: str, effort: str, t: list[int], c: list[float]) -> dict:
    return {"recommendation": rec, "reasoning": why, "effort": effort, "time_minutes": t, "cost_eur": c,
            "estimate_note": "Schätzung, keine Garantie"}


# ---- classification ----------------------------------------------------------------

CLASSIFY: dict[str, ClassifyResult] = {
    "textile": ClassifyResult(category="textile", risk_level="allowed", reason="Kleidungsstück aus Stoff mit sichtbarem Schaden, unkritisch."),
    "shoe": ClassifyResult(category="shoe", risk_level="allowed", reason="Sneaker mit Sohlenschaden, unkritisch."),
    "battery_jacket": ClassifyResult(
        category="textile", risk_level="warn_only",
        reason="Die Jacke ist beheizbar und enthält einen Lithium-Akku. Beschädigte oder falsch behandelte Akkus "
               "können sich stark erhitzen oder in Brand geraten. Dafür gibt es hier keine Anleitung. "
               "Bitte wende dich an den Hersteller oder einen Fachbetrieb."),
    "helmet": ClassifyResult(
        category="unsupported", risk_level="professional",
        reason="Helme schützen bei Unfällen. Schon kleine Schäden oder Reparaturen können die Schutzwirkung "
               "aufheben. Bitte lass ihn von einem Fachbetrieb prüfen oder ersetze ihn."),
    "unsupported": ClassifyResult(
        category="unsupported", risk_level="allowed",
        reason="Dieses Objekt (zum Beispiel ein Fahrrad) wird nicht unterstützt. Die App hilft bei Textilien und Schuhen."),
}

# ---- segments ----------------------------------------------------------------------


def segments(scenario: str) -> list[Segment]:
    if scenario == "textile_grounding":
        return segments("textile_tear")[:1]
    if scenario == "textile_multi":
        result = segments("textile_tear")[:2]
        result.append(seg("seg_3", "Riss", "damage", "tear", 0.78, ribbon((0.2, 0.3), (0.45, 0.27), 0.02)))
        return result
    if scenario == "textile_rings":
        result = segments("textile_hole")[:2]
        result[1].mask.rings += [MaskRing(points=blob(0.50, 0.5, 0.008), hole=True),
                                 MaskRing(points=blob(0.54, 0.5, 0.008), hole=True),
                                 MaskRing(points=blob(0.50, 0.5, 0.003), hole=False)]
        return result
    if scenario in ("textile_tear", "textile_tear_needs_label"):
        return [
            seg("seg_1", "Kleidungsstück", "part", "garment", 0.93, rect(0.06, 0.08, 0.88, 0.86)),
            seg("seg_2", "Riss", "damage", "tear", 0.81, ribbon((0.34, 0.56), (0.62, 0.47), 0.024, 1.3)),
            seg("seg_3", "Offene Naht", "damage", "open seam", 0.58, ribbon((0.29, 0.575), (0.66, 0.455), 0.014, 2.1)),
        ]
    if scenario == "textile_hole":
        return [
            seg("seg_1", "Kleidungsstück", "part", "garment", 0.92, rect(0.05, 0.1, 0.9, 0.82)),
            seg("seg_2", "Loch", "damage", "hole", 0.84, blob(0.52, 0.5, 0.055)),
            seg("seg_3", "Ausgefranster Rand", "damage", "frayed edge", 0.47, blob(0.52, 0.5, 0.075)),
        ]
    if scenario == "textile_open_seam":
        return [
            seg("seg_1", "Kleidungsstück", "part", "garment", 0.94, rect(0.07, 0.06, 0.86, 0.88)),
            seg("seg_2", "Offene Naht", "damage", "open seam", 0.79, ribbon((0.78, 0.30), (0.74, 0.70), 0.02, 0.7)),
        ]
    if scenario == "textile_button":
        return [
            seg("seg_1", "Kleidungsstück", "part", "garment", 0.94, rect(0.08, 0.05, 0.84, 0.9)),
            seg("seg_2", "Knopfposition", "damage", "button", 0.52, blob(0.5, 0.42, 0.03, 20)),
            seg("seg_3", "Ausgefranster Rand", "damage", "frayed edge", 0.41, blob(0.5, 0.42, 0.045, 20)),
        ]
    if scenario == "shoe_sole":
        return [
            seg("seg_1", "Sohle", "part", "shoe sole", 0.88, rect(0.08, 0.62, 0.84, 0.2, 0.05)),
            seg("seg_2", "Abgelöste Sohle (Spitze)", "damage", "detached sole", 0.74,
                ribbon((0.1, 0.66), (0.34, 0.69), 0.04, 0.4)),
            seg("seg_3", "Naht", "part", "seam", 0.55, ribbon((0.12, 0.6), (0.7, 0.58), 0.014, 3.0)),
            seg("seg_4", "Absatz", "part", "heel", 0.8, rect(0.72, 0.64, 0.2, 0.17, 0.03)),
        ]
    return []


def tracking(concept: str) -> TrackResponse:
    from .sam import PROMPT_META

    label, kind = PROMPT_META.get(concept, (concept, "part"))
    frames = []
    for index in range(10):
        offset = index * 0.02
        segment = seg("seg_7", label, kind, concept, 0.9,
                      ribbon((0.2 + offset, 0.5), (0.45 + offset, 0.45), 0.02))
        frames.append(TrackFrame(index=index, segments=[TrackedSegment(**segment.model_dump(), object_id="7")]))
    return TrackResponse(frames=frames, fps=10.0)


# ---- textile: tear -----------------------------------------------------------------


def textile_tear_needs_label() -> DiagnosePlan:
    return _plan(
        {
            "summary": "Etwa 6 cm langer Riss, der entlang einer Naht verläuft. Der Stoff ist ein Webstoff (Jeans- oder "
                       "Baumwollstoff). Ob er Elasthan enthält, sehe ich nicht, und genau das bestimmt Nadel, Faden und Stichspannung.",
            "likely_causes": ["Naht durch Zugbelastung aufgegangen", "Fadenermüdung durch häufiges Waschen"],
            "confidence": 0.55, "evidence_segment_ids": ["seg_2", "seg_3"], "needs_more_info": True,
            "follow_up_questions": [{
                "id": "q1", "type": "photo", "purpose": "label",
                "prompt": "Mach ein Foto vom Pflegeetikett mit der Materialangabe (meist in der Seitennaht oder am Bund).",
            }],
            "label_info": {"materials": [], "care": []},
        },
        _decision("repair_self", "Vorläufig: Ein Riss entlang der Naht lässt sich meist unsichtbar von Hand schließen. "
                  "Die endgültige Empfehlung gebe ich nach dem Blick aufs Etikett.", "low", [20, 40], [3, 8]),
        [], [],
    )


def textile_tear(stretch: bool = True) -> DiagnosePlan:
    materials = ["98 % Baumwolle", "2 % Elasthan"] if stretch else ["100 % Baumwolle"]
    care = (["Waschen bei 30 °C", "Nicht bleichen", "Nicht im Wäschetrockner trocknen", "Bügeln max. 110 °C"]
            if stretch else ["Waschen bei 40 °C", "Nicht bleichen", "Wäschetrockner bei niedriger Temperatur", "Bügeln max. 150 °C"])
    fabric = "Stretch-Denim" if stretch else "Baumwollstoff"
    items = [
        _item(1, "Nähnadel Stärke 80–90", "tool", "2 Nadeln", True,
              "Handnähnadeln Stärke 80 90 Kugelspitze Stretch" if stretch else "Handnähnadeln Stärke 80 90 Universal",
              "Dünne Stopfnadel mit kleinem Öhr"),
        _item(2, "Polyestergarn in passender Farbe", "material", "1 Spule (ca. 100 m)", True,
              "Nähgarn Polyester 100 m passend zur Stofffarbe",
              "Faden aus der Saumzugabe oder Nahtzugabe des Kleidungsstücks (unauffällig herausziehen)"),
        _item(3, "Stecknadeln", "tool", "6–8 Stück", True, "Stecknadeln dünn", "Kleine Büroklammern oder Haushaltsklammern"),
        _item(4, "Kleine spitze Schere", "tool", "1 Stück", True, "Stickschere Fadenschere", "Nagelschere"),
        _item(5, "Fingerhut", "tool", "1 Stück", False, "Fingerhut Metall Größe M", "Pflaster oder Klebeband um den Mittelfinger"),
        _item(6, "Nahttrenner", "tool", "1 Stück", False, "Nahttrenner", "Spitze der Nagelschere (vorsichtig) oder Stecknadelspitze"),
        _item(7, "Bügeleisen und Bügeltuch", "tool", "1 Set", False, "Bügeltuch Baumwolle", "Dünnes, helles Baumwolltuch oder Geschirrtuch"),
    ]
    steps = [
        _step("Ränder ausrichten und fixieren",
              "Lege das Kleidungsstück links auf den Tisch und streiche den Stoff glatt. Bringe die beiden Rissränder so "
              "zusammen, dass sie genau Kante an Kante liegen, ohne zu überlappen. Stecke alle 2 cm eine Stecknadel quer "
              "zum Riss und lass die Nadelspitzen zum Rand zeigen.",
              "Überlappende Ränder: Dann wirft die Naht später Falten und der Riss wird sichtbar.",
              segs=["seg_2", "seg_3"], items=["item_3"], overlay=("highlight", None)),
        _step("Lose Fäden sauber kürzen",
              "Schneide ausgefranste Fadenenden am Riss mit der kleinen Schere auf 2–3 mm zurück. Lockere Schlingen der "
              "alten Naht löst du mit dem Nahttrenner, ohne in den Stoff zu stechen. Schere und Nadeln sind spitz: Schneide "
              "immer von dir weg und halte die Finger hinter der Schneide.",
              "Zu kurz schneiden: Der Stoff franst weiter aus und die Naht hat keinen Halt.",
              segs=["seg_2"], items=["item_4", "item_6"], critical=True, overlay=("highlight", None)),
        _step("Faden vorbereiten und einfädeln",
              "Schneide etwa 50 cm Faden ab: Längere Fäden verdrillen sich. Fädle ihn ein und nimm ihn einfach, nicht doppelt, "
              "das ist unauffälliger. "
              + ("Wegen des Elasthan-Anteils nimmst du Polyestergarn (leicht elastisch) und eine Nadel mit leicht runder Spitze, "
                 "sie schiebt die Fasern beiseite statt sie zu durchstechen. "
                 if stretch else "Bei reiner Baumwolle passt eine normale Universalnadel. ")
              + "Mache am kurzen Ende einen kleinen Knoten: Faden um den Zeigefinger legen, zwischen Daumen und Finger zu einer Schlaufe rollen, festziehen.",
              "Steifes Baumwollgarn bei Stretchstoff: Es gibt nicht nach und reißt beim Bewegen wieder aus." if stretch
              else "Knoten zu groß: Er drückt sich auf der Stoffseite durch.",
              segs=["seg_2"], items=["item_1", "item_2"], overlay=("highlight", None)),
        _step("Startknoten setzen und ersten Stich machen",
              "Beginne ca. 5 mm vor dem Rissende. Stich von der linken Stoffseite in den Nahtfalz ein, sodass der Knoten in der "
              "Falte verschwindet. Komm direkt am Rissende heraus. Bei dickem Jeansstoff hilft der Fingerhut am Mittelfinger, "
              "um die Nadel durchzuschieben.",
              "Knoten außen statt im Falz: Er scheuert und löst sich schneller.",
              segs=["seg_2"], items=["item_1", "item_5"], overlay=("stitch_path", "ladder_stitch")),
        _step("Leiterstich entlang des Risses",
              "Der Leiterstich arbeitet abwechselnd auf beiden Seiten: Stich genau gegenüber vom Ausgang in den Falz der "
              "anderen Seite ein und führe die Nadel 3–4 mm im Falz entlang, komme heraus. Wechsle dann wieder zur ersten Seite, "
              "auf gleicher Höhe. Die Fäden liegen wie Leitersprossen quer über dem Riss. "
              + ("Wegen des Elasthans: Stichlänge 3 mm und die Fäden nur locker führen, damit die Naht beim Bewegen mitgeht."
                 if stretch else "Stichlänge etwa 4 mm; nach 4–5 Stichen kannst du den Faden fest anziehen."),
              "Schräg einstechen: Die Sprossen verlaufen dann schief und der Riss klafft nach dem Anziehen.",
              segs=["seg_2"], items=["item_1"], overlay=("stitch_path", "ladder_stitch")),
        _step("Naht schließen und Abschlussknoten",
              "Zieh den Faden gleichmäßig an, bis sich die Sprossen im Falz verstecken und die Kanten stumpf aneinanderliegen. "
              + ("Beim Stretchstoff nur so fest, dass der Stoff noch etwas Spiel hat. " if stretch else "")
              + "Mache am Ende zwei kleine Sicherungsstiche auf der Stelle, bilde eine Schlaufe, ziehe den Faden hindurch und "
              "wiederhole das einmal (doppelter Abschlussknoten). Stich dann einen Zentimeter durch den Stoff, ziehe den Faden "
              "straff und schneide ihn dicht am Stoff ab; das Ende verschwindet im Inneren.",
              "Faden zu stramm ziehen: Der Stoff kräuselt sich entlang der Naht.",
              segs=["seg_2"], items=["item_1", "item_4"], overlay=("stitch_path", "ladder_stitch")),
        _step("Von links bügeln",
              f"Entferne alle Stecknadeln. Stelle das Bügeleisen auf {'Stufe 1 (max. 110 °C, laut Etikett), ohne Dampf' if stretch else 'Stufe 2 (max. 150 °C, laut Etikett)'}. "
              "Lege das Bügeltuch auf die linke Stoffseite und drücke das Eisen etwa 10 Sekunden auf die Naht, ohne zu schieben. "
              "Lass den Stoff vor dem Anziehen abkühlen. Das Bügeleisen ist heiß: nicht an der Sohle anfassen, danach abstecken.",
              "Zu heiß oder direkt auf dem Stoff bügeln: " + ("Elasthan wird spröde und der Stoff glänzt." if stretch else "Der Stoff glänzt und kann ausbleichen."),
              segs=["seg_2"], items=["item_7"], critical=True, overlay=("highlight", None)),
    ]
    why = (f"Der Riss (ca. 6 cm) verläuft entlang der Naht, der Stoff darum ist intakt und es fehlt kein Material. "
           f"Laut Etikett ({', '.join(materials)}) ist es {fabric}. ")
    why += ("Wegen 2 % Elasthan bekommst du Polyestergarn, eine Nadel mit runder Spitze und eine lockere Naht, damit sie beim "
            "Bewegen mitgeht. Der Leiterstich ist von außen kaum sichtbar." if stretch else
            "Der Leiterstich ist von außen kaum sichtbar und hält bei reiner Baumwolle auch mit festem Zug.")
    return _plan(
        {
            "summary": "Ca. 6 cm langer Riss entlang der Seitennaht, die Ränder sind leicht ausgefranst. Das Etikett bestätigt: "
                       + " und ".join(materials) + ".",
            "likely_causes": ["Naht durch Zugbelastung aufgegangen", "Fadenermüdung durch häufiges Waschen"],
            "confidence": 0.86, "evidence_segment_ids": ["seg_2", "seg_3"], "needs_more_info": False,
            "follow_up_questions": [], "label_info": {"materials": materials, "care": care},
        },
        _decision("repair_self", why, "low", [20, 40], [3, 8]), items, steps,
    )


# ---- textile: hole (darning) ---------------------------------------------------------


def textile_hole() -> DiagnosePlan:
    items = [
        _item(1, "Stopfnadel mit stumpfer Spitze, Stärke 3–5", "tool", "1 Stück", True, "Stopfnadel stumpf Wolle", "Dicke Nadel mit großem Öhr"),
        _item(2, "Stopfgarn oder Wolle in passender Farbe", "material", "1 Knäuel (ca. 3 m)", True,
              "Stopfgarn Wolle passend zur Farbe", "Garnrest vom Etikett-Beutel oder aus der Saumnaht herausgezogen"),
        _item(3, "Stopfpilz", "tool", "1 Stück", False, "Stopfpilz Holz", "Glühbirne (kalt), Tasse oder Marmeladenglas unterlegen"),
        _item(4, "Kleine spitze Schere", "tool", "1 Stück", True, "Stickschere", "Nagelschere"),
        _item(5, "Bügeleisen und Bügeltuch", "tool", "1 Set", False, "Bügeltuch Baumwolle", "Dünnes Geschirrtuch"),
    ]
    steps = [
        _step("Stopfhilfe unterlegen",
              "Lege den Pullover so, dass das Loch über einem Stopfpilz, einer Tasse oder einem Glas gespannt liegt. Der Stoff "
              "soll glatt, aber nicht gedehnt sein. Das Loch ist etwa 2 cm groß.",
              "Stoff zu stark spannen: Nach dem Entspannen zieht sich die Stopfstelle zusammen.",
              segs=["seg_2"], items=["item_3"], overlay=("highlight", None)),
        _step("Ränder ausputzen",
              "Schneide lose Fadenenden mit der kleinen Schere bündig ab, ohne das Loch zu vergrößern. Maschen, die sich noch "
              "halten, bleiben stehen. Schere und Nadel sind spitz: schneide immer vom Körper weg.",
              "Intakte Maschen mit abschneiden: Das Loch wird größer.",
              segs=["seg_2", "seg_3"], items=["item_4"], critical=True, overlay=("highlight", None)),
        _step("Faden einfädeln und verankern",
              "Fädle ca. 60 cm Garn in die Stopfnadel, einfach genommen. Verankere den Anfang auf der linken Seite mit zwei "
              "kleinen Vorstichen ca. 1 cm neben dem Loch im gesunden Gestrick, statt einen dicken Knoten zu machen.",
              "Dicker Knoten: Er scheuert auf der Haut und drückt sich durch.",
              segs=["seg_2"], items=["item_1", "item_2"], overlay=("highlight", None)),
        _step("Längsfäden spannen",
              "Führe das Garn in parallelen Bahnen über das Loch: ca. 1 cm in das gesunde Gestrick hinein, über das Loch, "
              "1 cm auf der anderen Seite wieder ein. Abstand der Bahnen etwa 2–3 mm. Lass an den Umkehrpunkten eine kleine "
              "Schlaufe locker, so kann das Gestrick atmen.",
              "Zu straff spannen: Das Gestrick zieht sich zusammen und wirft Falten.",
              segs=["seg_2"], items=["item_1"], overlay=("stitch_path", "darning")),
        _step("Querfäden einweben",
              "Drehe das Teil um 90° und webe das Garn quer durch die Längsfäden: über einen Faden, unter dem nächsten, in "
              "jeder Reihe versetzt. Schiebe jede Reihe leicht an die vorherige, ohne zu ziehen, bis das Loch gleichmäßig "
              "gefüllt ist.",
              "Immer über dem gleichen Faden laufen: Es entstehen Streifen statt eines dichten Gewebes.",
              segs=["seg_2"], items=["item_1"], overlay=("stitch_path", "darning")),
        _step("Ränder anbinden und vernähen",
              "Führe die letzte Reihe ein Stück in das gesunde Gestrick und sichere sie mit zwei kleinen Stichen. Ziehe den "
              "Faden auf links durch die Maschen, vernähe ihn über 2–3 cm und schneide ihn dicht ab.",
              "Faden nur verknoten: Der Knoten löst sich in der Wäsche.",
              segs=["seg_2"], items=["item_1", "item_4"], overlay=("stitch_path", "darning")),
        _step("Form glätten",
              "Lege das Teil mit der linken Seite nach oben, das Bügeltuch darüber. Bügle Wolle auf niedriger Stufe ohne Druck "
              "(Wolle nur leicht dämpfen). Das Bügeleisen ist heiß: nicht berühren und danach abstecken.",
              "Eisen fest aufdrücken: Das Gestopfte wird platt und glänzt.",
              segs=["seg_2"], items=["item_5"], critical=True, overlay=("highlight", None)),
    ]
    return _plan(
        {
            "summary": "Etwa 2 cm großes Loch in einem Strickstoff (vermutlich Wolle oder Baumwollmix). Die Ränder sind leicht "
                       "ausgelaufen, die Umgebung ist intakt.",
            "likely_causes": ["Materialverschleiß an einer stark belasteten Stelle", "Fadenzug durch Hängenbleiben"],
            "confidence": 0.82, "evidence_segment_ids": ["seg_2", "seg_3"], "needs_more_info": False,
            "follow_up_questions": [], "label_info": {"materials": [], "care": []},
        },
        _decision("repair_self", "Das Loch ist klein und die Umgebung stabil. Stopfen füllt es mit einem neuen Fadengewebe; "
                  "mit passendem Garn bleibt es unauffällig. Material unbekannt: Bei Wolle nimmst du Wollgarn, bei Synthetik "
                  "ein Garn gleicher Art.", "medium", [30, 60], [3, 8]),
        items, steps,
    )


# ---- textile: open seam ---------------------------------------------------------------


def textile_open_seam() -> DiagnosePlan:
    items = [
        _item(1, "Handnähnadel Stärke 80–90", "tool", "2 Nadeln", True, "Handnähnadeln Stärke 80 90", "Dünne Stopfnadel"),
        _item(2, "Nähgarn in passender Farbe", "material", "1 Spule (ca. 100 m)", True, "Nähgarn Polyester 100 m", "Faden aus der Nahtzugabe"),
        _item(3, "Stecknadeln", "tool", "6–8 Stück", True, "Stecknadeln dünn", "Büroklammern"),
        _item(4, "Kleine spitze Schere", "tool", "1 Stück", True, "Stickschere", "Nagelschere"),
        _item(5, "Bügeleisen und Bügeltuch", "tool", "1 Set", False, "Bügeltuch", "Geschirrtuch"),
    ]
    steps = [
        _step("Offene Naht säubern",
              "Wende das Teil auf links. Schneide Fadenreste der alten Naht mit der kleinen Schere ab und streiche die "
              "Nahtzugaben glatt. Die alten Stichlöcher zeigen dir die Nahtlinie. Schere und Nadel sind spitz: schneide "
              "vom Körper weg.",
              "Nahtzugabe mit abschneiden: Dann fehlt Stoff zum Nähen.",
              segs=["seg_2"], items=["item_4"], critical=True, overlay=("highlight", None)),
        _step("Kanten feststecken",
              "Lege beide Stoffteile rechts auf rechts und stecke sie entlang der Nahtlinie alle 3 cm quer fest. Beginne und "
              "ende 1 cm in der noch intakten Naht.",
              "Stecknadeln längs statt quer: Der Stoff verrutscht beim Nähen.",
              segs=["seg_2"], items=["item_3"], overlay=("highlight", None)),
        _step("Faden einfädeln",
              "Nimm ca. 60 cm Garn doppelt und mache einen kleinen Knoten am Ende. Doppelter Faden hält an der Seitennaht "
              "besser als einfacher.",
              "Zu langer Faden: Er verknotet sich beim Nähen.",
              segs=["seg_2"], items=["item_1", "item_2"], overlay=("highlight", None)),
        _step("Anfang mit Rückstichen sichern",
              "Setze 1 cm vor dem Beginn der offenen Naht an und mache drei Rückstiche (je 2 mm) genau in den alten Stichlöchern. "
              "So hängt dein Anfang fest in der alten Naht.",
              "Neben die alte Naht nähen: Die Nahtlinie verschiebt sich und das Teil sitzt anders.",
              segs=["seg_2"], items=["item_1"], overlay=("stitch_path", "running_stitch")),
        _step("Vorstich entlang der Nahtlinie",
              "Nähe mit kleinen Vorstichen (2–3 mm lang, gleiche Abstände) in den alten Löchern entlang. Alle 3–4 Stiche ziehst du "
              "den Faden an, bis die Naht flach liegt. Stich möglichst senkrecht durch alle Lagen.",
              "Zu große Stiche: Die Naht ist schwach und die Zähne öffnen sich beim Bewegen.",
              segs=["seg_2"], items=["item_1"], overlay=("stitch_path", "running_stitch")),
        _step("Ende sichern und glätten",
              "Mache am Ende des Nahtstücks wieder drei Rückstiche in der intakten Naht, verknote den Faden doppelt und schneide ihn "
              "dicht ab. Bügle die Naht auf links mit Bügeltuch auseinander (Temperatur wie im Etikett). Das Bügeleisen ist heiß.",
              "Naht ungebügelt lassen: Sie steht auf und scheuert.",
              segs=["seg_2"], items=["item_1", "item_4", "item_5"], critical=True, overlay=("highlight", None)),
    ]
    return _plan(
        {
            "summary": "Etwa 10 cm offene Seitennaht. Die Nahtzugaben sind intakt, der Faden ist an der Naht gerissen.",
            "likely_causes": ["Nahtfaden gerissen", "Zugbelastung an der Seitennaht"],
            "confidence": 0.88, "evidence_segment_ids": ["seg_2"], "needs_more_info": False,
            "follow_up_questions": [], "label_info": {"materials": [], "care": []},
        },
        _decision("repair_self", "Die Naht ist nur aufgegangen, der Stoff ist unbeschädigt. Du nähst sie in den alten Stichlöchern "
                  "neu, das ist stabil und unsichtbar.", "low", [20, 30], [2, 5]),
        items, steps,
    )


# ---- textile: lost button -------------------------------------------------------------


def textile_button() -> DiagnosePlan:
    items = [
        _item(1, "Passender Knopf", "material", "1 Knopf (plus 1 Ersatz)", True, "Knöpfe 15 mm 4-Loch",
              "Ersatzknopf vom Innensaum oder Hemdbrust, alter Knopf aus der Kramkiste"),
        _item(2, "Kräftiges Nähgarn in passender Farbe", "material", "1 Spule", True, "Knopfgarn Polyester stark", "Zahnseide (ungewachst) nur bei Notfall"),
        _item(3, "Nähnadel Stärke 80–90", "tool", "2 Nadeln", True, "Handnähnadeln Stärke 80 90", "Dünne Stopfnadel"),
        _item(4, "Streichholz oder Zahnstocher", "tool", "1 Stück", True, "Zahnstocher", "Stecknadel quer unter den Knopf"),
        _item(5, "Kleine spitze Schere", "tool", "1 Stück", True, "Stickschere", "Nagelschere"),
    ]
    steps = [
        _step("Position bestimmen",
              "Schließe das Kleidungsstück und markiere die Position gegenüber dem Knopfloch mit einer Stecknadel. "
              "Reste des alten Fadens an dieser Stelle entfernst du mit der Schere.",
              "Auf Augenmaß verschieben: Der Knopf sitzt dann zu hoch oder zu tief und das Teil zieht.",
              segs=["seg_2"], items=["item_5"], overlay=("highlight", None)),
        _step("Doppelten Faden einfädeln",
              "Fädle ca. 60 cm Garn ein, lege es doppelt und knote die Enden zusammen. So nähst du mit vier Fadenlagen und hältst fester.",
              "Zu dünner Faden: Der Knopf reißt nach wenigen Tagen ab.",
              segs=["seg_2"], items=["item_2", "item_3"], overlay=("highlight", None)),
        _step("Faden verankern",
              "Stich von links an der markierten Stelle ein und wieder zurück, zweimal übereinander, sodass der Knoten verdeckt "
              "bleibt. Achte darauf, die Nadel nicht gegen deine Finger zu führen.",
              "Nur durch eine Stofflage nähen: Das gibt später ein Loch im Stoff.",
              segs=["seg_2"], items=["item_3"], critical=True, overlay=("highlight", None)),
        _step("Knopf annähen",
              "Lege das Streichholz quer auf die Markierung, den Knopf darauf. Nähe 6–8 Stiche durch jedes Lochpaar (bei vier Löchern "
              "zweimal ein Paar). Der Faden läuft über das Streichholz, so bleibt ein Abstand.",
              "Ohne Abstandhalter nähen: Der Knopf sitzt zu fest und das Knopfloch lässt sich nicht schließen.",
              segs=["seg_2"], items=["item_3", "item_4"], overlay=("highlight", None)),
        _step("Steg wickeln",
              "Ziehe das Streichholz heraus, hebe den Knopf an und wickle den Faden 3–4 Mal fest um die Fäden zwischen Knopf und Stoff. "
              "Das gibt den Steg und der Knopf hält den Stoff nicht eingeklemmt.",
              "Steg weglassen: Der Stoff zieht sich um den Knopf zusammen und reißt.",
              segs=["seg_2"], items=["item_3"], overlay=("highlight", None)),
        _step("Vernähen und testen",
              "Stich auf die linke Seite, mache zwei Knoten dicht am Stoff und schneide den Faden ab. Knöpfe zur Probe zu: "
              "Der Knopf soll leicht durch das Knopfloch gehen, ohne zu wackeln.",
              "Faden einfach kappen: Ohne Knoten hält die Naht nur bis zur ersten Wäsche.",
              segs=["seg_2"], items=["item_5"], overlay=("highlight", None)),
    ]
    return _plan(
        {
            "summary": "Ein Knopf fehlt, an der Stelle sind nur Fadenreste zu sehen. Der Stoff darunter ist intakt.",
            "likely_causes": ["Faden gerissen oder durchgescheuert", "Zu locker angenähter Knopf"],
            "confidence": 0.9, "evidence_segment_ids": ["seg_2"], "needs_more_info": False,
            "follow_up_questions": [], "label_info": {"materials": [], "care": []},
        },
        _decision("repair_self", "Ein Knopf lässt sich in wenigen Minuten ersetzen; Stoff und Knopfloch sind unbeschädigt.",
                  "low", [10, 20], [1, 3]),
        items, steps,
    )


# ---- shoe -------------------------------------------------------------------------------


def shoe_sole() -> DiagnosePlan:
    items = [
        _item(1, "Kontaktkleber für Schuhe", "material", "1 Tube (ca. 30 g)", True, "Schuhkleber Kontaktkleber", None),
        _item(2, "Schleifpapier Körnung 80–120", "material", "1 Blatt", True, "Schleifpapier 80 Körnung", "Grobe Nagelfeile"),
        _item(3, "Aceton oder Isopropanol", "material", "kleine Menge", True, "Aceton Reinigung 100 ml", "Nagellackentferner mit Aceton"),
        _item(4, "Zwingen oder Klemmen", "tool", "2–3 Stück", True, "Schraubzwingen klein", "Gummibänder und schwere Bücher"),
        _item(5, "Pinsel oder Holzspatel", "tool", "1 Stück", False, "Klebepinsel", "Zahnstocher oder Eisstiel"),
        _item(6, "Lappen", "material", "1 Stück", True, "Baumwolllappen", "Küchenpapier"),
    ]
    steps = [
        _step("Schaden prüfen", "Schau dir die Sohle an der Spitze an: Die Klebekanten sollen sauber, trocken und ohne Risse im Material sein. Ziehe die Sohle vorsichtig 1–2 cm weiter ab, bis die lose Fläche erreicht ist.",
              "Zu weit abziehen: Dann zerreißt der intakte Teil der Klebung.", segs=["seg_1", "seg_2"], items=[], overlay=("highlight", None), seg_id="seg_2"),
        _step("Klebeflächen anrauen", "Raue beide Klebeflächen (Sohle und Schuhunterseite) mit dem Schleifpapier gleichmäßig an, bis der Glanz weg ist. Entferne den Staub mit dem Lappen.",
              "Nur eine Seite anrauen: Der Kleber haftet dann nur einseitig.", segs=["seg_2"], items=["item_2", "item_6"], overlay=("highlight", None), seg_id="seg_2"),
        _step("Flächen entfetten", "Reibe beide Flächen mit Aceton oder Isopropanol auf dem Lappen ab und lass sie 5 Minuten trocknen. Lüfte den Raum: Die Dämpfe sind gesundheitsschädlich und brennbar, keine offene Flamme.",
              "Mit bloßen Fingern berühren: Hautfett verhindert die Haftung.", segs=["seg_2"], items=["item_3", "item_6"], critical=True, overlay=("highlight", None), seg_id="seg_2"),
        _step("Kontaktkleber auftragen", "Trage auf beide Flächen eine dünne, gleichmäßige Schicht Kontaktkleber auf, mit Pinsel oder Spatel. Arbeite am offenen Fenster, Klebstoffdämpfe nicht einatmen, kein Hautkontakt.",
              "Zu dick auftragen: Der Kleber trocknet nicht durch und die Naht bleibt weich.", segs=["seg_2"], items=["item_1", "item_5"], critical=True, overlay=("highlight", None), seg_id="seg_2"),
        _step("Ablüften lassen", "Warte 10–15 Minuten, bis die Schichten sich fingertrocken anfühlen und nicht mehr kleben, wenn du sie kurz berührst.",
              "Zu früh zusammendrücken: Die Dämpfe sind noch im Kleber und die Haftung wird schwach.", segs=["seg_2"], items=[], overlay=("highlight", None), seg_id="seg_2"),
        _step("Zusammendrücken und fixieren", "Lege die Sohle exakt an und drücke sie von der Mitte nach außen fest zusammen. Fixiere die Spitze mit Zwingen oder mit Gummibändern und schweren Büchern.",
              "Verrutschen: Kontaktkleber lässt sich nach dem ersten Kontakt nicht mehr korrigieren.", segs=["seg_1", "seg_2"], items=["item_4"], overlay=("highlight", None), seg_id="seg_2"),
        _step("Aushärten lassen", "Lass den Schuh 24 Stunden mit Druck stehen. Erst danach tragen und nicht in Nässe stellen.",
              "Schon früher anziehen: Die Klebung löst sich nach wenigen Schritten wieder.", segs=["seg_2"], items=[], overlay=("highlight", None), seg_id="seg_2"),
    ]
    return _plan(
        {
            "summary": "Die Sohle des Sneakers löst sich an der Spitze auf einer Länge von etwa 4 cm. Das Sohlenmaterial und die Naht darüber sind intakt.",
            "likely_causes": ["Klebstoff durch Alterung und Feuchtigkeit gealtert", "Biegebelastung an der Zehenpartie"],
            "confidence": 0.84, "evidence_segment_ids": ["seg_1", "seg_2"], "needs_more_info": False,
            "follow_up_questions": [], "label_info": {"materials": [], "care": []},
        },
        _decision("repair_self", "Die Sohle ist nur abgelöst, nichts ist gerissen. Neu verkleben mit Kontaktkleber hält gut. "
                  "Etwa 30 Minuten Arbeit plus 24 Stunden Aushärten.", "medium", [30, 40], [8, 15]),
        items, steps,
    )
