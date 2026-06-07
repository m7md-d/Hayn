//! Lossless EXIF / XMP strip for ISOBMFF still images (AVIF, HEIF/HEIC).
//!
//! This is the capability Android never had (the Dart path only stripped JPEG/
//! PNG/WebP; HEIC/AVIF needed iOS ImageIO). EXIF and XMP live as *items* inside
//! the `meta` box, with their bytes in `mdat`. Removing them means rewriting
//! `iinf`/`iloc`/`iref` and rebuilding `mdat` — and because `iloc` stores
//! ABSOLUTE file offsets, every surviving item's offset shifts.
//!
//! Rather than patch offsets in place (one slip = a corrupt image — the exact
//! failure we must never ship), we **rebuild with fresh offsets**: copy only the
//! kept items' data into a new `mdat`, recompute their `iloc` offsets, and then
//! **self-validate** the result — re-parse it and byte-compare every kept item
//! (incl. the primary image) against the source. Any mismatch, or any structure
//! outside the supported subset, returns `UnsupportedFormat` so the caller skips
//! the file untouched. The codec payload (AV1/HEVC) is never touched.
//!
//! ICC/orientation in ISOBMFF are stored as item *properties* (`iprp`), not as
//! items, and are handled in the colour/correctness stage — not here.

use std::collections::HashSet;

use super::StripPolicy;
use crate::engine::error::{DarkError, Result};

/// Strip EXIF + XMP items. `policy` is accepted for interface symmetry but ICC/
/// orientation don't apply to item-level surgery (see module docs).
pub fn strip(b: &[u8], _policy: StripPolicy) -> Result<Vec<u8>> {
    strip_inner(b).ok_or(DarkError::UnsupportedFormat)
}

/// Raw EXIF (TIFF block) + XMP packet extracted from an ISOBMFF image.
type ExifXmp = (Option<Vec<u8>>, Option<Vec<u8>>);

/// Extract the raw EXIF (TIFF block) and XMP packet, if present. Reuses the box
/// parser; best-effort and bounds-safe (returns `(None, None)` on anything it
/// can't read).
pub fn extract_exif_xmp(b: &[u8]) -> ExifXmp {
    extract_inner(b).unwrap_or((None, None))
}

fn extract_inner(b: &[u8]) -> Option<ExifXmp> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(b, meta.body + 4, meta.end)?;
    let iinf = *mc.iter().find(|x| x.typ == *b"iinf")?;
    let iloc_box = *mc.iter().find(|x| x.typ == *b"iloc")?;
    let (_v, items) = parse_iinf(b, iinf)?;
    let loc = parse_iloc(b, iloc_box)?;

    let mut exif = None;
    let mut xmp = None;
    for (it, _) in &items {
        let Some(l) = loc.items.iter().find(|x| x.id == it.id) else {
            continue;
        };
        if it.typ == *b"Exif" {
            if let Some(data) = read_item(b, l) {
                // data = u32 exif_tiff_header_offset + the TIFF block.
                if data.len() >= 4 {
                    let off = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
                    if let Some(start) = 4usize.checked_add(off) {
                        if start <= data.len() {
                            exif = Some(data[start..].to_vec());
                        }
                    }
                }
            }
        } else if is_xmp(it) {
            if let Some(data) = read_item(b, l) {
                xmp = Some(data);
            }
        }
    }
    Some((exif, xmp))
}

/// Extract an embedded ICC profile — the `colr` item property of type `prof`
/// (or restricted `rICC`) inside `iprp`/`ipco`. Best-effort and bounds-safe.
///
/// nclx (coding-independent code points — the Display-P3 tag iPhone HEIC uses
/// instead of an embedded profile) is intentionally NOT returned here: it isn't
/// an ICC blob, and mapping it to one is a separate colour-management step.
pub fn extract_icc(b: &[u8]) -> Option<Vec<u8>> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(b, meta.body + 4, meta.end)?;
    let iprp = *mc.iter().find(|x| x.typ == *b"iprp")?;
    let ipco = *boxes_in(b, iprp.body, iprp.end)?
        .iter()
        .find(|x| x.typ == *b"ipco")?;
    for prop in boxes_in(b, ipco.body, ipco.end)? {
        // `colr` is a plain box: colour_type(4) then, for prof/rICC, the profile.
        if prop.typ == *b"colr" {
            let ct = b.get(prop.body..prop.body + 4)?;
            if ct == b"prof" || ct == b"rICC" {
                return b.get(prop.body + 4..prop.end).map(<[u8]>::to_vec);
            }
        }
    }
    None
}

/// Read the nclx colour code points (`colour_primaries`, `transfer_characteristics`)
/// from a `colr`/`nclx` property, if present. Lets a profile-less AVIF/HEIF (e.g.
/// iPhone's Display-P3 HEIC) be given a synthesised ICC on convert. `None` when
/// there is no nclx `colr`.
pub fn extract_nclx(b: &[u8]) -> Option<(u16, u16)> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(b, meta.body + 4, meta.end)?;
    let iprp = *mc.iter().find(|x| x.typ == *b"iprp")?;
    let ipco = *boxes_in(b, iprp.body, iprp.end)?
        .iter()
        .find(|x| x.typ == *b"ipco")?;
    for prop in boxes_in(b, ipco.body, ipco.end)? {
        if prop.typ == *b"colr" && b.get(prop.body..prop.body + 4)? == b"nclx" {
            // nclx: colour_type(4) + primaries(2) + transfer(2) + matrix(2) + range(1)
            return Some((be_u16(b, prop.body + 4)?, be_u16(b, prop.body + 6)?));
        }
    }
    None
}

/// Extract the primary item's coded AV1 bytes (the still picture's temporal unit)
/// from an AVIF, ready to hand to a decoder. Returns `None` when the primary item
/// isn't AV1 (`av01`) — e.g. HEVC-coded HEIC, which we never software-decode
/// (patents, CLAUDE.md §5) — or when it isn't a plain `construction_method == 0`
/// item (a `grid`/`idat` layout is outside this subset), so the caller falls back
/// to a platform decoder. Read-only and bounds-safe.
pub fn extract_primary_av1(b: &[u8]) -> Option<Vec<u8>> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(b, meta.body + 4, meta.end)?;
    let primary_id = parse_pitm(b, *mc.iter().find(|x| x.typ == *b"pitm")?)?;
    let (_v, items) = parse_iinf(b, *mc.iter().find(|x| x.typ == *b"iinf")?)?;
    let (prim, _) = items.iter().find(|(it, _)| it.id == primary_id)?;
    if prim.typ != *b"av01" {
        return None; // HEVC/HEIC or a derived (grid/tmap) primary — not ours
    }
    let loc = parse_iloc(b, *mc.iter().find(|x| x.typ == *b"iloc")?)?;
    let l = loc.items.iter().find(|x| x.id == primary_id)?;
    if l.method != 0 {
        return None; // idat / item-offset construction — outside the simple subset
    }
    read_item(b, l)
}

/// Extract the AV1 configuration OBUs (the sequence header) from the first `av1C`
/// property in `iprp`/`ipco`. AVIF keeps the sequence header here and the frame
/// OBUs in the item data; prepending these makes the stream self-contained for a
/// decoder. `None` when absent. (A single still has one `av1C`; an alpha-aux image
/// adds a second — selecting per-item via `ipma` lands with alpha decode.)
pub fn extract_av1c_config_obus(b: &[u8]) -> Option<Vec<u8>> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(b, meta.body + 4, meta.end)?;
    let iprp = *mc.iter().find(|x| x.typ == *b"iprp")?;
    let ipco = *boxes_in(b, iprp.body, iprp.end)?
        .iter()
        .find(|x| x.typ == *b"ipco")?;
    for prop in boxes_in(b, ipco.body, ipco.end)? {
        if prop.typ == *b"av1C" {
            // av1C: marker+version(1) + seq_profile/level(1) + flags(1) + delay(1),
            // then the configOBUs (the sequence header).
            return b.get(prop.body + 4..prop.end).map(<[u8]>::to_vec);
        }
    }
    None
}

/// Whether this ISOBMFF still carries an HDR gain map — either an ISO 21496-1
/// `tmap` (tone-map) derived item, or an auxiliary image whose `auxC` URN names
/// a gain map (e.g. Apple's `…:hdrgainmap`). Read-only; the gain map is a
/// first-class auxiliary asset that container ops must never silently drop.
pub fn has_gainmap(b: &[u8]) -> bool {
    gainmap_inner(b).unwrap_or(false)
}

fn gainmap_inner(b: &[u8]) -> Option<bool> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(b, meta.body + 4, meta.end)?;
    // ISO 21496-1: the gain map is a `tmap` derived item.
    if let Some(iinf) = mc.iter().find(|x| x.typ == *b"iinf") {
        if let Some((_, items)) = parse_iinf(b, *iinf) {
            if items.iter().any(|(it, _)| it.typ == *b"tmap") {
                return Some(true);
            }
        }
    }
    // Apple/aux gain map: an `auxC` property whose URN names a gain map.
    if let Some(iprp) = mc.iter().find(|x| x.typ == *b"iprp") {
        if let Some(ipco) = boxes_in(b, iprp.body, iprp.end)?
            .iter()
            .find(|x| x.typ == *b"ipco")
        {
            for prop in boxes_in(b, ipco.body, ipco.end)? {
                if prop.typ == *b"auxC" {
                    // FullBox(4) then a null-terminated aux_type URN.
                    let urn = b.get(prop.body + 4..prop.end)?;
                    let end = urn.iter().position(|&c| c == 0).unwrap_or(urn.len());
                    if contains_ascii_ci(&urn[..end], b"gainmap") {
                        return Some(true);
                    }
                }
            }
        }
    }
    Some(false)
}

fn contains_ascii_ci(haystack: &[u8], needle: &[u8]) -> bool {
    needle.len() <= haystack.len()
        && haystack
            .windows(needle.len())
            .any(|w| w.eq_ignore_ascii_case(needle))
}

// ── big-endian readers ──────────────────────────────────────────────────────

