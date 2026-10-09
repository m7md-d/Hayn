//! XMP as the metadata model carries it between containers (Hayn metadata
//! model, docs/10-DARKLIB.md): one packet, whatever the source held. JPEG's
//! Extended XMP is joined to its main packet, IPTC-IIM goes in as the XMP it
//! maps to, and a packet too large for one JPEG segment is split into a main
//! packet and Extended XMP again (XMP specification part 3, 1.1.3.1).
//!
//! Packets are edited as text, at the byte positions of their RDF elements:
//! what is not touched stays as it was, MakerNote-like private namespaces
//! included. A packet that does not parse is never edited.

use std::collections::HashSet;
use std::ops::Range;

use quick_xml::events::Event;
use quick_xml::name::{QName, ResolveResult};
use quick_xml::{NsReader, XmlVersion};

use super::md5;

const RDF: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
const XMP_NOTE: (&str, &str) = ("xmpNote", "http://ns.adobe.com/xmp/note/");

/// Extended XMP for a JPEG: the GUID its main packet names, and the packet.
pub(crate) type Extended = (String, Vec<u8>);

/// A property value to add.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Value {
    Text(String),
    /// A language alternative with only the default (`x-default`).
    Alt(String),
    Bag(Vec<String>),
    Seq(Vec<String>),
}

/// A property to add where the packet lacks it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct NewProp {
    pub prefix: &'static str,
    pub uri: &'static str,
    pub local: &'static str,
    pub value: Value,
}

/// A top-level property: an element child of an `rdf:Description` (with its
/// byte span) or an attribute of one.
struct Prop {
    uri: String,
    local: String,
    span: Option<Range<usize>>,
    text: Option<String>,
    desc: usize,
}

/// An `rdf:Description` directly under `rdf:RDF`: its start tag, the inside
/// (empty for a self-closing one) and its attributes as written.
struct Desc {
    tag: Range<usize>,
    inner: Range<usize>,
    attrs: Vec<(String, String)>,
}

/// Where things are in a packet.
struct Layout {
    rdf_close: usize,
    descs: Vec<Desc>,
    props: Vec<Prop>,
    /// Every `xmlns:` declaration in the packet, by prefix, first one wins.
    ns: Vec<(String, String)>,
}

