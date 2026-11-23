# Security Policy

**Organization**: Ergentics · **License**: MIT (`Copyright (c) 2026 Ergentics, LLC`)

## Supported Versions

| Version | Supported |
|---|---|
| `0.1.x` | Yes |

## Security Model

- All Lean, Rust, and Swift compartments have zero third-party package dependencies.
- Rust crates forbid `unsafe` code (`#![forbid(unsafe_code)]`) and avoid ambient subprocess execution.
- Lean modules use no `sorry`, no `native_decide`, and no custom axioms.
- Swift targets compile in Swift 6 strict concurrency mode with warnings treated as errors and no silent `try?` error swallowing.
- No secrets, tokens, credentials, or local machine paths are stored in this repository.

## Reporting a Vulnerability

Do not open a public issue for a suspected security defect, soundness flaw, or credential leak.

Report it privately using GitHub Security Advisories for this repository:
- Open a private advisory at `https://github.com/Ergentics1/SCargo/security/advisories/new`.

Include steps to reproduce, the affected compartment or file path, and the expected versus observed behavior.
