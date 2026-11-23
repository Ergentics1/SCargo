#!/usr/bin/env python3
# Copyright (c) 2026 Ergentics, LLC
# Licensed under the MIT License. See LICENSE in the project root.
"""
Adversarial & metamorphic pressure-test suite for Paper 001 figure renderer (AUD-07).

Verifies:
  1. Static anti-hardcoding guard on render_figures.py source itself.
  2. Happy-path canonical rendering + cryptographic SHA-256 manifest verification.
  3. Metamorphic 50% proof-mass scaling: zero old-number leakage, exact dynamic claim correspondence.
  4. Poisoned negative controls (fail-closed + explicit healing diagnostics):
     - Zero CLI arguments (refuses implicit hardcoded paths)
     - Commit-SHA mismatch between baseline, trace, and lineage
     - Baked empirical numeral smuggled into presentation JSON (anti-cheat guard)
     - Missing presentation display key (strict fail-closed + healing check)
     - Missing/invalid font directory (no silent bitmap fallback)
"""

from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PAPER_DIR = Path(__file__).resolve().parent
SCARGO_ROOT = PAPER_DIR.parents[2]
RENDERER = PAPER_DIR / "render_figures.py"
BASELINE_JSON = SCARGO_ROOT / "data" / "baselines" / "riemannian_51d9b1a280_inventory.json"
TRACE_JSON = SCARGO_ROOT / "data" / "traces" / "riemannian_51d9b1a280_trace.json"
LINEAGE_JSON = SCARGO_ROOT / "data" / "sources" / "formulary_lineage_v1.json"
PRESENTATION_JSON = SCARGO_ROOT / "data" / "sources" / "paper_001_presentation_v1.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke_renderer(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RENDERER), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class TestRenderFiguresPressure(unittest.TestCase):
    def test_01_static_source_contains_zero_hardcoded_corpus_literals(self) -> None:
        src = RENDERER.read_text(encoding="utf-8")
        forbidden_literals = [
            "51d9b1a280",
            "149,397",
            "15,168,601",
            "5,308",
            "1.64M",
            "1,300–3,100",
            "1837–2026",
            "(5 lines)",
        ]
        found = [lit for lit in forbidden_literals if lit in src]
        self.assertEqual(found, [], f"Hardcoded corpus literals leaked into renderer: {found}")

    def test_02_canonical_render_and_sha256_manifest_integrity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "figs"
            proc = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(TRACE_JSON),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(PRESENTATION_JSON),
                    "--out-dir", str(out_dir),
                ]
            )
            self.assertEqual(proc.returncode, 0, msg=f"stderr:\n{proc.stderr}\nstdout:\n{proc.stdout}")
            manifest_path = out_dir / "figures_manifest.json"
            self.assertTrue(manifest_path.is_file())
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

            self.assertEqual(len(manifest["guards"]), 5)
            self.assertTrue(all(g["passed"] for g in manifest["guards"]))
            self.assertEqual(len(manifest["outputs"]), 4)
            for fname, info in manifest["outputs"].items():
                p = out_dir / fname
                self.assertTrue(p.is_file())
                self.assertEqual(sha256(p), info["sha256"])
                self.assertEqual(p.stat().st_size, info["bytes"])

    def test_03_metamorphic_scaled_dataset_zero_old_metric_leak(self) -> None:
        """Metamorphic correspondence test: mutate every metric & commit SHA, verify epsilon=0 claim update."""
        new_sha = "deadbeef" * 5  # 40 hex chars
        baseline = copy.deepcopy(json.loads(BASELINE_JSON.read_text(encoding="utf-8")))
        trace = copy.deepcopy(json.loads(TRACE_JSON.read_text(encoding="utf-8")))
        lineage = copy.deepcopy(json.loads(LINEAGE_JSON.read_text(encoding="utf-8")))

        baseline["source_repo_commit"] = new_sha
        trace["source_repo_commit"] = new_sha
        lineage["source_repo_commit"] = new_sha

        baseline["totals"]["files"] = 74698
        baseline["totals"]["lines"] = 7584300
        baseline["totals"]["bytes"] = 280000000
        baseline["totals"]["blank_lines"] = 900000
        baseline["top_level3_subtrees"][0]["bytes"] = 112000000  # exactly 40.0%

        for d in trace["top_module_dominators"]:
            d["dominated_lines"] = max(1, d["dominated_lines"] // 2)
            if d["fan_out"] >= 1000:
                d["fan_out"] = 2411
        for hb in trace["top_fan_in_hubs"]:
            hb["fan_in"] = max(1, hb["fan_in"] // 2)
            if hb.get("dominated_modules") == 1 and hb.get("dominated_lines", 0) <= 10:
                hb["dominated_lines"] = 9

        # Drop first entry (1837) so span shifts from 1837-2026 (15 entries, 189 yrs) to 1859-2026 (14 entries, 167 yrs)
        lineage["entries"] = lineage["entries"][1:]

        with tempfile.TemporaryDirectory() as tmp:
            tdir = Path(tmp)
            b_p = tdir / "b.json"
            t_p = tdir / "t.json"
            l_p = tdir / "l.json"
            out_dir = tdir / "figs"
            b_p.write_text(json.dumps(baseline), encoding="utf-8")
            t_p.write_text(json.dumps(trace), encoding="utf-8")
            l_p.write_text(json.dumps(lineage), encoding="utf-8")

            proc = invoke_renderer(
                [
                    "--baseline", str(b_p),
                    "--trace", str(t_p),
                    "--lineage", str(l_p),
                    "--presentation", str(PRESENTATION_JSON),
                    "--out-dir", str(out_dir),
                ]
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            manifest = json.loads((out_dir / "figures_manifest.json").read_text(encoding="utf-8"))
            claims_blob = json.dumps(manifest["rendered_claims"], ensure_ascii=False)

            # Assert exact updated values appear
            self.assertIn("40.0% of all source bytes", claims_blob)
            self.assertIn("74,698 modules", claims_blob)
            self.assertIn("7,584,300 total source lines", claims_blob)
            self.assertIn("1859–2026", claims_blob)
            self.assertIn("14 primary-archive milestones bridging 167 years", claims_blob)
            self.assertIn("2,411 direct imports", claims_blob)
            self.assertIn("(9 lines)", claims_blob)
            self.assertIn("deadbeefde", claims_blob)

            # Assert ZERO stale numbers leaked from original 51d9b1a280 baseline
            for stale in ("51d9b1a280", "149,397", "15,168,601", "5,308", "1.64M", "3,119", "(5 lines)", "1837", "189 years"):
                self.assertNotIn(stale, claims_blob, f"Stale baseline literal {stale!r} leaked into mutated render!")

    def test_04_poison_zero_cli_args_fails_closed(self) -> None:
        proc = invoke_renderer([])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("--baseline", proc.stderr)

    def test_05_poison_commit_sha_mismatch_fails_closed_with_healing(self) -> None:
        trace = copy.deepcopy(json.loads(TRACE_JSON.read_text(encoding="utf-8")))
        trace["source_repo_commit"] = "0" * 40
        with tempfile.TemporaryDirectory() as tmp:
            t_p = Path(tmp) / "bad_trace.json"
            t_p.write_text(json.dumps(trace), encoding="utf-8")
            proc = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(t_p),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(PRESENTATION_JSON),
                    "--out-dir", str(Path(tmp) / "figs"),
                ]
            )
            self.assertEqual(proc.returncode, 2)
            self.assertIn("commit_sha_correspondence", proc.stderr)
            self.assertIn("Heal:", proc.stderr)

    def test_06_poison_baked_metric_in_presentation_fails_closed(self) -> None:
        pres = copy.deepcopy(json.loads(PRESENTATION_JSON.read_text(encoding="utf-8")))
        pres["dominator_labels"]["EveryCharacterOfLiteratureOfVWin"]["domain"] = "Iterated Theta Lifts (5,308 direct imports)"
        with tempfile.TemporaryDirectory() as tmp:
            p_p = Path(tmp) / "poison_pres.json"
            p_p.write_text(json.dumps(pres), encoding="utf-8")
            proc = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(TRACE_JSON),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(p_p),
                    "--out-dir", str(Path(tmp) / "figs"),
                ]
            )
            self.assertEqual(proc.returncode, 2)
            self.assertIn("presentation_anti_baked_metrics", proc.stderr)
            self.assertIn("Heal:", proc.stderr)

    def test_07_poison_missing_presentation_key_fails_closed_and_heals(self) -> None:
        pres = copy.deepcopy(json.loads(PRESENTATION_JSON.read_text(encoding="utf-8")))
        del pres["hub_labels"]["UniformisationConclusion"]
        with tempfile.TemporaryDirectory() as tmp:
            p_p = Path(tmp) / "incomplete_pres.json"
            p_p.write_text(json.dumps(pres), encoding="utf-8")
            out_dir = Path(tmp) / "figs"

            # Strict mode MUST fail closed
            proc = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(TRACE_JSON),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(p_p),
                    "--out-dir", str(out_dir),
                ]
            )
            self.assertEqual(proc.returncode, 2)
            self.assertIn("presentation_label_coverage", proc.stderr)
            self.assertIn("UniformisationConclusion", proc.stderr)

            # Healing path 1: explicit opt-in flag succeeds visibly
            proc_opt = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(TRACE_JSON),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(p_p),
                    "--out-dir", str(out_dir),
                    "--allow-fallback-labels",
                ]
            )
            self.assertEqual(proc_opt.returncode, 0, msg=proc_opt.stderr)

    def test_08_poison_missing_font_dir_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            proc = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(TRACE_JSON),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(PRESENTATION_JSON),
                    "--out-dir", str(Path(tmp) / "figs"),
                    "--font-dir", str(Path(tmp) / "no_such_fonts"),
                ]
            )
            self.assertEqual(proc.returncode, 2)
            self.assertIn("portable_font_resolution", proc.stderr)
            self.assertIn("Heal:", proc.stderr)

    def test_09_manifest_contains_zero_absolute_host_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "figs"
            proc = invoke_renderer(
                [
                    "--baseline", str(BASELINE_JSON),
                    "--trace", str(TRACE_JSON),
                    "--lineage", str(LINEAGE_JSON),
                    "--presentation", str(PRESENTATION_JSON),
                    "--out-dir", str(out_dir),
                ]
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            manifest = json.loads((out_dir / "figures_manifest.json").read_text(encoding="utf-8"))
            for name, info in manifest["inputs"].items():
                self.assertFalse(
                    info["path"].startswith("/"),
                    f"Input '{name}' leaked absolute host path: {info['path']}",
                )
                self.assertTrue(
                    info["path"].startswith("data/"),
                    f"Expected portable repo-relative path for '{name}', got {info['path']}",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
