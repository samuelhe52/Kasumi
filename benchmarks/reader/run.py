#!/usr/bin/env python3
"""Sequential, repository-owned benchmark runner. Python standard library only."""
import argparse
import datetime
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SCHEMA = 1
SEED = 20261117
LATENCY_GEOMETRY = {"width": 1179, "height": 701, "fontSize": 18, "scale": 2, "colorSpace": "sRGB SDR"}
MEMORY_GEOMETRY = {"width": 900, "height": 714, "fontSize": 18, "scale": 1, "colorSpace": "sRGB SDR"}
PHASES = {"cold", "warm", "resize", "afterPrepare", "paint", "find", "memory"}


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def quantile(values, p):
    ordered = sorted(values)
    if not ordered or any(not math.isfinite(x) or x < 0 for x in ordered):
        raise ValueError("empty, negative or non-finite observations")
    return ordered[max(0, math.ceil(len(ordered) * p) - 1)]


def stats(values):
    return {"n": len(values), "p50": quantile(values, .5),
            "p95": quantile(values, .95) if len(values) >= 100 else None,
            "p99": quantile(values, .99) if len(values) >= 1000 else None,
            "max": max(values)}


def command_info(args):
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    if result.returncode:
        raise RuntimeError("metadata command failed: " + repr(args) + "\n" + result.stdout)
    return result.stdout.strip()


def provenance(binary, native):
    # Hash actual tracked and nonignored untracked source bytes, including symlinks.
    names = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT).split(b"\0")
    files = {}
    for name in sorted(set(names)):
        if not name:
            continue
        relative = os.fsdecode(name)
        # Baseline outputs are measurements, not build inputs. Exclude them to avoid self-reference.
        if relative.startswith("benchmarks/reader/baselines/"):
            continue
        path = ROOT / relative
        if path.is_file():
            files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            files[relative] = "deleted"
    diff = subprocess.check_output(["git", "diff", "HEAD", "--binary"], cwd=ROOT)
    status = command_info(["git", "status", "--porcelain"])
    return {
        "revision": command_info(["git", "rev-parse", "HEAD"]), "dirty": bool(status), "gitStatus": status,
        "trackedDiffSHA256": hashlib.sha256(diff).hexdigest(),
        "sourceTreeSHA256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(), "sourceFiles": files,
        "host": {"os": command_info(["sw_vers"]), "cpu": command_info(["sysctl", "-n", "machdep.cpu.brand_string"]),
                 "model": command_info(["sysctl", "-n", "hw.model"]), "memoryBytes": int(command_info(["sysctl", "-n", "hw.memsize"])),
                 "architecture": platform.machine(), "power": command_info(["pmset", "-g", "batt"]),
                 "swift": command_info(["swift", "--version"]), "xcode": command_info(["xcodebuild", "-version"])},
        "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "nativeBinarySHA256": hashlib.sha256(native.read_bytes()).hexdigest() if native else None,
        "buildCommand": "swift build -c release --product KasumiReaderBench --scratch-path .build/bench",
        "scratchPath": ".build/bench", "seed": SEED,
    }


def verify_corpus(actual, expected, directory):
    if actual != expected:
        raise ValueError("corpus manifest changed: inspect generator and deliberately update corpus.json")
    ids = set()
    for case in actual["cases"]:
        if case["id"] in ids:
            raise ValueError("duplicate corpus case")
        ids.add(case["id"])
        data = (directory / (case["id"] + ".md")).read_bytes()
        if hashlib.sha256(data).hexdigest() != case["sha256"] or len(data) != case["utf8Bytes"]:
            raise ValueError("sample bytes do not match manifest")
        if len(data.decode("utf-8").encode("utf-16-le")) // 2 != case["utf16Units"]:
            raise ValueError("sample UTF16 length does not match manifest")


