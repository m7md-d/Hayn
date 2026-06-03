//! Container detection (magic bytes) + per-format capability descriptor.

/// Image container, detected from leading magic bytes. Mirrors the set the app
/// already recognises (`SniffedFormat` in Dart), so behaviour is unchanged when
/// the live code migrates onto DarkLib.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageFormat {
    Jpeg,
    Png,
    Webp,
    Gif,
    Bmp,
    Tiff,
    Heic,
    Avif,
    Unknown,
}

/// Identify the container from its leading bytes. Pure; never panics.
pub fn detect(b: &[u8]) -> ImageFormat {
    if b.len() < 12 {
        return ImageFormat::Unknown;
    }
    // JPEG: FF D8 FF
    if b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF {
        return ImageFormat::Jpeg;
    }
    // PNG: 89 50 4E 47
    if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 {
        return ImageFormat::Png;
    }
    // GIF: "GIF8"
    if &b[0..4] == b"GIF8" {
        return ImageFormat::Gif;
    }
    // BMP: "BM"
    if b[0] == 0x42 && b[1] == 0x4D {
        return ImageFormat::Bmp;
    }
    // TIFF: "II*\0" or "MM\0*"
    if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00)
        || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A)
    {
        return ImageFormat::Tiff;
    }
    // RIFF????WEBP
    if &b[0..4] == b"RIFF" && &b[8..12] == b"WEBP" {
        return ImageFormat::Webp;
    }
    // ISO-BMFF "ftyp" box at offset 4; brand at 8..12 distinguishes HEIC/AVIF.
    if &b[4..8] == b"ftyp" {
        let brand = &b[8..12];
        if brand == b"avif" || brand == b"avis" {
            return ImageFormat::Avif;
        }
        if brand == b"heic"
            || brand == b"heix"
            || brand == b"mif1"
            || brand == b"hevc"
            || brand == b"msf1"
        {
            return ImageFormat::Heic;
        }
    }
    ImageFormat::Unknown
}

/// What a container can carry / support. Drives capability gating in the UI
/// (disable impossible options; warn on expected loss when converting). This
/// describes the FORMAT'S abilities, not whether DarkLib has implemented the op
/// yet — `metadata::strip` answers the latter via its `Result`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FormatDescriptor {
    pub format: ImageFormat,
    pub supports_exif: bool,
    pub supports_xmp: bool,
    pub supports_icc: bool,
    pub supports_iptc: bool,
    /// Metadata can be added/removed via container surgery, with no re-encode.
    pub lossless_metadata_ops: bool,
    /// The container can represent HDR (deep bit depth / gain map).
    pub hdr_capable: bool,
}

impl FormatDescriptor {
    pub fn of(format: ImageFormat) -> Self {
        let (exif, xmp, icc, iptc, lossless, hdr) = match format {
            ImageFormat::Jpeg => (true, true, true, true, true, false),
            ImageFormat::Png => (true, true, true, false, true, false),
            ImageFormat::Webp => (true, true, true, false, true, false),
            ImageFormat::Avif => (true, true, true, false, true, true),
            ImageFormat::Heic => (true, true, true, false, true, true),
            ImageFormat::Tiff => (true, true, true, true, false, false),
            ImageFormat::Gif => (false, true, false, false, false, false),
            ImageFormat::Bmp => (false, false, false, false, false, false),
            ImageFormat::Unknown => (false, false, false, false, false, false),
        };
        Self {
            format,
            supports_exif: exif,
            supports_xmp: xmp,
            supports_icc: icc,
            supports_iptc: iptc,
            lossless_metadata_ops: lossless,
            hdr_capable: hdr,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn isobmff(brand: &[u8; 4]) -> Vec<u8> {
        let mut v = vec![0x00, 0x00, 0x00, 0x18];
        v.extend_from_slice(b"ftyp");
        v.extend_from_slice(brand);
        v.extend_from_slice(&[0; 8]);
        v
    }

    #[test]
    fn detects_known_containers() {
        assert_eq!(
            detect(&[0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]),
            ImageFormat::Jpeg
        );
        assert_eq!(
            detect(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]),
            ImageFormat::Png
        );
        let mut webp = b"RIFF\0\0\0\0WEBPVP8 ".to_vec();
        webp.resize(20, 0);
        assert_eq!(detect(&webp), ImageFormat::Webp);
        assert_eq!(detect(&isobmff(b"avif")), ImageFormat::Avif);
        assert_eq!(detect(&isobmff(b"heic")), ImageFormat::Heic);
        assert_eq!(detect(&isobmff(b"mif1")), ImageFormat::Heic);
    }

    #[test]
    fn unknown_and_too_short() {
        assert_eq!(detect(&[]), ImageFormat::Unknown);
        assert_eq!(detect(&[0xFF, 0xD8]), ImageFormat::Unknown); // < 12 bytes
        assert_eq!(detect(&[0u8; 12]), ImageFormat::Unknown);
    }

    #[test]
    fn descriptor_flags_match_format() {
        assert!(FormatDescriptor::of(ImageFormat::Avif).hdr_capable);
        assert!(!FormatDescriptor::of(ImageFormat::Jpeg).hdr_capable);
        assert!(FormatDescriptor::of(ImageFormat::Png).supports_icc);
        assert!(!FormatDescriptor::of(ImageFormat::Bmp).lossless_metadata_ops);
    }
}