fn be_u16(b: &[u8], o: usize) -> Option<u16> {
    b.get(o..o + 2).map(|s| u16::from_be_bytes([s[0], s[1]]))
}
fn be_u32(b: &[u8], o: usize) -> Option<u32> {
    b.get(o..o + 4)
        .map(|s| u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}
fn be_u64(b: &[u8], o: usize) -> Option<u64> {
    b.get(o..o + 8)
        .map(|s| u64::from_be_bytes(s.try_into().unwrap()))
}
/// Read an `n`-byte big-endian uint (n ∈ {0,4,8}); returns (value, next offset).
fn read_uint(b: &[u8], o: usize, n: usize) -> Option<(u64, usize)> {
    match n {
        0 => Some((0, o)),
        4 => be_u32(b, o).map(|v| (v as u64, o + 4)),
        8 => be_u64(b, o).map(|v| (v, o + 8)),
        _ => None,
    }
}
fn write_uint(out: &mut Vec<u8>, v: u64, n: usize) {
    match n {
        4 => out.extend_from_slice(&(v as u32).to_be_bytes()),
        8 => out.extend_from_slice(&v.to_be_bytes()),
        _ => {}
    }
}

// ── box model ───────────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
struct Bx {
    typ: [u8; 4],
    start: usize, // box start (the size field)
    body: usize,  // payload start
    end: usize,   // box end (exclusive)
}

fn read_box(b: &[u8], pos: usize) -> Option<Bx> {
    if pos + 8 > b.len() {
        return None;
    }
    let size32 = be_u32(b, pos)? as usize;
    let typ = [b[pos + 4], b[pos + 5], b[pos + 6], b[pos + 7]];
    let (size, body) = if size32 == 1 {
        (be_u64(b, pos + 8)? as usize, pos + 16)
    } else if size32 == 0 {
        (b.len() - pos, pos + 8)
    } else {
        (size32, pos + 8)
    };
    let end = pos.checked_add(size)?;
    if end > b.len() || body > end {
        return None;
    }
    Some(Bx {
        typ,
        start: pos,
        body,
        end,
    })
}

fn boxes_in(b: &[u8], start: usize, end: usize) -> Option<Vec<Bx>> {
    let mut v = Vec::new();
    let mut p = start;
    while p < end {
        let bx = read_box(b, p)?;
        if bx.end <= p || bx.end > end {
            return None;
        }
        v.push(bx);
        p = bx.end;
    }
    Some(v)
}

fn wrap_box(typ: &[u8; 4], payload: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(8 + payload.len());
    v.extend_from_slice(&((8 + payload.len()) as u32).to_be_bytes());
    v.extend_from_slice(typ);
    v.extend_from_slice(payload);
    v
}

// ── parsed structures ───────────────────────────────────────────────────────

struct Item {
    id: u32,
    typ: [u8; 4],
    content_type: Option<String>,
}

struct Extent {
    offset: u64,
    length: u64,
}

struct Loc {
    id: u32,
    method: u8,
    data_ref: u16,
    base_offset: u64,
    extents: Vec<Extent>,
    /// Byte span of this item's record inside the source `iloc` payload, so the
    /// in-place path can copy kept entries verbatim (offsets untouched).
    entry: (usize, usize),
}

struct Iloc {
    version: u8,
    offset_size: usize,
    length_size: usize,
    base_offset_size: usize,
    index_size: usize,
    items: Vec<Loc>,
}

fn parse_iinf(b: &[u8], iinf: Bx) -> Option<(u8, Vec<(Item, Bx)>)> {
    let p = iinf.body;
    let version = *b.get(p)?;
    let mut q = p + 4; // version + flags
    let count = if version == 0 {
        let c = be_u16(b, q)? as usize;
        q += 2;
        c
    } else {
        let c = be_u32(b, q)? as usize;
        q += 4;
        c
    };
    let infes = boxes_in(b, q, iinf.end)?;
    if infes.len() != count {
        return None;
    }
    let mut items = Vec::with_capacity(count);
    for ib in infes {
        if ib.typ != *b"infe" {
            return None;
        }
        items.push((parse_infe(b, ib)?, ib));
    }
    Some((version, items))
}

fn parse_infe(b: &[u8], infe: Bx) -> Option<Item> {
    let p = infe.body;
    let version = *b.get(p)?;
    let mut q = p + 4; // version + flags
    let id = match version {
        2 => {
            let v = be_u16(b, q)? as u32;
            q += 2;
            v
        }
        3 => {
            let v = be_u32(b, q)?;
            q += 4;
            v
        }
        _ => return None, // pre-v2 infe unsupported → bail
    };
    q += 2; // item_protection_index
    let typ = [*b.get(q)?, *b.get(q + 1)?, *b.get(q + 2)?, *b.get(q + 3)?];
    q += 4;
    // item_name (null-terminated)
    let name = b.get(q..infe.end)?;
    let name_len = name.iter().position(|&c| c == 0)?;
    q += name_len + 1;
    let content_type = if typ == *b"mime" {
        let ct = b.get(q..infe.end)?;
        let ct_len = ct.iter().position(|&c| c == 0).unwrap_or(ct.len());
        Some(String::from_utf8_lossy(&ct[..ct_len]).into_owned())
    } else {
        None
    };
    Some(Item {
        id,
        typ,
        content_type,
    })
}

fn parse_iloc(b: &[u8], iloc: Bx) -> Option<Iloc> {
    let p = iloc.body;
    let version = *b.get(p)?;
    let mut q = p + 4;
    let byte0 = *b.get(q)?;
    let byte1 = *b.get(q + 1)?;
    q += 2;
    let offset_size = (byte0 >> 4) as usize;
    let length_size = (byte0 & 0x0F) as usize;
    let base_offset_size = (byte1 >> 4) as usize;
    let index_size = (byte1 & 0x0F) as usize;
    let item_count = if version < 2 {
        let c = be_u16(b, q)? as usize;
        q += 2;
        c
    } else {
        let c = be_u32(b, q)? as usize;
        q += 4;
        c
    };
    let mut items = Vec::with_capacity(item_count);
    for _ in 0..item_count {
        let entry_start = q;
        let id = if version < 2 {
            let v = be_u16(b, q)? as u32;
            q += 2;
            v
        } else {
            let v = be_u32(b, q)?;
            q += 4;
            v
        };
        let method = if version == 1 || version == 2 {
            let v = be_u16(b, q)?;
            q += 2;
            (v & 0x0F) as u8
        } else {
            0
        };
        let data_ref = be_u16(b, q)?;
        q += 2;
        let (base_offset, nq) = read_uint(b, q, base_offset_size)?;
        q = nq;
        let extent_count = be_u16(b, q)? as usize;
        q += 2;
        let mut extents = Vec::with_capacity(extent_count);
        for _ in 0..extent_count {
            if (version == 1 || version == 2) && index_size > 0 {
                let (_idx, nq) = read_uint(b, q, index_size)?;
                q = nq;
            }
            let (offset, nq) = read_uint(b, q, offset_size)?;
            q = nq;
            let (length, nq) = read_uint(b, q, length_size)?;
            q = nq;
            extents.push(Extent { offset, length });
        }
        items.push(Loc {
            id,
            method,
            data_ref,
            base_offset,
            extents,
            entry: (entry_start, q),
        });
    }
    Some(Iloc {
        version,
        offset_size,
        length_size,
        base_offset_size,
        index_size,
        items,
    })
}

fn is_xmp(it: &Item) -> bool {
    it.typ == *b"mime"
        && it
            .content_type
            .as_deref()
            .map(|c| c.starts_with("application/rdf+xml"))
            .unwrap_or(false)
}

fn is_victim(it: &Item) -> bool {
    it.typ == *b"Exif" || is_xmp(it)
}

fn read_item(file: &[u8], it: &Loc) -> Option<Vec<u8>> {
    let mut d = Vec::new();
    for e in &it.extents {
        let off = (it.base_offset + e.offset) as usize;
        let end = off.checked_add(e.length as usize)?;
        d.extend_from_slice(file.get(off..end)?);
    }
    Some(d)
}

// ── serialisers ─────────────────────────────────────────────────────────────

fn rebuild_iinf(
    b: &[u8],
    iinf: Bx,
    items: &[(Item, Bx)],
    victims: &HashSet<u32>,
) -> Option<Vec<u8>> {
    let p = iinf.body;
    let version = *b.get(p)?;
    let mut payload = b.get(p..p + 4)?.to_vec(); // version + flags
    let kept: Vec<&(Item, Bx)> = items
        .iter()
        .filter(|(it, _)| !victims.contains(&it.id))
        .collect();
    if version == 0 {
        payload.extend_from_slice(&(kept.len() as u16).to_be_bytes());
    } else {
        payload.extend_from_slice(&(kept.len() as u32).to_be_bytes());
    }
    for (_, bx) in kept {
        payload.extend_from_slice(b.get(bx.start..bx.end)?);
    }
    Some(wrap_box(b"iinf", &payload))
}

fn serialize_iloc(b: &[u8], iloc: Bx, src: &Iloc, new_items: &[Loc]) -> Option<Vec<u8>> {
    let p = iloc.body;
    let mut payload = b.get(p..p + 4)?.to_vec(); // version + flags
    payload.push(((src.offset_size as u8) << 4) | (src.length_size as u8 & 0x0F));
    payload.push(((src.base_offset_size as u8) << 4) | (src.index_size as u8 & 0x0F));
    if src.version < 2 {
        payload.extend_from_slice(&(new_items.len() as u16).to_be_bytes());
    } else {
        payload.extend_from_slice(&(new_items.len() as u32).to_be_bytes());
    }
    for it in new_items {
        if src.version < 2 {
            payload.extend_from_slice(&(it.id as u16).to_be_bytes());
        } else {
            payload.extend_from_slice(&it.id.to_be_bytes());
        }
        if src.version == 1 || src.version == 2 {
            payload.extend_from_slice(&((it.method as u16) & 0x0F).to_be_bytes());
        }
        payload.extend_from_slice(&it.data_ref.to_be_bytes());
        write_uint(&mut payload, it.base_offset, src.base_offset_size);
        payload.extend_from_slice(&(it.extents.len() as u16).to_be_bytes());
        for e in &it.extents {
            // index_size == 0 is enforced by the caller, so no extent index.
            write_uint(&mut payload, e.offset, src.offset_size);
            write_uint(&mut payload, e.length, src.length_size);
        }
    }
    Some(wrap_box(b"iloc", &payload))
}

fn read_id(b: &[u8], o: usize, n: usize) -> Option<u32> {
    match n {
        2 => be_u16(b, o).map(|v| v as u32),
        4 => be_u32(b, o),
        _ => None,
    }
}
fn write_id(out: &mut Vec<u8>, v: u32, n: usize) {
    match n {
        2 => out.extend_from_slice(&(v as u16).to_be_bytes()),
        4 => out.extend_from_slice(&v.to_be_bytes()),
        _ => {}
    }
}

fn rewrite_iref(b: &[u8], iref: Bx, victims: &HashSet<u32>) -> Option<Vec<u8>> {
    let p = iref.body;
    let version = *b.get(p)?;
    let id_bytes = if version == 0 { 2 } else { 4 };
    let mut children = Vec::new();
    for child in boxes_in(b, p + 4, iref.end)? {
        let mut cq = child.body;
        let from_id = read_id(b, cq, id_bytes)?;
        cq += id_bytes;
        let count = be_u16(b, cq)? as usize;
        cq += 2;
        let mut tos = Vec::with_capacity(count);
        for _ in 0..count {
            tos.push(read_id(b, cq, id_bytes)?);
            cq += id_bytes;
        }
        if victims.contains(&from_id) {
            continue; // drop the whole reference (e.g. an EXIF item's `cdsc`)
        }
        let kept: Vec<u32> = tos.into_iter().filter(|t| !victims.contains(t)).collect();
        if kept.is_empty() {
            continue;
        }
        let mut cbody = Vec::new();
        write_id(&mut cbody, from_id, id_bytes);
        cbody.extend_from_slice(&(kept.len() as u16).to_be_bytes());
        for t in kept {
            write_id(&mut cbody, t, id_bytes);
        }
        children.extend_from_slice(&wrap_box(&child.typ, &cbody));
    }
    let mut payload = b.get(p..p + 4)?.to_vec(); // version + flags
    payload.extend_from_slice(&children);
    Some(wrap_box(b"iref", &payload))
}

// ── the rebuild ─────────────────────────────────────────────────────────────

/// Two-tier strip. Tier 1 (`strip_compact`) rebuilds with fresh offsets and
/// reclaims the freed bytes, but only for the conservative single-`mdat`,
/// `construction_method == 0` subset. Anything outside it (multiple `mdat`,
/// `idat`-backed grid items, etc. — common in real Samsung HEIC) falls through
/// to tier 2 (`strip_in_place`), which never moves a kept byte: it zero-fills the
/// EXIF/XMP payloads, delists them, and pads `meta` back to its original size so
/// every surviving absolute offset stays valid. Both self-validate.
fn strip_inner(b: &[u8]) -> Option<Vec<u8>> {
    strip_compact(b).or_else(|| strip_in_place(b))
}

fn strip_compact(b: &[u8]) -> Option<Vec<u8>> {
    let top = boxes_in(b, 0, b.len())?;
    if top.iter().filter(|x| x.typ == *b"mdat").count() != 1 {
        return None;
    }
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mdat = *top.iter().find(|x| x.typ == *b"mdat")?;
    if meta.start > mdat.start {
        return None; // we assume meta precedes mdat (offsets into mdat)
    }

    let meta_children = boxes_in(b, meta.body + 4, meta.end)?;
    let iinf = *meta_children.iter().find(|x| x.typ == *b"iinf")?;
    let iloc_box = *meta_children.iter().find(|x| x.typ == *b"iloc")?;

    let (_iinf_ver, items) = parse_iinf(b, iinf)?;
    let loc = parse_iloc(b, iloc_box)?;

    let victims: HashSet<u32> = items
        .iter()
        .filter(|(it, _)| is_victim(it))
        .map(|(it, _)| it.id)
        .collect();
    if victims.is_empty() {
        return Some(b.to_vec()); // already clean — nothing to strip
    }

    // Supported subset only; anything else bails (the caller skips, untouched).
    if !matches!(loc.offset_size, 4 | 8) || !matches!(loc.length_size, 4 | 8) {
        return None;
    }
    if loc.index_size != 0 {
        return None;
    }
    for it in &loc.items {
        if it.method != 0 || it.data_ref != 0 {
            return None;
        }
    }

    let new_iinf = rebuild_iinf(b, iinf, &items, &victims)?;
    let iref_box = meta_children.iter().find(|x| x.typ == *b"iref").copied();
    let new_iref = match iref_box {
        Some(ir) => Some(rewrite_iref(b, ir, &victims)?),
        None => None,
    };

    // iloc length is value-independent (field sizes are fixed), so measure it
    // with placeholder offsets to get the new `meta` size, then place data.
    let placeholder: Vec<Loc> = loc
        .items
        .iter()
        .filter(|it| !victims.contains(&it.id))
        .map(|it| Loc {
            id: it.id,
            method: it.method,
            data_ref: it.data_ref,
            base_offset: 0,
            extents: it
                .extents
                .iter()
                .map(|e| Extent {
                    offset: 0,
                    length: e.length,
                })
                .collect(),
            entry: (0, 0),
        })
        .collect();
    let new_iloc_len = serialize_iloc(b, iloc_box, &loc, &placeholder)?.len();

    let meta_children_len: usize = meta_children
        .iter()
        .map(|c| match &c.typ {
            b"iinf" => new_iinf.len(),
            b"iloc" => new_iloc_len,
            b"iref" => new_iref.as_ref().map(|v| v.len()).unwrap_or(0),
            _ => c.end - c.start,
        })
        .sum();
    let meta_new_size = 8 + 4 + meta_children_len; // 32-bit header + ver/flags

    // mdat payload start = size of everything assembled before mdat + its header.
    let mut prefix = 0usize;
    for x in &top {
        if x.start >= mdat.start {
            break;
        }
        prefix += if x.typ == *b"meta" {
            meta_new_size
        } else {
            x.end - x.start
        };
    }
    let mdat_payload_start = prefix + 8;

    // Copy kept items' data into the new mdat, assigning fresh absolute offsets.
    let mut new_mdat = Vec::new();
    let mut new_locs: Vec<Loc> = Vec::with_capacity(placeholder.len());
    for it in &loc.items {
        if victims.contains(&it.id) {
            continue;
        }
        let mut new_ext = Vec::with_capacity(it.extents.len());
        for e in &it.extents {
            let src_off = (it.base_offset + e.offset) as usize;
            let src_end = src_off.checked_add(e.length as usize)?;
            let data = b.get(src_off..src_end)?;
            let new_off = mdat_payload_start + new_mdat.len();
            new_mdat.extend_from_slice(data);
            new_ext.push(Extent {
                offset: new_off as u64,
                length: e.length,
            });
        }
        new_locs.push(Loc {
            id: it.id,
            method: it.method,
            data_ref: it.data_ref,
            base_offset: 0,
            extents: new_ext,
            entry: (0, 0),
        });
    }
    let new_iloc = serialize_iloc(b, iloc_box, &loc, &new_locs)?;
    if new_iloc.len() != new_iloc_len {
        return None; // length model disagreed — refuse rather than risk bad offsets
    }

    // Reassemble meta (verbatim children except iinf/iloc/iref).
    let mut meta_payload = Vec::with_capacity(4 + meta_children_len);
    meta_payload.extend_from_slice(b.get(meta.body..meta.body + 4)?);
    for c in &meta_children {
        match &c.typ {
            b"iinf" => meta_payload.extend_from_slice(&new_iinf),
            b"iloc" => meta_payload.extend_from_slice(&new_iloc),
            b"iref" => {
                if let Some(ir) = &new_iref {
                    meta_payload.extend_from_slice(ir);
                }
            }
            _ => meta_payload.extend_from_slice(b.get(c.start..c.end)?),
        }
    }
    let meta_box = wrap_box(b"meta", &meta_payload);

    // Assemble the file in source order, substituting meta + mdat.
    let mut out = Vec::with_capacity(b.len());
    for x in &top {
        if x.typ == *b"meta" {
            out.extend_from_slice(&meta_box);
        } else if x.typ == *b"mdat" {
            out.extend_from_slice(&wrap_box(b"mdat", &new_mdat));
        } else {
            out.extend_from_slice(b.get(x.start..x.end)?);
        }
    }

    validate(b, &loc, &victims, &out)?;
    Some(out)
}

/// Re-parse the output and prove the surgery was lossless for everything kept:
/// no EXIF/XMP item remains, and every surviving item's bytes equal the source.
///
/// `read_item` resolves offsets as absolute file positions, which is only true
/// for `construction_method == 0`. Items with another method (e.g. an `idat`-
/// backed grid item) are copied verbatim by both strip paths, so they're proven
/// unchanged by construction and skipped here rather than mis-read.
fn validate(src: &[u8], src_loc: &Iloc, victims: &HashSet<u32>, out: &[u8]) -> Option<()> {
    let top = boxes_in(out, 0, out.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(out, meta.body + 4, meta.end)?;
    let iinf = *mc.iter().find(|x| x.typ == *b"iinf")?;
    let iloc = *mc.iter().find(|x| x.typ == *b"iloc")?;

    let (_v, items) = parse_iinf(out, iinf)?;
    if items.iter().any(|(it, _)| is_victim(it)) {
        return None; // a metadata item survived
    }
    let out_loc = parse_iloc(out, iloc)?;
    for src_item in &src_loc.items {
        if victims.contains(&src_item.id) || src_item.method != 0 {
            continue;
        }
        let out_item = out_loc.items.iter().find(|x| x.id == src_item.id)?;
        if read_item(src, src_item)? != read_item(out, out_item)? {
            return None; // a kept item's bytes changed — refuse
        }
    }
    Some(())
}

// ── tier 2: in-place zero-fill (general) ─────────────────────────────────────

/// Strip EXIF/XMP without moving any kept byte. Works for the structures tier 1
/// refuses (multiple `mdat`, `idat` grids, base offsets): zero the victim
/// payloads in place, drop their `iinf`/`iloc`/`iref` records, and absorb the
/// space the records freed with a `free` box so `meta` keeps its exact size —
/// leaving every surviving absolute offset valid. Bails (→ caller skips the file
/// untouched) on anything it can't locate safely.
fn strip_in_place(b: &[u8]) -> Option<Vec<u8>> {
    let top = boxes_in(b, 0, b.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let meta_children = boxes_in(b, meta.body + 4, meta.end)?;
    let iinf = *meta_children.iter().find(|x| x.typ == *b"iinf")?;
    let iloc_box = *meta_children.iter().find(|x| x.typ == *b"iloc")?;

    let (_iinf_ver, items) = parse_iinf(b, iinf)?;
    let loc = parse_iloc(b, iloc_box)?;

    let victims: HashSet<u32> = items
        .iter()
        .filter(|(it, _)| is_victim(it))
        .map(|(it, _)| it.id)
        .collect();
    if victims.is_empty() {
        return Some(b.to_vec()); // already clean
    }

    // Locate every victim's payload as an absolute file range. We can only do
    // that for construction_method 0 (file/mdat offsets); a victim stored via
    // idat/item offset is rare and unsafe to locate here → bail.
    let mut zero_ranges: Vec<(usize, usize)> = Vec::new();
    for vloc in loc.items.iter().filter(|it| victims.contains(&it.id)) {
        if vloc.method != 0 {
            return None;
        }
        for e in &vloc.extents {
            let off = vloc.base_offset.checked_add(e.offset)? as usize;
            let end = off.checked_add(e.length as usize)?;
            if end > b.len() {
                return None;
            }
            zero_ranges.push((off, end));
        }
    }

    // Rebuild the three boxes that name the victims, copying kept records
    // verbatim (no offset rewrite — kept payloads don't move).
    let new_iinf = rebuild_iinf(b, iinf, &items, &victims)?;
    let new_iloc = rebuild_iloc_drop(b, iloc_box, &loc, &victims)?;
    let new_iref = match meta_children.iter().find(|x| x.typ == *b"iref") {
        Some(ir) => Some(rewrite_iref(b, *ir, &victims)?),
        None => None,
    };

    let mut children = Vec::with_capacity(meta.end - meta.body);
    for c in &meta_children {
        match &c.typ {
            b"iinf" => children.extend_from_slice(&new_iinf),
            b"iloc" => children.extend_from_slice(&new_iloc),
            b"iref" => {
                if let Some(ir) = &new_iref {
                    children.extend_from_slice(ir);
                }
            }
            _ => children.extend_from_slice(b.get(c.start..c.end)?),
        }
    }

    // Pad `meta` back to its original size so nothing after it moves. The dropped
    // records are always larger than a box header, so the delta fits a `free`.
    let orig_children_len = meta.end - (meta.body + 4);
    if children.len() > orig_children_len {
        return None; // unexpected growth — refuse
    }
    let delta = orig_children_len - children.len();
    if delta != 0 {
        if delta < 8 {
            return None; // can't represent as a box; refuse rather than shift
        }
        children.extend_from_slice(&(delta as u32).to_be_bytes());
        children.extend_from_slice(b"free");
        children.resize(children.len() + (delta - 8), 0);
    }

    let mut meta_payload = b.get(meta.body..meta.body + 4)?.to_vec(); // ver/flags
    meta_payload.extend_from_slice(&children);
    let new_meta = wrap_box(b"meta", &meta_payload);
    if new_meta.len() != meta.end - meta.start {
        return None; // size model disagreed — refuse
    }

    let mut out = b.to_vec();
    out[meta.start..meta.end].copy_from_slice(&new_meta);
    for (s, e) in zero_ranges {
        out[s..e].fill(0);
    }

    validate(b, &loc, &victims, &out)?;
    Some(out)
}

/// Re-serialise `iloc` with the victim items removed, copying every kept item's
/// record byte-for-byte (offsets unchanged — the in-place path moves nothing).
fn rebuild_iloc_drop(b: &[u8], iloc: Bx, src: &Iloc, victims: &HashSet<u32>) -> Option<Vec<u8>> {
    let p = iloc.body;
    let mut payload = b.get(p..p + 6)?.to_vec(); // ver/flags + the two size bytes
    let kept: Vec<&Loc> = src
        .items
        .iter()
        .filter(|it| !victims.contains(&it.id))
        .collect();
    if src.version < 2 {
        payload.extend_from_slice(&(kept.len() as u16).to_be_bytes());
    } else {
        payload.extend_from_slice(&(kept.len() as u32).to_be_bytes());
    }
    for it in kept {
        payload.extend_from_slice(b.get(it.entry.0..it.entry.1)?);
    }
    Some(wrap_box(b"iloc", &payload))
}

// ── inject: ADD EXIF / XMP items (the inverse of strip) ──────────────────────

/// Add `Exif` / XMP items and/or an ICC profile to an ISOBMFF still (AVIF/HEIF)
/// so metadata survives a re-encode. `exif` is the raw TIFF block (the caller
/// normalises orientation), `xmp` the bare packet, `icc` a raw profile (added as
/// a `colr`/`prof` property + an `ipma` association). This mirrors
/// `strip_compact`'s rebuild: because `iloc` holds ABSOLUTE offsets, `meta` (a
/// larger `iinf`/`iloc`/`iref`/`iprp`) and `mdat` (existing items copied, then
/// the new payloads) are rebuilt with fresh offsets, then self-validated. Outside
/// the supported subset (single `mdat`, method-0 items) the input is returned
/// unchanged — never a corrupt file.
pub fn inject(b: &[u8], exif: Option<&[u8]>, xmp: Option<&[u8]>, icc: Option<&[u8]>) -> Vec<u8> {
    if exif.is_none() && xmp.is_none() && icc.is_none() {
        return b.to_vec();
    }
    inject_inner(b, exif, xmp, icc).unwrap_or_else(|| b.to_vec())
}

fn parse_pitm(b: &[u8], pitm: Bx) -> Option<u32> {
    let p = pitm.body;
    if *b.get(p)? == 0 {
        be_u16(b, p + 4).map(u32::from)
    } else {
        be_u32(b, p + 4)
    }
}

/// A version-2 `infe` (item info entry): u16 id, no protection, 4-byte type, an
/// empty item name, and (for `mime`) a null-terminated content type.
fn build_infe(id: u32, item_type: &[u8; 4], content_type: Option<&str>) -> Option<Vec<u8>> {
    if id > 0xFFFF {
        return None; // a version-2 infe stores the id as u16
    }
    let mut p = vec![2u8, 0, 0, 0]; // version 2 + flags
    p.extend_from_slice(&(id as u16).to_be_bytes());
    p.extend_from_slice(&0u16.to_be_bytes()); // item_protection_index
    p.extend_from_slice(item_type);
    p.push(0); // item_name = "" (null-terminated)
    if let Some(ct) = content_type {
        p.extend_from_slice(ct.as_bytes());
        p.push(0);
    }
    Some(wrap_box(b"infe", &p))
}

/// `iinf` with the existing `infe` entries (verbatim) plus the new ones.
fn build_iinf_add(
    b: &[u8],
    iinf: Bx,
    items: &[(Item, Bx)],
    new_infes: &[Vec<u8>],
) -> Option<Vec<u8>> {
    let p = iinf.body;
    let mut payload = b.get(p..p + 4)?.to_vec(); // version + flags
    let count = items.len() + new_infes.len();
    if *b.get(p)? == 0 {
        payload.extend_from_slice(&(count as u16).to_be_bytes());
    } else {
        payload.extend_from_slice(&(count as u32).to_be_bytes());
    }
    for (_, bx) in items {
        payload.extend_from_slice(b.get(bx.start..bx.end)?);
    }
    for infe in new_infes {
        payload.extend_from_slice(infe);
    }
    Some(wrap_box(b"iinf", &payload))
}

/// `iref` with the existing references (verbatim) plus a `cdsc` (content
/// describes) for each new (from_item → primary) pair. Matches the existing
/// box's id width, or version 0 (u16) when creating one from scratch.
fn build_iref(b: &[u8], existing: Option<Bx>, new_refs: &[(u32, u32)]) -> Option<Vec<u8>> {
    let version = match existing {
        Some(ir) => *b.get(ir.body)?,
        None => 0,
    };
    let id_bytes = if version == 0 { 2 } else { 4 };
    if id_bytes == 2 && new_refs.iter().any(|&(f, t)| f > 0xFFFF || t > 0xFFFF) {
        return None;
    }
    let mut children = Vec::new();
    if let Some(ir) = existing {
        for child in boxes_in(b, ir.body + 4, ir.end)? {
            children.extend_from_slice(b.get(child.start..child.end)?);
        }
    }
    for &(from, to) in new_refs {
        let mut cbody = Vec::new();
        write_id(&mut cbody, from, id_bytes);
        cbody.extend_from_slice(&1u16.to_be_bytes()); // reference_count
        write_id(&mut cbody, to, id_bytes);
        children.extend_from_slice(&wrap_box(b"cdsc", &cbody));
    }
    let mut payload = vec![version, 0, 0, 0];
    payload.extend_from_slice(&children);
    Some(wrap_box(b"iref", &payload))
}

/// `iprp` with an ICC `colr`/`prof` property appended to `ipco` and an `ipma`
/// association linking it to the primary item. Existing properties keep their
/// indices (the new one is appended). Single-`ipma` files only (the common case).
fn build_iprp_add_icc(b: &[u8], iprp: Bx, primary: u32, icc: &[u8]) -> Option<Vec<u8>> {
    let children = boxes_in(b, iprp.body, iprp.end)?;
    let ipco = *children.iter().find(|x| x.typ == *b"ipco")?;
    let (new_ipco, index) = build_ipco_add_colr(b, ipco, icc)?;
    let mut payload = Vec::new();
    for c in &children {
        match &c.typ {
            b"ipco" => payload.extend_from_slice(&new_ipco),
            b"ipma" => payload.extend_from_slice(&build_ipma_add(b, *c, primary, index)?),
            _ => payload.extend_from_slice(b.get(c.start..c.end)?),
        }
    }
    Some(wrap_box(b"iprp", &payload))
}

/// Append a `colr`/`prof` (ICC) property to `ipco`; returns (new ipco, its
/// 1-based property index).
fn build_ipco_add_colr(b: &[u8], ipco: Bx, icc: &[u8]) -> Option<(Vec<u8>, u16)> {
    let index = boxes_in(b, ipco.body, ipco.end)?.len() + 1;
    if index > 0x7FFF {
        return None; // beyond the widest ipma association index
    }
    let mut payload = b.get(ipco.body..ipco.end)?.to_vec(); // properties verbatim
    let mut colr = b"prof".to_vec();
    colr.extend_from_slice(icc);
    payload.extend_from_slice(&wrap_box(b"colr", &colr));
    Some((wrap_box(b"ipco", &payload), index as u16))
}

/// Append a non-essential association (`prop_index`) to `target`'s entry in
/// `ipma`, copying every other entry verbatim. Bails if `target` has no entry.
fn build_ipma_add(b: &[u8], ipma: Bx, target: u32, prop_index: u16) -> Option<Vec<u8>> {
    let p = ipma.body;
    let version = *b.get(p)?;
    let wide = *b.get(p + 3)? & 1 == 1; // flags bit 0 → 15-bit indices (2 bytes)
    let id_size = if version >= 1 { 4 } else { 2 };
    if (!wide && prop_index > 0x7F) || (wide && prop_index > 0x7FFF) {
        return None;
    }
    let mut q = p + 4;
    let entry_count = be_u32(b, q)?;
    q += 4;
    let mut entries = Vec::new();
    let mut found = false;
    for _ in 0..entry_count {
        let id = read_id(b, q, id_size)?;
        entries.extend_from_slice(b.get(q..q + id_size)?);
        q += id_size;
        let assoc_count = *b.get(q)? as usize;
        q += 1;
        let bytes = assoc_count * if wide { 2 } else { 1 };
        let assoc = b.get(q..q + bytes)?;
        q += bytes;
        if id == target {
            if assoc_count >= 0xFF {
                return None; // can't widen the u8 association count
            }
            found = true;
            entries.push((assoc_count + 1) as u8);
            entries.extend_from_slice(assoc);
            // essential bit clear (descriptive property): high bit stays 0.
            if wide {
                entries.extend_from_slice(&(prop_index & 0x7FFF).to_be_bytes());
            } else {
                entries.push(prop_index as u8 & 0x7F);
            }
        } else {
            entries.push(assoc_count as u8);
            entries.extend_from_slice(assoc);
        }
    }
    if !found {
        return None;
    }
    let mut payload = b.get(p..p + 4)?.to_vec(); // version + flags
    payload.extend_from_slice(&entry_count.to_be_bytes());
    payload.extend_from_slice(&entries);
    Some(wrap_box(b"ipma", &payload))
}

fn inject_inner(
    b: &[u8],
    exif: Option<&[u8]>,
    xmp: Option<&[u8]>,
    icc: Option<&[u8]>,
) -> Option<Vec<u8>> {
    let top = boxes_in(b, 0, b.len())?;
    if top.iter().filter(|x| x.typ == *b"mdat").count() != 1 {
        return None;
    }
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mdat = *top.iter().find(|x| x.typ == *b"mdat")?;
    if meta.start > mdat.start {
        return None; // we assume meta precedes mdat (offsets point into mdat)
    }

    let meta_children = boxes_in(b, meta.body + 4, meta.end)?;
    let iinf = *meta_children.iter().find(|x| x.typ == *b"iinf")?;
    let iloc_box = *meta_children.iter().find(|x| x.typ == *b"iloc")?;
    let pitm = *meta_children.iter().find(|x| x.typ == *b"pitm")?;
    let iref_box = meta_children.iter().find(|x| x.typ == *b"iref").copied();
    let iprp_box = meta_children.iter().find(|x| x.typ == *b"iprp").copied();

    let (_iinf_ver, items) = parse_iinf(b, iinf)?;
    let loc = parse_iloc(b, iloc_box)?;
    let primary = parse_pitm(b, pitm)?;

    // Supported subset (mirror strip_compact): fixed-size method-0 offsets only.
    if !matches!(loc.offset_size, 4 | 8) || !matches!(loc.length_size, 4 | 8) {
        return None;
    }
    if loc.index_size != 0 {
        return None;
    }
    if loc
        .items
        .iter()
        .any(|it| it.method != 0 || it.data_ref != 0)
    {
        return None;
    }

    // Add only a kind not already present (a fresh encode has none of them).
    let has_exif = items.iter().any(|(it, _)| it.typ == *b"Exif");
    let has_xmp = items.iter().any(|(it, _)| is_xmp(it));
    let add_exif = exif.filter(|_| !has_exif);
    let add_xmp = xmp.filter(|_| !has_xmp);
    let add_icc = icc.filter(|_| extract_icc(b).is_none());
    if add_exif.is_none() && add_xmp.is_none() && add_icc.is_none() {
        return Some(b.to_vec()); // nothing to add
    }

    let mut next_id = loc.items.iter().map(|it| it.id).max().unwrap_or(0);
    let mut new_infes: Vec<Vec<u8>> = Vec::new();
    let mut new_payloads: Vec<(u32, Vec<u8>)> = Vec::new();
    let mut new_refs: Vec<(u32, u32)> = Vec::new();

    if let Some(tiff) = add_exif {
        next_id += 1;
        new_infes.push(build_infe(next_id, b"Exif", None)?);
        let mut payload = vec![0u8, 0, 0, 0]; // exif_tiff_header_offset = 0
        payload.extend_from_slice(tiff);
        new_payloads.push((next_id, payload));
        new_refs.push((next_id, primary));
    }
    if let Some(packet) = add_xmp {
        next_id += 1;
        new_infes.push(build_infe(next_id, b"mime", Some("application/rdf+xml"))?);
        new_payloads.push((next_id, packet.to_vec()));
        new_refs.push((next_id, primary));
    }
    if loc.version < 2 && next_id > 0xFFFF {
        return None; // iloc v<2 stores ids as u16
    }

    let new_iinf = build_iinf_add(b, iinf, &items, &new_infes)?;
    let had_iref = iref_box.is_some();
    // Only build an iref when there are references to write (an ICC-only inject
    // adds no items, so it must not synthesise an empty iref).
    let new_iref = if new_refs.is_empty() && !had_iref {
        None
    } else {
        Some(build_iref(b, iref_box, &new_refs)?)
    };
    let new_iprp = match add_icc {
        Some(profile) => Some(build_iprp_add_icc(b, iprp_box?, primary, profile)?),
        None => None,
    };

    // iloc length is offset-value-independent, so model `meta`'s new size with a
    // placeholder carrying the full (existing + new) item set, then place data.
    let placeholder: Vec<Loc> = loc
        .items
        .iter()
        .map(|it| Loc {
            id: it.id,
            method: it.method,
            data_ref: it.data_ref,
            base_offset: 0,
            extents: it
                .extents
                .iter()
                .map(|e| Extent {
                    offset: 0,
                    length: e.length,
                })
                .collect(),
            entry: (0, 0),
        })
        .chain(new_payloads.iter().map(|(id, payload)| Loc {
            id: *id,
            method: 0,
            data_ref: 0,
            base_offset: 0,
            extents: vec![Extent {
                offset: 0,
                length: payload.len() as u64,
            }],
            entry: (0, 0),
        }))
        .collect();
    let new_iloc_len = serialize_iloc(b, iloc_box, &loc, &placeholder)?.len();

    let mut meta_children_len: usize = meta_children
        .iter()
        .map(|c| match &c.typ {
            b"iinf" => new_iinf.len(),
            b"iloc" => new_iloc_len,
            b"iref" => new_iref.as_ref().map_or(c.end - c.start, |v| v.len()),
            b"iprp" => new_iprp.as_ref().map_or(c.end - c.start, |v| v.len()),
            _ => c.end - c.start,
        })
        .sum();
    if !had_iref {
        if let Some(ir) = &new_iref {
            meta_children_len += ir.len(); // appended below
        }
    }
    let meta_new_size = 8 + 4 + meta_children_len; // header + ver/flags

    // mdat payload start = bytes of everything before mdat in the OUTPUT + header.
    let mut prefix = 0usize;
    for x in &top {
        if x.start >= mdat.start {
            break;
        }
        prefix += if x.typ == *b"meta" {
            meta_new_size
        } else {
            x.end - x.start
        };
    }
    let mdat_payload_start = prefix + 8;

    // New mdat: existing items copied with fresh offsets, then the new payloads.
    let mut new_mdat = Vec::new();
    let mut new_locs: Vec<Loc> = Vec::with_capacity(loc.items.len() + new_payloads.len());
    for it in &loc.items {
        let mut new_ext = Vec::with_capacity(it.extents.len());
        for e in &it.extents {
            let src_off = (it.base_offset + e.offset) as usize;
            let src_end = src_off.checked_add(e.length as usize)?;
            let data = b.get(src_off..src_end)?;
            let new_off = mdat_payload_start + new_mdat.len();
            new_mdat.extend_from_slice(data);
            new_ext.push(Extent {
                offset: new_off as u64,
                length: e.length,
            });
        }
        new_locs.push(Loc {
            id: it.id,
            method: 0,
            data_ref: 0,
            base_offset: 0,
            extents: new_ext,
            entry: (0, 0),
        });
    }
    for (id, payload) in &new_payloads {
        let new_off = mdat_payload_start + new_mdat.len();
        new_mdat.extend_from_slice(payload);
        new_locs.push(Loc {
            id: *id,
            method: 0,
            data_ref: 0,
            base_offset: 0,
            extents: vec![Extent {
                offset: new_off as u64,
                length: payload.len() as u64,
            }],
            entry: (0, 0),
        });
    }
    let new_iloc = serialize_iloc(b, iloc_box, &loc, &new_locs)?;
    if new_iloc.len() != new_iloc_len {
        return None; // length model disagreed — refuse rather than risk offsets
    }

    // Reassemble meta (verbatim children except iinf/iloc/iref; append iref if new).
    let mut meta_payload = Vec::with_capacity(4 + meta_children_len);
    meta_payload.extend_from_slice(b.get(meta.body..meta.body + 4)?);
    for c in &meta_children {
        match &c.typ {
            b"iinf" => meta_payload.extend_from_slice(&new_iinf),
            b"iloc" => meta_payload.extend_from_slice(&new_iloc),
            b"iref" => {
                if let Some(ir) = &new_iref {
                    meta_payload.extend_from_slice(ir);
                }
            }
            b"iprp" => match &new_iprp {
                Some(ip) => meta_payload.extend_from_slice(ip),
                None => meta_payload.extend_from_slice(b.get(c.start..c.end)?),
            },
            _ => meta_payload.extend_from_slice(b.get(c.start..c.end)?),
        }
    }
    if !had_iref {
        if let Some(ir) = &new_iref {
            meta_payload.extend_from_slice(ir);
        }
    }
    let meta_box = wrap_box(b"meta", &meta_payload);
    if meta_box.len() != meta_new_size {
        return None; // size model disagreed — refuse
    }

    // Assemble the file in source order, substituting meta + mdat.
    let mut out = Vec::with_capacity(b.len() + new_mdat.len());
    for x in &top {
        if x.typ == *b"meta" {
            out.extend_from_slice(&meta_box);
        } else if x.typ == *b"mdat" {
            out.extend_from_slice(&wrap_box(b"mdat", &new_mdat));
        } else {
            out.extend_from_slice(b.get(x.start..x.end)?);
        }
    }

    validate_inject(
        b,
        &loc,
        &out,
        add_exif.is_some(),
        add_xmp.is_some(),
        add_icc.is_some(),
    )?;
    Some(out)
}

/// Prove the add-item surgery was safe: every pre-existing item's bytes are
/// byte-identical (the AV1/HEVC payload never moved logically), and the metadata
/// we added re-extracts cleanly.
fn validate_inject(
    src: &[u8],
    src_loc: &Iloc,
    out: &[u8],
    want_exif: bool,
    want_xmp: bool,
    want_icc: bool,
) -> Option<()> {
    let top = boxes_in(out, 0, out.len())?;
    let meta = *top.iter().find(|x| x.typ == *b"meta")?;
    let mc = boxes_in(out, meta.body + 4, meta.end)?;
    let iloc = *mc.iter().find(|x| x.typ == *b"iloc")?;
    let out_loc = parse_iloc(out, iloc)?;
    for src_item in &src_loc.items {
        if src_item.method != 0 {
            continue;
        }
        let out_item = out_loc.items.iter().find(|x| x.id == src_item.id)?;
        if read_item(src, src_item)? != read_item(out, out_item)? {
            return None; // a pre-existing item's bytes changed — refuse
        }
    }
    let (exif, xmp) = extract_exif_xmp(out);
    if (want_exif && exif.is_none()) || (want_xmp && xmp.is_none()) {
        return None; // the metadata we added isn't readable back — refuse
    }
    if want_icc && extract_icc(out).is_none() {
        return None; // the ICC property we added isn't readable back — refuse
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fullbox(typ: &[u8; 4], version: u8, flags: [u8; 3], body: &[u8]) -> Vec<u8> {
        let mut p = vec![version, flags[0], flags[1], flags[2]];
        p.extend_from_slice(body);
        wrap_box(typ, &p)
    }

    fn infe(id: u16, typ: &[u8; 4]) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(&id.to_be_bytes());
        body.extend_from_slice(&0u16.to_be_bytes()); // protection index
        body.extend_from_slice(typ);
        body.push(0); // empty item_name
        fullbox(b"infe", 2, [0, 0, 0], &body)
    }

    /// Build a minimal but well-formed HEIF: one `av01` image item (id 1) and
    /// one `Exif` item (id 2), data in `mdat`, linked by an `iref cdsc`.
    fn sample_heif(av01: &[u8], exif: &[u8]) -> Vec<u8> {
        // hdlr
        let mut hdlr_body = vec![0, 0, 0, 0];
        hdlr_body.extend_from_slice(b"pict");
        hdlr_body.extend_from_slice(&[0; 12]);
        hdlr_body.push(0);
        let hdlr = fullbox(b"hdlr", 0, [0, 0, 0], &hdlr_body);
        // pitm -> id 1
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        // iinf with two infe
        let mut iinf_body = Vec::new();
        iinf_body.extend_from_slice(&2u16.to_be_bytes()); // count
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        iinf_body.extend_from_slice(&infe(2, b"Exif"));
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);
        // iref cdsc: from 2 -> 1
        let mut cdsc = Vec::new();
        cdsc.extend_from_slice(&2u16.to_be_bytes());
        cdsc.extend_from_slice(&1u16.to_be_bytes()); // count
        cdsc.extend_from_slice(&1u16.to_be_bytes()); // to
        let cdsc_box = wrap_box(b"cdsc", &cdsc);
        let iref = fullbox(b"iref", 0, [0, 0, 0], &cdsc_box);

        // iloc v1, offset_size=4, length_size=4, base=0, index=0. Offsets are
        // patched once the prefix length is known.
        let build_iloc = |o1: u32, o2: u32| -> Vec<u8> {
            let mut body = Vec::new();
            body.push(0x44); // offset_size=4, length_size=4
            body.push(0x00); // base_offset_size=0, index_size=0
            body.extend_from_slice(&2u16.to_be_bytes()); // item count
            for (id, off, len) in [(1u16, o1, av01.len() as u32), (2u16, o2, exif.len() as u32)] {
                body.extend_from_slice(&id.to_be_bytes());
                body.extend_from_slice(&0u16.to_be_bytes()); // method 0 (v1)
                body.extend_from_slice(&0u16.to_be_bytes()); // data_ref
                body.extend_from_slice(&1u16.to_be_bytes()); // extent count
                body.extend_from_slice(&off.to_be_bytes());
                body.extend_from_slice(&len.to_be_bytes());
            }
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };

        let assemble = |iloc: &[u8]| -> Vec<u8> {
            let mut meta_payload = vec![0, 0, 0, 0]; // meta ver/flags
            meta_payload.extend_from_slice(&hdlr);
            meta_payload.extend_from_slice(&pitm);
            meta_payload.extend_from_slice(&iinf);
            meta_payload.extend_from_slice(&iref);
            meta_payload.extend_from_slice(iloc);
            let meta = wrap_box(b"meta", &meta_payload);
            let ftyp = wrap_box(b"ftyp", b"heic\0\0\0\0mif1heic");
            let mut mdat_data = Vec::new();
            mdat_data.extend_from_slice(av01);
            mdat_data.extend_from_slice(exif);
            let mdat = wrap_box(b"mdat", &mdat_data);
            let mut f = Vec::new();
            f.extend_from_slice(&ftyp);
            f.extend_from_slice(&meta);
            f.extend_from_slice(&mdat);
            f
        };

        // First pass with placeholder offsets to learn the prefix length, then
        // fix the real absolute offsets (iloc size is offset-value independent).
        let probe = assemble(&build_iloc(0, 0));
        let mdat_payload = probe.len() - (av01.len() + exif.len());
        let o1 = mdat_payload as u32;
        let o2 = (mdat_payload + av01.len()) as u32;
        assemble(&build_iloc(o1, o2))
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    /// A minimal HEIF with ONLY the primary `av01` image item (id 1), no EXIF/XMP
    /// and no `iref` — the shape a fresh encoder emits, and the input to `inject`.
    fn sample_heif_image_only(av01: &[u8]) -> Vec<u8> {
        let hdlr = fullbox(
            b"hdlr",
            0,
            [0, 0, 0],
            b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0",
        );
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        let mut iinf_body = 1u16.to_be_bytes().to_vec(); // count
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);
        let build_iloc = |o1: u32| {
            let mut body = vec![0x44, 0x00]; // offset_size=4, length_size=4
            body.extend_from_slice(&1u16.to_be_bytes()); // item count
            body.extend_from_slice(&1u16.to_be_bytes()); // id
            body.extend_from_slice(&0u16.to_be_bytes()); // method 0 (v1)
            body.extend_from_slice(&0u16.to_be_bytes()); // data_ref
            body.extend_from_slice(&1u16.to_be_bytes()); // extent count
            body.extend_from_slice(&o1.to_be_bytes());
            body.extend_from_slice(&(av01.len() as u32).to_be_bytes());
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };
        let assemble = |iloc: &[u8]| {
            let mut mp = vec![0, 0, 0, 0];
            mp.extend_from_slice(&hdlr);
            mp.extend_from_slice(&pitm);
            mp.extend_from_slice(&iinf);
            mp.extend_from_slice(iloc);
            let meta = wrap_box(b"meta", &mp);
            let ftyp = wrap_box(b"ftyp", b"mif1\0\0\0\0mif1heic");
            let mdat = wrap_box(b"mdat", av01);
            [ftyp, meta, mdat].concat()
        };
        let probe = assemble(&build_iloc(0));
        let base = probe.len() - av01.len();
        assemble(&build_iloc(base as u32))
    }

    #[test]
    fn inject_adds_exif_and_xmp_items_to_image_only_heif() {
        let av01 = [0xC0u8, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5];
        let file = sample_heif_image_only(&av01);
        assert_eq!(extract_exif_xmp(&file), (None, None), "starts clean");

        let tiff = b"II\x2a\x00\x08\x00\x00\x00".to_vec();
        let xmp = b"<x:xmpmeta>hi</x:xmpmeta>".to_vec();
        let out = inject(&file, Some(&tiff), Some(&xmp), None);

        let (gx, gxmp) = extract_exif_xmp(&out);
        assert_eq!(gx.as_deref(), Some(tiff.as_slice()), "EXIF carried");
        assert_eq!(gxmp.as_deref(), Some(xmp.as_slice()), "XMP carried");
        assert!(contains(&out, &av01), "image payload byte-identical");
        assert!(out.len() > file.len(), "file grew");
        // Still a single-mdat ISOBMFF with a cdsc link for the new items.
        let top = boxes_in(&out, 0, out.len()).unwrap();
        assert_eq!(top.iter().filter(|x| x.typ == *b"mdat").count(), 1);
        assert!(contains(&out, b"cdsc"), "iref cdsc created");
    }

    #[test]
    fn inject_noop_without_metadata() {
        let file = sample_heif_image_only(&[1, 2, 3, 4, 5, 6]);
        assert_eq!(inject(&file, None, None, None), file);
    }

    #[test]
    fn inject_icc_without_iprp_is_safe_noop() {
        // The image-only sample has no `iprp` to host a colr property, so an
        // ICC inject must return the input unchanged rather than corrupt it.
        let file = sample_heif_image_only(&[9, 8, 7, 6]);
        assert_eq!(inject(&file, None, None, Some(b"icc-bytes")), file);
    }

    #[test]
    fn inject_skips_a_kind_already_present() {
        // sample_heif already has an Exif item → re-injecting EXIF is a no-op.
        let av01 = [0x55u8; 6];
        let mut exif = b"Exif\0\0".to_vec();
        exif.extend_from_slice(b"II\x2a\x00\x08\x00\x00\x00");
        let file = sample_heif(&av01, &exif);
        let out = inject(&file, Some(b"II\x2a\x00\x08\x00\x00\x00"), None, None);
        assert_eq!(out, file, "existing EXIF item not duplicated");
    }

    #[test]
    fn extract_icc_reads_colr_prof() {
        let icc = b"icc-profile-bytes".to_vec();
        let mut colr_body = b"prof".to_vec();
        colr_body.extend_from_slice(&icc);
        let ipco = wrap_box(b"ipco", &wrap_box(b"colr", &colr_body));
        let iprp = wrap_box(b"iprp", &ipco);
        let mut mp = vec![0, 0, 0, 0];
        mp.extend_from_slice(&iprp);
        let file = [
            wrap_box(b"ftyp", b"mif1\0\0\0\0mif1avif"),
            wrap_box(b"meta", &mp),
        ]
        .concat();
        assert_eq!(extract_icc(&file).as_deref(), Some(icc.as_slice()));
    }

    #[test]
    fn extract_icc_ignores_nclx_and_absent() {
        // nclx carries code points, not a profile → None.
        let nclx = wrap_box(b"colr", b"nclx\0\x01\0\x0d\0\x06\x80");
        let ipco = wrap_box(b"ipco", &nclx);
        let iprp = wrap_box(b"iprp", &ipco);
        let mut mp = vec![0, 0, 0, 0];
        mp.extend_from_slice(&iprp);
        let file = [
            wrap_box(b"ftyp", b"mif1\0\0\0\0mif1avif"),
            wrap_box(b"meta", &mp),
        ]
        .concat();
        assert_eq!(extract_icc(&file), None);
        // No iprp at all → None (never panics).
        assert_eq!(extract_icc(&sample_heif_image_only(&[1, 2, 3, 4])), None);
    }

    #[test]
    fn extract_nclx_reads_code_points() {
        let mut nclx = b"nclx".to_vec();
        nclx.extend_from_slice(&12u16.to_be_bytes()); // primaries: Display P3
        nclx.extend_from_slice(&13u16.to_be_bytes()); // transfer: sRGB
        nclx.extend_from_slice(&1u16.to_be_bytes()); // matrix
        nclx.push(0x80); // full range
        let ipco = wrap_box(b"ipco", &wrap_box(b"colr", &nclx));
        let iprp = wrap_box(b"iprp", &ipco);
        let mut mp = vec![0, 0, 0, 0];
        mp.extend_from_slice(&iprp);
        let file = [
            wrap_box(b"ftyp", b"mif1\0\0\0\0mif1avif"),
            wrap_box(b"meta", &mp),
        ]
        .concat();
        assert_eq!(extract_nclx(&file), Some((12, 13)));
        // A `prof` colr carries no nclx code points.
        let prof = wrap_box(
            b"iprp",
            &wrap_box(b"ipco", &wrap_box(b"colr", b"profICCDATA")),
        );
        let mut mp2 = vec![0, 0, 0, 0];
        mp2.extend_from_slice(&prof);
        let f2 = [
            wrap_box(b"ftyp", b"mif1\0\0\0\0mif1avif"),
            wrap_box(b"meta", &mp2),
        ]
        .concat();
        assert_eq!(extract_nclx(&f2), None);
    }

    #[test]
    fn has_gainmap_detects_tmap_and_auxc() {
        // ISO 21496-1: a `tmap` derived item.
        let mut iinf_body = 2u16.to_be_bytes().to_vec();
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        iinf_body.extend_from_slice(&infe(2, b"tmap"));
        let mut mp = vec![0, 0, 0, 0];
        mp.extend_from_slice(&fullbox(b"iinf", 0, [0, 0, 0], &iinf_body));
        let tmap_file = [
            wrap_box(b"ftyp", b"mif1\0\0\0\0mif1avif"),
            wrap_box(b"meta", &mp),
        ]
        .concat();
        assert!(has_gainmap(&tmap_file), "tmap item → gain map");

        // Apple aux: an `auxC` URN naming a gain map.
        let mut auxc = vec![0, 0, 0, 0]; // version + flags
        auxc.extend_from_slice(b"urn:com:apple:photo:2020:aux:hdrgainmap\0");
        let iprp = wrap_box(b"iprp", &wrap_box(b"ipco", &wrap_box(b"auxC", &auxc)));
        let mut mp2 = vec![0, 0, 0, 0];
        mp2.extend_from_slice(&iprp);
        let aux_file = [
            wrap_box(b"ftyp", b"mif1\0\0\0\0mif1heic"),
            wrap_box(b"meta", &mp2),
        ]
        .concat();
        assert!(has_gainmap(&aux_file), "auxC hdrgainmap URN → gain map");

        // A plain image-only HEIF has no gain map.
        assert!(!has_gainmap(&sample_heif_image_only(&[1, 2, 3, 4])));
    }

    /// A minimal HEIF with three method-0 items: primary `av01`, a `tmap` gain
    /// map, and an `Exif` item — to prove a privacy strip keeps the gain map.
    fn sample_heif_with_tmap(av01: &[u8], tmap: &[u8], exif: &[u8]) -> Vec<u8> {
        let hdlr = fullbox(
            b"hdlr",
            0,
            [0, 0, 0],
            b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0",
        );
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        let mut iinf_body = 3u16.to_be_bytes().to_vec();
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        iinf_body.extend_from_slice(&infe(2, b"tmap"));
        iinf_body.extend_from_slice(&infe(3, b"Exif"));
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);
        let build_iloc = |o1: u32, o2: u32, o3: u32| {
            let mut body = vec![0x44, 0x00];
            body.extend_from_slice(&3u16.to_be_bytes());
            for (id, off, len) in [
                (1u16, o1, av01.len() as u32),
                (2, o2, tmap.len() as u32),
                (3, o3, exif.len() as u32),
            ] {
                body.extend_from_slice(&id.to_be_bytes());
                body.extend_from_slice(&0u16.to_be_bytes()); // method 0 (v1)
                body.extend_from_slice(&0u16.to_be_bytes());
                body.extend_from_slice(&1u16.to_be_bytes());
                body.extend_from_slice(&off.to_be_bytes());
                body.extend_from_slice(&len.to_be_bytes());
            }
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };
        let assemble = |iloc: &[u8]| {
            let mut mp = vec![0, 0, 0, 0];
            mp.extend_from_slice(&hdlr);
            mp.extend_from_slice(&pitm);
            mp.extend_from_slice(&iinf);
            mp.extend_from_slice(iloc);
            let meta = wrap_box(b"meta", &mp);
            let ftyp = wrap_box(b"ftyp", b"mif1\0\0\0\0mif1avif");
            let mut md = av01.to_vec();
            md.extend_from_slice(tmap);
            md.extend_from_slice(exif);
            [ftyp, meta, wrap_box(b"mdat", &md)].concat()
        };
        let base = assemble(&build_iloc(0, 0, 0)).len() - (av01.len() + tmap.len() + exif.len());
        assemble(&build_iloc(
            base as u32,
            (base + av01.len()) as u32,
            (base + av01.len() + tmap.len()) as u32,
        ))
    }

    #[test]
    fn strip_preserves_the_gain_map() {
        let av01 = [0xA0u8, 0xA1, 0xA2, 0xA3];
        let tmap = b"GAINMAP-PIXELS".to_vec();
        let mut exif = b"Exif\0\0".to_vec();
        exif.extend_from_slice(b"GPS-secret");
        let file = sample_heif_with_tmap(&av01, &tmap, &exif);
        assert!(has_gainmap(&file));

        let out = strip(&file, StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"GPS-secret"), "EXIF stripped");
        assert!(contains(&out, b"GAINMAP-PIXELS"), "gain-map payload kept");
        assert!(has_gainmap(&out), "gain-map item survives the strip");
    }

    #[test]
    fn strips_exif_keeps_image_payload() {
        let av01 = [0xA0u8, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7];
        let mut exif = b"Exif\0\0".to_vec();
        exif.extend_from_slice(b"GPS-secret-location-data");
        let file = sample_heif(&av01, &exif);
        assert!(contains(&file, b"GPS-secret-location-data"));

        let out = strip(&file, StripPolicy::default()).unwrap();
        assert!(
            !contains(&out, b"GPS-secret-location-data"),
            "EXIF payload gone"
        );
        assert!(!contains(&out, b"Exif"), "Exif item declaration gone");
        assert!(contains(&out, &av01), "image payload byte-identical");
        assert!(out.len() < file.len(), "file shrank");

        // Only the image item (id 1, av01) remains.
        let top = boxes_in(&out, 0, out.len()).unwrap();
        let meta = *top.iter().find(|x| x.typ == *b"meta").unwrap();
        let mc = boxes_in(&out, meta.body + 4, meta.end).unwrap();
        let iinf = *mc.iter().find(|x| x.typ == *b"iinf").unwrap();
        let (_v, items) = parse_iinf(&out, iinf).unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].0.typ, *b"av01");
    }

    #[test]
    fn strips_xmp_item() {
        let av01 = [0x10u8, 0x11, 0x12, 0x13];
        // An XMP item is a `mime` infe with content_type application/rdf+xml.
        let mut iinf_body = Vec::new();
        iinf_body.extend_from_slice(&2u16.to_be_bytes());
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        let mut mime_body = Vec::new();
        mime_body.extend_from_slice(&2u16.to_be_bytes()); // id
        mime_body.extend_from_slice(&0u16.to_be_bytes());
        mime_body.extend_from_slice(b"mime");
        mime_body.push(0); // item_name
        mime_body.extend_from_slice(b"application/rdf+xml\0");
        iinf_body.extend_from_slice(&fullbox(b"infe", 2, [0, 0, 0], &mime_body));

        // Reuse the EXIF sample plumbing by swapping the iinf via a fresh build.
        // Simpler: build directly here.
        let xmp = b"<x:xmpmeta>secret-xmp</x:xmpmeta>".to_vec();
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);
        let hdlr = fullbox(
            b"hdlr",
            0,
            [0, 0, 0],
            b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0",
        );
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        let build_iloc = |o1: u32, o2: u32| {
            let mut body = vec![0x44, 0x00];
            body.extend_from_slice(&2u16.to_be_bytes());
            for (id, off, len) in [(1u16, o1, av01.len() as u32), (2u16, o2, xmp.len() as u32)] {
                body.extend_from_slice(&id.to_be_bytes());
                body.extend_from_slice(&0u16.to_be_bytes());
                body.extend_from_slice(&0u16.to_be_bytes());
                body.extend_from_slice(&1u16.to_be_bytes());
                body.extend_from_slice(&off.to_be_bytes());
                body.extend_from_slice(&len.to_be_bytes());
            }
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };
        let assemble = |iloc: &[u8]| {
            let mut mp = vec![0, 0, 0, 0];
            mp.extend_from_slice(&hdlr);
            mp.extend_from_slice(&pitm);
            mp.extend_from_slice(&iinf);
            mp.extend_from_slice(iloc);
            let meta = wrap_box(b"meta", &mp);
            let ftyp = wrap_box(b"ftyp", b"mif1\0\0\0\0mif1heic");
            let mut md = av01.to_vec();
            md.extend_from_slice(&xmp);
            let mdat = wrap_box(b"mdat", &md);
            [ftyp, meta, mdat].concat()
        };
        let probe = assemble(&build_iloc(0, 0));
        let base = probe.len() - (av01.len() + xmp.len());
        let file = assemble(&build_iloc(base as u32, (base + av01.len()) as u32));

        let out = strip(&file, StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"secret-xmp"), "XMP gone");
        assert!(contains(&out, &av01), "image intact");
    }

    #[test]
    fn no_metadata_is_returned_unchanged() {
        // A file whose only item is the image → nothing to strip.
        let av01 = [1u8, 2, 3, 4, 5];
        let hdlr = fullbox(
            b"hdlr",
            0,
            [0, 0, 0],
            b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0",
        );
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        let mut iinf_body = Vec::new();
        iinf_body.extend_from_slice(&1u16.to_be_bytes());
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);
        let build = |o: u32| {
            let mut body = vec![0x44, 0x00];
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&o.to_be_bytes());
            body.extend_from_slice(&(av01.len() as u32).to_be_bytes());
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };
        let assemble = |iloc: &[u8]| {
            let mut mp = vec![0, 0, 0, 0];
            mp.extend_from_slice(&hdlr);
            mp.extend_from_slice(&pitm);
            mp.extend_from_slice(&iinf);
            mp.extend_from_slice(iloc);
            let meta = wrap_box(b"meta", &mp);
            let ftyp = wrap_box(b"ftyp", b"avif\0\0\0\0avifmif1");
            let mdat = wrap_box(b"mdat", &av01);
            [ftyp, meta, mdat].concat()
        };
        let probe = assemble(&build(0));
        let base = probe.len() - av01.len();
        let file = assemble(&build(base as u32));
        let out = strip(&file, StripPolicy::default()).unwrap();
        assert_eq!(out, file, "clean file returned unchanged");
    }

    #[test]
    fn malformed_bails() {
        let junk = vec![0u8; 40];
        assert!(strip(&junk, StripPolicy::default()).is_err());
    }

    // ── tier 2 (in-place) — structures tier 1 refuses ────────────────────────

    /// Two `mdat` boxes (image in one, EXIF in the other) — tier 1 bails on the
    /// `mdat`-count guard, tier 2 zero-strips in place at the original size.
    #[test]
    fn in_place_strips_across_multiple_mdat() {
        let av01 = [0xA0u8, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7];
        let exif = b"Exif\0\0tiff-GPS-secret-2".to_vec();

        let hdlr = fullbox(
            b"hdlr",
            0,
            [0, 0, 0],
            b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0",
        );
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        let mut iinf_body = Vec::new();
        iinf_body.extend_from_slice(&2u16.to_be_bytes());
        iinf_body.extend_from_slice(&infe(1, b"av01"));
        iinf_body.extend_from_slice(&infe(2, b"Exif"));
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);
        let mut cdsc = Vec::new();
        cdsc.extend_from_slice(&2u16.to_be_bytes());
        cdsc.extend_from_slice(&1u16.to_be_bytes());
        cdsc.extend_from_slice(&1u16.to_be_bytes());
        let iref = fullbox(b"iref", 0, [0, 0, 0], &wrap_box(b"cdsc", &cdsc));

        let build_iloc = |o1: u32, o2: u32| -> Vec<u8> {
            let mut body = vec![0x44, 0x00];
            body.extend_from_slice(&2u16.to_be_bytes());
            for (id, off, len) in [(1u16, o1, av01.len() as u32), (2u16, o2, exif.len() as u32)] {
                body.extend_from_slice(&id.to_be_bytes());
                body.extend_from_slice(&0u16.to_be_bytes()); // method 0
                body.extend_from_slice(&0u16.to_be_bytes()); // data_ref
                body.extend_from_slice(&1u16.to_be_bytes()); // extent count
                body.extend_from_slice(&off.to_be_bytes());
                body.extend_from_slice(&len.to_be_bytes());
            }
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };

        let ftyp = wrap_box(b"ftyp", b"heic\0\0\0\0mif1heic");
        let build_meta = |iloc: &[u8]| -> Vec<u8> {
            let mut mp = vec![0, 0, 0, 0];
            mp.extend_from_slice(&hdlr);
            mp.extend_from_slice(&pitm);
            mp.extend_from_slice(&iinf);
            mp.extend_from_slice(&iref);
            mp.extend_from_slice(iloc);
            wrap_box(b"meta", &mp)
        };
        let assemble = |iloc: &[u8]| -> Vec<u8> {
            [
                ftyp.clone(),
                build_meta(iloc),
                wrap_box(b"mdat", &av01),
                wrap_box(b"mdat", &exif),
            ]
            .concat()
        };

        let meta_len = build_meta(&build_iloc(0, 0)).len();
        let o1 = (ftyp.len() + meta_len + 8) as u32; // av01 in mdat #1
        let o2 = o1 + av01.len() as u32 + 8; // exif in mdat #2
        let file = assemble(&build_iloc(o1, o2));
        assert!(contains(&file, b"GPS-secret-2"));

        let out = strip(&file, StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"GPS-secret-2"), "EXIF payload zeroed");
        assert!(!contains(&out, b"Exif"), "EXIF item delisted");
        assert!(contains(&out, &av01), "image payload intact");
        assert_eq!(out.len(), file.len(), "in-place keeps the file size");

        let top = boxes_in(&out, 0, out.len()).unwrap();
        assert_eq!(top.iter().filter(|x| x.typ == *b"mdat").count(), 2);
        let meta = *top.iter().find(|x| x.typ == *b"meta").unwrap();
        let mc = boxes_in(&out, meta.body + 4, meta.end).unwrap();
        let iinf = *mc.iter().find(|x| x.typ == *b"iinf").unwrap();
        let (_v, items) = parse_iinf(&out, iinf).unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].0.typ, *b"av01");
    }

    /// A `grid` primary backed by `idat` (construction_method 1) plus an `av01`
    /// tile and an `Exif` item — the typical Samsung HEIC shape. Tier 1 bails on
    /// the method-0-only guard; tier 2 zero-strips EXIF, leaves the grid (idat)
    /// and the tile byte-identical.
    #[test]
    fn in_place_strips_with_idat_grid_item() {
        let tile = [0x10u8, 0x11, 0x12, 0x13, 0x14, 0x15];
        let exif = b"Exif\0\0tiff-GPS-here-data".to_vec();
        let grid = b"GRID-DESC-bytes".to_vec();

        let hdlr = fullbox(
            b"hdlr",
            0,
            [0, 0, 0],
            b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0",
        );
        let pitm = fullbox(b"pitm", 0, [0, 0, 0], &1u16.to_be_bytes());
        let mut iinf_body = Vec::new();
        iinf_body.extend_from_slice(&3u16.to_be_bytes());
        iinf_body.extend_from_slice(&infe(1, b"grid"));
        iinf_body.extend_from_slice(&infe(2, b"Exif"));
        iinf_body.extend_from_slice(&infe(3, b"av01"));
        let iinf = fullbox(b"iinf", 0, [0, 0, 0], &iinf_body);

        let mut dimg = Vec::new(); // grid (1) → tile (3)
        dimg.extend_from_slice(&1u16.to_be_bytes());
        dimg.extend_from_slice(&1u16.to_be_bytes());
        dimg.extend_from_slice(&3u16.to_be_bytes());
        let mut cdsc = Vec::new(); // exif (2) describes grid (1)
        cdsc.extend_from_slice(&2u16.to_be_bytes());
        cdsc.extend_from_slice(&1u16.to_be_bytes());
        cdsc.extend_from_slice(&1u16.to_be_bytes());
        let iref = fullbox(
            b"iref",
            0,
            [0, 0, 0],
            &[wrap_box(b"dimg", &dimg), wrap_box(b"cdsc", &cdsc)].concat(),
        );
        let idat = wrap_box(b"idat", &grid);

        let build_iloc = |o_tile: u32, o_exif: u32| -> Vec<u8> {
            let mut body = vec![0x44, 0x00];
            body.extend_from_slice(&3u16.to_be_bytes());
            // item 1: grid, method 1 (offset into idat)
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&1u16.to_be_bytes()); // method 1
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&0u32.to_be_bytes());
            body.extend_from_slice(&(grid.len() as u32).to_be_bytes());
            // item 3: av01 tile, method 0
            body.extend_from_slice(&3u16.to_be_bytes());
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&o_tile.to_be_bytes());
            body.extend_from_slice(&(tile.len() as u32).to_be_bytes());
            // item 2: exif, method 0
            body.extend_from_slice(&2u16.to_be_bytes());
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&0u16.to_be_bytes());
            body.extend_from_slice(&1u16.to_be_bytes());
            body.extend_from_slice(&o_exif.to_be_bytes());
            body.extend_from_slice(&(exif.len() as u32).to_be_bytes());
            fullbox(b"iloc", 1, [0, 0, 0], &body)
        };

        let ftyp = wrap_box(b"ftyp", b"heic\0\0\0\0mif1heic");
        let build_meta = |iloc: &[u8]| -> Vec<u8> {
            let mut mp = vec![0, 0, 0, 0];
            mp.extend_from_slice(&hdlr);
            mp.extend_from_slice(&pitm);
            mp.extend_from_slice(&iinf);
            mp.extend_from_slice(&iref);
            mp.extend_from_slice(&idat);
            mp.extend_from_slice(iloc);
            wrap_box(b"meta", &mp)
        };
        let assemble = |iloc: &[u8]| -> Vec<u8> {
            let mut md = tile.to_vec();
            md.extend_from_slice(&exif);
            [ftyp.clone(), build_meta(iloc), wrap_box(b"mdat", &md)].concat()
        };

        let meta_len = build_meta(&build_iloc(0, 0)).len();
        let o_tile = (ftyp.len() + meta_len + 8) as u32;
        let o_exif = o_tile + tile.len() as u32;
        let file = assemble(&build_iloc(o_tile, o_exif));
        assert!(contains(&file, b"GPS-here"));

        let out = strip(&file, StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"GPS-here"), "EXIF payload zeroed");
        assert!(contains(&out, b"GRID-DESC"), "idat grid descriptor intact");
        assert!(contains(&out, &tile), "tile payload intact");
        assert_eq!(out.len(), file.len(), "in-place keeps the file size");

        let top = boxes_in(&out, 0, out.len()).unwrap();
        let meta = *top.iter().find(|x| x.typ == *b"meta").unwrap();
        let mc = boxes_in(&out, meta.body + 4, meta.end).unwrap();
        let iinf = *mc.iter().find(|x| x.typ == *b"iinf").unwrap();
        let (_v, items) = parse_iinf(&out, iinf).unwrap();
        assert_eq!(items.len(), 2);
        assert!(items.iter().any(|(it, _)| it.typ == *b"grid"));
        assert!(items.iter().any(|(it, _)| it.typ == *b"av01"));
        assert!(!items.iter().any(|(it, _)| it.typ == *b"Exif"));
    }
}
