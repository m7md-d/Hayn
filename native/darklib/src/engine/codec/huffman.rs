//! Lossless Huffman re-optimisation of a baseline JPEG (Hayn RUN-01 step 6).
//!
//! libjpeg's `optimize_coding` builds the tables from every symbol of the image
//! before writing a byte, so it keeps all the quantised coefficients: 128 bytes
//! per 8×8 block, about 1.1 GB for 200 MP. Here the image is first coded with
//! the standard tables, row by row, then this module reads the entropy-coded
//! data twice: once to count the symbols, once to write them again under
//! tables built by libjpeg's own algorithm (`jpeg_gen_optimal_table`). No DCT
//! and no pixels: memory follows the compressed size. With no restart markers
//! the scan comes out byte for byte as `optimize_coding` writes it.
//!
//! With restart markers each interval is independent, so both passes are
//! spread over threads: the counts are summed, and the intervals re-coded side
//! by side and joined in order.
//!
//! Input is DarkLib's own encoder output (see `jpeg_stream`), but nothing here
//! trusts it: a code, run or length that does not fit is an error, never a
//! panic.

use crate::engine::error::{DarkError, Result};

const BAD: DarkError = DarkError::Malformed("jpeg: entropy data does not decode");

/// A Huffman table as DHT stores it: code counts per length 1..=16, then the
/// symbols in code order.
#[derive(Clone)]
struct Table {
    bits: [u8; 17],
    vals: Vec<u8>,
}

/// Code and length per symbol; length 0 when the symbol has no code.
struct Codes {
    code: [u16; 256],
    len: [u8; 256],
}

const FAST: u32 = 10;

/// Decoding tables: a FAST-bit lookahead (entry = length << 8 | symbol, 0 for
/// longer codes), and for those the canonical limits of F.2.2.3.
struct Look {
    fast: Vec<u16>,
    maxcode: [i32; 17],
    base: [i32; 17],
    index: [usize; 17],
    vals: Vec<u8>,
}

impl Table {
    /// Canonical codes (Annex C). `None` when the counts overflow a length.
    fn codes(&self) -> Option<Codes> {
        let mut c = Codes {
            code: [0; 256],
            len: [0; 256],
        };
        let (mut code, mut k) = (0u32, 0usize);
        for l in 1..=16 {
            for _ in 0..self.bits[l] {
                let s = *self.vals.get(k)? as usize;
                if code >= 1 << l {
                    return None;
                }
                c.code[s] = code as u16;
                c.len[s] = l as u8;
                code += 1;
                k += 1;
            }
            code <<= 1;
        }
        Some(c)
    }

    fn look(&self) -> Option<Look> {
        let c = self.codes()?;
        let mut fast = vec![0u16; 1 << FAST];
        for s in 0..256 {
            let l = c.len[s] as u32;
            if l == 0 || l > FAST {
                continue;
            }
            let first = (c.code[s] as usize) << (FAST - l);
            for e in fast.get_mut(first..first + (1 << (FAST - l)))? {
                *e = (l as u16) << 8 | s as u16;
            }
        }
        let (mut maxcode, mut base, mut index) = ([-1i32; 17], [0i32; 17], [0usize; 17]);
        let (mut code, mut k) = (0i32, 0usize);
        for l in 1..=16 {
            base[l] = code;
            index[l] = k;
            code += self.bits[l] as i32;
            k += self.bits[l] as usize;
            if self.bits[l] > 0 {
                maxcode[l] = code - 1;
            }
            code <<= 1;
        }
        Some(Look {
            fast,
            maxcode,
            base,
            index,
            vals: self.vals.clone(),
        })
    }
}

