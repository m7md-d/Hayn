# Hayn Performance Review Notes

## Scope

This document records performance-related observations found while reviewing the current **Hayn / `bedrock`** codebase, with particular attention to:

- large-image memory behavior,
- native image pipelines in `native/darklib`,
- Flutter ↔ Rust data transfer,
- concurrency and task execution,
- image preview behavior,
- AVIF / HEIC processing,
- metadata surgery,
- repeated decode / probe work,
- and places where the current implementation may scale poorly on very large media.

This is **not** a declaration that every item below is a bug.

Some of the behavior may be intentional because of:

- implementation simplicity,
- portability,
- correctness requirements,
- platform limitations,
- early-stage architecture,
- intentionally conservative fallbacks,
- or because the project currently optimizes for 12–50 MP images rather than extreme files.

The goal is therefore to identify **performance risk surfaces**, explain why they deserve measurement, and distinguish:

1. **behavior that is directly visible in the implementation**,  
2. **behavior already supported by project benchmarks or documentation**, and  
3. **hypotheses that still require profiling before being treated as defects**.

---

# 1. Executive Summary

The most important performance risks currently appear to come from **memory amplification**, **duplicate work**, and **unbounded overlap of expensive operations**, rather than from any single slow algorithm.

The key pattern is:

> A media operation that is individually acceptable can become dangerous when multiple full-resolution buffers, codec workspaces, FFI copies, previews, and overlapping tasks coexist.

For very large images, a single RGBA buffer is already expensive:

```text
200 MP × 4 bytes ≈ 800 MB (decimal)
256 Mi-pixel × 4 bytes = 1 GiB
```

Therefore, code that temporarily holds:

```text
source RGBA
+ cloned RGBA
+ RGB conversion
+ encoded output
+ decoder workspace
+ preview decode
```

can exceed several gigabytes even though every individual allocation looks reasonable in isolation.

The strongest areas worth investigating are:

1. **Heavy tasks appear able to overlap without a global memory/concurrency budget.**
2. **The encoded “after” preview can decode the result at full resolution.**
3. **The 256 MP decode limit is a pixel-count limit, not a true peak-memory limit.**
4. **Alpha-preservation verification may perform additional full-resolution decodes after encoding.**
5. **Transparent → JPEG conversion currently appears to introduce a full PNG intermediate.**
6. **The same source may be inspected multiple times across Dart, Rust, and platform channels.**
7. **Large `Vec<u8>` values cross the Flutter Rust Bridge serialization path repeatedly.**
8. **AVIF decode/conversion contains deliberately conservative single-thread/scalar work.**
9. **AVIF grid encoding retains more intermediate data than the existing comment suggests.**
10. **Orientation and metadata/container surgery can temporarily duplicate large buffers.**

These are not all equally urgent.

The first three can become **process-level memory failures** under large media or concurrency and should be measured before lower-level codec tuning.

---

# 2. Review Method

The review focused on static inspection of:

- `lib/`
- `native/darklib/`
- generated Flutter Rust Bridge bindings,
- image-processing paths,
- project performance/stabilization documentation,
- and the current task execution model.

The project already contains useful performance evidence, including large-image measurements in documentation such as:

- `docs/18-PERFORMANCE.md`
- `docs/23-LARGE-IMAGES.md`
- related stabilization/issue documents

Where this report references measured memory values, they are treated as **project evidence**, not as universal device-independent values.

Where the report says “may”, “can”, or “risk”, it intentionally means that the code shape suggests a potential scaling problem that should be verified with profiling.

---

# 3. Risk Classification Used in This Report

### Critical performance risk

A pattern that can plausibly lead to:

- process termination,
- OS memory pressure,
- multiple-gigabyte transient allocation,
- extreme thermal load,
- or user-visible stalls on supported inputs.

### High performance risk

A pattern that may:

- duplicate full-image work,
- create large temporary buffers,
- serialize expensive work unnecessarily,
- or scale poorly with image size.

### Medium performance risk

A real source of overhead, but one whose practical cost depends heavily on:

- file size,
- format,
- device,
- codec backend,
- or how often the path is called.

### Profiling candidate

A code pattern that looks expensive, but cannot responsibly be called a problem without measurements.

---

# 4. Observation: Heavy Tasks Do Not Appear to Be Globally Memory-Bounded

## Area

```text
lib/core/isolates/task_runner.dart
```

## Observation

The current `TaskRunner` starts tasks immediately after enqueueing them rather than obviously placing expensive operations behind a strict global heavy-task semaphore or memory budget.

The important distinction is that a structure may be called a “task runner” or “queue” while still allowing several expensive task streams to execute at the same time.