fn layout(packet: &[u8]) -> Option<Layout> {
    let text = std::str::from_utf8(packet).ok()?;
    let mut r = NsReader::from_str(text);
    let mut out = Layout {
        rdf_close: 0,
        descs: Vec::new(),
        props: Vec::new(),
        ns: Vec::new(),
    };
    let mut depth = 0usize;
    let mut rdf_depth = None;
    let mut desc_depth = None;
    // An open property element: start, depth, namespace, name, text.
    let mut open: Option<(usize, usize, String, String, Option<String>)> = None;
    loop {
        let at = r.buffer_position() as usize;
        let (res, ev) = r.read_resolved_event().ok()?;
        let uri = match res {
            ResolveResult::Bound(ns) => String::from_utf8_lossy(ns.as_ref()).into_owned(),
            _ => String::new(),
        };
        let after = r.buffer_position() as usize;
        match ev {
            Event::Start(ref e) | Event::Empty(ref e) => {
                let empty = matches!(ev, Event::Empty(_));
                let level = depth + 1;
                let local = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                let mut attrs = Vec::new();
                for a in e.attributes() {
                    let a = a.ok()?;
                    let key = String::from_utf8_lossy(a.key.as_ref()).into_owned();
                    let value = a.normalized_value(XmlVersion::default()).ok()?.into_owned();
                    if let Some(p) = key.strip_prefix("xmlns:") {
                        if !out.ns.iter().any(|(q, _)| q == p) {
                            out.ns.push((p.to_owned(), value.clone()));
                        }
                    }
                    attrs.push((key, value));
                }
                if rdf_depth.is_none() && uri == RDF && local == "RDF" {
                    rdf_depth = Some(level);
                } else if rdf_depth.is_some_and(|d| level == d + 1)
                    && uri == RDF
                    && local == "Description"
                {
                    let desc = out.descs.len();
                    for (key, value) in &attrs {
                        if key.starts_with("xmlns") || key.starts_with("xml:") {
                            continue;
                        }
                        let (res, name) = r.resolver().resolve_attribute(QName(key.as_bytes()));
                        let ResolveResult::Bound(ns) = res else {
                            continue;
                        };
                        let ns = String::from_utf8_lossy(ns.as_ref()).into_owned();
                        if ns != RDF {
                            out.props.push(Prop {
                                uri: ns,
                                local: String::from_utf8_lossy(name.as_ref()).into_owned(),
                                span: None,
                                text: Some(value.clone()),
                                desc,
                            });
                        }
                    }
                    out.descs.push(Desc {
                        tag: at..after,
                        inner: after..after,
                        attrs,
                    });
                    if !empty {
                        desc_depth = Some(level);
                    }
                } else if desc_depth.is_some_and(|d| level == d + 1) {
                    if empty {
                        out.props.push(Prop {
                            uri,
                            local,
                            span: Some(at..after),
                            text: None,
                            desc: out.descs.len() - 1,
                        });
                    } else {
                        open = Some((at, level, uri, local, None));
                    }
                }
                if !empty {
                    depth = level;
                }
            }
            Event::Text(t) => {
                if let Some((_, d, _, _, text)) = open.as_mut() {
                    if *d == depth {
                        let s = t.decode().ok()?;
                        *text = Some(text.take().unwrap_or_default() + &s);
                    }
                }
            }
            Event::End(_) => {
                if open.as_ref().is_some_and(|o| o.1 == depth) {
                    let (start, _, uri, local, text) = open.take()?;
                    out.props.push(Prop {
                        uri,
                        local,
                        span: Some(start..after),
                        text,
                        desc: out.descs.len() - 1,
                    });
                }
                if desc_depth == Some(depth) {
                    out.descs.last_mut()?.inner.end = at;
                    desc_depth = None;
                }
                if rdf_depth == Some(depth) {
                    out.rdf_close = at;
                    rdf_depth = None;
                }
                depth = depth.checked_sub(1)?;
            }
            Event::Eof => break,
            _ => {}
        }
    }
    (out.rdf_close > 0).then_some(out)
}

/// The (namespace, name) of each top-level property; `None` when the packet
/// does not parse.
#[cfg(test)]
pub(crate) fn properties(packet: &[u8]) -> Option<HashSet<(String, String)>> {
    Some(
        layout(packet)?
            .props
            .into_iter()
            .map(|p| (p.uri, p.local))
            .collect(),
    )
}

/// The GUID a main packet names for its Extended XMP (`xmpNote:HasExtendedXMP`).
pub(crate) fn extended_guid(main: &[u8]) -> Option<String> {
    let l = layout(main)?;
    let p = l
        .props
        .iter()
        .find(|p| p.uri == XMP_NOTE.1 && p.local == "HasExtendedXMP")?;
    let guid = p.text.as_deref()?.trim();
    (guid.len() == 32 && guid.bytes().all(|c| c.is_ascii_hexdigit())).then(|| guid.to_owned())
}

fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// An `rdf:Description` declaring `ns`, with `attrs` and `inner` as given.
fn description(ns: &[(String, String)], attrs: &[(String, String)], inner: &str) -> String {
    let mut s = String::from("<rdf:Description rdf:about=\"\"");
    let mut declared: Vec<&str> = Vec::new();
    for (p, u) in ns {
        if p != "rdf" && !declared.contains(&p.as_str()) {
            s += &format!(" xmlns:{p}=\"{}\"", escape(u));
            declared.push(p);
        }
    }
    for (k, v) in attrs {
        if !k.starts_with("xmlns") && k != "rdf:about" {
            s += &format!(" {k}=\"{}\"", escape(v));
        }
    }
    s + ">" + inner + "</rdf:Description>"
}

/// A whole packet around `descriptions`.
fn packet(descriptions: &str) -> Vec<u8> {
    format!(
        "<?xpacket begin=\"\u{feff}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n\
         <x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n\
         <rdf:RDF xmlns:rdf=\"{RDF}\">\n{descriptions}\n</rdf:RDF>\n</x:xmpmeta>\n\
         <?xpacket end=\"w\"?>"
    )
    .into_bytes()
}

