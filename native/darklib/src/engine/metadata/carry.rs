//! The metadata model's one step from the intermediate form ([`Canonical`])
//! to what a container takes (Hayn metadata model, docs/10-DARKLIB.md). Every
//! writer goes through it, so a conversion between any two containers loses
//! only what the target cannot hold at all:
//!
//! - EXIF for new pixels: orientation 1 (they are upright) and no thumbnail
//!   (a picture of the old pixels). JPEG holds 64 KB of it.
//! - XMP as one packet: JPEG's Extended XMP joined to its main packet, then,
//!   for a JPEG target, split again where a segment cannot hold it.
//! - IPTC-IIM as it is for JPEG; elsewhere, the XMP the IPTC standard maps
//!   it to, where the packet lacks it.
//! - ICC as it is (a JPEG takes it in numbered chunks).

use super::xmp_carry::Extended;
use super::{exif, iptc, xmp_carry, Canonical, MetaKind};

/// An APPn payload's limit: the segment length (u16) counts itself.
pub(crate) const APP_MAX: usize = 0xFFFF - 2;
/// The APP1 signature of a main XMP packet.
pub(crate) const XMP_SIG: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
/// The APP1 signature of an Extended XMP segment.
pub(crate) const XMP_EXT_SIG: &[u8] = b"http://ns.adobe.com/xmp/extension/\0";

/// What a container gets, and the kinds it could not.
#[derive(Debug, Default)]
pub(crate) struct ForTarget {
    pub exif: Option<Vec<u8>>,
    /// The bare packet (for JPEG, the main one).
    pub xmp: Option<Vec<u8>>,
    /// JPEG only: the GUID and the Extended XMP it names.
    pub xmp_extended: Option<Extended>,
    pub icc: Option<Vec<u8>>,
    /// JPEG only: the APP13 payload.
    pub iptc: Option<Vec<u8>>,
    pub dropped: Vec<MetaKind>,
}

/// `meta` for a JPEG target (`jpeg`) or another one.
pub(crate) fn for_target(meta: &Canonical, jpeg: bool) -> ForTarget {
    let mut t = ForTarget {
        exif: meta.exif.as_deref().map(exif::for_new_pixels),
        icc: meta.icc.clone(),
        ..Default::default()
    };
    // One packet: the Extended XMP joined, or the main one alone if the two do
    // not parse together (reported).
    let mut xmp = meta.xmp.clone();
    if let (Some(main), Some(ext)) = (&meta.xmp, &meta.xmp_extended) {
        match xmp_carry::merge(main, ext) {
            Some(one) => xmp = Some(one),
            None => t.dropped.push(MetaKind::Xmp),
        }
    }
    if jpeg {
        if t.exif.as_ref().is_some_and(|e| e.len() + 6 > APP_MAX) {
            t.exif = None;
            t.dropped.push(MetaKind::Exif);
        }
        // Up to 255 numbered chunks: 16 MB of profile.
        if t.icc
            .as_ref()
            .is_some_and(|p| p.len() > 255 * (APP_MAX - 14))
        {
            t.icc = None;
            t.dropped.push(MetaKind::Icc);
        }
        // A main packet that fits, with its Extended XMP as it came; else the
        // joined packet split again.
        let verbatim = meta
            .xmp
            .as_ref()
            .zip(meta.xmp_extended.as_ref())
            .and_then(|(m, e)| {
                let guid = xmp_carry::extended_guid(m)?;
                (m.len() + XMP_SIG.len() <= APP_MAX).then(|| (m.clone(), Some((guid, e.clone()))))
            });
        let split = verbatim.or_else(|| {
            xmp.as_deref()
                .map(|p| xmp_carry::split_for_jpeg(p, APP_MAX - XMP_SIG.len()))?
        });
        match (xmp.is_some(), split) {
            (_, Some((main, ext))) => {
                t.xmp = Some(main);
                t.xmp_extended = ext;
            }
            (true, None) => t.dropped.push(MetaKind::Xmp),
            (false, None) => {}
        }
        match &meta.iptc {
            Some(p) if p.len() <= APP_MAX => t.iptc = Some(p.clone()),
            Some(_) => t.dropped.push(MetaKind::Iptc),
            None => {}
        }
    } else {
        t.xmp = xmp;
        // IIM has no place here: its XMP goes in where the packet lacks it.
        // Where the packet has it, the IIM's value is lost unless its digest
        // says the XMP was kept in step (see `iptc`). Photoshop's other
        // resources have no place at all: recorded.
        if let Some(iim) = meta.iptc.as_deref().and_then(iptc::read) {
            let (props, unmapped) = iptc::to_xmp(&iim.sets);
            let lost = iim.others
                || match xmp_carry::add(t.xmp.as_deref(), &props) {
                    _ if props.is_empty() => unmapped,
                    Some((p, had)) => {
                        if !p.is_empty() {
                            t.xmp = Some(p);
                        }
                        unmapped || (had > 0 && !iim.in_sync)
                    }
                    None => true,
                };
            if lost {
                t.dropped.push(MetaKind::Iptc);
            }
        }
    }
    t
}

/// [`for_target`] as the container writers take it.
pub(crate) struct Prepared {
    /// A [`Canonical`] to write as it is.
    pub ready: Canonical,
    /// For a JPEG, the Extended XMP after the main packet.
    pub extended: Option<Extended>,
    /// The kinds left out.
    pub dropped: Vec<MetaKind>,
}

/// `meta` prepared for a JPEG target (`jpeg`) or another one.
pub(crate) fn prepared(meta: &Canonical, jpeg: bool) -> Prepared {
    let t = for_target(meta, jpeg);
    Prepared {
        ready: Canonical {
            exif: t.exif,
            xmp: t.xmp,
            xmp_extended: None,
            icc: t.icc,
            iptc: t.iptc,
            orientation: 1,
        },
        extended: t.xmp_extended,
        dropped: t.dropped,
    }
}
