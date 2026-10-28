"""Pydantic models mirroring the JSON contract in PRD section 8."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

ESTIMATE_NOTE = "Schätzung, keine Garantie"

Category = Literal["textile", "shoe", "low_voltage_electronics", "unsupported"]
RiskLevel = Literal["allowed", "warn_only", "professional"]
Stage = Literal["classify", "segment", "diagnose", "plan"]
SegmentSource = Literal["text", "tap", "grounding"]
StitchType = Literal["ladder_stitch", "running_stitch", "darning", "whip_stitch"]
Normalized = Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]


class Base(BaseModel):
    model_config = ConfigDict(extra="ignore")


# ---- Requests -------------------------------------------------------------


class ExtraImage(Base):
    purpose: Literal["label", "closeup", "other"]
    image_base64: Annotated[str, Field(max_length=25_000_000)]


class Answer(Base):
    question_id: str
    text: str


class AnalyzeRequest(Base):
    image_base64: Annotated[str, Field(max_length=25_000_000)]
    user_note: str | None = None
    extra_images: list[ExtraImage] = Field(default_factory=list, max_length=49)  # 50 images incl. main
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


class RefinePoint(Base):
    x: Normalized
    y: Normalized
    label: Literal["positive", "negative"]


class RefineRequest(Base):
    image_base64: Annotated[str, Field(max_length=25_000_000)]
    points: list[RefinePoint] = Field(default_factory=list, max_length=256)
    box: Annotated[list[Normalized], Field(min_length=4, max_length=4)] | None = None
    label: Annotated[str, Field(min_length=1, max_length=200, pattern=r"\S")]

    @model_validator(mode="after")
    def valid_geometry(self):
        if self.box is not None:
            x, y, w, h = self.box
            if w <= 0 or h <= 0 or x + w > 1 + 1e-9 or y + h > 1 + 1e-9:
                raise ValueError("Die Box muss vollständig im Bild liegen und eine positive Fläche haben.")
        elif not any(p.label == "positive" for p in self.points):
            raise ValueError("Bitte markiere die Schadstelle mit einer Box oder einem positiven Punkt.")
        return self


class TrackRequest(Base):
    video_base64: Annotated[str, Field(max_length=66_666_700)]
    concept: Annotated[str, Field(min_length=1, max_length=200, pattern=r"\S")]


class AfterPreviewRequest(Base):
    image_base64: Annotated[str, Field(max_length=25_000_000)]
    diagnosis_summary: Annotated[str, Field(min_length=1, max_length=2000, pattern=r"\S")]
    stitch_type: StitchType


class AfterPreviewResponse(Base):
    image_base64: str
    model: str


class GroundingResult(Base):
    concept: Literal["tear", "hole", "open seam", "frayed edge", "detached sole"]
    # Spark perception grounding: [x1, y1, x2, y2] on the 0..1000 grid.
    box: Annotated[list[Annotated[float, Field(allow_inf_nan=False)]], Field(min_length=4, max_length=4)] | None

    @model_validator(mode="after")
    def valid_box(self):
        if self.box is not None:
            x1, y1, x2, y2 = [max(0.0, min(1000.0, v)) for v in self.box]
            if x2 <= x1 or y2 <= y1:
                raise ValueError("Die lokalisierte Schadstelle muss eine positive Fläche haben.")
        return self


# ---- Model answer: prompt A -----------------------------------------------


class ClassifyResult(Base):
    category: Category
    risk_level: RiskLevel
    reason: str


# ---- Response parts ---------------------------------------------------------


class MaskRing(Base):
    points: list[Annotated[list[float], Field(min_length=2, max_length=2)]]
    hole: bool


class Mask(Base):
    """App-facing mask format: polygon in normalized image coordinates (0..1)."""

    format: Literal["polygon"] = "polygon"
    points: list[Annotated[list[float], Field(min_length=2, max_length=2)]]
    rings: list[MaskRing] | None = None


class Segment(Base):
    id: str
    label: str
    kind: Literal["part", "damage"]
    prompt: str
    box: Annotated[list[float], Field(min_length=4, max_length=4)]  # [x, y, w, h], normalized
    mask: Mask | None = None
    score: float
    source: SegmentSource | None = None


class TrackedSegment(Segment):
    object_id: str


class TrackFrame(Base):
    index: Annotated[int, Field(ge=0)]
    segments: list[TrackedSegment]


class TrackResponse(Base):
    frames: list[TrackFrame]
    fps: Annotated[float, Field(gt=0, allow_inf_nan=False)] | None = None


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
    stitch_type: StitchType | None = None
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
    instances: dict[str, Annotated[int, Field(ge=0)]] | None = None
