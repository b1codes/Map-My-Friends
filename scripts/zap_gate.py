#!/usr/bin/env python3
"""Decides whether a ZAP scan passes, from its JSON report and .zap/rules.tsv.

    scripts/zap_gate.py build/dast/zap-report.json .zap/rules.tsv

ZAP's own scripts treat every rule as WARN unless the config says otherwise,
so on their own they'd let a new high-risk alert through. Here the default
follows the alert's risk instead:

    High, Medium  -> FAIL
    Low           -> WARN
    Informational -> INFO

and a line in the rules file overrides it for one rule (by plugin id):
IGNORE, INFO, WARN or FAIL, or OUTOFSCOPE with a URL regex to drop only the
matching instances. The same file is passed to ZAP with -c, which also stops
it running active rules set to IGNORE.

Exits 1 if anything FAILs. Writes a Markdown summary to $GITHUB_STEP_SUMMARY
when that's set. Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

LEVELS = ("IGNORE", "INFO", "WARN", "FAIL")
DEFAULT_BY_RISK = {"3": "FAIL", "2": "FAIL", "1": "WARN", "0": "INFO"}
RISK_NAMES = {"3": "High", "2": "Medium", "1": "Low", "0": "Informational"}


def load_rules(path: Path):
    levels, reasons, out_of_scope = {}, {}, {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 3:
            sys.exit(f"{path}:{number}: expected tab-separated id, level, name/regex[, reason]")
        rule_id, level = fields[0], fields[1]
        if level == "OUTOFSCOPE":
            for one in rule_id.split(","):
                out_of_scope.setdefault(one, []).append(re.compile(fields[2]))
            continue
        if level not in LEVELS:
            sys.exit(f"{path}:{number}: unknown level {level!r}")
        if level in ("IGNORE", "INFO", "WARN") and (len(fields) < 4 or not fields[3].strip()):
            sys.exit(f"{path}:{number}: {level} needs a reason in the fourth column")
        levels[rule_id] = level
        reasons[rule_id] = fields[3].strip() if len(fields) > 3 else ""
    return levels, reasons, out_of_scope


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    levels, reasons, out_of_scope = load_rules(Path(sys.argv[2]))

    results = []  # (level, risk, plugin id, name, instances, total, reason)
    for site in report.get("site", []):
        for alert in site.get("alerts", []):
            plugin = str(alert["pluginid"])
            scopes = out_of_scope.get(plugin, []) + out_of_scope.get("*", [])
            instances = [
                i for i in alert.get("instances", []) if not any(s.match(i.get("uri", "")) for s in scopes)
            ]
            if not instances:
                continue
            # The report keeps a sample of instances; count is the total.
            total = len(instances) if scopes else int(alert.get("count", len(instances)))
            level = levels.get(plugin, DEFAULT_BY_RISK.get(str(alert["riskcode"]), "WARN"))
            results.append(
                (level, str(alert["riskcode"]), plugin, alert["name"], instances, total, reasons.get(plugin, ""))
            )

    order = {level: i for i, level in enumerate(reversed(LEVELS))}
    results.sort(key=lambda r: (order[r[0]], -int(r[1]), r[2]))
    lines = []
    for level, risk, plugin, name, instances, total, reason in results:
        lines.append(f"{level}: [{plugin}] {name} ({RISK_NAMES.get(risk, risk)}) x {total}")
        if reason:
            lines.append(f"    {reason}")
        if level in ("FAIL", "WARN"):
            for instance in instances[:5]:
                evidence = (instance.get("evidence") or "").replace("\n", " ")[:120]
                param = instance.get("param") or ""
                lines.append(
                    f"    {instance.get('method', '')} {instance.get('uri', '')}"
                    + (f" param={param}" if param else "")
                    + (f" evidence={evidence!r}" if evidence else "")
                )
            if total > 5:
                lines.append(f"    ... and {total - 5} more in the report")

    failures = sum(1 for r in results if r[0] == "FAIL")
    counts = {level: sum(1 for r in results if r[0] == level) for level in LEVELS}
    summary = "ZAP gate: " + ", ".join(f"{counts[level]} {level}" for level in reversed(LEVELS))
    print("\n".join(lines))
    print(summary)

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as f:
            f.write(f"### ZAP API scan\n\n{summary}\n\n```\n" + "\n".join(lines) + "\n```\n")

    if failures:
        print(
            "Medium and high alerts fail the scan. Fix them, or triage one in .zap/rules.tsv "
            "with a reason (see docs/testing.md, Security scans).",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
