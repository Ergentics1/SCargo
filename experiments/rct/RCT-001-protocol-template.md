# Pre-Registered RCT Protocol Template (`RCT-001`)

- **Organization**: Ergentics (© 2026 Ergentics, LLC)
- **Study Design**: Prospective Stratified Randomized Controlled Trial (`stratified_rct`)
- **Randomization Instrument**: `compartments/rust/scargo-probe rct-sample` (deterministic SplitMix64 PRNG, fixed seed recorded in `data/trials/`)
- **Containment Level**: ISS MSG Level-2 Glovebox (isolated copy/branch; zero direct writes to `Riemannian/main`)
- **Retest Trigger**: Any change to `Riemannian` HEAD SHA (`51d9b1a280`) or `lean-toolchain` (`v4.36.0`) invalidates trial receipts (Falcon Table 7-2).

## 1. Eligibility & Stratification
- **Population**: All reachable project modules in `Riemannian/src` matching a target filter (`wrappers`, `explicit`, or `all`), excluding Zone A protected files (`Main`, `Challenge`, `Statements`).
- **Stratification Matrix**: Cross-product of Top-Level Library (`Development`, `Formalism`, `GroundTheory`, `ReciprocityTheory`, `CompanionTheory`, `PositivityTheory`, `Lemmata`) × File Line-Count Bucket (`<=20`, `21-50`, `51-100`, `101-250`, `251-1000`, `>1000`).
- **Allocation**: Within each stratum, sort deterministically by relative path, permute via SplitMix64(`seed`), and allocate balanced pairs $1:1$ to **Treatment** ($\Phi$) vs. **Control** (no-op baseline).

## 2. Endpoints

### Primary Efficacy Endpoints (Continuous)
1. Net source-line delta ($\Delta L$, absolute and %).
2. Net raw-byte delta ($\Delta B$, absolute and %).
3. Net file-count delta ($\Delta F$, if pass deletes/merges modules).

### Secondary Endpoints
4. Per-module Lean `v4.36.0` elaboration wall-clock time & heartbeat count (when Lean runner is attached).
5. Direct-importer `.olean` public/private interface diff count.

### Hard Safety Endpoints (Binary — Any Failure Halts Transfer)
- `S1`: Dangling project imports $= 0$.
- `S2`: Import graph cycles $= 0$.
- `S3`: Zone A protected core diff $= 0$ bytes.
- `S4`: Direct-importer compilation pass rate $= 100\%$ (for Lean-checked arms).
- `S5`: New `sorry` / `axiom` / `native_decide` / `maxHeartbeats` overrides $= 0$.

## 3. Generating a Reproducible Allocation Artifact

```bash
compartments/rust/target/release/scargo-probe rct-sample \
  --root ../Riemannian \
  --seed 20261122 \
  --per-stratum 10 \
  --filter wrappers \
  --out data/trials/rct_001_wrappers_allocation.json
```

## 4. Decision Rule for Promotion to Transfer Airlock (`transfer/`)
Promote treatment pass $\Phi$ from Qualification to Acceptance transfer only if:
- All Safety Endpoints `S1`–`S5` pass on 100% of treatment units, AND
- Median per-stratum primary reduction exceeds pre-registered threshold (e.g., $\ge 15\%$ line reduction in target class), AND
- No systematic failure clustering appears in any single library or size stratum.
