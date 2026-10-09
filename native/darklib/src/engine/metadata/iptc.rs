//! IPTC-IIM, as JPEG keeps it (APP13, Photoshop's image resource 0x0404),
//! and the XMP it maps to under the IPTC Photo Metadata Standard (IPTC Core,
//! "IIM" column), for the containers that have no IIM: PNG, WebP, HEIF and
//! AVIF hold it as XMP. The XMP the source already has wins: a property is
//! added only where the packet lacks it. Whether the IIM's own value is then
//! lost is the Metadata Working Group's IPTCDigest rule: a digest (resource
//! 0x0425) matching the IIM means the XMP-aware tool that wrote it kept both
//! in step, so the XMP is the current value; no digest, or one that does not
//! match, means the IIM was edited without the XMP, and its value is lost.

use super::md5;
use super::xmp_carry::{NewProp, Value};

pub(crate) const DC: (&str, &str) = ("dc", "http://purl.org/dc/elements/1.1/");
pub(crate) const PHOTOSHOP: (&str, &str) = ("photoshop", "http://ns.adobe.com/photoshop/1.0/");
pub(crate) const IPTC_CORE: (&str, &str) = (
    "Iptc4xmpCore",
    "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/",
);

/// IIM datasets as (record, dataset, value), in file order.
pub(crate) type Datasets<'a> = Vec<(u8, u8, &'a [u8])>;

/// A JPEG's APP13: its IIM datasets, whether its IPTCDigest says the XMP was
/// kept in step with them, and whether it holds Photoshop's own resources
/// besides (resolution, its thumbnail…), which only a JPEG keeps.
pub(crate) struct Iim<'a> {
    pub sets: Datasets<'a>,
    pub in_sync: bool,
    pub others: bool,
}

/// What an APP13 payload (`Photoshop 3.0\0` then `8BIM` resources) holds;
/// `None` when it does not parse. No IIM resource: no datasets.
pub(crate) fn read(app13: &[u8]) -> Option<Iim<'_>> {
    let mut b = app13.strip_prefix(b"Photoshop 3.0\0".as_slice())?;
    let (mut data, mut digest, mut others) = (None, None, false);
    while b.len() >= 12 && &b[..4] == b"8BIM" {
        let id = u16::from_be_bytes([b[4], b[5]]);
        // A Pascal name padded to an even length, its length byte included.
        let name = (1 + b[6] as usize + 1) & !1;
        let at = 6 + name;
        let size = u32::from_be_bytes(b.get(at..at + 4)?.try_into().ok()?) as usize;
        let value = b.get(at + 4..at + 4 + size)?;
        match id {
            0x0404 => data = Some(value),
            0x0425 => digest = Some(value),
            _ => others = true,
        }
        b = b.get((at + 4 + size + 1) & !1..).unwrap_or(&[]);
    }
    let sets = match data {
        Some(d) => iim(d)?,
        None => Vec::new(),
    };
    Some(Iim {
        sets,
        in_sync: data.zip(digest).is_some_and(|(d, g)| g == md5::digest(d)),
        others,
    })
}

/// IIM records: `0x1C`, record, dataset, a 16-bit length (or, with its top
/// bit set, the count of bytes that hold the length), the value.
fn iim(mut b: &[u8]) -> Option<Datasets<'_>> {
    let mut out = Vec::new();
    while let [0x1C, record, dataset, l0, l1, rest @ ..] = b {
        let mut len = u16::from_be_bytes([*l0, *l1]) as usize;
        let mut rest = rest;
        if len & 0x8000 != 0 {
            let n = len & 0x7FFF;
            if n > 4 {
                return None;
            }
            let bytes = rest.get(..n)?;
            len = bytes.iter().fold(0usize, |v, &x| v << 8 | x as usize);
            rest = &rest[n..];
        }
        out.push((*record, *dataset, rest.get(..len)?));
        b = &rest[len..];
    }
    Some(out)
}

