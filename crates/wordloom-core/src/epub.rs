//! EPUB 3 export (with an EPUB 2 table of contents for older readers).
//!
//! Each top-level heading starts a new chapter file, so readers paginate and
//! list chapters properly. Without chapter headings the book is one file.

use crate::compile::{esc, piece_html, CompileOptions, Piece};
use crate::model::{Project, RootRole};
use crate::zip::ZipWriter;

const CSS: &str = "\
body{font-family:Georgia,serif;line-height:1.5;margin:0 5%}
p{margin:0;text-indent:1.5em}
h2+p,h3+p,h4+p,h5+p,h6+p,.sep+p,blockquote+p{text-indent:0}
h2{text-align:center;margin:3em 0 2em}
h3,h4,h5,h6{margin:2em 0 1em}
.sep{text-align:center;margin:1em 0;text-indent:0}
blockquote{margin:1em 2em;font-style:italic}
.title-page{text-align:center;margin-top:30%}
.title-page h1{font-size:2em;margin-bottom:1em}
.title-page .author{text-indent:0;font-size:1.2em}
";

struct Chapter {
    title: String,
    body: String,
}

pub(crate) fn build(p: &Project, opts: &CompileOptions, pieces: &[Piece]) -> Vec<u8> {
    let title = if p.meta.title.trim().is_empty() {
        "Untitled".to_string()
    } else {
        p.meta.title.clone()
    };
    let author = p.meta.author.trim();
    // Stable per project, so re-exports update the same book in a library.
    let uid = format!("urn:uuid:{}", p.root(RootRole::Manuscript));
    let modified = p.meta.modified.format("%Y-%m-%dT%H:%M:%SZ").to_string();

    let mut chapters = split(pieces, opts, &title);
    // Note references link to the Notes chapter (always the last).
    if matches!(pieces.last(), Some(Piece::Notes(_))) {
        let file = format!("c{}.xhtml", chapters.len());
        for c in &mut chapters {
            c.body = c.body.replace(crate::footnotes::NOTES_FILE, &file);
        }
    }

    let mut z = ZipWriter::new(p.meta.modified);
    z.add("mimetype", b"application/epub+zip");
    z.add(
        "META-INF/container.xml",
        br#"<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"#,
    );
    z.add("OEBPS/style.css", CSS.as_bytes());

    // (manifest id, file name, nav label)
    let mut files: Vec<(String, String, String)> = Vec::new();
    if opts.title_page {
        let mut body = format!("<section class=\"title-page\"><h1>{}</h1>", esc(&title));
        if !author.is_empty() {
            body.push_str(&format!("<p class=\"author\">{}</p>", esc(author)));
        }
        body.push_str("</section>\n");
        z.add("OEBPS/title.xhtml", xhtml(&title, &body).as_bytes());
        files.push(("title".into(), "title.xhtml".into(), "Title Page".into()));
    }
    for (i, c) in chapters.iter().enumerate() {
        let name = format!("c{}.xhtml", i + 1);
        z.add(
            &format!("OEBPS/{name}"),
            xhtml(&c.title, &c.body).as_bytes(),
        );
        files.push((format!("c{}", i + 1), name, c.title.clone()));
    }

    let mut manifest = String::new();
    let mut spine = String::new();
    let mut nav = String::new();
    let mut ncx = String::new();
    for (n, (id, file, label)) in files.iter().enumerate() {
        manifest.push_str(&format!(
            "<item id=\"{id}\" href=\"{file}\" media-type=\"application/xhtml+xml\"/>\n"
        ));
        spine.push_str(&format!("<itemref idref=\"{id}\"/>\n"));
        nav.push_str(&format!("<li><a href=\"{file}\">{}</a></li>\n", esc(label)));
        ncx.push_str(&format!(
            "<navPoint id=\"n{0}\" playOrder=\"{0}\"><navLabel><text>{1}</text></navLabel><content src=\"{2}\"/></navPoint>\n",
            n + 1,
            esc(label),
            file
        ));
    }
    let creator = if author.is_empty() {
        String::new()
    } else {
        format!("<dc:creator>{}</dc:creator>\n", esc(author))
    };
    let opf = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">{uid}</dc:identifier>
<dc:title>{title}</dc:title>
{creator}<dc:language>en</dc:language>
<meta property="dcterms:modified">{modified}</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="css" href="style.css" media-type="text/css"/>
{manifest}</manifest>
<spine toc="ncx">
{spine}</spine>
</package>
"#,
        title = esc(&title),
    );
    z.add("OEBPS/content.opf", opf.as_bytes());
    let nav_doc = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<head><meta charset="utf-8"/><title>Contents</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body><nav epub:type="toc" id="toc"><h2>Contents</h2><ol>
{nav}</ol></nav></body></html>
"#
    );
    z.add("OEBPS/nav.xhtml", nav_doc.as_bytes());
    let ncx_doc = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="{uid}"/></head>
