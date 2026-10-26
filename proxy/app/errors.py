"""Application errors carrying a stable code and a German user-facing message."""


class AppError(Exception):
    def __init__(self, code: str, message: str, status: int = 500) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


class ModelOutputError(AppError):
    """Model answer was not valid JSON / violated the contract (after the single retry)."""

    def __init__(self, detail: str = "") -> None:
        super().__init__(
            "model_output_invalid",
            "Die Antwort des Modells war ungültig. Bitte versuche es erneut.",
            502,
        )
        self.detail = detail


class BudgetExceeded(AppError):
    def __init__(self, limit_usd: float) -> None:
        super().__init__(
            "budget_exceeded",
            f"Das Tageslimit für API-Kosten ({limit_usd:.2f} $) ist erreicht. "
            "Bitte versuche es morgen erneut.",
            429,
        )