/// libjpeg's `jpeg_gen_optimal_table` (Annex K.2, with K.3's limit of 16
/// bits): the same counts give the same table, so the same bytes. `None` when
/// nothing was counted.
fn optimal(counts: &[u64; 256]) -> Option<Table> {
    if counts.iter().all(|&f| f == 0) {
        return None;
    }
    let mut freq = [0u64; 257];
    freq[..256].copy_from_slice(counts);
    freq[256] = 1; // reserved, so no code is all ones
    let mut codesize = [0usize; 257];
    let mut others = [usize::MAX; 257];
    loop {
        // The smallest nonzero count, the last such on ties; then the next.
        let mut c1 = None;
        let mut v = u64::MAX;
        for (i, &f) in freq.iter().enumerate() {
            if f != 0 && f <= v {
                v = f;
                c1 = Some(i);
            }
        }
        let mut c2 = None;
        let mut v = u64::MAX;
        for (i, &f) in freq.iter().enumerate() {
            if f != 0 && f <= v && Some(i) != c1 {
                v = f;
                c2 = Some(i);
            }
        }
        let (Some(a), Some(b)) = (c1, c2) else { break };
        freq[a] += freq[b];
        freq[b] = 0;
        let mut x = a;
        codesize[x] += 1;
        while others[x] != usize::MAX {
            x = others[x];
            codesize[x] += 1;
        }
        others[x] = b;
        let mut x = b;
        codesize[x] += 1;
        while others[x] != usize::MAX {
            x = others[x];
            codesize[x] += 1;
        }
    }
    let mut bits = [0i64; 33];
    for &s in &codesize {
        if s != 0 {
            *bits.get_mut(s)? += 1;
        }
    }
    let mut i = 32;
    while i > 16 {
        while bits[i] > 0 {
            let mut j = i - 2;
            while bits[j] == 0 {
                j = j.checked_sub(1)?;
            }
            bits[i] -= 2;
            bits[i - 1] += 1;
            bits[j + 1] += 2;
            bits[j] -= 1;
        }
        i -= 1;
    }
    while bits[i] == 0 {
        i = i.checked_sub(1)?;
    }
    bits[i] -= 1; // the reserved code
    let mut t = Table {
        bits: [0; 17],
        vals: Vec::new(),
    };
    for (count, &n) in t.bits.iter_mut().zip(&bits).skip(1) {
        *count = u8::try_from(n).ok()?;
    }
    for l in 1..=32 {
        for (s, &size) in codesize.iter().take(256).enumerate() {
            if size == l {
                t.vals.push(s as u8);
            }
        }
    }
    Some(t)
}

/// Bits of one restart interval, unstuffed, MSB first. Past the end it reads
/// zeros and counts them, so overrunning the data is caught.
struct Reader<'a> {
    d: &'a [u8],
    pos: usize,
    acc: u64,
    n: u32,
    padded: u32,
}

impl<'a> Reader<'a> {
    fn new(d: &'a [u8]) -> Self {
        Reader {
            d,
            pos: 0,
            acc: 0,
            n: 0,
            padded: 0,
        }
    }

    #[inline]
    fn fill(&mut self) {
        while self.n <= 56 {
            let b = match self.d.get(self.pos) {
                Some(&0xFF) if self.d.get(self.pos + 1) == Some(&0) => {
                    self.pos += 2;
                    0xFF
                }
                Some(&0xFF) | None => {
                    self.padded += 1; // a marker or the end: no more data
                    0
                }
                Some(&b) => {
                    self.pos += 1;
                    b
                }
            };
            self.acc = self.acc << 8 | b as u64;
            self.n += 8;
        }
    }

    #[inline]
    fn peek(&mut self, k: u32) -> u32 {
        if self.n < k {
            self.fill();
        }
        ((self.acc >> (self.n - k)) & ((1u64 << k) - 1)) as u32
    }

    #[inline]
    fn take(&mut self, k: u32) -> u32 {
        let v = self.peek(k);
        self.n -= k;
        v
    }

    #[inline]
    fn symbol(&mut self, t: &Look) -> Result<u8> {
        let e = t.fast[self.peek(FAST) as usize];
        if e != 0 {
            self.n -= (e >> 8) as u32;
            return Ok(e as u8);
        }
        let p = self.peek(16) as i32;
        for l in FAST as usize + 1..=16 {
            let code = p >> (16 - l);
            if code <= t.maxcode[l] {
                self.n -= l as u32;
                let k = t.index[l] + (code - t.base[l]) as usize;
                return t.vals.get(k).copied().ok_or(BAD);
            }
        }
        Err(BAD)
    }

    /// Whether the reads stayed within the data: the padding pushed past the
    /// end is still unread.
    fn within(&self) -> bool {
        self.padded * 8 <= self.n
    }
}