<docTitle><text>{title}</text></docTitle>
<navMap>
{ncx}</navMap>
</ncx>
"#,
        title = esc(&title),
    );
    z.add("OEBPS/toc.ncx", ncx_doc.as_bytes());
    z.finish()
}

/// Split at top-level headings. Text before the first one becomes its own
/// opening section.
fn split(pieces: &[Piece], opts: &CompileOptions, book_title: &str) -> Vec<Chapter> {
    let mut out: Vec<Chapter> = Vec::new();
    let mut current: Option<Chapter> = None;
    for piece in pieces {
        // The notes are a chapter of their own, so references can link to it.
        if let Piece::Notes(_) = piece {
            out.extend(current.take());
            current = Some(Chapter {
                title: "Notes".into(),
                body: String::new(),
            });
        }
        if let Piece::Heading(1, t) = piece {
            out.extend(current.take());
            let n = out.len() + 1;
            current = Some(Chapter {
                title: if t.trim().is_empty() {
                    format!("Chapter {n}")
                } else {
                    t.clone()
                },
                body: String::new(),
            });
        }
        let c = current.get_or_insert_with(|| Chapter {
            title: book_title.to_string(),
            body: String::new(),
        });
        c.body.push_str(&piece_html(piece, opts));
    }
    out.extend(current);
    if out.is_empty() {
        out.push(Chapter {
            title: book_title.to_string(),
            body: "<p></p>\n".into(),
        });
    }
    out
}

fn xhtml(title: &str, body: &str) -> String {
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head><meta charset="utf-8"/><title>{}</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
{body}</body></html>
"#,
        esc(title)
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compile::{compile_file, Format};
    use crate::model::NodeKind;

    fn book() -> Project {
        let mut p = Project::new("Tom & Jerry", "A. Writer");
        let ms = p.root(RootRole::Manuscript);
        let ch1 = p.nodes[&ms].children[0];
        p.node_mut(ch1).unwrap().title = "Arrival".into();
        let s1 = p.nodes[&ch1].children[0];
        p.set_text(s1, "It was *dark* & <cold>.".into()).unwrap();
        let ch2 = p.add_node(ms, None, NodeKind::Folder, "").unwrap();
        let s2 = p.add_node(ch2, None, NodeKind::Text, "S").unwrap();
        p.set_text(s2, "Morning.".into()).unwrap();
        p
    }

    fn text(bytes: &[u8]) -> String {
        String::from_utf8_lossy(bytes).into_owned()
    }

    #[test]
    fn package() {
        let p = book();
        let opts = CompileOptions {
            format: Format::Epub,
            ..Default::default()
        };
        let bytes = compile_file(&p, &opts);
        assert_eq!(&bytes[30..58], b"mimetypeapplication/epub+zip");
        let s = text(&bytes);
        assert!(s.contains("<dc:title>Tom &amp; Jerry</dc:title>"));
        assert!(s.contains("<dc:creator>A. Writer</dc:creator>"));
        assert!(s.contains("<p>It was <em>dark</em> &amp; &lt;cold&gt;.</p>"));
        // Two chapters plus the title page, listed in order.
        assert!(s.contains(
            "<itemref idref=\"title\"/>\n<itemref idref=\"c1\"/>\n<itemref idref=\"c2\"/>"
        ));
        assert!(s.contains("<a href=\"c1.xhtml\">Arrival</a>"));
        // An untitled folder still gets a usable contents entry.
        assert!(s.contains("<a href=\"c2.xhtml\">Chapter 2</a>"));
    }

    #[test]
    fn without_chapter_headings_is_one_file() {
        let p = book();
        let opts = CompileOptions {
            format: Format::Epub,
            folder_titles: false,
            title_page: false,
            ..Default::default()
        };
        let s = text(&compile_file(&p, &opts));
        assert!(s.contains("OEBPS/c1.xhtml"));
        assert!(!s.contains("OEBPS/c2.xhtml"));
        assert!(!s.contains("title.xhtml"));
        assert!(s.contains("Morning."));
    }
}
