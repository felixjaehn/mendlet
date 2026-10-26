"""Pydantic models mirroring the JSON contract in PRD section 8."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

ESTIMATE_NOTE = "Schätzung, keine Garantie"

Category = Literal["textile", "shoe", "low_voltage_electronics", "unsupported"]
RiskLevel = Literal["allowed", "warn_only", "professional"]
Stage = Literal["classify", "segment", "diagnose", "plan"]


class Base(BaseModel):
    model_config = ConfigDict(extra="ignore")


# ---- Requests -------------------------------------------------------------


class ExtraImage(Base):
    purpose: Literal["label", "closeup", "other"]
    image_base64: str


class Answer(Base):
    question_id: str
    text: str


class AnalyzeRequest(Base):
    image_base64: Annotated[str, Field(max_length=25_000_000)]
    user_note: str | None = None
    extra_images: list[ExtraImage] = []
    answers: list[Answer] = []
    locale: str = "de"
    mock_scenario: str | None = None  # ignored in real mode

    @property
    def note(self) -> str:
        return self.user_note or ""

    @property
    def is_followup_round(self) -> bool:
        return bool(self.answers) or bool(self.extra_images)


class StepRef(Base):
    n: int
    title: str
    text: str


class StepHelpRequest(Base):
    step: StepRef
    diagnosis_summary: str
    risk_level: RiskLevel
    issue_text: str
    image_base64: str | None = None


class StepHelpResponse(Base):
    answer: str
    retry_hint: str | None = None
    escalate: bool = False


# ---- Model answer: prompt A -----------------------------------------------


class ClassifyResult(Base):
    category: Category
    risk_level: RiskLevel
    reason: str


# ---- Response parts ---------------------------------------------------------


class Mask(Base):
    """App-facing mask format: polygon in normalized image coordinates (0..1)."""

    format: Literal["polygon"] = "polygon"
    points: list[Annotated[list[float], Field(min_length=2, max_length=2)]]


class Segment(Base):
    id: str
    label: str
    kind: Literal["part", "damage"]
    prompt: str
    box: Annotated[list[float], Field(min_length=4, max_length=4)]  # [x, y, w, h], normalized
    mask: Mask | None = None
    score: float


class Safety(Base):
    blocked: bool = False
    reason: str | None = None


class FollowUpQuestion(Base):
    id: str
    type: Literal["photo", "voice_or_text", "choice"]
    prompt: str
    purpose: Literal["label", "closeup", "other"] = "other"


class LabelInfo(Base):
    materials: list[str] = []
    care: list[str] = []


class Diagnosis(Base):
    summary: str
    likely_causes: list[str]
    confidence: float  # clamped to 0..1 by safety.enforce, not rejected by the parser
    evidence_segment_ids: list[str]
    needs_more_info: bool
    follow_up_questions: list[FollowUpQuestion] = []
    label_info: LabelInfo = LabelInfo()


class Decision(Base):
    recommendation: Literal["repair_self", "repair_pro", "replace"]
    reasoning: str
    effort: Literal["low", "medium", "high"]
    time_minutes: Annotated[list[int], Field(min_length=2, max_length=2)]
    cost_eur: Annotated[list[float], Field(min_length=2, max_length=2)]
    estimate_note: str = ESTIMATE_NOTE


class ShoppingItem(Base):
    id: str
    name: str
    kind: Literal["material", "tool"]
    quantity: str
    required: bool
    search_term: str
    household_alternative: str | None = None


class Overlay(Base):
    type: Literal["stitch_path", "highlight"]
    stitch_type: Literal["ladder_stitch", "running_stitch", "darning", "whip_stitch"] | None = None
    segment_id: str


class Step(Base):
    n: int
    title: str
    text: str
    common_mistake: str
    safety_critical: bool
    requires_confirmation: bool
    segment_ids: list[str] = []
    uses_items: list[str] = []
    overlay: Overlay | None = None


class Guide(Base):
    steps: list[Step] = []


# ---- Model answer: prompt B -----------------------------------------------


class DiagnosePlan(Base):
    diagnosis: Diagnosis
    decision: Decision
    shopping_list: list[ShoppingItem] = []
    guide: Guide = Guide()


# ---- Final /analyze response ------------------------------------------------


class AnalyzeResponse(Base):
    case_id: str
    category: Category
    risk_level: RiskLevel
    safety: Safety
    segments: list[Segment]
    diagnosis: Diagnosis
    decision: Decision
    shopping_list: list[ShoppingItem]
    guide: Guide
