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

fn strip_inner(b: &[u8]) -> Option<Vec<u8>> {
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
        if victims.contains(&src_item.id) {
            continue;
        }
        let out_item = out_loc.items.iter().find(|x| x.id == src_item.id)?;
        if read_item(src, src_item)? != read_item(out, out_item)? {
            return None; // a kept item's bytes changed — refuse
        }
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
}