The current pattern appears broadly similar to:

```dart
state = [
  ...state,
  TaskState(
    task: task,
    status: TaskStatus.running,
    ...
  ),
];

final sub = task.run().listen(...);
```

This means that concurrency can be determined by callers rather than by a single central resource governor.

## Why this matters

Large image operations already use substantial memory individually.

Project measurements have shown that a single very-large-image operation can consume on the order of hundreds of megabytes to multiple gigabytes depending on format/backend.

If two such tasks overlap:

```text
Task A peak memory
+
Task B peak memory
+
Flutter/UI/cache/native overhead
```

the result can cross the OS memory-pressure threshold even though each operation succeeds independently.

This is especially important on mobile where:

- application memory limits are lower than desktop machines,
- thermal throttling is aggressive,
- background services may compete for memory,
- and the kernel may terminate the application rather than allow swapping behavior comparable to desktop Linux/macOS.

## Why the current design may be intentional

Possible reasons include:

- simpler task semantics,
- early implementation stage,
- allowing independent lightweight tasks to run concurrently,
- relying on per-feature throttling,
- or avoiding unnecessary serialization of unrelated jobs.

Therefore, the observation is not:

> “all tasks must be serialized.”

It is:

> “expensive media tasks currently need an explicit resource policy if the application intends to support very large assets safely.”

## Recommended validation

Test at least:

```text
1 × 200 MP JPEG encode
2 × 200 MP JPEG encode concurrently
1 × large AVIF encode + 1 × JPEG encode
2 × HEIC/AVIF conversions
```

Record:

- peak RSS,
- native heap,
- Dart heap,
- execution time,
- device temperature,
- cancellation latency,
- whether the OS kills the process.

A useful design may be:

```text
light jobs: limited parallelism
heavy pixel jobs: 1 at a time
very-large jobs: exclusive memory lane
```

rather than a single global serial queue.

---

# 5. Observation: The “After” Preview Can Decode the Encoded Result at Full Resolution

## Area

Compression screen / preview path, approximately:

```text
lib/features/image_ops/presentation/compress_screen.dart
```

## Observation

The original/before preview includes a decode bound such as `cacheWidth`, but the encoded-result preview appears to use a direct `Image.memory(...)` without an equivalent resize/cache bound.

Conceptually:

```dart
Image.memory(
  encoded.bytes,
  fit: BoxFit.contain,
)
```

while the original preview uses a constrained decode.

## Why this matters

The encoded file may be small while its decoded bitmap is enormous.

For example:

```text
200 MP JPEG file: perhaps tens of MB on disk
decoded RGBA: roughly 800 MB
```

So the dangerous sequence is:

```text
full-resolution encode completes
→ encoded bytes remain in memory
→ Flutter decodes encoded result for preview
→ another full-resolution bitmap appears
```

The preview can therefore become the largest allocation **after** the expensive operation has already finished.

This is especially easy to miss because:

- compression itself succeeds,
- benchmark code may measure only the encoder,
- then UI rendering causes the real memory spike.

## Why the current design may be intentional

A full-resolution preview could be deliberate if the intended behavior is:

- pixel-level inspection,
- exact before/after comparison,
- or avoiding preview artifacts.

However, a phone screen does not normally need hundreds of megapixels resident simultaneously.

A high-resolution preview does not require the complete original resolution unless the UI supports deep zoom/pixel peeping.

## Recommended validation

Run the real screen, not only encoder tests:

```text
open 100 MP image
open 200 MP image
encode JPEG
wait until after-preview appears
measure process RSS before and after image display
```

Also test navigating away and back to detect cache retention.

## Possible direction

Keep:

```text
full-resolution encoded bytes for saving
```

but display a bounded decode:

```text
ResizeImage / cacheWidth / cacheHeight
```

For advanced zoom later, use region/tiled decoding rather than a permanent full-resolution Flutter bitmap.

---

# 6. Observation: `MAX_DECODE_PIXELS` Is Not a Peak-Memory Budget

## Area

DarkLib decode limits.

Example:

```rust
pub const MAX_DECODE_PIXELS: u64 = 256 * 1024 * 1024;
```

with a limit conceptually equivalent to:

```rust
limits.max_alloc = Some(MAX_DECODE_PIXELS * 4);
```

## Observation

A pixel-count limit constrains one expected image allocation, but not the number of simultaneous full-resolution buffers created by the rest of the pipeline.

At the maximum limit:

```text
256 Mi-pixel × 4 bytes = 1 GiB RGBA
```

That is already a large allocation for a mobile process.

Some encode paths then create additional representations.

