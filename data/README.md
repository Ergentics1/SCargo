# SCargo Data Vault (`data/`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

## Code / Data Separation Contract

`data/` holds **immutable, schema-versioned measurement datasets, independent trace outputs, primary-source registries, and ICD manifests**. Executable code in `compartments/` reads from and writes to `data/`, but raw datasets are **never** hardcoded into source code.

## Sub-Vaults

| Directory | Contents | Mutability Rule |
|---|---|---|
| `data/sources/` | Strictly separated primary-source vaults: Bernhard Riemann RH lineage (`formulary_lineage_v1.json`, `RIEM-A`), Hugo Riemann music theory & typed Neo-Riemannian/orbifold bridge (`hugo_riemann_works_v1.json`, `RIEM-C`, 88 entries), Euler 1735–1739 common trunk & exact $G_{PLR}$ Ihara Graph-RH spectral invariants (`riemann_lattice_graph_rh_v1.json`, `RIEM-LATTICE`), Schwartz–Zippel (ODLSZ) lemma, PIT, generalizations & verified lattice benchmarks (`schwartz_zippel_research_v1.json`, `PIT-SZ`, 38 entries), SWE verification literature (`methodology_literature_v1.json`, 55 entries), cross-era lexicon (`standard_vocabulary_v1.json`), and pure declarative chart presentation (`paper_001_presentation_v1.json`) | Append/versioned (`_v1`, `_v2`); primary archives & peer-reviewed venues only; zero cross-tradition conflation |
| `data/fixtures/` | Declarative Rung 1 negative-control and matched clean-control recipes (`rung1_negative_controls_v1.json`, 21 poisoned + 5 clean; zero raw BiDi bytes or tracked symlinks) | Immutable per schema version; materialized out-of-tree at qualification time |
| `data/baselines/` | Live telemetry snapshots emitted by `scargo-probe` (`riemannian_<sha>_inventory.json`) | Immutable once written; tagged with `source_repo_commit` & `tool` |
| `data/traces/` | Independent DAG, dominator-tree, critical-path, and lineage-reachability traces emitted by `scargo-trace` | Immutable per commit & root module; 100% independently computed |
| `data/manifests/` | Normative SWE-sweep policy (`swe_sweep_policy_v1.json` `v1.2.0`), interface boundary specs (`transfer_zones_v1.json`), and upstream acceptance rules (`upstream_requirements_v1.json`) | Versioned; commit mismatch triggers re-qualification |
| `data/audits/` | Live self-audit ledgers, boolean-guard remediation states, and time-bounded waivers (`live_self_audit_v1.json`) | Append/versioned; strictly separated from normative policy (`data/manifests/`) and primary literature (`data/sources/`) |
| `data/trials/` | Deterministic RCT configs & allocations (`rct_r1_config_v1.json`, `rct_001_*.json`), Rung 2 seeded fuzz corpus config (`rung2_fuzz_corpus_v1.json`), and read-only clean-room dry-run qualification reports (`dryrun_*.json`) | Immutable per trial ID & PRNG seed |

