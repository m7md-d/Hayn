//! XMP property surgery — keep the HDR gain-map metadata, drop everything else.
//!
//! A privacy strip normally removes the whole XMP packet, which silently
//! downgrades an Ultra-HDR JPEG to SDR: the `hdrgm` parameters and the Google
//! `Container` directory that LOCATES the gain map live in XMP. Instead we filter
//! the packet to a strict ALLOWLIST — only the RDF scaffolding (`rdf`/`x`) and the
//! gain-map namespaces (`hdrgm`, `Container`, `Item`) survive; every other
//! property (`exif`/`tiff`/`dc`/`photoshop`/GPS/…) is dropped. Privacy-safe by
//! construction (anything not explicitly HDR is removed) and HDR-preserving.

use quick_xml::events::{BytesStart, Event};
use quick_xml::{Reader, Writer};

/// Namespaces kept: the RDF scaffolding plus the gain-map metadata.
const KEEP_PREFIXES: &[&[u8]] = &[b"rdf", b"x", b"hdrgm", b"Container", b"Item"];
/// Of those, the ones whose presence means "this packet carries HDR".
const HDR_PREFIXES: &[&[u8]] = &[b"hdrgm", b"Container", b"Item"];

fn prefix_of(name: &[u8]) -> Option<&[u8]> {
    name.iter().position(|&c| c == b':').map(|i| &name[..i])
}

/// Keep a prefixed name only when its namespace is allow-listed; unprefixed names
/// are RDF structure and kept.
fn keep_name(name: &[u8]) -> bool {
    match prefix_of(name) {
        Some(p) => KEEP_PREFIXES.contains(&p),
        None => true,
    }
}

fn is_hdr_name(name: &[u8]) -> bool {
    prefix_of(name).is_some_and(|p| HDR_PREFIXES.contains(&p))
}

/// Keep an attribute: `xmlns`/`xml:` machinery for allow-listed namespaces, or a
/// name in an allow-listed namespace. (An `xmlns:exif` decl is dropped too, so no
/// privacy namespace even lingers.)
fn keep_attr(key: &[u8]) -> bool {
    if key == b"xmlns" {
        return true;
    }
    if let Some(rest) = key.strip_prefix(b"xmlns:") {
        return KEEP_PREFIXES.contains(&rest);
    }
    key.starts_with(b"xml:") || keep_name(key)
}

/// Filter `packet` (the raw XMP XML) to the HDR allow-list. Returns the filtered
/// packet, or `None` when no gain-map metadata survived (the caller then drops
/// the XMP entirely — the non-HDR case). A parse error also yields `None` (fail
/// safe: drop rather than risk leaking privacy data).
pub fn strip_privacy_keeping_hdr(packet: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::from_reader(packet);
    let mut writer = Writer::new(Vec::new());
    let mut buf = Vec::new();
    let mut skip_depth = 0u32;
    let mut kept_hdr = false;

    loop {
        match reader.read_event_into(&mut buf).ok()? {
            Event::Start(e) => {
                if skip_depth > 0 {
                    skip_depth += 1;
                } else if keep_name(e.name().as_ref()) {
                    let filtered = filter_start(&e, &mut kept_hdr)?;
                    writer.write_event(Event::Start(filtered)).ok()?;
                } else {
                    skip_depth = 1; // drop this element and its whole subtree
                }
            }
            Event::End(e) => {
                if skip_depth > 0 {
                    skip_depth -= 1;
                } else {
                    writer.write_event(Event::End(e)).ok()?;
                }
            }
            Event::Empty(e) => {
                if skip_depth == 0 && keep_name(e.name().as_ref()) {
                    let filtered = filter_start(&e, &mut kept_hdr)?;
                    writer.write_event(Event::Empty(filtered)).ok()?;
                }
            }
            Event::Eof => break,
            other => {
                if skip_depth == 0 {
                    writer.write_event(other).ok()?;
                }
            }
        }
        buf.clear();
    }
    kept_hdr.then(|| writer.into_inner())
}

/// Rebuild a start tag keeping only allow-listed attributes. Flags `kept_hdr`
/// when the element or any kept attribute is a gain-map property. The kept
/// attribute values (gain-map numbers, MIME types, namespace URIs, `rdf:about=""`)
/// carry no XML metacharacters, so writing them verbatim can't double-escape.
fn filter_start(e: &BytesStart, kept_hdr: &mut bool) -> Option<BytesStart<'static>> {
    if is_hdr_name(e.name().as_ref()) {
        *kept_hdr = true;
    }
    let mut out = BytesStart::new(String::from_utf8_lossy(e.name().as_ref()).into_owned());
    for attr in e.attributes() {
        let attr = attr.ok()?;
        let key = attr.key.as_ref();
        if keep_attr(key) {
            if is_hdr_name(key) {
                *kept_hdr = true;
            }
            let k = String::from_utf8_lossy(key).into_owned();
            let v = String::from_utf8_lossy(&attr.value).into_owned();
            out.push_attribute((k.as_str(), v.as_str()));
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    const HDR_XMP: &str = r#"<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/"
    xmlns:Container="http://ns.google.com/photos/1.0/container/"
    xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
    xmlns:exif="http://ns.adobe.com/exif/1.0/"
    xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
    hdrgm:Version="1.0"
    exif:GPSLatitude="12,34.56N"
    tiff:Make="SecretCam">
   <hdrgm:GainMapMax>3.5</hdrgm:GainMapMax>
   <Container:Directory><rdf:Seq><rdf:li Item:Length="9999" Item:Mime="image/jpeg"/></rdf:Seq></Container:Directory>
   <exif:UserComment>private-note</exif:UserComment>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>"#;

    #[test]
    fn keeps_gainmap_drops_privacy() {
        let out = strip_privacy_keeping_hdr(HDR_XMP.as_bytes()).expect("HDR survives");
        // Gain-map metadata kept (values intact for the GContainer to stay valid).
        assert!(contains(&out, b"hdrgm:Version"), "hdrgm kept");
        assert!(contains(&out, b"GainMapMax") && contains(&out, b"3.5"));
        assert!(contains(&out, b"Container:Directory"));
        assert!(
            contains(&out, b"9999") && contains(&out, b"image/jpeg"),
            "GContainer intact"
        );
        // Every privacy trace gone — values, names AND the xmlns declarations.
        assert!(!contains(&out, b"GPSLatitude"));
        assert!(!contains(&out, b"SecretCam"));
        assert!(!contains(&out, b"private-note"));
        assert!(!contains(&out, b"exif"), "no exif namespace lingers");
        assert!(!contains(&out, b"tiff"), "no tiff namespace lingers");
        // Still well-formed XML (re-parses without error).
        let mut r = Reader::from_reader(out.as_slice());
        let mut b = Vec::new();
        loop {
            match r.read_event_into(&mut b).expect("valid XML") {
                Event::Eof => break,
                _ => b.clear(),
            }
        }
    }

    #[test]
    fn non_hdr_xmp_is_dropped() {
        let xmp = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
   <dc:creator>Somebody</dc:creator>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>"#;
        assert!(
            strip_privacy_keeping_hdr(xmp.as_bytes()).is_none(),
            "no gain-map → drop the whole packet"
        );
    }

    #[test]
    fn malformed_is_dropped() {
        assert!(strip_privacy_keeping_hdr(b"<x:xmpmeta><unclosed").is_none());
    }
}