For example, a path that conceptually performs:

```rust
RGBA source
→ clone RGBA
→ convert to RGB
→ encoder workspace
```

can hold several full-frame buffers simultaneously.

## Example memory amplification

For 200 MP:

```text
RGBA source      ≈ 800 MB
RGBA clone       ≈ 800 MB
RGB buffer       ≈ 600 MB
--------------------------------
pixel buffers    ≈ 2.2 GB
```

before accounting for:

- codec state,
- encoded output,
- Rust allocator overhead,
- Dart-side bytes,
- Flutter image cache,
- FFI serialization,
- metadata structures.

The project's own large-image measurements are consistent with this class of amplification.

## Why the current design may be intentional

A pixel limit is:

- simple,
- deterministic,
- format independent,
- and protects against obviously pathological dimensions.

It is a useful safety boundary.

The issue is only that:

> it should not be interpreted as evidence that every accepted image can be processed within a predictable memory budget.

## Recommended direction

Consider a second model:

```text
operation-specific estimated peak memory
```

For example:

```text
decode only:
    1 × RGBA + codec overhead

JPEG encode:
    RGBA + RGB + workspace

rotation 90°:
    source RGBA + destination RGBA

grid AVIF:
    source RGBA + tile + encoded tile accumulation + encoder
```

Then reject or route operations according to a device/resource budget.

---

# 7. Observation: Alpha-Preservation Verification May Decode Large Outputs Again

## Area

Image verification / alpha-preservation checks.

Relevant concepts include functions similar to:

```text
ImageProbe.keepsAlpha(...)
alpha_kept(...)
transparency(...)
had_transparency(...)
```

## Observation

After encoding succeeds, the application may verify whether transparency survived.

The verification path can decode the produced image to inspect alpha:

```text
encode source
→ decode encoded output
→ scan output alpha
```

In some branches, determining whether the source originally contained transparency can trigger another source inspection/decode.

Potential worst-case logical sequence:

```text
decode source
→ encode output
→ decode output
→ decode/inspect source again
```

## Why this matters

Verification is usually thought of as inexpensive metadata logic, but here it can become another complete image pipeline.

For a 100–200 MP image, “verify alpha” may therefore cost:

- another huge bitmap,
- another codec decode,
- full pixel scanning,
- and another large FFI transfer.

## Why the current design may be intentional

This behavior can be justified by correctness.

The project explicitly cares about preservation semantics, and blindly trusting:

- requested output format,
- backend promises,
- or container metadata

would weaken correctness.

Therefore, the question is not whether verification should exist.

The performance question is:

> Can preservation be verified using information already produced by the encoder/backend without always re-decoding the entire output?

## Recommended validation

Benchmark separately:

```text
encode only
encode + alpha verification
```

for:

- transparent PNG,
- WebP alpha,
- AVIF alpha,
- opaque images,
- images where alpha state is unknown before decode.

Measure how much of total conversion time belongs to verification.

---

# 8. Observation: Transparent → JPEG Appears to Use a Full PNG Intermediate

## Area

Flutter image encoder / alpha flatten pipeline.

Approximate path:

```text
AlphaFlatten.toOpaquePng(...)
→ ImageEncoder JPEG path
```

## Observation

The current design appears to flatten transparency by producing an opaque PNG first, then pass that PNG into the JPEG encoder.

Conceptually:

```text
source
↓ decode
RGBA pixels
↓ flatten onto white
RGB pixels
↓ encode PNG
PNG bytes
↓ decode PNG
pixels
↓ encode JPEG
```

The PNG is not the final user-selected format.

## Why this matters

For large images this introduces:

- one full extra encode,
- one full extra decode,
- another large byte buffer crossing layer boundaries,
- extra allocations,
- and additional CPU time.

PNG itself can also be expensive for large images.

This pattern is a strong candidate for avoidable cost.

## Why the current design may be intentional

Possible reasons:

- reuse of an existing flattening API,
- clear separation of responsibilities,
- avoiding duplicate alpha-compositing code across encoders,
- keeping the JPEG backend independent from source format handling,
- or supporting multiple fallback encoders through one normalized intermediate.

Architecturally, this can be clean even if it is expensive.

## Better question

Instead of asking:

> “Why is PNG used?”

the useful question is:

> “Does the architectural simplicity justify the full intermediate encode/decode for the target workloads?”

## Recommended benchmark

Compare:

```text
current:
source → flatten → PNG → JPEG

experimental:
source → decode → flatten pixels → JPEG directly
```

at:

- 12 MP,
- 50 MP,
- 100 MP,
- 200 MP.

Measure:

- total time,
- peak RSS,
- temporary bytes,
- output equivalence.

---

# 9. Observation: Source Inspection Is Repeated Across Layers

## Area

Examples include:

```text
SourceInspector
ImageProbe
DarkLibCore.inspect
NativeImageProbe
```

## Observation

A single source can be inspected more than once before encoding.

The flow appears to include combinations similar to:

```text
DarkLib inspect
DarkLib inspect again
native HDR/platform probe
another native/platform probe
```

depending on the screen and requested operation.

This means the same input bytes may repeatedly cross:

- Dart,
- Rust,
- platform channels,
- native decoders/parsers.

## Why this matters

For small images this is probably negligible.

For 30–150 MB image files, repeated probing can mean:

- repeated large byte copies,
- repeated container parsing,
- repeated bridge serialization,
- repeated native setup,
- and duplicated platform calls before the actual conversion begins.

If a “probe” internally decodes pixels for unsupported metadata cases, the cost becomes much higher.

## Why the current design may be intentional

Separate probes can keep modules decoupled:

```text
alpha ownership
HDR ownership
container ownership
platform capability ownership
```

This is often easier to maintain than one large “god object” inspection API.

Therefore, merging everything into one function is not automatically better architecture.

## Recommended direction

A compromise is a per-source cached facts object:

```text
SourceFacts
├─ dimensions
├─ alpha: true / false / unknown
├─ HDR
├─ ICC/CICP
├─ orientation
├─ container
└─ backend capability hints
```

Each subsystem can still own its interpretation, while the expensive raw inspection is reused.

---

# 10. Observation: Flutter Rust Bridge Transfers Large Byte Arrays Through Serialization

## Area

Generated Flutter Rust Bridge bindings.

## Observation

The generated Rust deserialization for `Vec<u8>` uses element-wise reconstruction similar to:

```rust
let mut ans = Vec::with_capacity(len);

for _ in 0..len {
    ans.push(u8::sse_decode(deserializer));
}
```

Serialization back to Dart similarly iterates over bytes on the Rust side.

On Dart, bulk byte operations may exist, but the end-to-end bridge still represents a large in-memory transfer and reconstruction.

## Scale

For a 100 MB payload:

```text
~100 million byte elements
```

must conceptually pass through the serialization layer.

Even if optimized by compiler/runtime details, the design is fundamentally more expensive than:

- borrowed native memory,
- file descriptors,
- mmap,
- path-based processing,
- shared buffers,
- or a dedicated zero-copy bridge.

## Why this matters

The same source can cross the bridge multiple times for:

- inspect,
- decode,
- encode,
- metadata transfer,
- verification,
- alpha handling.

The cost is therefore multiplicative.

## Why the current design may be intentional

Using `Vec<u8>` is extremely convenient:

- simple API,
- safe ownership,
- easy tests,
- no lifetime coordination,
- no temporary file semantics,
- and good enough for ordinary photo sizes.

This is a valid tradeoff for early-stage or moderate-size media.

## Recommended validation

Benchmark bridge overhead independently:

```text
1 MB
10 MB
50 MB
100 MB
250 MB
```

using a function that only receives and returns bytes without doing codec work.

This separates:

```text
bridge cost
```

from:

```text
image processing cost
```

Only after measuring that should a file-backed/zero-copy path be considered necessary.

---

# 11. Observation: AVIF Decode Uses Conservative Threading

## Area

DarkLib AVIF decode path / rav1d settings.

Observed configuration includes behavior similar to:

```rust
settings.n_threads = 1;
settings.max_frame_delay = 1;
```

## Observation

AV1 decode is deliberately constrained to one thread.

After decoding, YUV → RGB(A) conversion appears to execute through explicit per-pixel loops.

Conceptually:

```rust
for y in 0..height {
    for x in 0..width {
        // sample planes
        // convert YCbCr → RGB
        // clamp/convert
    }
}
```

## Why this matters

AV1 is computationally heavy.

A single-thread decoder plus scalar conversion may leave substantial performance unused on modern phones with:

- multiple performance cores,
- SIMD,
- high memory bandwidth.

For large AVIF files, CPU time may scale almost directly with pixel count.

## Why the current design may be intentional

Single-threading can be a deliberate stability choice:

- deterministic memory use,
- reduced thermal spikes,
- avoiding oversubscription when Flutter already runs multiple tasks,
- easier cross-platform behavior,
- or known decoder limitations.

Similarly, a straightforward scalar YUV conversion may prioritize correctness and maintainability before optimization.

Therefore, the report does **not** assume “more threads = better”.

## Recommended benchmark

Test:

```text
n_threads = 1
n_threads = 2
n_threads = 4
```

while recording:

- latency,
- peak memory,
- CPU utilization,
- device temperature,
- battery power if available.

Separately benchmark YUV conversion.

SIMD may provide a better performance/watt improvement than simply increasing thread count.

---

# 12. Observation: AVIF Grid Encoding Retains More Than “Source + One Tile”

## Area

AVIF grid encoding implementation.

## Observation

The implementation contains a memory description suggesting that grid encoding is approximately:

```text
source buffer + one tile
```

However, the actual flow appears to retain additional data.

A simplified structure is:

```rust
let mut tiles = Vec::with_capacity(rows * cols);

for each tile {
    create/copy tile pixels
    encode tile
    tiles.push(encoded_tile)
}

build_grid_avif(tiles)
```

During final assembly, the code also builds complete `mdat` / final container buffers.

Therefore peak memory includes some combination of:

```text
full source pixels
+ current uncompressed tile
+ codec workspace
+ all encoded tile payloads retained so far
+ concatenated mdat
+ final AVIF container
```

The encoded tiles are much smaller than RGBA pixels, so this is still significantly better than holding all tiles uncompressed.

But the existing comment understates the true live-data set.

## Why this matters

Documentation and comments often become the basis for future safety assumptions.

If later code chooses the grid path believing it guarantees:

```text
source + one tile only
```

memory estimates may become inaccurate.

## Why the design may be intentional

Keeping encoded tiles in memory makes container assembly dramatically simpler.

For typical compressed sizes, this may be an excellent tradeoff.

The recommendation is not necessarily to stream them immediately.

It is primarily to:

- correct the memory model,
- measure real peak memory,
- and avoid relying on an overly optimistic comment.

---

# 13. Observation: AVIF Tile Encoding Clones Tile Pixel Buffers

## Area

AVIF grid tile creation / single-tile encode interface.

## Observation

The tile path appears to create a tile buffer and then clone it into another owned image structure before encoding.

Conceptually:

```rust
tile_buffer
→ block.clone()
→ encoder image
```

For a 1024 × 1024 RGBA tile:

```text
~4 MiB
```

per duplicate tile buffer.

This is not catastrophic by itself, especially compared with a 200 MP source.

## Why it matters

It is an example of a repeated copy inside an already memory-sensitive path.

When combined with:

- encoder workspace,
- retained encoded tile output,
- source pixels,
- container assembly,

small avoidable copies contribute to peak memory and allocator pressure.

## Why the current design may be intentional

Ownership simplifies APIs.

Passing borrowed buffers through encoder abstractions may:

- complicate lifetimes,
- require API changes,
- or interact poorly with external crates.

This should be treated as an optimization candidate, not a correctness defect.

---

# 14. Observation: AVIF Grid Failure Can Trigger Expensive Full-Image Fallback

## Area

Grid encoder fallback.

Conceptually:

```rust
if let Ok(output) = encode_avif_grid(...) {
    return Ok(output);
}

encode_avif_single(...)
```

## Observation

If the grid attempt fails late, the implementation may discard substantial completed work and start a full-image AVIF encode.

Worst case:

```text
many tiles encoded successfully
→ late grid/container failure
→ discard work
→ encode full image from scratch
```

## Why this matters

Late fallback compounds both:

- latency,
- and memory pressure.

The fallback may also move from the safer tiled path into the more memory-demanding monolithic path.

## Why the current design may be intentional

Fallback behavior is often intentionally broad because:

- user success is more important than preserving the first implementation path,
- grid support may fail for unusual images,
- single-image encoding may support cases the grid builder does not.

This can be the right UX policy.

## Recommended refinement

Differentiate failure stages:

```text
failure before expensive tile work:
    fallback freely

failure after significant tile work:
    reconsider fallback or require memory check

structural grid incompatibility:
    choose single path before encoding
```

The point is to avoid a fallback whose cost is hidden.

---

# 15. Observation: 90° / 270° Rotation Requires Another Full RGBA Buffer

## Area

Pixel orientation transforms.

The rotation implementation contains a pattern such as:

```rust
let mut dst = vec![0u8; src.len()];
```

## Observation

For transforms that change pixel position significantly, a second full-size image buffer is allocated.

At 200 MP RGBA:

```text
source ≈ 800 MB
destination ≈ 800 MB
```

So orientation alone can temporarily require roughly:

```text
1.6 GB
```

of pixel buffers.

## Why this matters

Orientation is often perceived as metadata handling, but when it is baked into pixels it becomes a full image transformation.

If rotation occurs immediately before encode, the encoder may allocate still more buffers.

