//! A minimal zip writer for EPUB and DOCX packages and zip backups, and a
//! reader for .docx imports and restoring backups.
//!
//! Entries are stored uncompressed. EPUB requires that for its first entry
//! (`mimetype`), and manuscripts are small enough that compressing the rest
//! isn't worth a dependency.

use chrono::{DateTime, Datelike, Timelike, Utc};

pub(crate) struct ZipWriter {
    buf: Vec<u8>,
    central: Vec<u8>,
    entries: u16,
    time: u16,
    date: u16,
}

impl ZipWriter {
    /// Every entry gets `modified` as its timestamp.
    pub fn new(modified: DateTime<Utc>) -> Self {
        let year = modified.year().clamp(1980, 2107) as u16;
        Self {
            buf: Vec::new(),
            central: Vec::new(),
            entries: 0,
            time: ((modified.hour() as u16) << 11)
                | ((modified.minute() as u16) << 5)
                | (modified.second() as u16 / 2),
            date: ((year - 1980) << 9) | ((modified.month() as u16) << 5) | modified.day() as u16,
        }
    }

    pub fn add(&mut self, name: &str, data: &[u8]) {
        let crc = crc32(data);
        let offset = self.buf.len() as u32;
        let size = data.len() as u32;
        let name_len = name.len() as u16;
        // Bit 11: the file name is UTF-8.
        let flags: u16 = 1 << 11;

        let b = &mut self.buf;
        b.extend_from_slice(&0x0403_4b50u32.to_le_bytes());
        b.extend_from_slice(&20u16.to_le_bytes()); // version needed
        b.extend_from_slice(&flags.to_le_bytes());
        b.extend_from_slice(&0u16.to_le_bytes()); // method: stored
        b.extend_from_slice(&self.time.to_le_bytes());
        b.extend_from_slice(&self.date.to_le_bytes());
        b.extend_from_slice(&crc.to_le_bytes());
        b.extend_from_slice(&size.to_le_bytes()); // compressed
        b.extend_from_slice(&size.to_le_bytes()); // uncompressed
        b.extend_from_slice(&name_len.to_le_bytes());
        b.extend_from_slice(&0u16.to_le_bytes()); // extra field length
        b.extend_from_slice(name.as_bytes());
        b.extend_from_slice(data);

        let c = &mut self.central;
        c.extend_from_slice(&0x0201_4b50u32.to_le_bytes());
        c.extend_from_slice(&20u16.to_le_bytes()); // version made by
        c.extend_from_slice(&20u16.to_le_bytes()); // version needed
        c.extend_from_slice(&flags.to_le_bytes());
        c.extend_from_slice(&0u16.to_le_bytes());
        c.extend_from_slice(&self.time.to_le_bytes());
        c.extend_from_slice(&self.date.to_le_bytes());
        c.extend_from_slice(&crc.to_le_bytes());
        c.extend_from_slice(&size.to_le_bytes());
        c.extend_from_slice(&size.to_le_bytes());
        c.extend_from_slice(&name_len.to_le_bytes());
        c.extend_from_slice(&[0; 8]); // extra, comment, disk, internal attrs
        c.extend_from_slice(&0u32.to_le_bytes()); // external attrs
        c.extend_from_slice(&offset.to_le_bytes());
        c.extend_from_slice(name.as_bytes());
        self.entries += 1;
    }

    pub fn finish(mut self) -> Vec<u8> {
        let cd_offset = self.buf.len() as u32;
        let cd_size = self.central.len() as u32;
        self.buf.extend_from_slice(&self.central);
        let b = &mut self.buf;
        b.extend_from_slice(&0x0605_4b50u32.to_le_bytes());
        b.extend_from_slice(&[0; 4]); // disk numbers
        b.extend_from_slice(&self.entries.to_le_bytes());
        b.extend_from_slice(&self.entries.to_le_bytes());
        b.extend_from_slice(&cd_size.to_le_bytes());
        b.extend_from_slice(&cd_offset.to_le_bytes());
        b.extend_from_slice(&0u16.to_le_bytes()); // comment length
        self.buf
    }
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = (crc >> 1) ^ (0xEDB8_8320 & (crc & 1).wrapping_neg());
        }
    }
    !crc
}

/// Every file in a zip archive (stored or deflated), as (name, bytes), in
/// the archive's order. `None` if it isn't a zip this reader understands.
pub(crate) fn entries(zip: &[u8]) -> Option<Vec<(String, Vec<u8>)>> {
    let mut out = Vec::new();
    walk(zip, |name, data| {
        out.push((name.to_string(), data()?));
        Some(true)
    })?;
    Some(out)
}

/// The bytes of `name` in a zip archive (stored or deflated).
pub(crate) fn entry(zip: &[u8], name: &str) -> Option<Vec<u8>> {
    let mut found = None;
    walk(zip, |n, data| {
        if n == name {
            found = Some(data()?);
            return Some(false);
        }
        Some(true)
    })?;
    found
}

/// Visit the central directory: `f(name, read)` per entry, where `read()`
/// unpacks it; `f` returns Some(false) to stop, None on a damaged entry.
fn walk(
    zip: &[u8],
    mut f: impl FnMut(&str, &dyn Fn() -> Option<Vec<u8>>) -> Option<bool>,
) -> Option<()> {
    let u16le = |i: usize| {
        zip.get(i..i + 2)
            .map(|b| u16::from_le_bytes([b[0], b[1]]) as usize)
    };
    let u32le = |i: usize| {
        zip.get(i..i + 4)
            .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize)
    };
    // End of central directory: the last "PK\5\6".
    let from = zip.len().saturating_sub(22 + 65_535);
    let eocd = (from..zip.len().saturating_sub(21))
        .rev()
        .find(|&i| zip[i..i + 4] == *b"PK\x05\x06")?;
    let count = u16le(eocd + 10)?;
    let mut at = u32le(eocd + 16)?;
    for _ in 0..count {
        if zip.get(at..at + 4)? != b"PK\x01\x02" {
            return None;
        }
        let method = u16le(at + 10)?;
        let csize = u32le(at + 20)?;
        let nlen = u16le(at + 28)?;
        let elen = u16le(at + 30)?;
        let clen = u16le(at + 32)?;
        let local = u32le(at + 42)?;
        let name = std::str::from_utf8(zip.get(at + 46..at + 46 + nlen)?).ok()?;
        let read = || -> Option<Vec<u8>> {
            let data_at = local + 30 + u16le(local + 26)? + u16le(local + 28)?;
            let raw = zip.get(data_at..data_at + csize)?;
            match method {
                0 => Some(raw.to_vec()),
                8 => miniz_oxide::inflate::decompress_to_vec(raw).ok(),
                _ => None,
            }
        };
        if !f(name, &read)? {
            return Some(());
        }
        at += 46 + nlen + elen + clen;
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crc_known_value() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }

    #[test]
    fn layout() {
        let mut z = ZipWriter::new(Utc::now());
        z.add("mimetype", b"application/epub+zip");
        z.add("a/b.txt", b"hi");
        let bytes = z.finish();
        assert_eq!(&bytes[..4], b"PK\x03\x04");
        // The first entry's name and data are at fixed offsets (EPUB relies
        // on this to sniff the type).
        assert_eq!(&bytes[30..38], b"mimetype");
        assert_eq!(&bytes[38..58], b"application/epub+zip");
        let eocd = bytes.len() - 22;
        assert_eq!(&bytes[eocd..eocd + 4], b"PK\x05\x06");
        assert_eq!(u16::from_le_bytes([bytes[eocd + 10], bytes[eocd + 11]]), 2);
    }
}