struct Writer {
    out: Vec<u8>,
    acc: u64,
    n: u32,
}

impl Writer {
    #[inline]
    fn put(&mut self, v: u32, k: u32) {
        self.acc = self.acc << k | v as u64;
        self.n += k;
        while self.n >= 8 {
            let b = (self.acc >> (self.n - 8)) as u8;
            self.out.push(b);
            if b == 0xFF {
                self.out.push(0);
            }
            self.n -= 8;
        }
    }

    /// Pads the last byte with ones (F.1.2.3).
    fn flush(&mut self) {
        if self.n > 0 {
            let pad = 8 - self.n;
            self.put((1 << pad) - 1, pad);
        }
    }
}

/// One restart interval: its bytes (without the marker) and MCU count.
struct Interval<'a> {
    data: &'a [u8],
    mcus: usize,
}

/// What a pass does with each symbol (table 0 DC, 1 AC) and its extra bits.
trait Sink {
    fn symbol(&mut self, class: usize, s: u8);
    fn bits(&mut self, v: u32, k: u32);
}

/// Decodes one block, handing each symbol and its extra bits to `sink`.
#[inline]
fn walk_block(r: &mut Reader, dc: &Look, ac: &Look, sink: &mut impl Sink) -> Result<()> {
    let s = r.symbol(dc)?;
    if s > 15 {
        return Err(BAD);
    }
    sink.symbol(0, s);
    let x = r.take(s as u32);
    sink.bits(x, s as u32);
    let mut k = 1;
    while k < 64 {
        let rs = r.symbol(ac)?;
        sink.symbol(1, rs);
        let (run, size) = ((rs >> 4) as usize, (rs & 15) as u32);
        if size == 0 {
            if run != 15 {
                break; // EOB
            }
            k += 16;
            continue;
        }
        let x = r.take(size);
        sink.bits(x, size);
        k += run + 1;
        if k > 64 {
            return Err(BAD);
        }
    }
    Ok(())
}

/// Pass 1: counts per class and table.
struct Count<'a> {
    f: &'a mut Counts,
    tables: [usize; 2],
}

impl Sink for Count<'_> {
    #[inline]
    fn symbol(&mut self, class: usize, s: u8) {
        self.f[class][self.tables[class]][s as usize] += 1;
    }
    #[inline]
    fn bits(&mut self, _: u32, _: u32) {}
}

/// Pass 2: the symbol under its new code, then its bits as they were.
struct Recode<'a> {
    w: &'a mut Writer,
    codes: [&'a Codes; 2],
    missing: bool,
}

impl Sink for Recode<'_> {
    #[inline]
    fn symbol(&mut self, class: usize, s: u8) {
        let c = self.codes[class];
        let len = c.len[s as usize];
        if len == 0 {
            self.missing = true;
        }
        self.w.put(c.code[s as usize] as u32, len as u32);
    }
    #[inline]
    fn bits(&mut self, v: u32, k: u32) {
        self.w.put(v, k);
    }
}

type Counts = [[[u64; 256]; 4]; 2];

