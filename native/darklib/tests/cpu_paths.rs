//! rav1d's arm64 assembly on CPUs this project has no phone for (Hayn PERF-05).
//!
//! rav1d picks its routines from the CPU's features once per process: NEON on
//! every arm64, then dotprod and i8mm where the CPU reports them. The one
//! phone (user decision 2026-10-09: simulate what is not there) has both, so
//! the routines a phone without them runs are reached by masking the
//! features: each mask decodes the AVIF samples in a process of its own, and
//! every mask must give the same pixels. On x86 there is no assembly and all
//! masks agree trivially; the run that counts is on the phone
//! (`tool/test_darklib_on_phone.sh`). In rav1d 1.1.0 dotprod and i8mm only
//! select motion compensation (`mc.rs`), which a still image's intra frames
//! never call, so this shows a photo decodes the same without them.

use std::collections::BTreeMap;
use std::process::Command;

use darklib::engine::codec;

/// The child's mask; the parent leaves it unset.
const MASK: &str = "DARKLIB_CPU_MASK";
/// Where the samples are when the test binary runs away from the source tree.
const FIXTURES: &str = "DARKLIB_FIXTURES";
const TEST: &str = "every_cpu_path_decodes_the_same";

/// rav1d's arm64 flags: NEON (1), dotprod (2), i8mm (4); !0 = all reported.
const MASKS: [(&str, u32); 4] = [
    ("neon", 1),
    ("neon+dotprod", 3),
    ("neon+dotprod+i8mm", 7),
    ("all", !0),
];

fn fixtures() -> String {
    std::env::var(FIXTURES)
        .unwrap_or_else(|_| concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures").into())
}

/// FNV-1a over the decoded RGBA and size, or over the error.
fn digest(bytes: &[u8]) -> String {
    match codec::decode(bytes, None) {
        Ok(d) => {
            let mut h: u64 = 0xcbf29ce484222325;
            for &b in d
                .width
                .to_le_bytes()
                .iter()
                .chain(&d.height.to_le_bytes())
                .chain(&d.rgba)
            {
                h = (h ^ b as u64).wrapping_mul(0x100000001b3);
            }
            format!("{}x{}:{h:016x}", d.width, d.height)
        }
        Err(e) => format!("error:{e}"),
    }
}

#[test]
fn every_cpu_path_decodes_the_same() {
    if let Ok(mask) = std::env::var(MASK) {
        rav1d::src::cpu::dav1d_set_cpu_flags_mask(mask.parse().expect("mask"));
        let mut names: Vec<_> = std::fs::read_dir(fixtures())
            .expect("fixtures")
            .filter_map(|e| e.ok()?.file_name().into_string().ok())
            .filter(|n| n.ends_with(".avif"))
            .collect();
        names.sort();
        for name in names {
            let bytes = std::fs::read(format!("{}/{name}", fixtures())).unwrap();
            println!("DIGEST {name} {}", digest(&bytes));
        }
        return;
    }
    // What this CPU reports, before any mask (NEON 1, dotprod 2, i8mm 4).
    println!(
        "detected: {:#b}",
        rav1d::src::cpu::CpuFlags::run_time_detect().bits()
    );
    let exe = std::env::current_exe().unwrap();
    let mut results: BTreeMap<&str, Vec<String>> = BTreeMap::new();
    for (label, mask) in MASKS {
        let out = Command::new(&exe)
            .args([TEST, "--exact", "--nocapture", "--test-threads=1"])
            .env(MASK, mask.to_string())
            .output()
            .expect("child test");
        assert!(
            out.status.success(),
            "{label}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        let lines: Vec<String> = String::from_utf8_lossy(&out.stdout)
            .lines()
            // The harness may print "test … " on the first line before it.
            .filter_map(|l| l.split_once("DIGEST ").map(|(_, d)| d.to_owned()))
            .collect();
        assert!(lines.len() >= 9, "{label}: {} samples", lines.len());
        println!("{label}: {} samples", lines.len());
        results.insert(label, lines);
    }
    let want = &results["neon"];
    for (label, got) in &results {
        assert_eq!(got, want, "{label} differs from NEON alone");
    }
}
