#!/usr/bin/env python3
"""Strip transcript text from a Pass 0 report before it is committed to the public repo.

Scoring needs only times, levels, tags, latency and haptics, so every utterance's
`text` and the free-form `notes` are blanked.

    python3 scripts/redact_report.py exported.json docs/evidence/<date>-<device>.json
"""
import json
import sys

source, target = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as f:
    report = json.load(f)

report["notes"] = ""
for session in report.get("sessions", []):
    for utterance in session.get("utterances", []):
        utterance["text"] = ""

with open(target, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