/// The JPEG with the same scan under optimal tables. `threads` spreads the
/// work over restart intervals (1 = in this thread).
pub fn optimize(jpg: &[u8], threads: usize) -> Result<Vec<u8>> {
    let p = parse(jpg)?;
    let look: Vec<[Option<Look>; 2]> = (0..4)
        .map(|k| {
            [
                p.dht[0][k].as_ref().and_then(Table::look),
                p.dht[1][k].as_ref().and_then(Table::look),
            ]
        })
        .collect();
    let mut blocks = Vec::with_capacity(p.layout.len());
    for &(dc, ac) in &p.layout {
        let (Some(d), Some(a)) = (look[dc][0].as_ref(), look[ac][1].as_ref()) else {
            return Err(DarkError::Malformed("jpeg: scan uses a missing table"));
        };
        blocks.push((dc, ac, d, a));
    }

    let groups = split(&p.intervals, threads.max(1));

    // Pass 1: the symbol counts of each group, summed.
    let counted: Vec<Result<Box<Counts>>> = std::thread::scope(|s| {
        let tasks: Vec<_> = groups
            .iter()
            .map(|g| {
                let blocks = &blocks;
                s.spawn(move || {
                    let mut f: Box<Counts> = Box::new([[[0; 256]; 4]; 2]);
                    for iv in *g {
                        let mut r = Reader::new(iv.data);
                        for _ in 0..iv.mcus {
                            for &(dc, ac, d, a) in blocks {
                                let mut sink = Count {
                                    f: &mut f,
                                    tables: [dc, ac],
                                };
                                walk_block(&mut r, d, a, &mut sink)?;
                            }
                        }
                        if !r.within() {
                            return Err(DarkError::Malformed("jpeg: truncated scan"));
                        }
                    }
                    Ok(f)
                })
            })
            .collect();
        tasks
            .into_iter()
            .map(|t| t.join().unwrap_or(Err(BAD)))
            .collect()
    });
    let mut freq: Box<Counts> = Box::new([[[0; 256]; 4]; 2]);
    for f in counted {
        let f = f?;
        for c in 0..2 {
            for t in 0..4 {
                for s in 0..256 {
                    freq[c][t][s] += f[c][t][s];
                }
            }
        }
    }

    // New tables for the tables the scan uses.
    let mut new: [[Option<Table>; 4]; 2] = Default::default();
    for &(dc, ac, _, _) in &blocks {
        if new[0][dc].is_none() {
            new[0][dc] = Some(optimal(&freq[0][dc]).ok_or(BAD)?);
        }
        if new[1][ac].is_none() {
            new[1][ac] = Some(optimal(&freq[1][ac]).ok_or(BAD)?);
        }
    }
    let mut codes: [[Option<Codes>; 4]; 2] = Default::default();
    for c in 0..2 {
        for t in 0..4 {
            if let Some(table) = &new[c][t] {
                codes[c][t] = Some(table.codes().ok_or(BAD)?);
            }
        }
    }

    // Pass 2: each group re-coded on its own, restart markers numbered by the
    // interval's place in the whole scan.
    let total = p.intervals.len();
    let firsts: Vec<usize> = groups
        .iter()
        .scan(0, |n, g| {
            let first = *n;
            *n += g.len();
            Some(first)
        })
        .collect();
    let coded: Vec<Result<Vec<u8>>> = std::thread::scope(|s| {
        let tasks: Vec<_> = groups
            .iter()
            .zip(&firsts)
            .map(|(g, &first)| {
                let (blocks, codes) = (&blocks, &codes);
                s.spawn(move || {
                    let bytes: usize = g.iter().map(|iv| iv.data.len()).sum();
                    let mut w = Writer {
                        out: Vec::with_capacity(bytes),
                        acc: 0,
                        n: 0,
                    };
                    for (j, iv) in g.iter().enumerate() {
                        let mut r = Reader::new(iv.data);
                        for _ in 0..iv.mcus {
                            for &(dc, ac, d, a) in blocks {
                                let (Some(cd), Some(ca)) =
                                    (codes[0][dc].as_ref(), codes[1][ac].as_ref())
                                else {
                                    return Err(BAD);
                                };
                                let mut sink = Recode {
                                    w: &mut w,
                                    codes: [cd, ca],
                                    missing: false,
                                };
                                walk_block(&mut r, d, a, &mut sink)?;
                                if sink.missing {
                                    return Err(BAD);
                                }
                            }
                        }
                        if !r.within() {
                            return Err(DarkError::Malformed("jpeg: truncated scan"));
                        }
                        w.flush();
                        let index = first + j;
                        if index + 1 < total {
                            w.out.extend_from_slice(&[0xFF, 0xD0 + (index % 8) as u8]);
                        }
                    }
                    Ok(w.out)
                })
            })
            .collect();
        tasks
            .into_iter()
            .map(|t| t.join().unwrap_or(Err(BAD)))
            .collect()
    });

    let mut scan = Vec::with_capacity(p.scan_len);
    for c in coded {
        scan.extend_from_slice(&c?);
    }

    let mut out = Vec::with_capacity(scan.len() + p.sos_at + 1024);
    out.extend_from_slice(&jpg[..2]);
    for seg in &p.kept {
        out.extend_from_slice(seg);
    }
    let mut dht = Vec::new();
    for (tc, row) in new.iter().enumerate() {
        for (th, t) in row.iter().enumerate() {
            if let Some(t) = t {
                dht.push((tc << 4 | th) as u8);
                dht.extend_from_slice(&t.bits[1..]);
                dht.extend_from_slice(&t.vals);
            }
        }
    }
    out.extend_from_slice(&[0xFF, 0xC4]);
    out.extend_from_slice(&u16::try_from(dht.len() + 2).map_err(|_| BAD)?.to_be_bytes());
    out.extend_from_slice(&dht);
    out.extend_from_slice(p.sos);
    out.extend_from_slice(&scan);
    out.extend_from_slice(&jpg[p.scan_end..]);
    Ok(out)
}

