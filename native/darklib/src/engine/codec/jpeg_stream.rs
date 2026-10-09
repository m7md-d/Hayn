//! JPEG to JPEG with memory that does not follow the image (Hayn RUN-01 step 6).
//!
//! The source is decoded and re-encoded a band of rows at a time by
//! libjpeg-turbo's code (mozjpeg-sys in its v6 profile, `JCP_FASTEST`): the
//! same quantisation, colour conversion and 4:2:0 as Android's
//! `Bitmap.compress`. That encoder can only optimise its Huffman tables by
//! keeping every coefficient (about 1.1 GB at 200 MP), so the scan is coded
//! with the standard tables and [`huffman::optimize`] re-codes it under
//! optimal ones: the pixels are those `optimize_coding` gives, at the size it
//! gives, with memory near the compressed size.
//!
//! Pixels keep the source's stored orientation (rotating needs the whole
//! image), so the source's EXIF goes with them as it is, Orientation included.
//! Everything else the source carries besides its coding segments (EXIF, XMP,
//! ICC, IPTC, comments) is copied verbatim; the caller strips it when the user
//! asked to. An Ultra HDR gain map stays valid, as the geometry does not
//! change: the MPF images after the primary are appended and their offsets
//! moved. The values are the stored ones, so the colour profile stays right.
//!
//! Sources this path does not take: progressive or multi-scan files (libjpeg
//! decodes those through a whole-image buffer), CMYK, 12-bit and arithmetic
//! coding ([`DarkError::Unsupported`]). Any libjpeg warning, such as corrupt or
//! truncated data, is a failure rather than grey rows.

use std::os::raw::{c_int, c_ulong};
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};
use std::ptr;

use mozjpeg_sys as ffi;

use super::{huffman, MAX_DECODE_PIXELS};
use crate::engine::error::{DarkError, Result};

/// How the re-encode runs. Restart markers let the Huffman pass spread over
/// threads; without them the scan matches libjpeg's `optimize_coding` byte for
/// byte, at the cost of one thread.
#[derive(Clone, Copy, Debug)]
pub struct Options {
    pub restart: bool,
    pub threads: usize,
}

impl Default for Options {
    fn default() -> Self {
        let threads = std::thread::available_parallelism()
            .map_or(1, |n| n.get())
            .min(8);
        Options {
            restart: true,
            threads,
        }
    }
}

/// `src` re-encoded at `quality` (1..=100), with its metadata as it is.
pub fn reencode(src: &[u8], quality: u8) -> Result<Vec<u8>> {
    reencode_with(src, quality, Options::default())
}

pub fn reencode_with(src: &[u8], quality: u8, options: Options) -> Result<Vec<u8>> {
    let source = Layout::parse(src)?;
    let coded = code(src, &source, quality.clamp(1, 100), options.restart, false)?;
    let optimal = huffman::optimize(&coded, if options.restart { options.threads } else { 1 })?;
    drop(coded);
    assemble(src, &source, &optimal)
}

/// What the source's header says, and where its parts are.
struct Layout {
    width: usize,
    height: usize,
    components: usize,
    /// Segments to carry, as ranges of the source, in order.
    carried: Vec<(usize, usize)>,
    /// The carried MPF index: its place in `carried` and where its TIFF header
    /// sits in the source.
    mpf: Option<(usize, usize)>,
    /// Just past the primary image's EOI.
    primary_end: usize,
}

const MALFORMED: DarkError = DarkError::Malformed("jpeg: header does not parse");

