#!/usr/bin/env python3
# Copyright (c) 2026 Ergentics, LLC
# Licensed under the MIT License. See LICENSE in the project root.
"""
Adversarial & metamorphic pressure-test suite for Paper 002 figure renderer (AUD-07).
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
PATCH_PLAN = SCARGO_ROOT / "transfer" / "patches" / "arc6_patch_plan_v1.json"
BUNDLES = SCARGO_ROOT / "transfer" / "bundles" / "arc5_preflight_bundles_v1.json"
REHEARSAL = SCARGO_ROOT / "transfer" / "rehearsal" / "arc7_g4_g5_rehearsal_v1.json"
PRESENTATION = SCARGO_ROOT / "data" / "sources" / "paper_002_presentation_v1.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RENDERER), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class TestPaper002RenderFigures(unittest.TestCase):
    def test_01_static_source_zero_hardcoded_corpus_literals(self) -> None:
        src = RENDERER.read_text(encoding="utf-8")
        forbidden = ["51d9b1a280", "32,166", "19,052", "1,650,480", "127,440", "5,054", "8,060"]
        found = [lit for lit in forbidden if lit in src]
        self.assertEqual(found, [], f"Hardcoded literals leaked into Paper 002 renderer: {found}")

    def test_02_canonical_render_and_sha256_manifest_integrity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "figs"
            proc = invoke([
                "--patch-plan", str(PATCH_PLAN),
                "--bundles", str(BUNDLES),
                "--rehearsal", str(REHEARSAL),
                "--presentation", str(PRESENTATION),
                "--out-dir", str(out_dir),
            ])
            self.assertEqual(proc.returncode, 0, msg=f"stderr:\n{proc.stderr}\nstdout:\n{proc.stdout}")
            mpath = out_dir / "figures_manifest.json"
            self.assertTrue(mpath.is_file())
            m = json.loads(mpath.read_text(encoding="utf-8"))
            self.assertEqual(len(m["guards"]), 5)
            self.assertTrue(all(g["passed"] for g in m["guards"]))
            self.assertEqual(len(m["outputs"]), 3)
            for fn, info in m["outputs"].items():
                p = out_dir / fn
                self.assertTrue(p.is_file())
                self.assertEqual(sha256(p), info["sha256"])
                self.assertEqual(p.stat().st_size, info["bytes"])

    def test_03_metamorphic_scaled_dataset_zero_stale_leak(self) -> None:
        new_sha = "cafebabe" * 5
        pp = copy.deepcopy(json.loads(PATCH_PLAN.read_text(encoding="utf-8")))
        bd = copy.deepcopy(json.loads(BUNDLES.read_text(encoding="utf-8")))
        rh = copy.deepcopy(json.loads(REHEARSAL.read_text(encoding="utf-8")))

        pp["source_repo_commit"] = new_sha
        bd["source_repo_commit"] = new_sha
        rh["source_repo_commit"] = new_sha
        pp["zone_summaries"]["Z-C2"]["saved_lines"] = 9999
        pp["zone_summaries"]["Z-C2"]["lines_after"] = pp["zone_summaries"]["Z-C2"]["lines_before"] - 9999

        with tempfile.TemporaryDirectory() as tmp:
            t = Path(tmp)
            p1, p2, p3 = t / "pp.json", t / "bd.json", t / "rh.json"
            p1.write_text(json.dumps(pp), encoding="utf-8")
            p2.write_text(json.dumps(bd), encoding="utf-8")
            p3.write_text(json.dumps(rh), encoding="utf-8")
            out_dir = t / "figs"
            proc = invoke([
                "--patch-plan", str(p1),
                "--bundles", str(p2),
                "--rehearsal", str(p3),
                "--presentation", str(PRESENTATION),
                "--out-dir", str(out_dir),
            ])
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            claims = json.dumps(json.loads((out_dir / "figures_manifest.json").read_text())["rendered_claims"])
            self.assertIn("cafebabeca", claims)
            self.assertNotIn("51d9b1a280", claims)
            self.assertNotIn("32,166", claims)

    def test_04_poison_zero_cli_args_fails_closed(self) -> None:
        proc = invoke([])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("--patch-plan", proc.stderr)

    def test_05_poison_commit_sha_mismatch_fails_closed(self) -> None:
        rh = copy.deepcopy(json.loads(REHEARSAL.read_text(encoding="utf-8")))
        rh["source_repo_commit"] = "0" * 40
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad_rh.json"
            bad.write_text(json.dumps(rh), encoding="utf-8")
            proc = invoke([
                "--patch-plan", str(PATCH_PLAN),
                "--bundles", str(BUNDLES),
                "--rehearsal", str(bad),
                "--presentation", str(PRESENTATION),
                "--out-dir", str(Path(tmp) / "figs"),
            ])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("commit_sha_correspondence", proc.stderr)
            self.assertIn("Heal:", proc.stderr)

    def test_06_poison_baked_metric_in_presentation_fails_closed(self) -> None:
        pres = copy.deepcopy(json.loads(PRESENTATION.read_text(encoding="utf-8")))
        pres["zone_labels"]["Z-C2"]["title"] = "Capelli Collapse (19,052 lines)"
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad_pres.json"
            bad.write_text(json.dumps(pres), encoding="utf-8")
            proc = invoke([
                "--patch-plan", str(PATCH_PLAN),
                "--bundles", str(BUNDLES),
                "--rehearsal", str(REHEARSAL),
                "--presentation", str(bad),
                "--out-dir", str(Path(tmp) / "figs"),
            ])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("presentation_anti_baked_metrics", proc.stderr)
            self.assertIn("Heal:", proc.stderr)

    def test_07_poison_missing_font_dir_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            proc = invoke([
                "--patch-plan", str(PATCH_PLAN),
                "--bundles", str(BUNDLES),
                "--rehearsal", str(REHEARSAL),
                "--presentation", str(PRESENTATION),
                "--out-dir", str(Path(tmp) / "figs"),
                "--font-dir", str(Path(tmp) / "missing_fonts"),
            ])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("portable_font_resolution", proc.stderr)

    def test_08_manifest_zero_absolute_host_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "figs"
            proc = invoke([
                "--patch-plan", str(PATCH_PLAN),
                "--bundles", str(BUNDLES),
                "--rehearsal", str(REHEARSAL),
                "--presentation", str(PRESENTATION),
                "--out-dir", str(out_dir),
            ])
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            m = json.loads((out_dir / "figures_manifest.json").read_text(encoding="utf-8"))
            for name, info in m["inputs"].items():
                self.assertFalse(info["path"].startswith("/"), f"Absolute path leaked in {name}: {info['path']}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
