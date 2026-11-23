# Contributing to SCargo

Thank you for your interest in contributing to SCargo.

## Core Rules

1. **Keep code and data separate**: Put executable tools in `compartments/`, versioned datasets and source registries in `data/`, specifications in `models/`, and papers in `research/`.
2. **Run each language on its own**: Lean (`compartments/lean`), Rust (`compartments/rust`), and Swift (`compartments/swift`) must build and pass tests independently without cross-language wrapper scripts.
3. **Zero warnings and zero suppressions**: Do not silence compiler warnings or linters (`#[allow(...)]`, `try?`, `sorry`, `native_decide`, or disabled lint rules). Fix the root cause.
4. **Use primary sources only**: Entries in `data/sources/` must point to primary archives, national libraries, university presses, peer-reviewed journals, or arXiv preprints — never crowdsourced wikis.
5. **Public repository hygiene**: Never commit credentials, API tokens, personal emails, symlinks, local machine home paths, local file URIs, or external CDN scripts.
6. **Keep commit messages short and clear**: Write plain-English commit messages that state what changed without unnecessary jargon.

## Standalone Verification Before Opening a PR

Run the checks for every compartment you modify:

```bash
# Lean (v4.36.0)
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean build
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean test

# Rust (1.100.0)
RUSTFLAGS="-D warnings" cargo clippy --manifest-path compartments/rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path compartments/rust/Cargo.toml

# Swift (6.4.3)
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- test --package-path compartments/swift
```

## License

By contributing, you agree that your contributions will be licensed under the MIT License in [`LICENSE`](LICENSE).