/// IIM 2:xx datasets and the XMP property each maps to (IPTC Core).
const MAP: &[(u8, (&str, &str), &str, Kind)] = &[
    (5, DC, "title", Kind::Alt),
    (10, PHOTOSHOP, "Urgency", Kind::Text),
    (15, PHOTOSHOP, "Category", Kind::Text),
    (20, PHOTOSHOP, "SupplementalCategories", Kind::Bag),
    (25, DC, "subject", Kind::Bag),
    (40, PHOTOSHOP, "Instructions", Kind::Text),
    (80, DC, "creator", Kind::Seq),
    (85, PHOTOSHOP, "AuthorsPosition", Kind::Text),
    (90, PHOTOSHOP, "City", Kind::Text),
    (92, IPTC_CORE, "Location", Kind::Text),
    (95, PHOTOSHOP, "State", Kind::Text),
    (100, IPTC_CORE, "CountryCode", Kind::Text),
    (101, PHOTOSHOP, "Country", Kind::Text),
    (103, PHOTOSHOP, "TransmissionReference", Kind::Text),
    (105, PHOTOSHOP, "Headline", Kind::Text),
    (110, PHOTOSHOP, "Credit", Kind::Text),
    (115, PHOTOSHOP, "Source", Kind::Text),
    (116, DC, "rights", Kind::Alt),
    (120, DC, "description", Kind::Alt),
    (122, PHOTOSHOP, "CaptionWriter", Kind::Text),
];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Text,
    Alt,
    Bag,
    Seq,
}

/// The XMP properties `datasets` map to, and whether any dataset has no XMP
/// equivalent here (then the IIM is not carried whole). The record versions
/// (1:00, 2:00) and the character set (1:90) describe the IIM itself.
pub(crate) fn to_xmp(datasets: &Datasets) -> (Vec<NewProp>, bool) {
    // UTF-8 when it reads as UTF-8 (declared by 1:90 `ESC % G` or not, as
    // the Metadata Working Group advises), else IIM's default, Latin-1.
    let text = |v: &[u8]| -> String {
        match std::str::from_utf8(v) {
            Ok(s) => s.to_owned(),
            Err(_) => v.iter().map(|&c| c as char).collect(),
        }
    };
    let mut props: Vec<NewProp> = Vec::new();
    let mut unmapped = false;
    for &(record, dataset, value) in datasets {
        if (record, dataset) == (2, 55) || (record, dataset) == (2, 60) {
            continue; // with each other below
        }
        let Some(&(_, (prefix, uri), local, kind)) =
            MAP.iter().find(|m| record == 2 && m.0 == dataset)
        else {
            unmapped |= !matches!((record, dataset), (1, 0) | (1, 90) | (2, 0));
            continue;
        };
        let v = text(value).trim_end_matches('\0').to_owned();
        match props.iter_mut().find(|p| p.uri == uri && p.local == local) {
            Some(NewProp {
                value: Value::Bag(items) | Value::Seq(items),
                ..
            }) => items.push(v),
            Some(_) => {} // a second value of a single one: the first stays
            None => props.push(NewProp {
                prefix,
                uri,
                local,
                value: match kind {
                    Kind::Text => Value::Text(v),
                    Kind::Alt => Value::Alt(v),
                    Kind::Bag => Value::Bag(vec![v]),
                    Kind::Seq => Value::Seq(vec![v]),
                },
            }),
        }
    }
    if let Some(date) = date_created(datasets) {
        props.push(NewProp {
            prefix: PHOTOSHOP.0,
            uri: PHOTOSHOP.1,
            local: "DateCreated",
            value: Value::Text(date),
        });
    }
    (props, unmapped)
}