/// Byte edits, applied from the last: (range replaced, new bytes).
fn edit(bytes: &[u8], mut edits: Vec<(Range<usize>, Vec<u8>)>) -> Vec<u8> {
    edits.sort_by_key(|e| std::cmp::Reverse(e.0.start));
    let mut out = bytes.to_vec();
    for (range, with) in edits {
        out.splice(range, with);
    }
    out
}

/// `main` with the descriptions of its Extended XMP `extended` moved in and
/// the pointer to it gone: one packet, for a container with no segment limit.
pub(crate) fn merge(main: &[u8], extended: &[u8]) -> Option<Vec<u8>> {
    let lm = layout(main)?;
    let le = layout(extended)?;
    let text = std::str::from_utf8(extended).ok()?;
    let moved: String = le
        .descs
        .iter()
        .map(|d| description(&le.ns, &d.attrs, &text[d.inner.clone()]))
        .collect();
    let mut edits = vec![(lm.rdf_close..lm.rdf_close, moved.into_bytes())];
    for p in lm
        .props
        .iter()
        .filter(|p| p.uri == XMP_NOTE.1 && p.local == "HasExtendedXMP")
    {
        match &p.span {
            Some(span) => edits.push((span.clone(), Vec::new())),
            None => {
                // An attribute: its Description's start tag without it.
                let d = &lm.descs[p.desc];
                let attrs: Vec<_> = d
                    .attrs
                    .iter()
                    .filter(|(k, _)| !k.ends_with(":HasExtendedXMP"))
                    .cloned()
                    .collect();
                let mut tag = String::from("<rdf:Description");
                for (k, v) in &attrs {
                    tag += &format!(" {k}=\"{}\"", escape(v));
                }
                let empty = d.inner.is_empty() && main[d.tag.clone()].ends_with(b"/>");
                tag += if empty { "/>" } else { ">" };
                edits.push((d.tag.clone(), tag.into_bytes()));
            }
        }
    }
    Some(edit(main, edits))
}

fn value_xml(prefix: &str, local: &str, value: &Value) -> String {
    let li = |items: &[String]| -> String {
        items
            .iter()
            .map(|v| format!("<rdf:li>{}</rdf:li>", escape(v)))
            .collect()
    };
    let inner = match value {
        Value::Text(v) => escape(v),
        Value::Alt(v) => format!(
            "<rdf:Alt><rdf:li xml:lang=\"x-default\">{}</rdf:li></rdf:Alt>",
            escape(v)
        ),
        Value::Bag(v) => format!("<rdf:Bag>{}</rdf:Bag>", li(v)),
        Value::Seq(v) => format!("<rdf:Seq>{}</rdf:Seq>", li(v)),
    };
    format!("<{prefix}:{local}>{inner}</{prefix}:{local}>")
}

/// `packet` (or a new one) with the properties of `props` it lacks, and how
/// many it already had; `None` when a packet is given that does not parse.
pub(crate) fn add(packet_in: Option<&[u8]>, props: &[NewProp]) -> Option<(Vec<u8>, usize)> {
    let (have, close) = match packet_in {
        Some(p) => {
            let l = layout(p)?;
            let have: HashSet<_> = l.props.into_iter().map(|p| (p.uri, p.local)).collect();
            (have, Some(l.rdf_close))
        }
        None => (HashSet::new(), None),
    };
    let missing: Vec<&NewProp> = props
        .iter()
        .filter(|p| !have.contains(&(p.uri.to_owned(), p.local.to_owned())))
        .collect();
    let had = props.len() - missing.len();
    if missing.is_empty() {
        return Some((packet_in.map(<[u8]>::to_vec).unwrap_or_default(), had));
    }
    let mut ns: Vec<(String, String)> = Vec::new();
    for p in &missing {
        if !ns.iter().any(|(q, _)| q == p.prefix) {
            ns.push((p.prefix.to_owned(), p.uri.to_owned()));
        }
    }
    let inner: String = missing
        .iter()
        .map(|p| value_xml(p.prefix, p.local, &p.value))
        .collect();
    let desc = description(&ns, &[], &inner);
    let out = match (packet_in, close) {
        (Some(p), Some(at)) => edit(p, vec![(at..at, desc.into_bytes())]),
        _ => packet(&desc),
    };
    Some((out, had))
}