def validate_worker(data, phase, case):
    if data.get("schema") != SCHEMA or data.get("phase") != phase or data.get("case") != case:
        raise ValueError("wrong worker schema, phase or corpus identity")
    if data.get("valid") is not True or not isinstance(data.get("result"), dict):
        raise ValueError("invalid worker result")
    result = data["result"]
    if phase in ["cold", "warm"]:
        required = {"parseMs", "sessionSetupMs", "firstSnapshotMs", "firstPaintMs", "sourceToFirstBitmapMs"}
        if phase == "cold":
            required.add("fileToFirstBitmapMs")
        if set(data["result"].get("timings", {})) != required:
            raise ValueError("missing opening timing")
        quantile(list(data["result"]["timings"].values()), .5)
    if phase == "afterPrepare":
        if result.get("eligible") != (not case.startswith("single-")):
            raise ValueError("unexpected preparation eligibility")
        quantile([result["prepareMs"], result["widthChangeAfterPrepareMs"]], .5)
    if phase == "resize":
        rows = result["widthSamples"]
        if {r["width"] for r in rows} != {1179, 1000, 900, 440} or not result["refinementSamples"]:
            raise ValueError("missing resize/refinement observations")
        for row in rows:
            quantile([row[k] for k in ["layoutMs", "paintMs", "oldSnapshotReleaseMs"]], .5)
        for row in result["refinementSamples"]:
            quantile([row["movingAnchorMs"], row["sameWidthMs"]], .5)
    if phase == "find":
        if not result["samples"]:
            raise ValueError("missing Find observations")
        for row in result["samples"]:
            if row["matches"] <= 0:
                raise ValueError("missing Find matches")
            quantile([row[k] for k in ["searchMissMs", "searchHitMs", "remapIndexMs", "viewportGeometryMs"]], .5)
        quantile([result["wholeDocumentSelectionMs"]], .5)
    if phase == "memory":
        if data.get("geometry") != {"width": 900, "height": 714, "fontSize": 18, "scale": 1}:
            raise ValueError("wrong memory geometry")
        stages = {s["stage"] for s in data["result"].get("samples", [])}
        if stages != {"afterParse", "afterFirstViewport", "preparedAndOneViewport", "afterFullTraversal"}:
            raise ValueError("missing memory stage")
        for row in result["samples"]:
            if any(row["memory"][k] <= 0 for k in ["physicalFootprintBytes", "peakPhysicalFootprintBytes", "residentBytes", "peakResidentBytes"]):
                raise ValueError("invalid memory observation")
    if phase == "paint":
        sessions = data["result"]["sessions"]
        if not sessions:
            raise ValueError("no traversal pairs")
        for session in sessions:
            if not session["tops"] or len(session["tops"]) != len(session["firstMs"]) or len(session["tops"]) != len(session["returnMs"]):
                raise ValueError("incomplete traversal pair")
            quantile(session["firstMs"], .5)
            quantile(session["returnMs"], .5)
    return data


def validate_native(data, phase):
    if data.get("schema") != 1 or len(data.get("results", [])) != 2:
        raise ValueError("invalid native result schema")
    for row in data["results"]:
        if not row["settledViewportMeasured"] or row["samples"] <= 0:
            raise ValueError("native did not settle")
        if phase != "nativeFastControl" and row["uncoveredSamples"] != 0:
            raise ValueError("native coverage miss")
        if phase == "nativeFast" and not row["fullyMeasuredBeforeTraversal"]:
            raise ValueError("native fast traversal started before readiness")
    if "processMemory" not in data:
        raise ValueError("native process memory absent")


def child(args, output, phase, case, record, timeout=300, env=None):
    log = output.with_suffix(".log")
    started = time.monotonic()
    entry = {"id": output.stem, "phase": phase, "case": case, "status": "running"}
    record.append(entry)
    try:
        with log.open("wb") as stream:
            proc = subprocess.Popen(args, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, env=env)
            try:
                code = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise RuntimeError("child timeout after %ss; partial output retained" % timeout)
            except BaseException:
                proc.kill()
                proc.wait()
                raise
        if code:
            raise RuntimeError("child exited %s; see %s" % (code, log.name))
        data = json.loads(output.read_text())
        if phase.startswith("native"):
            validate_native(data, phase)
        else:
            validate_worker(data, phase, case)
        entry.update(status="passed", raw=data)
        return data
    except Exception as error:
        entry.update(status="failed", error=str(error))
        # Retain partial/bad JSON at its original path, and a bounded log in the portable archive.
        entry["log"] = log.read_text(errors="replace")[-16000:] if log.exists() else ""
        raise
    finally:
        entry["processWallMs"] = (time.monotonic() - started) * 1000


