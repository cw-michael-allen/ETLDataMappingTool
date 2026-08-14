"""
Single point of contact for LLM-backed mapping suggestions.

Calls Claude via cw_services_toolkit.anthropic_ai (Teams/TeamExpressWay's own
copy of the org's shared toolkit lives alongside this project in the same
repo, at ServicesSharedUtilities/cw_services_toolkit/ -- see its README for
setup) rather than hitting the Anthropic API directly. That module shells out
to headless Claude Code (`claude -p`), authenticated via the user's own Claude
Team/Enterprise subscription login -- no API key, no ANTHROPIC_API_KEY env
var, nothing for this file to hold or leak. This replaces this file's
original direct-urllib-call implementation (see git history), which predates
the toolkit existing; that's also why this migration closes out the SSRF/
API_URL-scheme-validation concern a security scan raised against the old
version -- there's no longer a configurable request URL in this file at all.

Lazy-imported (matching poc/create_template.py's own _load_openpyxl()
convention): cw_services_toolkit isn't on this repo's stdlib-only dependency
list, so an install that never touched it (or whose Python version the
toolkit's own pyproject.toml excludes -- it requires 3.13.14+, excluding
3.14.0-3.14.5, for CVE-2026-7210's fix) still runs fine, same as today's
"no ANTHROPIC_API_KEY set" case -- suggestions just come back as "no
confident match" instead of the app failing to start. See poc/README.md's
"Mapping suggestions (LLM fallback)" section for the real setup steps
(install Claude Code, log in once, install the toolkit).
"""

import json

_anthropic_ai = None
_anthropic_ai_unavailable = None

DEFAULT_TARGET_LABEL = "CaseWorthy"

# The target application is a parameter, not a constant: CaseWorthy and
# ServTracker are separate products with separate schemas, and telling the model
# it's mapping to CaseWorthy while handing it ServTracker candidates is simply
# wrong -- it invites the model to reason from the wrong product's conventions.
#
# No JSON-formatting instructions here anymore -- ask_structured()'s schema
# (RESPONSE_SCHEMA below) is enforced natively by Claude Code itself
# (--json-schema), not by asking the model nicely and hoping it complies,
# which is what this file's previous direct-API implementation had to do
# (see git history: it stripped markdown fences and manually json.loads()'d
# the response text).
SYSTEM_PROMPT_TEMPLATE = """You are helping a CaseWorthy data migration specialist map a \
customer's source field to {target}'s target ETL schema. You will be given a source field \
name/description and a list of valid target candidates.
Rules:
- Only choose table/field values that appear in the candidate list. Never invent a field.
- If the source field looks like a custom/organization-specific field with no reasonable \
match, set table and field to null and confidence to "none".
- Prefer exact or near-exact name matches, then semantic matches (e.g. "DOB" -> BirthDate).
- Keep reasoning under 20 words."""

RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {"type": ["string", "null"]},
        "field": {"type": ["string", "null"]},
        "confidence": {"type": "string", "enum": ["high", "medium", "low", "none"]},
        "reasoning": {"type": "string"},
    },
    "required": ["table", "field", "confidence", "reasoning"],
}


def _load_anthropic_ai():
    global _anthropic_ai, _anthropic_ai_unavailable
    if _anthropic_ai is not None or _anthropic_ai_unavailable is not None:
        return _anthropic_ai
    try:
        from cw_services_toolkit import anthropic_ai
        _anthropic_ai = anthropic_ai
    except ImportError:
        _anthropic_ai_unavailable = (
            "cw_services_toolkit isn't installed -- suggestions will come back as "
            "'no confident match' until it is. See poc/README.md, "
            "\"Mapping suggestions (LLM fallback)\"."
        )
    return _anthropic_ai


def _fallback_response(reasoning):
    return {"table": None, "field": None, "confidence": "none", "reasoning": reasoning}


def is_available():
    """Whether cw_services_toolkit.anthropic_ai is importable -- doesn't
    confirm Claude Code is actually installed/logged in (that's only known
    at call time, see suggest_mapping's own AnthropicAIError handling), just
    that suggest_mapping has a real chance of reaching it rather than
    degrading straight to "no confident match". For app.py's own startup
    banner."""
    return _load_anthropic_ai() is not None


def suggest_mapping(source_system, field_name, desc, candidates, target_label=DEFAULT_TARGET_LABEL):
    anthropic_ai = _load_anthropic_ai()
    if anthropic_ai is None:
        return _fallback_response(_anthropic_ai_unavailable)

    system_prompt = SYSTEM_PROMPT_TEMPLATE.format(target=target_label or DEFAULT_TARGET_LABEL)
    user_msg = json.dumps(
        {
            "sourceSystem": source_system,
            "sourceField": field_name,
            "sourceDescription": desc or "",
            "candidates": candidates,
        }
    )
    try:
        resp = anthropic_ai.ask_structured(user_msg, schema=RESPONSE_SCHEMA, system=system_prompt)
        parsed = resp.data
        if not isinstance(parsed, dict) or "confidence" not in parsed:
            raise ValueError("unexpected response shape")
        return parsed
    except (anthropic_ai.AnthropicAIError, ValueError) as e:
        # Exception messages here are already actionable (e.g.
        # ClaudeCLINotFoundError/AuthenticationError spell out exactly what
        # to install/run) -- surfaced as-is rather than replaced with a
        # generic message.
        return _fallback_response(f"Could not reach the mapping service ({e}) — please assign manually.")
