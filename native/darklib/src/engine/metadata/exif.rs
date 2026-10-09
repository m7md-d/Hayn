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

/// An IFD entry: tag, type, count, and where its value (or offset) is.
type Entry = (u16, u16, u32, usize);
/// Byte ranges, start to end.
type Ranges = Vec<(usize, usize)>;

/// One IFD's entries as (tag, type, count, value-or-offset field position).
fn read_ifd(t: &Tiff, off: usize) -> Option<Vec<Entry>> {
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

/// A minimal little-endian TIFF/EXIF block holding only the Orientation tag,
/// for a strip that removes every other tag but must keep the image upright
/// (IMG-07). `None` for 1 and invalid values: absence already means upright.
pub fn orientation_only(orientation: u16) -> Option<Vec<u8>> {
    if !(2..=8).contains(&orientation) {
        return None;
    }
    let mut t = b"II\x2a\x00".to_vec();
    t.extend_from_slice(&8u32.to_le_bytes()); // IFD0 offset
    t.extend_from_slice(&1u16.to_le_bytes()); // one entry
    t.extend_from_slice(&0x0112u16.to_le_bytes()); // Orientation
    t.extend_from_slice(&3u16.to_le_bytes()); // SHORT
    t.extend_from_slice(&1u32.to_le_bytes()); // count
    t.extend_from_slice(&orientation.to_le_bytes());
    t.extend_from_slice(&[0, 0]);
    t.extend_from_slice(&0u32.to_le_bytes()); // no next IFD
    Some(t)
}

/// Return a copy of `tiff` with the Orientation tag forced to 1 (call after
/// baking orientation into the pixels — single source of truth). No Orientation
/// tag → returned unchanged (absence means upright). Bounds-safe; never panics.
pub fn with_orientation_1(tiff: &[u8]) -> Vec<u8> {
    let mut out = tiff.to_vec();
    if out.len() < 8 {
        return out;
    }
    let le = match &out[0..2] {
        b"II" => true,
        b"MM" => false,
        _ => return out,
    };
    let r16 = |b: &[u8], o: usize| -> Option<u16> {
        b.get(o..o + 2).map(|s| {
            if le {
                u16::from_le_bytes([s[0], s[1]])
            } else {
                u16::from_be_bytes([s[0], s[1]])
            }
        })
    };
    let r32 = |b: &[u8], o: usize| -> Option<u32> {
        b.get(o..o + 4).map(|s| {
            if le {
                u32::from_le_bytes([s[0], s[1], s[2], s[3]])
            } else {
                u32::from_be_bytes([s[0], s[1], s[2], s[3]])
            }
        })
    };
    if r16(&out, 2) != Some(0x002A) {
        return out;
    }
    let ifd0 = match r32(&out, 4) {
        Some(v) => v as usize,
        None => return out,
    };
    let count = match r16(&out, ifd0) {
        Some(c) => c as usize,
        None => return out,
    };
    let mut p = ifd0 + 2;
    for _ in 0..count {
        if p + 12 > out.len() {
            break;
        }
        if r16(&out, p) == Some(0x0112) {
            let one: [u8; 2] = if le { [1, 0] } else { [0, 1] };
            out[p + 8] = one[0];
            out[p + 9] = one[1];
            out[p + 10] = 0;
            out[p + 11] = 0;
            break;
        }
        p += 12;
    }
    out
}

/// Bytes of one value of TIFF `typ`; 0 for an unknown type.
fn type_size(typ: u16) -> usize {
    match typ {
        1 | 2 | 6 | 7 => 1,
        3 | 8 => 2,
        4 | 9 | 11 | 13 => 4,
        5 | 10 | 12 => 8,
        _ => 0,
    }
}

/// The byte ranges of the IFD at `off` and of its values stored outside it.
fn ifd_ranges(t: &Tiff, off: usize) -> Option<(Vec<Entry>, Ranges)> {
    let entries = read_ifd(t, off)?;
    let mut ranges = vec![(off, off + 2 + 12 * entries.len() + 4)];
    for &(_, typ, count, field) in &entries {
        let size = type_size(typ).checked_mul(count as usize)?;
        if size > 4 {
            let at = t.u32(field)? as usize;
            ranges.push((at, at.checked_add(size)?));
        }
    }
    Some((entries, ranges))
}

/// A copy of `tiff` without its thumbnail (IFD1), for new pixels (Hayn
/// metadata model): the thumbnail is a picture of the old ones, and once
/// those are turned upright its own orientation is wrong too. IFD0 stops
/// linking to it, its bytes are zeroed (they show the old picture), and the
/// block is cut where they were last in it, as they usually are. No IFD1, or a
/// block not read: unchanged.
pub fn without_thumbnail(tiff: &[u8]) -> Vec<u8> {
    let mut out = tiff.to_vec();
    let Some((le, ifd0)) = header(tiff) else {
        return out;
    };
    let t = Tiff { b: tiff, le };
    let Some((ifd0_entries, mut kept)) = ifd_ranges(&t, ifd0) else {
        return out;
    };
    let next_at = ifd0 + 2 + 12 * ifd0_entries.len();
    let Some(ifd1) = t.u32(next_at).filter(|&o| o != 0).map(|o| o as usize) else {
        return out;
    };
    let Some((ifd1_entries, mut gone)) = ifd_ranges(&t, ifd1) else {
        return out;
    };
    // The thumbnail's data: a JPEG (0x201/0x202) or one strip (0x111/0x117).
    let value = |entries: &[Entry], tag: u16| {
        entries
            .iter()
            .find(|e| e.0 == tag && e.2 == 1)
            .and_then(|&(_, typ, _, field)| match typ {
                3 => t.u16(field).map(|v| v as usize),
                4 => t.u32(field).map(|v| v as usize),
                _ => None,
            })
    };
    for (at, len) in [(0x0201, 0x0202), (0x0111, 0x0117)] {
        if let (Some(at), Some(len)) = (value(&ifd1_entries, at), value(&ifd1_entries, len)) {
            gone.push((at, at.saturating_add(len)));
        }
    }
    // What the other IFDs use: Exif (0x8769), GPS (0x8825), Interop (0xA005).
    let mut pending: Vec<usize> = [0x8769, 0x8825]
        .iter()
        .filter_map(|&tag| value(&ifd0_entries, tag))
        .collect();
    while let Some(off) = pending.pop() {
        let Some((entries, ranges)) = ifd_ranges(&t, off) else {
            break;
        };
        pending.extend(value(&entries, 0xA005));
        kept.extend(ranges);
    }
    let write = |out: &mut Vec<u8>, at: usize, v: u32| {
        let b = if le { v.to_le_bytes() } else { v.to_be_bytes() };
        out[at..at + 4].copy_from_slice(&b);
    };
    write(&mut out, next_at, 0);
    // A malformed block may point IFD1 into data still in use: never zero that.
    let in_use = |s: usize, e: usize| kept.iter().any(|&(ks, ke)| s < ke && ks < e);
    for &(start, end) in &gone {
        if in_use(start, end) {
            continue;
        }
        if let Some(bytes) = out.get_mut(start..end.min(tiff.len())) {
            bytes.fill(0);
        }
    }
    // Cut only what ends the block: bytes after it may be a MakerNote's,
    // whose offsets can reach past the length it declares.
    let kept_end = kept.iter().map(|r| r.1).max().unwrap_or(0);
    let gone_start = gone.iter().map(|r| r.0).min().unwrap_or(usize::MAX);
    let gone_end = gone.iter().map(|r| r.1).max().unwrap_or(0);
    if gone_start >= kept_end && gone_end >= out.len() && gone_start < out.len() {
        out.truncate(gone_start.max(8));
    }
    out
}

/// The byte order and IFD0 offset of a TIFF block.
fn header(tiff: &[u8]) -> Option<(bool, usize)> {
    let le = match tiff.get(0..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let t = Tiff { b: tiff, le };
    (t.u16(2)? == 0x002A).then_some(())?;
    Some((le, t.u32(4)? as usize))
}

/// EXIF for new pixels: turned upright ([`with_orientation_1`]) and without
/// the old thumbnail ([`without_thumbnail`]).
pub fn for_new_pixels(tiff: &[u8]) -> Vec<u8> {
    without_thumbnail(&with_orientation_1(tiff))
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

    /// `sample_tiff` with an IFD1 linking a 6-byte "thumbnail" after it.
    fn with_thumbnail() -> Vec<u8> {
        let mut v = sample_tiff();
        let ifd1 = v.len() as u32;
        let next_at = 8 + 2 + 4 * 12;
        v[next_at..next_at + 4].copy_from_slice(&ifd1.to_le_bytes());
        let data = ifd1 + 2 + 2 * 12 + 4;
        v.extend_from_slice(&2u16.to_le_bytes());
        for (tag, value) in [(0x0201u16, data), (0x0202, 6)] {
            v.extend_from_slice(&tag.to_le_bytes());
            v.extend_from_slice(&4u16.to_le_bytes());
            v.extend_from_slice(&1u32.to_le_bytes());
            v.extend_from_slice(&value.to_le_bytes());
        }
        v.extend_from_slice(&0u32.to_le_bytes());
        v.extend_from_slice(b"\xFF\xD8OLD!");
        v
    }

    #[test]
    fn the_old_thumbnail_goes_with_its_bytes() {
        let tiff = with_thumbnail();
        let out = without_thumbnail(&tiff);
        assert_eq!(out, sample_tiff(), "unlinked and cut where it was last");
        assert_eq!(summarize(&out), summarize(&tiff), "the rest as it was");
        // Not last in the block (something follows): zeroed, not cut.
        let mut tiff = with_thumbnail();
        let gps = sample_tiff().len() - 4 - 12 - 2;
        tiff.extend_from_slice(b"tail");
        let out = without_thumbnail(&tiff);
        assert_eq!(out.len(), tiff.len());
        assert!(!out.windows(4).any(|w| w == b"OLD!"));
        assert!(out.ends_with(b"tail"));
        assert_eq!(&out[gps..gps + 2], &1u16.to_le_bytes(), "GPS IFD untouched");
        // No IFD1: unchanged; for new pixels also upright.
        assert_eq!(without_thumbnail(&sample_tiff()), sample_tiff());
        assert_eq!(
            summarize(&for_new_pixels(&with_thumbnail()))
                .unwrap()
                .orientation,
            1
        );
    }
}
