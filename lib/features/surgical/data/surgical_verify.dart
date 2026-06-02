// ─────────────────────────────────────────────────────────────────────────────
// SurgicalVerify — the safety gate of the surgical replace (CLAUDE.md §3,
// 06-TESTING.md §5): NOTHING is overwritten until the candidate is proven safe.
//
// Pure + dependency-free so the decision is fully unit-tested. The caller (the
// service) does the actual decode through the platform probe and feeds the
// facts in: the candidate's byte length + its DECODED dimensions (0 when the
// decode failed → corrupt), against the original's size + dimensions.
//
// Rules:
//   • empty        — no candidate bytes.
//   • corrupt      — candidate didn't decode (zero/negative dimensions).
//   • dimsMismatch — dimensions differ from the original (allowing an
//                    orientation swap W↔H), unless the user asked to resize.
//   • notSmaller   — candidate is not actually smaller → replacing wastes the
//                    original for no gain, so we refuse.
//   • ok           — safe to proceed.
// ─────────────────────────────────────────────────────────────────────────────

enum SurgicalVerifyResult { ok, empty, corrupt, dimsMismatch, notSmaller }

abstract final class SurgicalVerify {
  static SurgicalVerifyResult check({
    required int originalBytes,
    required int candidateBytes,
    required int originalWidth,
    required int originalHeight,
    required int decodedWidth,
    required int decodedHeight,
    bool allowResize = false,
  }) {
    if (candidateBytes <= 0) return SurgicalVerifyResult.empty;
    if (decodedWidth <= 0 || decodedHeight <= 0) {
      return SurgicalVerifyResult.corrupt;
    }

    if (!allowResize && originalWidth > 0 && originalHeight > 0) {
      // Accept an orientation swap: a baked-upright encode of a rotated source
      // legitimately reports W↔H relative to the source's stored dimensions.
      final sameOrientation =
          decodedWidth == originalWidth && decodedHeight == originalHeight;
      final swappedOrientation =
          decodedWidth == originalHeight && decodedHeight == originalWidth;
      if (!sameOrientation && !swappedOrientation) {
        return SurgicalVerifyResult.dimsMismatch;
      }
    }

    if (originalBytes > 0 && candidateBytes >= originalBytes) {
      return SurgicalVerifyResult.notSmaller;
    }

    return SurgicalVerifyResult.ok;
  }

  static bool passed(SurgicalVerifyResult r) => r == SurgicalVerifyResult.ok;
}