/// Contiguous runs of intervals, one per thread, of about equal bytes.
fn split<'a, 'b>(intervals: &'b [Interval<'a>], threads: usize) -> Vec<&'b [Interval<'a>]> {
    let total: usize = intervals.iter().map(|iv| iv.data.len()).sum();
    let per = total.div_ceil(threads.min(intervals.len()).max(1)).max(1);
    let mut groups = Vec::new();
    let (mut start, mut bytes) = (0, 0);
    for (i, iv) in intervals.iter().enumerate() {
        bytes += iv.data.len();
        if bytes >= per {
            groups.push(&intervals[start..=i]);
            start = i + 1;
            bytes = 0;
        }
    }
    if start < intervals.len() {
        groups.push(&intervals[start..]);
    }
    groups
}

/// The parts of a single-scan baseline JPEG the passes need.
struct Parsed<'a> {
    /// Segments before the scan other than DHT, marker included, in order.
    kept: Vec<&'a [u8]>,
    dht: [[Option<Table>; 4]; 2],
    /// (DC table, AC table) of each block of an MCU, in order.
    layout: Vec<(usize, usize)>,
    intervals: Vec<Interval<'a>>,
    sos: &'a [u8],
    sos_at: usize,
    scan_len: usize,
    /// Where the scan's data ends (the EOI marker).
    scan_end: usize,
}

struct Comp {
    id: u8,
    h: usize,
    v: usize,
}

