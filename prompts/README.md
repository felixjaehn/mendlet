# Prompts

Versioned system prompts for the three Muse Spark calls. The file names carry the version
(`prompt_<role>.v<N>.txt`); the active version of each prompt is pinned in `proxy/app/prompts.py`.

| Prompt | File | Purpose |
| --- | --- | --- |
| A | `prompt_a_classify.v2.txt` | Object, material and risk classification |
| B | `prompt_b_diagnose.v9.txt` | Diagnosis, repair plan and step-by-step guide |
| C | `prompt_c_step_help.v2.txt` | Help for a single repair step |

Versioning rules:

- Never edit a released prompt in place for a behaviour change. Add a new `.vN+1.txt`, point `PROMPTS` in
  `proxy/app/prompts.py` at it and re-run the benchmark. Superseded versions are removed from the tree and
  stay available in git history.
- The JSON schema block at the end of each file is generated from the Pydantic models. Regenerate it with
  `cd proxy && uv run python -m app.prompts --write`.
- `{language}` and `{estimate_note}` are the only placeholders; they are filled per request locale.