/// `packet` as JPEG takes it: whole when it fits `limit` (its padding gone
/// if need be), else a main packet that fits with the largest properties
/// moved to Extended XMP, named by the GUID. `None` when even that does not
/// fit (properties as attributes stay in the main packet).
pub(crate) fn split_for_jpeg(
    packet_in: &[u8],
    limit: usize,
) -> Option<(Vec<u8>, Option<Extended>)> {
    if packet_in.len() <= limit {
        return Some((packet_in.to_vec(), None));
    }
    // The padding before `<?xpacket end` is room for editing in place.
    let trimmed = trim_padding(packet_in);
    if trimmed.len() <= limit {
        return Some((trimmed, None));
    }
    let l = layout(&trimmed)?;
    let marker_len = 200; // the pointer's Description, with a 32-digit GUID
    let mut elements: Vec<&Prop> = l.props.iter().filter(|p| p.span.is_some()).collect();
    elements.sort_by_key(|p| std::cmp::Reverse(p.span.as_ref().map_or(0, |s| s.len())));
    let mut size = trimmed.len() + marker_len;
    let mut moved: Vec<&Prop> = Vec::new();
    for p in elements {
        if size <= limit {
            break;
        }
        size -= p.span.as_ref()?.len();
        moved.push(p);
    }
    if size > limit {
        return None;
    }
    moved.sort_by_key(|p| p.span.as_ref().map_or(0, |s| s.start));
    let text = std::str::from_utf8(&trimmed).ok()?;
    let inner: String = moved
        .iter()
        .map(|p| &text[p.span.clone().unwrap_or_default()])
        .collect();
    let extended = packet(&description(&l.ns, &[], &inner));
    let guid = md5::hex_upper(&extended);
    let pointer = description(
        &[(XMP_NOTE.0.to_owned(), XMP_NOTE.1.to_owned())],
        &[],
        &format!("<xmpNote:HasExtendedXMP>{guid}</xmpNote:HasExtendedXMP>"),
    );
    let mut edits: Vec<_> = moved
        .iter()
        .map(|p| (p.span.clone().unwrap_or_default(), Vec::new()))
        .collect();
    edits.push((l.rdf_close..l.rdf_close, pointer.into_bytes()));
    let main = edit(&trimmed, edits);
    (main.len() <= limit).then_some((main, Some((guid, extended))))
}

