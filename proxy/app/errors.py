"""Application errors carrying a stable code and a user-facing message (German, optional English)."""

from . import i18n


class AppError(Exception):
    def __init__(self, code: str, message: str, status: int = 500, en: str | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.message_en = en
        self.status = status

    def localized(self, locale: str | None = None) -> str:
        """The message in the request locale (set via i18n.set_current by the endpoints); German unless English exists."""
        return self.message_en if self.message_en and i18n.norm(locale or i18n.current()) == "en" else self.message


class ModelOutputError(AppError):
    """Model answer was not valid JSON / violated the contract (after the single retry)."""

    def __init__(self, detail: str = "") -> None:
        super().__init__(
            "model_output_invalid",
            "Die Antwort des Modells war ungültig. Bitte versuche es erneut.",
            502,
            "The model's answer was invalid. Please try again.",
        )
        self.detail = detail


class BudgetExceeded(AppError):
    def __init__(self, limit_usd: float) -> None:
        super().__init__(
            "budget_exceeded",
            f"Das Tageslimit für API-Kosten ({limit_usd:.2f} $) ist erreicht. Bitte versuche es morgen erneut.",
            429,
            f"The daily API cost limit (${limit_usd:.2f}) has been reached. Please try again tomorrow.",
        )