impl Layout {
    fn parse(b: &[u8]) -> Result<Layout> {
        if b.get(..2) != Some(&[0xFF, 0xD8]) {
            return Err(DarkError::UnsupportedFormat);
        }
        let mut frame = None;
        let mut carried = Vec::new();
        let mut mpf = None;
        let mut i = 2usize;
        // Header segments up to the first scan.
        let scan = loop {
            if *b.get(i).ok_or(MALFORMED)? != 0xFF {
                return Err(MALFORMED);
            }
            let marker = *b.get(i + 1).ok_or(MALFORMED)?;
            if marker == 0xFF {
                i += 1; // fill byte
                continue;
            }
            let len = u16::from_be_bytes([
                *b.get(i + 2).ok_or(MALFORMED)?,
                *b.get(i + 3).ok_or(MALFORMED)?,
            ]) as usize;
            let end = i + 2 + len;
            let body = b.get(i + 4..end).ok_or(MALFORMED)?;
            if len < 2 {
                return Err(MALFORMED);
            }
            match marker {
                0xC0 | 0xC1 => {
                    let (&precision, rest) = body.split_first().ok_or(MALFORMED)?;
                    let h = u16::from_be_bytes([
                        *rest.first().ok_or(MALFORMED)?,
                        *rest.get(1).ok_or(MALFORMED)?,
                    ]);
                    let w = u16::from_be_bytes([
                        *rest.get(2).ok_or(MALFORMED)?,
                        *rest.get(3).ok_or(MALFORMED)?,
                    ]);
                    let n = *rest.get(4).ok_or(MALFORMED)?;
                    if precision != 8 {
                        return Err(DarkError::Unsupported("jpeg_precision"));
                    }
                    if n != 1 && n != 3 {
                        return Err(DarkError::Unsupported("jpeg_components"));
                    }
                    frame = Some((w as usize, h as usize, n as usize));
                }
                0xC2 | 0xC6 | 0xCA | 0xCE => {
                    return Err(DarkError::Unsupported("jpeg_progressive"))
                }
                0xC3 | 0xC5 | 0xC7 | 0xC9 | 0xCB | 0xCD | 0xCF => {
                    return Err(DarkError::Unsupported("jpeg_coding"))
                }
                0xDA => break i,
                // APP0 (JFIF) and APP14 (Adobe) describe the source's own
                // coding; the encoder writes its JFIF.
                0xE0 | 0xEE => {}
                0xE1..=0xEF | 0xFE => {
                    if marker == 0xE2 && body.starts_with(b"MPF\0") {
                        if mpf.is_some() {
                            return Err(MALFORMED);
                        }
                        mpf = Some((carried.len(), i + 8));
                    }
                    carried.push((i, end));
                }
                _ => {}
            }
            i = end;
        };
        let (width, height, components) = frame.ok_or(MALFORMED)?;
        if width == 0 || height == 0 {
            return Err(MALFORMED);
        }
        if width as u64 * height as u64 > MAX_DECODE_PIXELS {
            return Err(DarkError::TooLarge);
        }
        let primary_end = primary_end(b, scan)?;
        Ok(Layout {
            width,
            height,
            components,
            carried,
            mpf,
            primary_end,
        })
    }
}

/// Just past the EOI that ends the image whose only scan starts at `sos`.
/// A second scan is refused: libjpeg would buffer the whole image for it.
fn primary_end(b: &[u8], sos: usize) -> Result<usize> {
    let len = u16::from_be_bytes([
        *b.get(sos + 2).ok_or(MALFORMED)?,
        *b.get(sos + 3).ok_or(MALFORMED)?,
    ]) as usize;
    let mut j = sos + 2 + len;
    loop {
        let byte = *b.get(j).ok_or(DarkError::Malformed("jpeg: truncated"))?;
        if byte != 0xFF {
            j += 1;
            continue;
        }
        match *b
            .get(j + 1)
            .ok_or(DarkError::Malformed("jpeg: truncated"))?
        {
            0x00 | 0xD0..=0xD7 => j += 2,
            0xFF => j += 1,
            0xD9 => return Ok(j + 2),
            0xDA => return Err(DarkError::Unsupported("jpeg_multi_scan")),
            _ => {
                // A table or DNL between the data and EOI.
                let len = u16::from_be_bytes([
                    *b.get(j + 2).ok_or(MALFORMED)?,
                    *b.get(j + 3).ok_or(MALFORMED)?,
                ]);
                j += 2 + len as usize;
            }
        }
    }
}

