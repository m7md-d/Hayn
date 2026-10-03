fn main() {
    // rav1d's arm64 assembly addresses its tables PC-relative, which a shared
    // library allows only if those symbols cannot be interposed (PERF-05).
    // Android's linker otherwise refuses: R_AARCH64_ADR_PREL_PG_HI21 against
    // an exported symbol. Apple's linker binds them locally already.
    let target = std::env::var("TARGET").unwrap_or_default();
    if target == "aarch64-linux-android" {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-Bsymbolic");
    }
}
