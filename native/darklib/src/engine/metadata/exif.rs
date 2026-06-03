//! Minimal EXIF (TIFF) reader — just enough for the "what will be removed"
//! summary and the unified orientation field. NOT a full tag dictionary: it
//! walks IFD0 plus the Exif and GPS sub-IFDs, fully bounds-checked, and never
//! panics. A non-TIFF / malformed block yields `None`.

/// A small summary of an EXIF/TIFF block.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ExifSummary {
    pub has_gps: bool,
    pub has_date: bool,
    pub has_camera: bool,
    /// EXIF orientation (1..=8); 1 = upright. Defaults to 1 when absent.
    pub orientation: u16,
    /// Total entries across IFD0 + Exif IFD + GPS IFD (an approximate "how much
    /// metadata is here" for the UI, not an exact tag census).
    pub tag_count: u32,
}

#[derive(Clone, Copy)]
struct Tiff<'a> {
    b: &'a [u8],
    le: bool,
}

impl Tiff<'_> {
    fn u16(&self, o: usize) -> Option<u16> {
        let s = self.b.get(o..o + 2)?;
        Some(if self.le {
            u16::from_le_bytes([s[0], s[1]])
        } else {
            u16::from_be_bytes([s[0], s[1]])
        })
    }
    fn u32(&self, o: usize) -> Option<u32> {
        let s = self.b.get(o..o + 4)?;
        let a = [s[0], s[1], s[2], s[3]];
        Some(if self.le {
            u32::from_le_bytes(a)
        } else {
            u32::from_be_bytes(a)
        })
    }
}

/// One IFD's entries as (tag, type, count, value-or-offset field position).
fn read_ifd(t: &Tiff, off: usize) -> Option<Vec<(u16, u16, u32, usize)>> {
    let count = t.u16(off)? as usize;
    let mut p = off.checked_add(2)?;
    let mut out = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        if p.checked_add(12)? > t.b.len() {
            return None;
        }
        out.push((t.u16(p)?, t.u16(p + 2)?, t.u32(p + 4)?, p + 8));
        p += 12;
    }
    Some(out)
}

/// Summarise a TIFF/EXIF block (starting at the `II`/`MM` header).
pub fn summarize(tiff: &[u8]) -> Option<ExifSummary> {
    if tiff.len() < 8 {
        return None;
    }
    let le = match &tiff[0..2] {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let t = Tiff { b: tiff, le };
    if t.u16(2)? != 0x002A {
        return None;
    }
    let ifd0 = read_ifd(&t, t.u32(4)? as usize)?;

    let mut s = ExifSummary {
        orientation: 1,
        ..Default::default()
    };
    let mut total = ifd0.len() as u32;
    let mut exif_off = None;
    let mut gps_off = None;
    for (tag, _typ, _cnt, vpos) in &ifd0 {
        match *tag {
            0x0112 => {
                if let Some(v) = t.u16(*vpos) {
                    if (1..=8).contains(&v) {
                        s.orientation = v;
                    }
                }
            }
            0x010F | 0x0110 => s.has_camera = true, // Make / Model
            0x0132 => s.has_date = true,            // DateTime
            0x8769 => exif_off = t.u32(*vpos).map(|v| v as usize), // Exif IFD pointer
            0x8825 => {
                gps_off = t.u32(*vpos).map(|v| v as usize); // GPS IFD pointer
                s.has_gps = true;
            }
            _ => {}
        }
    }
    if let Some(off) = exif_off {
        if let Some(e) = read_ifd(&t, off) {
            total += e.len() as u32;
            for (tag, _, _, _) in &e {
                if *tag == 0x9003 || *tag == 0x9004 {
                    s.has_date = true; // DateTimeOriginal / Digitized
                }
            }
        }
    }
    if let Some(off) = gps_off {
        if let Some(g) = read_ifd(&t, off) {
            total += g.len() as u32;
        }
    }
    s.tag_count = total;
    Some(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a tiny little-endian TIFF: IFD0(orientation, Make, DateTime, GPS
    /// pointer) + a GPS IFD with one entry.
    fn sample_tiff() -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(b"II");
        v.extend_from_slice(&0x002Au16.to_le_bytes());
        v.extend_from_slice(&8u32.to_le_bytes()); // IFD0 at offset 8

        let gps_ifd_off: u32 = 8 + 2 + 4 * 12 + 4; // header + IFD0
        let entry = |v: &mut Vec<u8>, tag: u16, typ: u16, cnt: u32, val: [u8; 4]| {
            v.extend_from_slice(&tag.to_le_bytes());
            v.extend_from_slice(&typ.to_le_bytes());
            v.extend_from_slice(&cnt.to_le_bytes());
            v.extend_from_slice(&val);
        };

        v.extend_from_slice(&4u16.to_le_bytes()); // IFD0 entry count
        entry(&mut v, 0x0112, 3, 1, [6, 0, 0, 0]); // Orientation = 6
        entry(&mut v, 0x010F, 2, 4, *b"Cam\0"); // Make
        entry(&mut v, 0x0132, 2, 4, *b"2024"); // DateTime
        entry(&mut v, 0x8825, 4, 1, gps_ifd_off.to_le_bytes()); // GPS IFD pointer
        v.extend_from_slice(&0u32.to_le_bytes()); // next IFD = 0

        // GPS IFD: one entry.
        v.extend_from_slice(&1u16.to_le_bytes());
        entry(&mut v, 0x0001, 2, 2, *b"N\0\0\0"); // GPSLatitudeRef
        v.extend_from_slice(&0u32.to_le_bytes());
        v
    }

    #[test]
    fn parses_orientation_gps_date_camera() {
        let s = summarize(&sample_tiff()).unwrap();
        assert_eq!(s.orientation, 6);
        assert!(s.has_gps);
        assert!(s.has_date);
        assert!(s.has_camera);
        assert_eq!(s.tag_count, 5); // 4 in IFD0 + 1 in GPS IFD
    }

    #[test]
    fn big_endian_orientation() {
        let mut v = Vec::new();
        v.extend_from_slice(b"MM");
        v.extend_from_slice(&0x002Au16.to_be_bytes());
        v.extend_from_slice(&8u32.to_be_bytes());
        v.extend_from_slice(&1u16.to_be_bytes()); // one entry
        v.extend_from_slice(&0x0112u16.to_be_bytes()); // Orientation
        v.extend_from_slice(&3u16.to_be_bytes()); // SHORT
        v.extend_from_slice(&1u32.to_be_bytes());
        v.extend_from_slice(&8u16.to_be_bytes()); // value 8 (in first 2 bytes, BE)
        v.extend_from_slice(&0u16.to_be_bytes()); // padding of the value field
        v.extend_from_slice(&0u32.to_be_bytes()); // next IFD
        let s = summarize(&v).unwrap();
        assert_eq!(s.orientation, 8);
        assert!(!s.has_gps);
    }

    #[test]
    fn non_tiff_is_none() {
        assert!(summarize(b"not a tiff at all").is_none());
        assert!(summarize(&[]).is_none());
    }
}