def summarize(records, planned):
    output = {"schema": SCHEMA, "complete": all(r["status"] == "passed" for r in records) and len(records) == len(planned),
              "plannedChildren": len(planned), "finishedChildren": len(records),
              "failedChildren": [{k: v for k, v in r.items() if k != "raw"} for r in records if r["status"] != "passed"],
              "missingChildren": [job for job in planned if job[0] not in {r["id"] for r in records}], "cases": {}, "native": {}}
    good = [r for r in records if r["status"] == "passed"]
    for case in sorted({r["case"] for r in good if r["case"] is not None}):
        rows = [r for r in good if r["case"] == case]
        summary = {}
        for phase in ["cold", "warm"]:
            phase_rows = [r["raw"] for r in rows if r["phase"] == phase]
            if phase_rows:
                summary[phase] = {metric: stats([r["result"]["timings"][metric] for r in phase_rows])
                                  for metric in phase_rows[0]["result"]["timings"]}
                summary[phase]["readDecodeMs"] = stats([r["readDecodeMs"] for r in phase_rows])
        resize = [r["raw"]["result"] for r in rows if r["phase"] == "resize"]
        if resize:
            data = resize[0]
            summary["resize"] = {}
            for width in [1179, 1000, 900, 440]:
                observations = [v for v in data["widthSamples"] if v["width"] == width]
                summary["resize"][str(width)] = {k: stats([r[k] for r in observations]) for k in ["layoutMs", "paintMs", "oldSnapshotReleaseMs"]}
            summary["refinement"] = {k: stats([r[k] for r in data["refinementSamples"]]) for k in ["movingAnchorMs", "sameWidthMs"]}
        prep = [r["raw"]["result"] for r in rows if r["phase"] == "afterPrepare"]
        if prep:
            summary["preparation"] = {k: stats([r[k] for r in prep]) for k in ["prepareMs", "widthChangeAfterPrepareMs"]}
            summary["preparation"]["eligible"] = prep[0]["eligible"]
        paint = [r["raw"]["result"] for r in rows if r["phase"] == "paint"]
        if paint:
            sessions = paint[0]["sessions"]
            summary["paint"] = {"sessionCount": len(sessions)}
            for phase in ["firstMs", "returnMs"]:
                pooled = [x for s in sessions for x in s[phase]]
                summary["paint"][phase] = stats(pooled)
                session_stats = [{"session": s["session"], "n": len(s[phase]), "median": quantile(s[phase], .5),
                                  "empiricalP95": quantile(s[phase], .95)} for s in sessions]
                threshold = quantile(pooled, .99)
                tails = [sum(x >= threshold for x in s[phase]) for s in sessions]
                largest = max(tails) / sum(tails)
                summary["paint"][phase].update(sessionStatistics=session_stats,
                    sessionMedianRange=[min(s["median"] for s in session_stats), max(s["median"] for s in session_stats)],
                    sessionEmpiricalP95Range=[min(s["empiricalP95"] for s in session_stats), max(s["empiricalP95"] for s in session_stats)],
                    largestSessionShareOfTopOnePercent=largest,
                    tailDominatedByOneSession=len(sessions) > 1 and largest > .5)
        find = [r["raw"]["result"] for r in rows if r["phase"] == "find"]
        if find:
            data = find[0]
            summary["find"] = {k: stats([r[k] for r in data["samples"]]) for k in ["searchMissMs", "searchHitMs", "remapIndexMs", "viewportGeometryMs"]}
            summary["find"].update(query=data["query"], matches=data["samples"][0]["matches"],
                                   wholeDocumentSelectionMs=data["wholeDocumentSelectionMs"], wholeDocumentRectangles=data["wholeDocumentRectangles"])
        memory = [r["raw"]["result"] for r in rows if r["phase"] == "memory"]
        if memory:
            summary["memory"] = memory[0]
        output["cases"][case] = summary
    for r in good:
        if r["phase"].startswith("native"):
            output["native"][r["phase"]] = r["raw"]
    output["hostFlags"] = []
    for r in good:
        raw = r["raw"]
        for state in [raw.get("hostStart", {}), raw.get("hostEnd", {}), raw.get("hostState", {})]:
            if state.get("thermalState", 0) > 0:
                output["hostFlags"].append(r["id"] + ": thermal state above nominal")
            if state.get("lowPowerMode"):
                output["hostFlags"].append(r["id"] + ": Low Power Mode")
    return output