/// The source decoded and encoded a band at a time, standard Huffman tables
/// (`optimize`, libjpeg's whole-image tables, is for the tests' reference).
fn code(src: &[u8], s: &Layout, quality: u8, restart: bool, optimize: bool) -> Result<Vec<u8>> {
    // SAFETY: see `code_unwinding`. libjpeg's fatal errors and warnings unwind
    // out of it (`fatal`, `message`); the guards free its state on the way.
    catch_unwind(AssertUnwindSafe(|| unsafe {
        code_unwinding(src, s, quality, restart, optimize)
    }))
    .unwrap_or(Err(DarkError::Malformed("jpeg: decode failed")))
}

extern "C-unwind" fn fatal(_: &mut ffi::jpeg_common_struct) {
    resume_unwind(Box::new("libjpeg error"));
}

/// Warnings (level -1: corrupt or truncated data, which libjpeg fills with
/// grey) fail the decode; trace messages are ignored.
extern "C-unwind" fn message(_: &mut ffi::jpeg_common_struct, level: c_int) {
    if level < 0 {
        resume_unwind(Box::new("libjpeg warning"));
    }
}

fn error_mgr() -> Box<ffi::jpeg_error_mgr> {
    // SAFETY: jpeg_error_mgr is a plain C struct (pointers, integers and
    // nullable fn pointers), so all zeroes is a valid value; jpeg_std_error
    // fills it before use.
    let mut err: Box<ffi::jpeg_error_mgr> = Box::new(unsafe { std::mem::zeroed() });
    unsafe { ffi::jpeg_std_error(&mut err) };
    err.error_exit = Some(fatal);
    err.emit_message = Some(message);
    err
}

/// Owns a decompressor; destroying an all-zero one is a no-op (`mem` null).
struct Decompress(Box<ffi::jpeg_decompress_struct>);

impl Drop for Decompress {
    fn drop(&mut self) {
        // SAFETY: the struct was zeroed or created by jpeg_CreateDecompress.
        unsafe { ffi::jpeg_destroy_decompress(&mut self.0) };
    }
}

struct Compress(Box<ffi::jpeg_compress_struct>);

impl Drop for Compress {
    fn drop(&mut self) {
        // SAFETY: as for Decompress.
        unsafe { ffi::jpeg_destroy_compress(&mut self.0) };
    }
}

/// The encoder's output: 64 KiB at a time into `out`. `mgr` comes first so
/// libjpeg's `dest` pointer is this struct's address.
#[repr(C)]
struct Dest {
    mgr: ffi::jpeg_destination_mgr,
    chunk: Vec<u8>,
    out: Vec<u8>,
}

const CHUNK: usize = 1 << 16;

extern "C-unwind" fn dest_init(c: &mut ffi::jpeg_compress_struct) {
    // SAFETY: `dest` is the `mgr` of a live Dest (set in code_unwinding).
    let d = unsafe { &mut *(c.dest as *mut Dest) };
    d.mgr.next_output_byte = d.chunk.as_mut_ptr();
    d.mgr.free_in_buffer = d.chunk.len();
}

extern "C-unwind" fn dest_empty(c: &mut ffi::jpeg_compress_struct) -> ffi::boolean {
    // SAFETY: as in dest_init. libjpeg calls this with the chunk full.
    let d = unsafe { &mut *(c.dest as *mut Dest) };
    d.out.extend_from_slice(&d.chunk);
    d.mgr.next_output_byte = d.chunk.as_mut_ptr();
    d.mgr.free_in_buffer = d.chunk.len();
    1
}

extern "C-unwind" fn dest_term(c: &mut ffi::jpeg_compress_struct) {
    // SAFETY: as in dest_init.
    let d = unsafe { &mut *(c.dest as *mut Dest) };
    let used = d.chunk.len() - d.mgr.free_in_buffer;
    d.out.extend_from_slice(&d.chunk[..used]);
}

