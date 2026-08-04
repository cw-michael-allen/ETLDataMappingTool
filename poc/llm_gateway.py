"""
Single point of contact for LLM-backed mapping suggestions.

Phase 0 (this file): calls the Anthropic API directly using a key from the
environment. Phase 2 requirement (see docs/PHASE_PLAN.md): calls must go
through CaseWorthy's internal API gateway for cost control. That gateway
doesn't exist yet to target from this POC — when it does, only this file
should need to change; every caller just imports `suggest_mapping`.
"""

import json
import os
import urllib.error
import urllib.request

API_URL = os.environ.get("ANTHROPIC_API_URL", "https://api.anthropic.com/v1/messages")
MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-5")
ANTHROPIC_VERSION = "2023-06-01"

SYSTEM_PROMPT = """You are helping a CaseWorthy data migration specialist map a customer's \
source system field to CaseWorthy's target ETL schema. You will be given a source field \
name/description and a list of valid target candidates. Respond with ONLY valid JSON, no \
markdown fences, no preamble, in this exact shape:
{"table": "<candidate table or null>", "field": "<candidate field or null>", "confidence": \
"high"|"medium"|"low"|"none", "reasoning": "<one short sentence>"}
Rules:
- Only choose table/field values that appear in the candidate list. Never invent a field.
- If the source field looks like a custom/organization-specific field with no reasonable \
match, set table and field to null and confidence to "none".
- Prefer exact or near-exact name matches, then semantic matches (e.g. "DOB" -> BirthDate).
- Keep reasoning under 20 words."""


def _no_key_response():
    return {
        "table": None,
        "field": None,
        "confidence": "none",
        "reasoning": "No ANTHROPIC_API_KEY set on the server — set that environment variable to enable suggestions.",
    }


def suggest_mapping(source_system, field_name, desc, candidates):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return _no_key_response()

    user_msg = json.dumps(
        {
            "sourceSystem": source_system,
            "sourceField": field_name,
            "sourceDescription": desc or "",
            "candidates": candidates,
        }
    )
    payload = {
        "model": MODEL,
        "max_tokens": 1000,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": user_msg}],
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": ANTHROPIC_VERSION,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        text_block = next((b for b in data.get("content", []) if b.get("type") == "text"), None)
        text = (text_block or {}).get("text", "")
        cleaned = text.replace("```json", "").replace("```", "").strip()
        parsed = json.loads(cleaned)
        if not isinstance(parsed, dict) or "confidence" not in parsed:
            raise ValueError("unexpected response shape")
        return parsed
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as e:
        return {
            "table": None,
            "field": None,
            "confidence": "none",
            "reasoning": f"Could not reach the mapping service ({e}) — please assign manually.",
        }