## Why the current design may be intentional

Out-of-place rotation is:

- straightforward,
- safe,
- easy to verify,
- and often significantly simpler than complex in-place block algorithms.

For moderate images it is a reasonable implementation.

Potential special cases such as 180° rotation or mirroring may be possible in-place, but implementing specialized paths increases complexity.

## Recommendation

Document orientation transforms as part of operation-specific memory estimation.

Only optimize to in-place/specialized variants if profiling shows the transform materially contributes to failures.

---

# 16. Observation: HEIF Alpha Reconstruction Can Accumulate Several Large Intermediates

## Area

HEIC/HEIF alpha extraction and reattachment path.

The logical pipeline appears similar to:

```text
HEIC source
→ extract alpha bitstream
→ temporary file
→ FFmpeg grayscale decode
→ read grayscale bytes
→ DarkLib attach alpha
→ decode base image
→ merge
```

## Observation

Large intermediates may coexist:

```text
source compressed bytes
base image bytes
grayscale alpha bytes
alpha plane
base RGBA pixels
output bytes
```

For very large images, the alpha plane itself is significant.

Example 200 MP grayscale plane:

```text
~200 MB at 8-bit
```

If duplicated, that alone can become hundreds of megabytes.

## Why this matters

The HEIF path may be perfectly acceptable at ordinary phone photo resolutions while becoming unsafe on extreme images.

This is a classic case where “works well at 12 MP” does not imply linear safety at 200 MP.

## Why the current design may be intentional

The path bridges multiple ecosystem limitations:

- platform HEIC support,
- FFmpeg behavior,
- alpha extraction,
- DarkLib's ownership of preservation policy.

Using intermediate files/buffers can be the most portable and understandable implementation.

## Recommended benchmark

Specifically test transparent HEIF/HEIC at:

```text
12 MP
50 MP
100 MP
200 MP (if realistically producible)
```

and record:

- peak RSS,
- temporary disk usage,
- processing time,
- whether grayscale buffers are duplicated.

---

# 17. Observation: ISOBMFF Metadata Injection Performs Full-Container Copies

## Area

ISOBMFF metadata/container surgery.

A simplified code shape includes:

```rust
let mut new_mdat = Vec::new();
new_mdat.extend_from_slice(...);

let mut out = Vec::with_capacity(...);

out.extend_from_slice(&wrap_box(b"mdat", &new_mdat));
```

with `wrap_box()` itself allocating a new complete vector.

## Observation

Large `mdat` payloads can therefore exist in multiple full copies:

```text
original container
new_mdat
wrapped_mdat
final output
```

Some of these lifetimes may not fully overlap depending on compiler/ownership scope, but the implementation creates several whole-container allocations.

## Why this matters

Metadata surgery sounds small because EXIF/ICC metadata is small.

However, rebuilding the container may copy the **entire compressed media payload** several times.

For a 200–500 MB media item, this can become:

- hundreds of MB of copying,
- substantial memory bandwidth,
- and temporary memory amplification.

## Why the current design may be intentional

In-memory rebuilding provides:

- simple offset calculations,
- atomic result construction,
- easy validation,
- fewer partial-file failure modes,
- easier testing.

This can be preferable to a streaming rewriter until real workloads require it.

## Recommended validation

Benchmark metadata-only operations versus file size:

```text
10 MB
50 MB
100 MB
250 MB
500 MB
```

If time and RSS scale strongly with whole-file size, consider a streaming/file-backed rewrite path for large media.

---

# 18. Observation: Preview Re-encoding Can Potentially Overlap During Interactive Quality Changes

## Area

Interactive compression UI.

## Observation

The screen uses sequencing/debounce logic to prevent stale results from replacing newer UI state.

However, a sequence number commonly solves:

```text
ignore obsolete result
```

but does not necessarily solve:

```text
cancel obsolete work
```

If the user adjusts quality repeatedly:

```text
encode Q90 starts
350 ms later → encode Q80 starts
350 ms later → encode Q70 starts
```

older jobs may still consume CPU and memory even if their results are discarded.

## Why this matters

This is especially dangerous for AVIF where one encode can take seconds.

Several obsolete encodes can overlap and turn an otherwise acceptable single-task peak into:

```text
N × codec workspace
N × pixel buffers
N × encoded output
```

## Why the current design may be intentional

True native cancellation is difficult.

Some encoders cannot be interrupted cleanly.

A debounce + ignore-old-result strategy is often the simplest safe UI model.

Therefore the right question is:

> Is obsolete-work overlap bounded enough for the supported formats and resolutions?

## Recommended validation

Instrument active encode count while rapidly changing quality:

