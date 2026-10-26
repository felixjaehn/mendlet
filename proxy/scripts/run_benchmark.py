"""Benchmark runner: runs every case through the pipeline and prints a markdown table.

Usage:  uv run python scripts/run_benchmark.py [--cases ../testdata/cases.example.json] [--fast]

Mock mode when META_API_KEY is unset (or MOCK_MODE=1). Image paths in the cases file are relative to
repair-assistant/testdata/. In mock mode, missing images are replaced by a blank placeholder.
Manual metrics (overlay on damage, diagnosis 0-2, decision plausible) are left blank for you to fill in.
"""

import argparse
import asyncio
import base64
import io
import json
import sys
import time
from dataclasses import replace
from pathlib import Path

PROXY_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROXY_DIR))

from PIL import Image  # noqa: E402

from app.budget import Budget  # noqa: E402
from app.clients import build_client  # noqa: E402
from app.config import REPO_DIR, Settings, load_dotenv  # noqa: E402
from app.errors import AppError  # noqa: E402
from app.images import prepare_request  # noqa: E402
from app.models import AnalyzeRequest  # noqa: E402
from app.pipeline import analyze  # noqa: E402

TESTDATA = REPO_DIR / "testdata"


def load_image(rel: str | None, mock: bool) -> str:
    path = TESTDATA / rel if rel else None
    if path and path.is_file():
        return base64.b64encode(path.read_bytes()).decode()
    if not mock:
        raise FileNotFoundError(f"missing image {rel}")
    buf = io.BytesIO()
    Image.new("RGB", (640, 480), (150, 150, 150)).save(buf, format="JPEG")
    return base64.b64encode(buf.getvalue()).decode()


async def run_case(case: dict, client, mock: bool) -> dict:
    row = {"id": case["id"], "group": case.get("group", ""), "error": None}
    expect = case.get("expect", {})
    start = time.perf_counter()
    try:
        req = AnalyzeRequest(
            image_base64=load_image(case.get("image"), mock),
            user_note=case.get("user_note"),
            mock_scenario=case.get("mock_scenario"),
        )
        resp = await analyze(prepare_request(req), client)
        if case.get("label_image") and resp.diagnosis.needs_more_info:  # second round with label photo
            req = AnalyzeRequest.model_validate({
                **req.model_dump(),
                "extra_images": [{"purpose": "label", "image_base64": load_image(case["label_image"], mock)}],
                "answers": [{"question_id": q.id, "text": case.get("answer", "")} for q in resp.diagnosis.follow_up_questions],
            })
            resp = await analyze(prepare_request(req), client)
        row.update(
            category=resp.category, risk=resp.risk_level, blocked=resp.safety.blocked,
            conf=resp.diagnosis.confidence, rec=resp.decision.recommendation,
            segs=len(resp.segments), steps=len(resp.guide.steps), items=len(resp.shopping_list),
        )
    except AppError as exc:
        row["error"] = exc.code
    row["seconds"] = time.perf_counter() - start
    row["category_ok"] = row.get("category") == expect.get("category") if "category" in expect else None
    row["blocked_ok"] = row.get("blocked") == expect["blocked"] if "blocked" in expect else None
    return row


def mark(v: bool | None) -> str:
    return "-" if v is None else ("ja" if v else "NEIN")


def report(rows: list[dict], mode: str) -> str:
    out = [f"# Benchmark ({mode})", "",
           "| Fall | Gruppe | Kategorie | Risiko | gesperrt | Konf. | Empfehlung | Segmente | Schritte | Sek. | Kat. ok | Sperre ok | Overlay ok | Diagnose 0-2 | Entscheidung ok |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        if r["error"]:
            out.append(f"| {r['id']} | {r['group']} | FEHLER: {r['error']} | | | | | | | {r['seconds']:.1f} | | | | | |")
            continue
        out.append(
            f"| {r['id']} | {r['group']} | {r['category']} | {r['risk']} | {r['blocked']} | {r['conf']:.2f} | {r['rec']} "
            f"| {r['segs']} | {r['steps']} | {r['seconds']:.1f} | {mark(r['category_ok'])} | {mark(r['blocked_ok'])} | | | |"
        )
    safety = [r for r in rows if r["group"] == "safety"]
    ok_safety = sum(1 for r in safety if r.get("blocked"))
    errors = sum(1 for r in rows if r["error"] == "model_output_invalid")
    lat = [r["seconds"] for r in rows if not r["error"] and r["group"] in ("textile", "shoe")]
    out += ["", "## Zusammenfassung", "",
            f"- Sicherheitsfälle gesperrt: {ok_safety} von {len(safety)} (Ziel: alle)",
            f"- Ungültiges JSON nach Retry: {errors} von {len(rows)} (Ziel: unter 5 %)",
            f"- Latenz Foto bis Ergebnis (Textil/Schuh): Mittel {sum(lat) / len(lat):.1f} s, Max {max(lat):.1f} s (Ziel: unter 30 s)" if lat else "- Latenz: keine Daten",
            f"- Fehler gesamt: {sum(1 for r in rows if r['error'])} von {len(rows)}",
            "", "_Mock-Modus: Zahlen sind Fixtures, keine Messung._" if mode == "mock" else ""]
    return "\n".join(out)


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", default=str(TESTDATA / "cases.json"))
    ap.add_argument("--fast", action="store_true", help="mock mode: no artificial delays")
    args = ap.parse_args()
    cases_path = Path(args.cases)
    if not cases_path.is_file():
        cases_path = TESTDATA / "cases.example.json"
    cases = json.loads(cases_path.read_text(encoding="utf-8"))["cases"]

    load_dotenv(PROXY_DIR / ".env")
    settings = Settings.from_env()
    if args.fast:
        settings = replace(settings, mock_delay_scale=0.0)
    budget = Budget(settings.cache_dir / "budget.json", settings.daily_budget_usd)
    client = build_client(settings, budget)
    rows = [await run_case(c, client, settings.mock_mode) for c in cases]
    print(report(rows, "mock" if settings.mock_mode else "real"))


if __name__ == "__main__":
    asyncio.run(main())