/// `packet` without the whitespace padding before its `<?xpacket end`.
fn trim_padding(packet_in: &[u8]) -> Vec<u8> {
    let end = b"<?xpacket end";
    let Some(at) = packet_in.windows(end.len()).rposition(|w| w == end) else {
        return packet_in.to_vec();
    };
    let start = packet_in[..at]
        .iter()
        .rposition(|c| !c.is_ascii_whitespace())
        .map_or(0, |p| p + 1);
    let mut out = packet_in[..start].to_vec();
    out.push(b'\n');
    out.extend_from_slice(&packet_in[at..]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const MAIN: &str = r#"<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4">
<dc:title><rdf:Alt><rdf:li xml:lang="x-default">Title &amp; more</rdf:li></rdf:Alt></dc:title>
</rdf:Description>
<rdf:Description rdf:about="" xmlns:xmpNote="http://ns.adobe.com/xmp/note/">
<xmpNote:HasExtendedXMP>0123456789ABCDEF0123456789ABCDEF</xmpNote:HasExtendedXMP>
</rdf:Description>
</rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>"#;

    const EXTENDED: &str = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:description><rdf:Alt><rdf:li xml:lang="x-default">long text</rdf:li></rdf:Alt></dc:description></rdf:Description></rdf:RDF></x:xmpmeta>"#;

    fn names(packet: &[u8]) -> HashSet<(String, String)> {
        properties(packet).expect("parses")
    }

    fn has(packet: &[u8], uri: &str, local: &str) -> bool {
        names(packet).contains(&(uri.to_owned(), local.to_owned()))
    }

    const DC: &str = "http://purl.org/dc/elements/1.1/";

    #[test]
    fn reads_the_pointer_and_the_properties() {
        assert_eq!(
            extended_guid(MAIN.as_bytes()).as_deref(),
            Some("0123456789ABCDEF0123456789ABCDEF")
        );
        assert!(has(MAIN.as_bytes(), DC, "title"));
        assert!(has(
            MAIN.as_bytes(),
            "http://ns.adobe.com/xap/1.0/",
            "Rating"
        ));
    }

    #[test]
    fn extended_joins_the_main_packet() {
        let merged = merge(MAIN.as_bytes(), EXTENDED.as_bytes()).expect("merged");
        assert!(has(&merged, DC, "title") && has(&merged, DC, "description"));
        assert_eq!(extended_guid(&merged), None, "the pointer is gone");
        let s = String::from_utf8(merged).unwrap();
        assert!(s.contains("Title &amp; more") && s.contains("long text"));
    }

    #[test]
    fn the_pointer_as_an_attribute_goes_too() {
        let main = MAIN.replace(
            "<rdf:Description rdf:about=\"\" xmlns:xmpNote=\"http://ns.adobe.com/xmp/note/\">\n<xmpNote:HasExtendedXMP>0123456789ABCDEF0123456789ABCDEF</xmpNote:HasExtendedXMP>\n</rdf:Description>",
            "<rdf:Description rdf:about=\"\" xmlns:xmpNote=\"http://ns.adobe.com/xmp/note/\" xmpNote:HasExtendedXMP=\"0123456789ABCDEF0123456789ABCDEF\"/>",
        );
        assert!(extended_guid(main.as_bytes()).is_some());
        let merged = merge(main.as_bytes(), EXTENDED.as_bytes()).unwrap();
        assert_eq!(extended_guid(&merged), None);
        assert!(has(&merged, DC, "description"));
    }

    #[test]
    fn adds_only_what_is_missing() {
        let props = [
            NewProp {
                prefix: "dc",
                uri: DC,
                local: "title",
                value: Value::Alt("IIM title".into()),
            },
            NewProp {
                prefix: "dc",
                uri: DC,
                local: "subject",
                value: Value::Bag(vec!["a<b".into(), "c".into()]),
            },
        ];
        let (out, had) = add(Some(MAIN.as_bytes()), &props).unwrap();
        assert_eq!(had, 1);
        let s = String::from_utf8(out.clone()).unwrap();
        assert!(!s.contains("IIM title"), "the packet's title wins");
        assert!(s.contains("<rdf:li>a&lt;b</rdf:li>"));
        assert!(has(&out, DC, "subject"));
        let (fresh, _) = add(None, &props).unwrap();
        assert!(has(&fresh, DC, "title") && has(&fresh, DC, "subject"));
        assert!(add(Some(b"<x:xmpmeta><broken"), &props).is_none());
    }

    #[test]
    fn a_large_packet_splits_for_jpeg() {
        let big = "y".repeat(80_000);
        let (one, _) = add(
            None,
            &[
                NewProp {
                    prefix: "dc",
                    uri: DC,
                    local: "description",
                    value: Value::Alt(big.clone()),
                },
                NewProp {
                    prefix: "dc",
                    uri: DC,
                    local: "title",
                    value: Value::Alt("short".into()),
                },
            ],
        )
        .unwrap();
        let (main, extended) = split_for_jpeg(&one, 65_504).expect("splits");
        assert!(main.len() <= 65_504);
        let (guid, extended) = extended.expect("extended");
        assert_eq!(extended_guid(&main).as_deref(), Some(guid.as_str()));
        assert_eq!(guid, md5::hex_upper(&extended));
        assert!(has(&main, DC, "title") && !has(&main, DC, "description"));
        assert!(has(&extended, DC, "description"));
        // And back: one packet again.
        let again = merge(&main, &extended).unwrap();
        assert!(has(&again, DC, "title") && has(&again, DC, "description"));
        assert!(String::from_utf8(again).unwrap().contains(&big));
        // A packet that fits is left as it is.
        assert_eq!(
            split_for_jpeg(MAIN.as_bytes(), 65_504).unwrap().0,
            MAIN.as_bytes()
        );
    }
}
