// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone Rung 1 13-witness SWE-sweep, D/R/P/Seam blind-spot guards,
//! 21-fixture out-of-tree negative-control qualifier, and Stratified RCT-R1 engine.

pub mod blindspots;
pub mod json;
pub mod rct;
pub mod sha256;
pub mod sweep;