/// 2:55 `CCYYMMDD` with 2:60 `HHMMSS±HHMM`, as an XMP date.
fn date_created(datasets: &Datasets) -> Option<String> {
    let find = |d: u8| datasets.iter().find(|x| x.0 == 2 && x.1 == d).map(|x| x.2);
    let date = find(55)?;
    if date.len() != 8 || !date.iter().all(u8::is_ascii_digit) {
        return None;
    }
    let s = |b: &[u8]| String::from_utf8_lossy(b).into_owned();
    let mut out = format!("{}-{}-{}", s(&date[..4]), s(&date[4..6]), s(&date[6..]));
    if let Some(t) = find(60).filter(|t| t.len() == 11 && t[..6].iter().all(u8::is_ascii_digit)) {
        out += &format!(
            "T{}:{}:{}{}:{}",
            s(&t[..2]),
            s(&t[2..4]),
            s(&t[4..6]),
            s(&t[6..9]),
            s(&t[9..])
        );
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An APP13 payload holding `datasets` as IIM in resource 0x0404.
    pub(crate) fn app13(datasets: &[(u8, u8, &[u8])]) -> Vec<u8> {
        let mut iim = Vec::new();
        for &(r, d, v) in datasets {
            iim.extend_from_slice(&[0x1C, r, d]);
            iim.extend_from_slice(&(v.len() as u16).to_be_bytes());
            iim.extend_from_slice(v);
        }
        let mut out = b"Photoshop 3.0\0".to_vec();
        // Another resource first: the walk must step over it.
        out.extend_from_slice(b"8BIM\x03\xED\0\0\0\0\0\x03abc\0");
        out.extend_from_slice(b"8BIM\x04\x04\0\0");
        out.extend_from_slice(&(iim.len() as u32).to_be_bytes());
        out.extend_from_slice(&iim);
        out
    }

    #[test]
    fn iim_maps_to_iptc_core() {
        let payload = app13(&[
            (1, 90, b"\x1b%G"),
            (2, 0, b"\0\x04"),
            (2, 5, b"Object"),
            (2, 25, b"one"),
            (2, 25, b"two"),
            (2, 80, "Byline \u{e9}".as_bytes()),
            (2, 90, b"Riyadh"),
            (2, 55, b"20240506"),
            (2, 60, b"070809+0300"),
        ]);
        let sets = read(&payload).expect("IIM").sets;
        let (props, unmapped) = to_xmp(&sets);
        assert!(!unmapped);
        let find = |local: &str| props.iter().find(|p| p.local == local).map(|p| &p.value);
        assert_eq!(find("title"), Some(&Value::Alt("Object".into())));
        assert_eq!(
            find("subject"),
            Some(&Value::Bag(vec!["one".into(), "two".into()]))
        );
        assert_eq!(
            find("creator"),
            Some(&Value::Seq(vec!["Byline \u{e9}".into()]))
        );
        assert_eq!(find("City"), Some(&Value::Text("Riyadh".into())));
        assert_eq!(
            find("DateCreated"),
            Some(&Value::Text("2024-05-06T07:08:09+03:00".into()))
        );
    }

    #[test]
    fn a_dataset_without_xmp_is_reported() {
        // 2:131 Image Orientation has no IPTC Core property.
        let payload = app13(&[(2, 25, b"one"), (2, 131, b"L")]);
        let (props, unmapped) = to_xmp(&read(&payload).unwrap().sets);
        assert_eq!(props.len(), 1);
        assert!(unmapped);
        // Latin-1 when neither declared nor valid UTF-8.
        let payload = app13(&[(2, 90, b"Z\xfcrich")]);
        let (props, _) = to_xmp(&read(&payload).unwrap().sets);
        assert_eq!(props[0].value, Value::Text("Z\u{fc}rich".into()));
    }

    #[test]
    fn photoshop_resources_besides_iim() {
        let only = read(b"Photoshop 3.0\08BIM\x03\xED\0\0\0\0\0\x01a\0").unwrap();
        assert!(only.sets.is_empty() && only.others);
        assert!(!read(&app13(&[(2, 25, b"one")])).unwrap().sets.is_empty());
        assert!(read(b"not photoshop").is_none());
    }

    /// The IPTCDigest says whether the XMP was kept in step with the IIM.
    #[test]
    fn the_digest_says_whether_xmp_is_current() {
        let payload = app13(&[(2, 25, b"one")]);
        assert!(!read(&payload).unwrap().in_sync, "no digest");
        let iim = &payload[payload.len() - 8..];
        let mut synced = payload.clone();
        synced.extend_from_slice(b"8BIM\x04\x25\0\0\0\0\0\x10");
        synced.extend_from_slice(&md5::digest(iim));
        assert!(read(&synced).unwrap().in_sync);
        let mut stale = payload;
        stale.extend_from_slice(b"8BIM\x04\x25\0\0\0\0\0\x10");
        stale.extend_from_slice(&[0; 16]);
        assert!(!read(&stale).unwrap().in_sync);
    }
}