```text
JPEG slider spam
WebP slider spam
AVIF slider spam
```

Track:

- active native operations,
- peak memory,
- CPU usage,
- cancellation effectiveness.

If cancellation is not practical, a single-flight scheduler can ensure:

```text
current operation finishes
→ only latest queued request runs next
```

instead of launching every intermediate value.

---

# 19. Observation: Full-Image Decode Happens Before Downscaling in Some Preview/Decode Paths

## Area

DarkLib decode with `max_edge` / preview-oriented decoding.

## Observation

The logical sequence appears to be:

```text
decode full-resolution source
→ then resize to requested maximum edge
```

rather than decode directly at a reduced resolution.

## Why this matters

For a huge source, requesting a tiny preview does not reduce the peak decode allocation.

Example:

```text
200 MP input
requested preview: 2048 px edge
```

still requires the full large image before the resize step.

This defeats the memory-saving purpose of previews for large images.

## Why the current design may be intentional

Generic image crates often expose:

```text
decode full image
```

more easily than format-specific scaled decode.

True reduced-resolution decode requires backend-specific support:

- JPEG IDCT scaling,
- HEIF thumbnails/derived images,
- AVIF decoder scaling or tiled decode,
- region decoding.

That complexity may not be justified yet.

## Recommended direction

Treat it as a capability optimization, not a universal rewrite:

```text
JPEG: use scaled decode if backend supports it
HEIF: use thumbnail/derived image when available
others: keep current fallback
```

This can dramatically improve large-image preview behavior without changing full-resolution processing semantics.

---

# 20. Compound Failure Scenarios

The most dangerous behavior is likely to emerge from combinations.

## Scenario A — Large AVIF preview while user changes quality

```text
200 MP source bytes retained
+ first AVIF encode
+ second obsolete AVIF encode
+ third current AVIF encode
+ output verification
+ after-preview full decode
```

Individually acceptable mechanisms may combine into an unrecoverable memory spike.

---

## Scenario B — Transparent large image → JPEG

```text
source bytes
→ source full decode
→ alpha flatten pixels
→ PNG intermediate
→ PNG decode
→ JPEG encode buffers
→ encoded JPEG bytes
→ alpha/preservation checks
→ full-resolution after-preview
```

This path deserves dedicated profiling because it crosses many of the identified amplification points.

---

## Scenario C — Two heavy queue tasks

```text
TaskRunner launches large job A
TaskRunner launches large job B
each creates several full-resolution buffers
Flutter keeps previews/cache
OS applies memory pressure
```

This can fail even though every isolated benchmark passes.

---

# 21. Suggested Benchmark Matrix

Before changing architecture, capture measurements.

## Dimensions

```text
12 MP
50 MP
100 MP
200 MP
```

## Formats

```text
JPEG
PNG
WebP
AVIF
HEIC
transparent PNG/WebP/AVIF/HEIC where supported
```

## Operations

```text
decode only
preview decode
encode only
encode + verification
metadata strip
metadata transplant
rotate 90°
alpha flatten → JPEG
AVIF grid encode
```

## Concurrency

```text
1 heavy task
2 heavy tasks
3 rapid preview encodes
heavy task + interactive preview
```

## Metrics

```text
wall-clock latency
peak RSS
Dart heap
native heap if measurable
CPU utilization
number of active workers
temporary disk bytes
encoded-output size
device thermal state
process termination / OOM
```

---

# 22. Measurements That Would Resolve the Most Uncertainty

The highest-value experiments are:

### 1. After-preview memory test

Does displaying the encoded result cause a major RSS jump?

### 2. Bridge-only byte transfer benchmark

How expensive is Flutter Rust Bridge for 10–250 MB byte arrays without codec work?

### 3. Alpha verification benchmark

How much time/memory is added by preservation verification after encoding?

### 4. Transparent → JPEG comparison

Current PNG-intermediate path versus direct pixel flatten → JPEG.

### 5. Concurrent task test

Can two individually successful large operations run safely together?

### 6. Interactive AVIF slider test

Do obsolete preview encodes remain alive concurrently?

These six tests would clarify most of the important architectural questions in this report.

---

# 23. Prioritization

## Tier 1 — Protect process stability

Focus first on:

1. heavy-task concurrency,
2. after-preview decode bounds,
3. peak-memory estimation,
4. obsolete interactive encode overlap.

These can determine whether the process survives.

---

## Tier 2 — Remove duplicated full-frame work

Investigate:

1. alpha verification re-decodes,
2. transparent → JPEG PNG intermediate,
3. repeated source inspection,
4. unnecessary full-buffer clones.

