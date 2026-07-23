#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PIPELINE_SCRIPTS = Path(__file__).resolve().parents[2] / "skills" / "extract-memory" / "scripts"
sys.path.insert(0, str(PIPELINE_SCRIPTS))
import run_pipeline as pipeline


STAGES = {
    "compression": ("memory-compressor", "00-evidence-capsule.json", "10-compressed.json"),
    "extraction": ("memory-extractor", "10-compressed.json", "20-extracted.json"),
    "formatting": ("memory-formatter", "20-extracted.json", "30-candidates.json"),
}


def summarize(stage: str, value: dict, atomic_ids: set[str]) -> dict:
    if stage != "formatting":
        keys = {
            "compression": ("claims", "evidence", "excluded", "conflicts"),
            "extraction": ("concepts", "facts", "decisions", "relations", "procedures", "problems"),
        }[stage]
        return {key: len(value.get(key, [])) for key in keys}
    candidates = value.get("candidates", [])
    dispositions = value.get("source_disposition", [])
    def counts(field: str) -> dict:
        result: dict[str, int] = {}
        for item in candidates:
            key = str(item.get(field, "missing"))
            result[key] = result.get(key, 0) + 1
        return result
    atomic_actions = {
        item.get("source_id"): item.get("action")
        for item in dispositions if item.get("source_id") in atomic_ids
    }
    return {
        "candidate_count": len(candidates),
        "actions": counts("action"),
        "types": counts("type"),
        "statuses": counts("status"),
        "source_disposition": {
            action: sum(1 for item in dispositions if item.get("action") == action)
            for action in sorted({item.get("action") for item in dispositions})
        },
        "atomic_source_count": len(atomic_ids),
        "atomic_sources_retained": sum(action == "retain" for action in atomic_actions.values()),
        "atomic_sources_replaced": sorted(source for source, action in atomic_actions.items() if action != "retain"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare one memory stage with an ad hoc model override")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--stage", choices=tuple(STAGES), required=True)
    parser.add_argument("--model", required=True, help="provider/model override")
    parser.add_argument("--label", required=True, help="short output label")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,31}", args.label):
        pipeline.fail("label must contain lowercase letters, digits, underscores, or hyphens")

    project = Path.cwd().resolve()
    runtime = project / ".workflow"
    run_dir = runtime / "runs" / "memory" / args.run_id
    workflow = runtime / "bin" / "workflow"
    agent, input_name, baseline_name = STAGES[args.stage]
    if not run_dir.is_dir() or not (run_dir / input_name).is_file() or not (run_dir / baseline_name).is_file():
        pipeline.fail("run is missing stage input or baseline output")

    capsule = json.loads((run_dir / "00-evidence-capsule.json").read_text(encoding="utf-8"))
    sources = capsule.get("sources", [])
    source_ids = {item.get("id") for item in sources if isinstance(item, dict)}
    note_ids = {item.get("id") for item in sources if isinstance(item, dict) and item.get("type") == "memory-note"}
    source_bodies = []
    atomic_ids: set[str] = set()
    for source in sources:
        path = project / source.get("path", "")
        if path.is_file():
            text = path.read_text(encoding="utf-8")
            source_bodies.append(text)
            if re.search(r"(?m)^type:\s*workflow_memory\s*$", "\n".join(text.splitlines()[:20])):
                atomic_ids.add(source.get("id"))

    output_name = baseline_name.replace(".json", f".{args.label}.json")
    output_path = run_dir / output_name
    prompt = (
        f"Load extract-memory and perform only the {args.stage} stage as an isolated comparison run. "
        f"Read {(run_dir / input_name).relative_to(project)} and write strict JSON to {output_path.relative_to(project)}. "
    )
    if args.stage == "compression":
        prompt += (
            f"Also read every source in the capsule and {(run_dir / '06-emotion-signals.json').relative_to(project)}. "
            "Emotion and user_signals are attention metadata, never evidence. "
        )
    elif args.stage == "formatting":
        prompt += (
            f"Also read {(run_dir / '10-compressed.json').relative_to(project)} and "
            f"{(run_dir / '00-evidence-capsule.json').relative_to(project)}. Existing type: workflow_memory notes are atomic: "
            "equivalent knowledge must be skip, stronger evidence is update, and their source disposition is retain. "
            "Never recreate or supersede atomic notes due to wording changes. Concept candidate subject and derived_from "
            "must use the exact extraction concept ID. "
        )
    prompt += "Do not apply memory, read unrelated files, invent semantics, or include Markdown fences."

    result = subprocess.run(
        [str(workflow), "run", "--agent", agent, "--model", args.model, prompt],
        cwd=project, text=True, capture_output=True, env=os.environ.copy(),
    )
    (run_dir / f"compare-{args.stage}-{args.label}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode != 0 or not output_path.is_file():
        pipeline.fail(f"comparison model failed; see compare-{args.stage}-{args.label}.log")
    value = json.loads(output_path.read_text(encoding="utf-8"))
    prior = {}
    if args.stage in {"extraction", "formatting"}:
        prior["compression"] = json.loads((run_dir / "10-compressed.json").read_text(encoding="utf-8"))
    if args.stage == "formatting":
        prior["extraction"] = json.loads((run_dir / "20-extracted.json").read_text(encoding="utf-8"))
    errors = pipeline.validate_stage(args.stage, value, source_ids, note_ids, prior, "\n".join(source_bodies))
    repair_attempted = False
    if errors:
        repair_attempted = True
        repair_prompt = (
            prompt
            + " Your previous comparison output failed deterministic validation with these errors: "
            + json.dumps(errors, ensure_ascii=False)
            + ". Rewrite the complete output, correcting only those contract violations."
        )
        repair = subprocess.run(
            [str(workflow), "run", "--agent", agent, "--model", args.model, repair_prompt],
            cwd=project, text=True, capture_output=True, env=os.environ.copy(),
        )
        with (run_dir / f"compare-{args.stage}-{args.label}.log").open("a", encoding="utf-8") as log:
            log.write("\n--- deterministic comparison repair ---\n")
            log.write(repair.stdout + repair.stderr)
        if repair.returncode == 0 and output_path.is_file():
            value = json.loads(output_path.read_text(encoding="utf-8"))
            errors = pipeline.validate_stage(args.stage, value, source_ids, note_ids, prior, "\n".join(source_bodies))
    baseline = json.loads((run_dir / baseline_name).read_text(encoding="utf-8"))
    report = {
        "schema_version": 1,
        "run_id": args.run_id,
        "stage": args.stage,
        "comparison": {"label": args.label, "model": args.model, "output": output_name, "valid": not errors, "errors": errors, "repair_attempted": repair_attempted, "summary": summarize(args.stage, value, atomic_ids)},
        "baseline": {"output": baseline_name, "summary": summarize(args.stage, baseline, atomic_ids)},
        "apply": False,
    }
    pipeline.write_json(run_dir / f"compare-{args.stage}-{args.label}.json", report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
