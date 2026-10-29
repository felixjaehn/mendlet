"""Locale handling: German is the default, English is the second UI language.

`locale` comes from the request body (`"de"`, `"en"`, `"en-US"`, ...). Everything unknown falls back to German.
Texts that are model-facing or user-facing live here or next to the code that needs them as `{lang: text}` pairs.
"""

from contextvars import ContextVar
from typing import TypeVar

T = TypeVar("T")

DEFAULT = "de"
LANGUAGE_NAMES = {"de": "German (Deutsch)", "en": "English"}
_current: ContextVar[str] = ContextVar("locale", default=DEFAULT)


def norm(locale: str | None) -> str:
    code = (locale or DEFAULT).strip().lower().replace("_", "-").split("-")[0]
    return code if code in LANGUAGE_NAMES else DEFAULT


def language_name(locale: str | None) -> str:
    return LANGUAGE_NAMES[norm(locale)]


def set_current(locale: str | None) -> str:
    """Remember the request locale for AppError messages (context-local, so safe across concurrent requests)."""
    code = norm(locale)
    _current.set(code)
    return code


def current() -> str:
    return _current.get()


def pick(pair: dict[str, T], locale: str | None) -> T:
    return pair.get(norm(locale), pair[DEFAULT])


STAGE_LABELS: dict[str, dict[str, str]] = {
    "de": {
        "classify": "Objekt und Risiko prüfen",
        "segment": "Schadstelle markieren",
        "diagnose": "Schaden diagnostizieren",
        "plan": "Einkaufsliste und Anleitung erstellen",
    },
    "en": {
        "classify": "Checking object and risk",
        "segment": "Marking the damage",
        "diagnose": "Diagnosing the damage",
        "plan": "Creating shopping list and guide",
    },
}

GROUNDING_LABEL = {"de": "Schadstelle genauer lokalisieren", "en": "Locating the damage more precisely"}

# German segment label -> English (labels are produced from SAM prompts in sam.PROMPT_META and by the agent).
LABELS_EN: dict[str, str] = {
    "Riss": "Tear", "Loch": "Hole", "Offene Naht": "Open seam", "Ausgefranster Rand": "Frayed edge",
    "Kleidungsstück": "Garment", "Knopf": "Button", "Stoff": "Fabric", "Sohle": "Sole", "Naht": "Seam",
    "Abgelöste Sohle": "Detached sole", "Absatz": "Heel", "Kabelschaden": "Damaged wire", "Kabel": "Cable",
    "Stecker": "Connector", "Gehäuse": "Housing", "Rotes Kabel": "Red wire", "Schwarzes Kabel": "Black wire",
    "Abisoliertes Kabelende": "Stripped wire end", "Platine": "Circuit board", "Schadstelle": "Damaged area",
    "Lötpad +": "Solder pad +", "Lötpad −": "Solder pad −", "Lötpad": "Solder pad",
    "Etikett": "Label",
}


def label(label_de: str, locale: str | None) -> str:
    return LABELS_EN.get(label_de, label_de) if norm(locale) == "en" else label_de


def relabel(segments: list, locale: str | None) -> list:
    """Translate the German labels of `Segment`s for English requests (other labels, e.g. user-entered, stay)."""
    if norm(locale) != "en":
        return segments
    return [s.model_copy(update={"label": LABELS_EN[s.label]}) if s.label in LABELS_EN else s for s in segments]


ESTIMATE_NOTE = {"de": "Schätzung, keine Garantie", "en": "Estimate, no guarantee"}

AGENT_LABELS = {
    "segment": {"de": "SAM sucht „{}“", "en": "SAM is looking for “{}”"},
    "segment_at": {"de": "SAM segmentiert die Auswahl", "en": "SAM is segmenting the selection"},
    "locate": {"de": "Spark lokalisiert „{}“", "en": "Spark is locating “{}”"},
    "verify_mask": {"de": "Spark prüft Maske {}", "en": "Spark is checking mask {}"},
    "finish": {"de": "Masken geprüft · Übergabe an den Plan", "en": "Masks checked · handing over to the plan"},
}