These can improve both latency and memory.

---

## Tier 3 — Optimize codec throughput

Only after memory behavior is controlled:

1. AVIF threading,
2. SIMD YUV conversion,
3. grid allocation improvements,
4. format-specific reduced-resolution decode.

These are valuable but less important than preventing multi-gigabyte transient memory.

---

# 24. Important Design Caveat

Several observations in this report describe implementations that may be intentionally conservative.

Examples:

- one-thread AVIF decode may reduce thermal or concurrency pressure,
- full output verification may be required by preservation guarantees,
- in-memory ISOBMFF rewriting may be intentionally chosen for correctness,
- PNG intermediate flattening may simplify a multi-backend architecture,
- `Vec<u8>` APIs may be preferred for safety and testability,
- fallback to a monolithic AVIF encode may intentionally maximize success probability.

Therefore:

> The presence of an expensive operation does not automatically imply that the implementation is wrong.

The engineering decision should depend on:

```text
measured cost
× expected workload
× device limits
× correctness requirements
× implementation complexity
```

The purpose of this report is to make those tradeoffs visible.

---

# 25. Overall Assessment

Hayn already shows unusually strong awareness of media correctness:

- alpha semantics,
- metadata preservation,
- ICC/CICP handling,
- HDR constraints,
- output verification,
- format capability differences,
- large-image testing,
- and platform-specific behavior.

The performance risk is largely a consequence of that thoroughness:

> correctness-oriented pipelines often accumulate extra passes, buffers, verification steps, and fallback layers.

For ordinary phone-sized media, many of these choices may be entirely reasonable.

The main concern is the project's ambition to also handle very large images.

Once image dimensions reach 100–200 MP, architectural details that are harmless at 12 MP become dominant:

```text
one extra full RGBA copy = hundreds of MB
one extra decode = significant latency
one duplicate operation = potentially another gigabyte-scale workload
```

The strongest recommendation is therefore not an immediate rewrite.

It is to introduce a **measured resource model** around the existing architecture:

```text
What buffers are live?
How many full-resolution passes happen?
How many heavy jobs may overlap?
What is the real peak RSS for this operation?
```

Once those numbers are available, the project can preserve its correctness-oriented design while selectively replacing only the paths that demonstrably create unacceptable cost.

---

# 26. Short Findings Index

| ID | Observation | Confidence | Main Risk |
|---|---|---|---|
| PERF-01 | Heavy tasks can overlap without obvious global memory budget | High | OOM / process kill |
| PERF-02 | After-preview may decode full-resolution output | High | Large UI-side memory spike |
| PERF-03 | Pixel limit is not equivalent to peak-memory limit | High | Multi-GB transient allocation |
| PERF-04 | Alpha verification may trigger extra full decodes | High | Duplicate CPU/RAM cost |
| PERF-05 | Transparent → JPEG uses PNG intermediate | High | Extra full encode/decode |
| PERF-06 | Source inspection/probing is repeated | High | Repeated parsing/copying |
| PERF-07 | Large byte buffers use FRB serialization repeatedly | High | Transfer/CPU/memory overhead |
| PERF-08 | AVIF decode is deliberately single-threaded | High | Throughput bottleneck |
| PERF-09 | YUV → RGB path appears scalar/per-pixel | High | CPU cost on large AVIF |
| PERF-10 | AVIF grid retains encoded tiles + assembly buffers | High | Underestimated peak memory |
| PERF-11 | Tile input clone adds repeated buffer copies | Medium | Allocator/memory overhead |
| PERF-12 | Late grid failure may trigger full encode fallback | Medium–High | Duplicate expensive work |
| PERF-13 | 90° rotation allocates second full RGBA frame | High | Peak memory amplification |
| PERF-14 | HEIF alpha reconstruction holds several intermediates | Medium–High | Large-image memory spikes |
| PERF-15 | ISOBMFF rewrite copies full payload multiple times | High | Large-file bandwidth/RAM |
| PERF-16 | Interactive preview jobs may outlive newer requests | Medium–High | CPU/RAM overlap |
| PERF-17 | Some preview/downscale paths decode full size first | High | Preview OOM on giant media |

---

# 27. Final Note

None of the observations above should be treated as absolute proof that a redesign is required.

The intended use of this report is:

```text
observation
→ benchmark
→ confirm or reject impact
→ optimize only where evidence justifies it
```

That approach is particularly important in Hayn because several “expensive” paths exist specifically to preserve image correctness, metadata semantics, or cross-platform behavior.

Performance work should therefore avoid replacing a correct but expensive pipeline with a faster pipeline whose preservation behavior is weaker or less measurable.