fn parse(jpg: &[u8]) -> Result<Parsed<'_>> {
    const NOT: DarkError = DarkError::Malformed("jpeg: not a single-scan baseline JPEG");
    if jpg.get(..2) != Some(&[0xFF, 0xD8]) {
        return Err(NOT);
    }
    let mut kept = Vec::new();
    let mut dht: [[Option<Table>; 4]; 2] = Default::default();
    let mut comps: Vec<Comp> = Vec::new();
    let (mut w, mut h, mut restart) = (0usize, 0usize, 0usize);
    let mut i = 2;
    let (sos, sos_at) = loop {
        if jpg.get(i) != Some(&0xFF) {
            return Err(NOT);
        }
        let m = *jpg.get(i + 1).ok_or(NOT)?;
        let len =
            u16::from_be_bytes([*jpg.get(i + 2).ok_or(NOT)?, *jpg.get(i + 3).ok_or(NOT)?]) as usize;
        let seg = jpg.get(i..i + 2 + len).ok_or(NOT)?;
        let body = seg.get(4..).ok_or(NOT)?;
        match m {
            0xC4 => {
                let mut j = 0;
                while j < body.len() {
                    let (tc, th) = ((body[j] >> 4) as usize, (body[j] & 15) as usize);
                    if tc > 1 || th > 3 {
                        return Err(NOT);
                    }
                    let mut t = Table {
                        bits: [0; 17],
                        vals: Vec::new(),
                    };
                    t.bits[1..].copy_from_slice(body.get(j + 1..j + 17).ok_or(NOT)?);
                    let n: usize = t.bits.iter().map(|&b| b as usize).sum();
                    t.vals = body.get(j + 17..j + 17 + n).ok_or(NOT)?.to_vec();
                    dht[tc][th] = Some(t);
                    j += 17 + n;
                }
            }
            0xC0 => {
                if body.first() != Some(&8) {
                    return Err(NOT);
                }
                h = u16::from_be_bytes([*body.get(1).ok_or(NOT)?, *body.get(2).ok_or(NOT)?])
                    as usize;
                w = u16::from_be_bytes([*body.get(3).ok_or(NOT)?, *body.get(4).ok_or(NOT)?])
                    as usize;
                for k in 0..*body.get(5).ok_or(NOT)? as usize {
                    let c = body.get(6 + 3 * k..9 + 3 * k).ok_or(NOT)?;
                    let (hs, vs) = ((c[1] >> 4) as usize, (c[1] & 15) as usize);
                    if !(1..=4).contains(&hs) || !(1..=4).contains(&vs) {
                        return Err(NOT);
                    }
                    comps.push(Comp {
                        id: c[0],
                        h: hs,
                        v: vs,
                    });
                }
                kept.push(seg);
            }
            0xC1..=0xCF => return Err(NOT),
            0xDD => {
                restart = u16::from_be_bytes([*body.first().ok_or(NOT)?, *body.get(1).ok_or(NOT)?])
                    as usize;
                kept.push(seg);
            }
            0xDA => break (seg, i),
            _ => kept.push(seg),
        }
        i += 2 + len;
    };
    if w == 0 || h == 0 || comps.is_empty() {
        return Err(NOT);
    }
    let body = &sos[4..];
    let ns = *body.first().ok_or(NOT)? as usize;
    if ns != comps.len() || body.get(1 + 2 * ns..) != Some(&[0, 63, 0]) {
        return Err(NOT);
    }
    let mut scan = Vec::new();
    for k in 0..ns {
        let (cid, t) = (body[1 + 2 * k], body[2 + 2 * k]);
        let ci = comps.iter().position(|c| c.id == cid).ok_or(NOT)?;
        let (dc, ac) = ((t >> 4) as usize, (t & 15) as usize);
        if dc > 3 || ac > 3 {
            return Err(NOT);
        }
        scan.push((ci, dc, ac));
    }
    let hmax = comps.iter().map(|c| c.h).max().unwrap_or(1);
    let vmax = comps.iter().map(|c| c.v).max().unwrap_or(1);
    let (mcus, layout) = if ns == 1 {
        // One component: blocks in raster order, each its own MCU (A.2.2).
        let c = &comps[scan[0].0];
        let bw = (w * c.h).div_ceil(hmax).div_ceil(8);
        let bh = (h * c.v).div_ceil(vmax).div_ceil(8);
        (bw * bh, vec![(scan[0].1, scan[0].2)])
    } else {
        let mut l = Vec::new();
        for &(ci, dc, ac) in &scan {
            for _ in 0..comps[ci].h * comps[ci].v {
                l.push((dc, ac));
            }
        }
        (w.div_ceil(8 * hmax) * h.div_ceil(8 * vmax), l)
    };

    // The intervals: split at RSTn, up to the marker that ends the scan.
    let start = sos_at + sos.len();
    let mut intervals = Vec::new();
    let (mut from, mut j, mut left) = (start, start, mcus);
    let per = if restart == 0 { mcus } else { restart };
    let scan_end = loop {
        let b = *jpg
            .get(j)
            .ok_or(DarkError::Malformed("jpeg: truncated scan"))?;
        if b != 0xFF {
            j += 1;
            continue;
        }
        match jpg.get(j + 1) {
            Some(0) => j += 2,
            Some(0xD0..=0xD7) => {
                let n = per.min(left);
                intervals.push(Interval {
                    data: &jpg[from..j],
                    mcus: n,
                });
                left -= n;
                j += 2;
                from = j;
            }
            Some(0xFF) => j += 1, // fill byte before a marker
            _ => break j,
        }
    };
    if left == 0 {
        return Err(NOT); // a marker too many
    }
    intervals.push(Interval {
        data: &jpg[from..scan_end],
        mcus: left,
    });
    if left > per || jpg.get(scan_end..scan_end + 2) != Some(&[0xFF, 0xD9]) {
        return Err(NOT);
    }
    Ok(Parsed {
        kept,
        dht,
        layout,
        intervals,
        sos,
        sos_at,
        scan_len: scan_end - start,
        scan_end,
    })
}