/// # Safety
/// Calls libjpeg, whose errors unwind through these frames: run it under
/// `catch_unwind` only. `src` outlives the decompressor (dropped first), and
/// `dest` outlives the compressor, both owned here.
unsafe fn code_unwinding(
    src: &[u8],
    s: &Layout,
    quality: u8,
    restart: bool,
    optimize: bool,
) -> Result<Vec<u8>> {
    let mut derr = error_mgr();
    let mut cerr = error_mgr();
    // Declared before the codecs, so dropped after them.
    let mut dest = Box::new(Dest {
        mgr: ffi::jpeg_destination_mgr {
            next_output_byte: ptr::null_mut(),
            free_in_buffer: 0,
            init_destination: Some(dest_init),
            empty_output_buffer: Some(dest_empty),
            term_destination: Some(dest_term),
        },
        chunk: vec![0; CHUNK],
        // About the source's size; grown when the output is larger.
        out: Vec::with_capacity(src.len() + src.len() / 4),
    });

    let mut d = Decompress(Box::new(std::mem::zeroed()));
    d.0.common.err = &mut *derr;
    ffi::jpeg_create_decompress(&mut *d.0);
    ffi::jpeg_mem_src(&mut d.0, src.as_ptr(), src.len() as c_ulong);
    ffi::jpeg_read_header(&mut d.0, 1);
    let grey = s.components == 1;
    d.0.out_color_space = if grey {
        ffi::J_COLOR_SPACE::JCS_GRAYSCALE
    } else {
        ffi::J_COLOR_SPACE::JCS_RGB
    };
    ffi::jpeg_start_decompress(&mut d.0);
    let (w, h) = (d.0.output_width as usize, d.0.output_height as usize);
    let channels = d.0.output_components as usize;
    if (w, h) != (s.width, s.height) || channels != s.components {
        return Err(MALFORMED);
    }

    let mut c = Compress(Box::new(std::mem::zeroed()));
    c.0.common.err = &mut *cerr;
    ffi::jpeg_create_compress(&mut *c.0);
    c.0.dest = &mut dest.mgr;
    c.0.image_width = w as ffi::JDIMENSION;
    c.0.image_height = h as ffi::JDIMENSION;
    c.0.input_components = channels as c_int;
    c.0.in_color_space = d.0.out_color_space;
    ffi::jpeg_c_set_int_param(
        &mut c.0,
        ffi::J_INT_PARAM::JINT_COMPRESS_PROFILE,
        ffi::JINT_COMPRESS_PROFILE_VALUE::JCP_FASTEST as c_int,
    );
    ffi::jpeg_set_defaults(&mut c.0);
    // As Skia sets it: baseline tables at any quality.
    ffi::jpeg_set_quality(&mut c.0, quality as c_int, 1);
    c.0.optimize_coding = optimize as ffi::boolean;
    c.0.restart_in_rows = if restart { 1 } else { 0 };
    // The source's pixel density (JFIF), or libjpeg's 1:1 when it had none.
    c.0.density_unit = d.0.density_unit;
    c.0.X_density = d.0.X_density;
    c.0.Y_density = d.0.Y_density;
    ffi::jpeg_start_compress(&mut c.0, 1);

    // One MCU row of the output at a time.
    let band = (c.0.max_v_samp_factor.max(1) as usize) * 8;
    let stride = w * channels;
    let mut buf = vec![0u8; stride * band];
    let mut y = 0;
    while y < h {
        let rows = band.min(h - y);
        let mut got = 0;
        while got < rows {
            let mut ptrs: Vec<*mut u8> = (got..rows)
                .map(|r| buf.as_mut_ptr().add(r * stride))
                .collect();
            let n = ffi::jpeg_read_scanlines(
                &mut d.0,
                ptrs.as_mut_ptr(),
                (rows - got) as ffi::JDIMENSION,
            ) as usize;
            if n == 0 {
                return Err(DarkError::Malformed("jpeg: truncated"));
            }
            got += n;
        }
        let ptrs: Vec<*const u8> = (0..rows).map(|r| buf.as_ptr().add(r * stride)).collect();
        let n =
            ffi::jpeg_write_scanlines(&mut c.0, ptrs.as_ptr(), rows as ffi::JDIMENSION) as usize;
        if n != rows {
            return Err(DarkError::Malformed("jpeg: encode stalled"));
        }
        y += rows;
    }
    ffi::jpeg_finish_compress(&mut c.0);
    ffi::jpeg_finish_decompress(&mut d.0);
    drop(c);
    drop(d);
    Ok(std::mem::take(&mut dest.out))
}