def fmt(value):
    return "—" if value is None else "%.2f" % value


def report(summary, manifest):
    lines = ["# Reader benchmark baseline", "", "Run: `%s`; renderer revision `%s`. Profile: **%s**. Complete: **%s**." %
             (manifest["startedUTC"], manifest["provenance"]["revision"][:12], manifest["profile"], summary["complete"]), "",
             "Host: %s; %s. Standard Release, isolated `.build/bench`." %
             (manifest["provenance"]["host"]["cpu"], manifest["provenance"]["host"]["os"].replace("\n", "; ")), "",
             "Times are milliseconds; memory uses decimal MB. Cold means a fresh process with OS/font caches intact. "
             "Engine measurements exclude UIKit/AppKit installation and physical display presentation. "
             "No timing thresholds are asserted. p95 requires n≥100, p99 n≥1000; — means insufficient samples. "
             "Pooled paint observations are correlated within sessions, not independent confidence estimates. Maxima are observed maxima.", "",
             "Latency: 1179×701 pt, font18, 2× sRGB SDR. Resize uses widths1179/1000/900/440 and the same height/font/scale. "
             "Memory: 900×714 pt, font18, 1× SDR, reusable traversal context; every memory row has n=1. "
             "These geometries are separate comparison keys.", "",
             "## Opening and preparation", "", "| Case | Cold parse p50 | Cold first viewport p50 | Cold first paint p50 | Warm viewport p50 | Full prep p50 | First width change after prep p50 |", "|---|---:|---:|---:|---:|---:|---:|"]
    for case, data in summary["cases"].items():
        def metric(phase, key):
            return fmt(data.get(phase, {}).get(key, {}).get("p50"))
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (case, metric("cold", "parseMs"), metric("cold", "firstSnapshotMs"),
                     metric("cold", "firstPaintMs"), metric("warm", "firstSnapshotMs"), metric("preparation", "prepareMs"),
                     metric("preparation", "widthChangeAfterPrepareMs")))
    lines += ["", "Full preparation is measured after the first viewport; it is not first-screen loading. "
              "Single50k is outside the preparation envelope; its prepare number is an eligibility check returning nil.", "",
              "## Paint traversal", "", "| Case | Sessions / n each way | First p50 / p95 / p99 / max | Return p50 / p95 / p99 / max | First session median range | Return session median range |", "|---|---:|---:|---:|---:|---:|"]
    for case, data in summary["cases"].items():
        if "paint" not in data:
            continue
        p = data["paint"]; a, b = p["firstMs"], p["returnMs"]
        lines.append("| %s | %s / %s | %s | %s | %s | %s |" % (case, p["sessionCount"], a["n"],
                     " / ".join(fmt(a[k]) for k in ["p50", "p95", "p99", "max"]),
                     " / ".join(fmt(b[k]) for k in ["p50", "p95", "p99", "max"]),
                     "–".join(fmt(x) for x in a["sessionMedianRange"]), "–".join(fmt(x) for x in b["sessionMedianRange"])))
    lines += ["", "Complete forward/reverse pairs with a fresh session per pair; parsing, prep and release excluded. "
              "Bitmap/context/image creation included. Per-session empirical p95 ranges and tail concentration are in summary.json. "
              "Single50k uses a full-layout fallback and only one traversal pair.", "", "## Resize, refinement and Find", "",
              "| Case | Layout p50 @1179 / 1000 / 900 / 440 | Paint p50 @1179 / 1000 / 900 / 440 | Release max | Moving-anchor p50 / p95 | Find search miss / hit p50 | Find viewport geometry p50 / max |", "|---|---:|---:|---:|---:|---:|---:|"]
    for case, data in summary["cases"].items():
        if "resize" not in data:
            continue
        r, f = data["resize"], data.get("find", {})
        lines.append("| %s | %s | %s | %s | %s / %s | %s / %s | %s / %s |" % (case,
            " / ".join(fmt(r[str(w)]["layoutMs"]["p50"]) for w in [1179,1000,900,440]),
            " / ".join(fmt(r[str(w)]["paintMs"]["p50"]) for w in [1179,1000,900,440]),
            fmt(max(r[str(w)]["oldSnapshotReleaseMs"]["max"] for w in [1179,1000,900,440])),
            fmt(data["refinement"]["movingAnchorMs"]["p50"]), fmt(data["refinement"]["movingAnchorMs"]["p95"]),
            fmt(f.get("searchMissMs", {}).get("p50")), fmt(f.get("searchHitMs", {}).get("p50")), fmt(f.get("viewportGeometryMs", {}).get("p50")), fmt(f.get("viewportGeometryMs", {}).get("max"))))
    lines += ["", "Find measures the real reader search/cache and highlight-index helpers; match remapping and whole-document selection are also retained in summary.json. "
              "Snapshot release excludes session/cache destruction. No UI installation cost is inferred.", "", "## Retained engine memory", "",
              "| Case (n=1) | First viewport footprint / RSS | Prepared + one viewport, settled footprint / RSS | After full traversal, settled footprint / RSS | Lifetime peak footprint / RSS |", "|---|---:|---:|---:|---:|"]
    for case, data in summary["cases"].items():
        if "memory" not in data:
            continue
        samples = data["memory"]["samples"]
        def mem(stage):
            return [s["memory"] for s in samples if s["stage"] == stage][-1]
        def pair(m, prefix=""):
            keys = ["physicalFootprintBytes", "residentBytes"] if not prefix else ["peakPhysicalFootprintBytes", "peakResidentBytes"]
            return " / ".join(fmt(m[k] / 1e6) for k in keys)
        lines.append("| %s | %s | %s | %s | %s |" % (case, pair(mem("afterFirstViewport")), pair(mem("preparedAndOneViewport")),
                     pair(mem("afterFullTraversal")), pair(mem("afterFullTraversal"), "peak")))
    lines += ["", "Settled means the last explicitly timed idle observation, not proof of an eventual plateau. "
              "Both current footprint/RSS and lifetime peaks are recorded independently. Native app memory below includes additional AppKit/buffer costs.", "",
              "## Native AppKit coverage", "", "| Scenario | Nominal size | Ready before traversal | Missed / sampled | Maximum sampled gap ms | Process peak footprint / RSS MB |", "|---|---:|---|---:|---:|---:|"]
    for phase, native in summary["native"].items():
        memory = native["processMemory"]
        for row in native["results"]:
            lines.append("| %s | %s | %s | %s / %s | %s | %s / %s |" % (phase, row["nominalCharacters"], row["fullyMeasuredBeforeTraversal"],
                         row["uncoveredSamples"], row["samples"], fmt(row["maximumCoverageGapMs"]),
                         fmt(memory["peakPhysicalFootprintBytes"] / 1e6), fmt(memory["peakResidentBytes"] / 1e6)))
    lines += ["", "Native coverage is conservative layout metadata sampled around controller scrolling, not frame presentation or pixel evidence for every frame. "
              "Fast-control disables idle preparation; its misses are diagnostic, not a passing target. Native scenarios each hold both sizes in one process. "
              "Physical-device FPS, UIKit tiles and iPhone memory remain unmeasured.", "", "## Validity and host flags", "",
              "Children: %s planned; %s finished. Failed: %s; missing: %s." %
              (summary["plannedChildren"], summary["finishedChildren"], len(summary["failedChildren"]), len(summary["missingChildren"]))]
    flags = summary["hostFlags"]
    lines += ["", "Host warnings: " + ("; ".join(sorted(set(flags))) if flags else "none observed in worker snapshots.")]
    dominated = [case + ": " + phase for case, d in summary["cases"].items() for phase in ["firstMs", "returnMs"]
                 if d.get("paint", {}).get(phase, {}).get("tailDominatedByOneSession")]
    if dominated:
        lines += ["", "More than half of pooled top-1% observations came from one session in: " + "; ".join(dominated) + "."]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile", choices=["quick", "full"], default="quick")
    parser.add_argument("--native", type=Path)
    parser.add_argument("--corpus-only", action="store_true")
    args = parser.parse_args()
    binary = args.binary.resolve(); native = args.native.resolve() if args.native else None
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)  # Never overwrite or mix runs.
    samples_dir = output / "samples"; raw_dir = output / "cases"; raw_dir.mkdir()
    subprocess.run([str(binary), "--corpus", str(samples_dir)], cwd=ROOT, check=True, timeout=30)
    actual = json.loads((samples_dir / "manifest.json").read_text())
    verify_corpus(actual, json.loads((HERE / "corpus.json").read_text()), samples_dir)
    if args.corpus_only:
        print("Verified and exported %s fixed Markdown samples to %s" % (len(actual["cases"]), samples_dir))
        return
    manifest = {"schema": SCHEMA, "startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "profile": args.profile, "provenance": provenance(binary, native), "corpus": actual,
                "latencyGeometry": LATENCY_GEOMETRY, "memoryGeometry": MEMORY_GEOMETRY,
                "statistics": {"method": "nearest rank", "p95MinimumN": 100, "p99MinimumN": 1000}}
    dump(output / "manifest.json", manifest)
    cases = [c["id"] for c in actual["cases"]]
    if args.profile == "quick":
        cases = ["english-50000", "chinese-50000", "mixed-50000", "mixed-200000", "single-50000"]
    rng = random.Random(SEED)
    jobs = []
    # Seeded round-robin ordering: do not give every cold repetition of one case the same host-time slice.
    for phase, repetitions in [("cold", 10 if args.profile == "full" else 2), ("warm", 50 if args.profile == "full" else 3),
                                ("resize", 1), ("afterPrepare", 5 if args.profile == "full" else 1), ("paint", 1), ("find", 1)]:
        for repetition in range(repetitions):
            order = list(cases); rng.shuffle(order)
            for case in order:
                jobs.append(("%s-%s-%03d" % (phase, case, repetition), phase, case))
    memory_cases = ["english-50000", "english-200000", "chinese-50000", "chinese-200000", "mixed-50000", "mixed-200000"] if args.profile == "full" else ["mixed-200000"]
    rng.shuffle(memory_cases)
    jobs += [("memory-" + case, "memory", case) for case in memory_cases]
    if native:
        jobs += [(phase, phase, None) for phase in ["nativeOrdinary", "nativeFast", "nativeFastControl"]]
    manifest["plannedJobs"] = jobs
    dump(output / "manifest.json", manifest)
    records = []
    error = None
    try:
        for index, (job, phase, case) in enumerate(jobs):
            print("[%s/%s] %s" % (index + 1, len(jobs), job), flush=True)
            path = raw_dir / (job + ".json")
            if phase.startswith("native"):
                flag = "--scroll-check" if phase == "nativeOrdinary" else "--fast-scroll-check"
                env = dict(os.environ, KASUMI_REFLOW_IDLE_WARMUP="0" if phase == "nativeFastControl" else "1")
                child([str(native), flag, str(path)], path, phase, case, records, timeout=180, env=env)
            else:
                child([str(binary), "--worker", phase, case, str(samples_dir / (case + ".md")), str(path), args.profile],
                      path, phase, case, records, timeout=600 if phase in ["paint", "memory"] else 180)
    except (Exception, KeyboardInterrupt) as caught:
        error = str(caught) or type(caught).__name__
        print("Benchmark stopped: " + error, file=sys.stderr)
    finally:
        summary = summarize(records, jobs)
        summary["error"] = error
        manifest["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        dump(output / "manifest.json", manifest)
        dump(output / "summary.json", summary)
        (output / "report.md").write_text(report(summary, manifest))
        with gzip.open(output / "raw.json.gz", "wt") as archive:
            json.dump(records, archive, sort_keys=True, allow_nan=False)
    print("Results: " + str(output), flush=True)
    if not summary["complete"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