/// `coded` with the source's carried segments after its JFIF, then the MPF
/// images, their index moved to where they now are.
fn assemble(src: &[u8], s: &Layout, coded: &[u8]) -> Result<Vec<u8>> {
    // Keep MPF and the images after the primary only together: an index with
    // nothing after the image, or bytes no index points at, are dropped.
    let tail = src.get(s.primary_end..).unwrap_or_default();
    let mpf = s.mpf.filter(|_| !tail.is_empty());
    let jfif_end = if coded.get(2..4) == Some(&[0xFF, 0xE0]) {
        4 + u16::from_be_bytes([coded[4], coded[5]]) as usize
    } else {
        2
    };
    let carried: usize = s.carried.iter().map(|(a, b)| b - a).sum();
    let mut out =
        Vec::with_capacity(coded.len() + carried + if mpf.is_some() { tail.len() } else { 0 });
    out.extend_from_slice(coded.get(..jfif_end).ok_or(MALFORMED)?);
    let mut mpf_at = None;
    for (k, &(a, b)) in s.carried.iter().enumerate() {
        match s.mpf {
            Some((m, tiff)) if m == k => {
                if mpf.is_none() {
                    continue;
                }
                mpf_at = Some((out.len() + (tiff - a), tiff));
            }
            _ => {}
        }
        out.extend_from_slice(&src[a..b]);
    }
    out.extend_from_slice(&coded[jfif_end..]);
    if let Some((new_tiff, old_tiff)) = mpf_at {
        let primary = out.len();
        out.extend_from_slice(tail);
        crate::engine::metadata::jpeg::relocate_mpf(
            &mut out,
            new_tiff,
            old_tiff,
            s.primary_end,
            primary,
        )
        .ok_or(DarkError::Malformed(
            "jpeg: MPF index does not fit its images",
        ))?;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::metadata;

    /// A test source from libjpeg: `channels` 1 (grey), 3 (RGB) or 4 (CMYK).
    fn source(w: usize, h: usize, channels: usize, progressive: bool) -> Vec<u8> {
        let mut px = Vec::with_capacity(w * h * channels);
        for y in 0..h {
            for x in 0..w {
                for c in 0..channels {
                    // Gradients with some texture, so every table gets used.
                    let v = (x * 255 / w.max(1) + c * 60 + ((x * 7 + y * 13 + c) % 23) * 3) % 256;
                    px.push(((v + y * 255 / h.max(1)) / 2) as u8);
                }
            }
        }
        let space = match channels {
            1 => ffi::J_COLOR_SPACE::JCS_GRAYSCALE,
            3 => ffi::J_COLOR_SPACE::JCS_RGB,
            _ => ffi::J_COLOR_SPACE::JCS_CMYK,
        };
        catch_unwind(AssertUnwindSafe(|| unsafe {
            let mut err = error_mgr();
            let mut dest = Box::new(Dest {
                mgr: ffi::jpeg_destination_mgr {
                    next_output_byte: ptr::null_mut(),
                    free_in_buffer: 0,
                    init_destination: Some(dest_init),
                    empty_output_buffer: Some(dest_empty),
                    term_destination: Some(dest_term),
                },
                chunk: vec![0; CHUNK],
                out: Vec::new(),
            });
            let mut c = Compress(Box::new(std::mem::zeroed()));
            c.0.common.err = &mut *err;
            ffi::jpeg_create_compress(&mut *c.0);
            c.0.dest = &mut dest.mgr;
            c.0.image_width = w as u32;
            c.0.image_height = h as u32;
            c.0.input_components = channels as c_int;
            c.0.in_color_space = space;
            ffi::jpeg_c_set_int_param(
                &mut c.0,
                ffi::J_INT_PARAM::JINT_COMPRESS_PROFILE,
                ffi::JINT_COMPRESS_PROFILE_VALUE::JCP_FASTEST as c_int,
            );
            ffi::jpeg_set_defaults(&mut c.0);
            ffi::jpeg_set_quality(&mut c.0, 92, 1);
            if progressive {
                ffi::jpeg_simple_progression(&mut c.0);
            }
            ffi::jpeg_start_compress(&mut c.0, 1);
            for y in 0..h {
                let row = [px.as_ptr().add(y * w * channels)];
                ffi::jpeg_write_scanlines(&mut c.0, row.as_ptr(), 1);
            }
            ffi::jpeg_finish_compress(&mut c.0);
            drop(c);
            std::mem::take(&mut dest.out)
        }))
        .expect("test encode")
    }

    fn with_segments(jpg: &[u8], segments: &[(u8, &[u8])]) -> Vec<u8> {
        let mut out = jpg[..2].to_vec();
        for (marker, body) in segments {
            out.extend_from_slice(&[0xFF, *marker]);
            out.extend_from_slice(&((body.len() + 2) as u16).to_be_bytes());
            out.extend_from_slice(body);
        }
        out.extend_from_slice(&jpg[2..]);
        out
    }

    fn scan(jpg: &[u8]) -> &[u8] {
        let at = jpg.windows(2).position(|w| w == [0xFF, 0xDA]).unwrap();
        &jpg[at..]
    }

    fn pixels(jpg: &[u8]) -> image::DynamicImage {
        // zune-jpeg, through `image`: a decoder independent of libjpeg.
        image::load_from_memory_with_format(jpg, image::ImageFormat::Jpeg)
            .expect("independent decode")
    }

    #[test]
    fn without_restarts_the_scan_is_libjpegs_optimised_scan() {
        // Odd sizes leave partial MCUs on both edges.
        for &(w, h, ch) in &[(1, 1, 3), (17, 9, 3), (333, 250, 3), (640, 481, 1)] {
            let src = source(w, h, ch, false);
            let s = Layout::parse(&src).unwrap();
            for q in [30, 80, 95] {
                let reference = code(&src, &s, q, false, true).unwrap();
                let ours = reencode_with(
                    &src,
                    q,
                    Options {
                        restart: false,
                        threads: 1,
                    },
                )
                .unwrap();
                assert_eq!(scan(&ours), scan(&reference), "{w}x{h}x{ch} q{q}");
            }
        }
    }

    #[test]
    fn restarts_and_threads_change_no_pixel() {
        let src = source(1000, 700, 3, false);
        let s = Layout::parse(&src).unwrap();
        let reference = code(&src, &s, 85, false, true).unwrap();
        let want = pixels(&reference);
        for threads in [1, 3, 8] {
            let ours = reencode_with(
                &src,
                85,
                Options {
                    restart: true,
                    threads,
                },
            )
            .unwrap();
            assert_eq!(
                pixels(&ours).as_bytes(),
                want.as_bytes(),
                "{threads} threads"
            );
            // A restart per MCU row costs a few bytes: the marker, the padding
            // and a DC value coded whole.
            let rows = 700usize.div_ceil(16);
            assert!(
                ours.len() <= reference.len() + rows * 8,
                "{} vs {}",
                ours.len(),
                reference.len()
            );
        }
    }

    #[test]
    fn the_output_is_close_to_the_source() {
        let src = source(400, 300, 3, false);
        let out = reencode(&src, 90).unwrap();
        let (a, b) = (pixels(&src).to_rgb8(), pixels(&out).to_rgb8());
        assert_eq!(a.dimensions(), b.dimensions());
        let mse: f64 = a
            .as_raw()
            .iter()
            .zip(b.as_raw())
            .map(|(&x, &y)| (x as f64 - y as f64).powi(2))
            .sum::<f64>()
            / a.as_raw().len() as f64;
        let psnr = 10.0 * (255.0f64 * 255.0 / mse).log10();
        assert!(psnr > 32.0, "PSNR {psnr:.1}");
    }

    #[test]
    fn grey_stays_grey() {
        let out = reencode(&source(64, 48, 1, false), 80).unwrap();
        assert_eq!(pixels(&out).color(), image::ColorType::L8);
    }

    #[test]
    fn metadata_goes_as_it_is_with_the_orientation() {
        let exif = metadata::exif::orientation_only(6).unwrap();
        let mut app1 = b"Exif\0\0".to_vec();
        app1.extend_from_slice(&exif);
        let xmp = b"http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x='adobe:ns:meta/'/>";
        let icc = b"ICC_PROFILE\0\x01\x01not-a-real-profile";
        let adobe = b"Adobe\0\x64\0\0\0\0\x01";
        let src = with_segments(
            &source(40, 30, 3, false),
            &[
                (0xE1, &app1),
                (0xE1, xmp),
                (0xE2, icc),
                (0xEE, adobe),
                (0xFE, b"a comment"),
            ],
        );
        let out = reencode(&src, 80).unwrap();
        let (a, b) = (metadata::extract(&src), metadata::extract(&out));
        assert_eq!(b.orientation, 6, "stored pixels keep their tag");
        assert_eq!(b.exif, a.exif);
        assert_eq!(b.xmp, a.xmp);
        assert_eq!(b.icc, a.icc);
        assert!(out.windows(9).any(|w| w == b"a comment"));
        assert!(
            !out.windows(6).any(|w| w == b"Adobe\0"),
            "the source's colour transform is not the output's"
        );
        // JFIF stays first, as the encoder wrote it.
        assert_eq!(&out[2..4], &[0xFF, 0xE0]);
    }

    #[test]
    fn a_gain_map_is_carried_with_its_index_moved() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/");
        let seine = std::fs::read(format!("{dir}seine_sdr_gainmap_srgb.jpg")).unwrap();
        assert_eq!(
            crate::engine::inspect::inspect(&seine).gain_map,
            crate::engine::inspect::Presence::Present
        );
        for name in ["seine_sdr_gainmap_srgb.jpg", "apple_gainmap_new.jpg"] {
            let src = std::fs::read(format!("{dir}{name}")).unwrap();
            let s = Layout::parse(&src).unwrap();
            let tail = &src[s.primary_end..];
            let out = reencode(&src, 70).unwrap();
            assert!(
                out.ends_with(tail),
                "{name}: the images after the primary as they were"
            );
            // What DarkLib reads of the gain map is what it read of the source
            // (an ISO 21496-1 / Ultra HDR map; Apple's own is not recognised).
            let gain_map = |b: &[u8]| crate::engine::inspect::inspect(b).gain_map;
            assert_eq!(gain_map(&out), gain_map(&src), "{name}");
            // The strip walks the moved index and checks each image's SOI.
            let stripped = metadata::strip(&out, metadata::StripPolicy::default()).expect(name);
            assert_eq!(gain_map(&stripped), gain_map(&src), "{name}");
        }
    }

    #[test]
    fn what_this_path_does_not_take() {
        let unsupported = |src: &[u8]| match reencode(src, 80) {
            Err(DarkError::Unsupported(why)) => why,
            other => panic!("{other:?}"),
        };
        assert_eq!(unsupported(&source(32, 32, 3, true)), "jpeg_progressive");
        assert_eq!(unsupported(&source(32, 32, 4, false)), "jpeg_components");
        assert_eq!(
            reencode(b"\x89PNG\r\n\x1a\n", 80),
            Err(DarkError::UnsupportedFormat)
        );
    }

    #[test]
    fn damaged_data_fails_rather_than_greys() {
        let src = source(300, 200, 3, false);
        let s = Layout::parse(&src).unwrap();
        // Truncated: the scan cut in half, EOI after it.
        let mut cut = src[..s.primary_end / 2].to_vec();
        cut.extend_from_slice(&[0xFF, 0xD9]);
        assert!(matches!(reencode(&cut, 80), Err(DarkError::Malformed(_))));
        // Corrupt: a marker in the middle of the data.
        let mut bad = src.clone();
        let mid = (s.primary_end + scan(&src).as_ptr() as usize - src.as_ptr() as usize) / 2;
        bad[mid] = 0xFF;
        bad[mid + 1] = 0xD3;
        assert!(reencode(&bad, 80).is_err());
        // No EOI at all.
        assert!(reencode(&src[..s.primary_end - 2], 80).is_err());
    }

    #[test]
    fn a_header_past_the_budget_is_refused_before_decoding() {
        let mut src = source(16, 16, 3, false);
        let sof = src.windows(2).position(|w| w == [0xFF, 0xC0]).unwrap();
        src[sof + 5..sof + 9].copy_from_slice(&[0xFF, 0xFF, 0xFF, 0xFF]);
        assert_eq!(reencode(&src, 80), Err(DarkError::TooLarge));
    }
}
