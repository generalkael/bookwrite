//! DOCX (Word / LibreOffice / Google Docs) export.
//!
//! Output uses named styles (Title, Heading 1–3, First Paragraph, Separator,
//! Quote) rather than direct formatting, so the whole book can be restyled
//! in Word by editing a style. Chapters (top-level headings) start on a new
//! page.

use crate::compile::{blocks, esc, spans, Block, CompileOptions, Piece};
use crate::model::Project;
use crate::zip::ZipWriter;

const W: &str = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";

const CONTENT_TYPES: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>
"#;

const RELS: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>
"#;

const DOC_RELS: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>
</Relationships>
"#;

/// Sizes are in half-points, spacing and indents in twentieths of a point.
const STYLES: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults>
<w:rPrDefault><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:eastAsia="Georgia" w:cs="Georgia"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="360" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:firstLine="432"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="FirstParagraph"><w:name w:val="First Paragraph"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:firstLine="0"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Subtitle"/><w:qFormat/><w:pPr><w:spacing w:before="4320" w:after="480"/><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr><w:rPr><w:sz w:val="56"/><w:szCs w:val="56"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr><w:rPr><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:keepNext/><w:pageBreakBefore/><w:spacing w:before="2880" w:after="720"/><w:ind w:firstLine="0"/><w:jc w:val="center"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="480" w:after="240"/><w:ind w:firstLine="0"/><w:jc w:val="center"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:ind w:firstLine="0"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Separator"><w:name w:val="Scene Separator"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:spacing w:before="240" w:after="240"/><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:spacing w:before="120" w:after="120"/><w:ind w:left="720" w:right="720" w:firstLine="0"/></w:pPr><w:rPr><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="FootnoteText"><w:name w:val="footnote text"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:line="240" w:lineRule="auto"/><w:ind w:firstLine="0"/></w:pPr><w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>
<w:style w:type="character" w:styleId="FootnoteReference"><w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>
</w:styles>
"#;

pub(crate) fn build(p: &Project, opts: &CompileOptions, pieces: &[Piece]) -> Vec<u8> {
    let mut body = Body::default();
    if opts.title_page {
        body.para("Title", &p.meta.title, false);
        if !p.meta.author.trim().is_empty() {
            body.para("Subtitle", &p.meta.author, false);
        }
        // Heading 1 already starts a new page.
        if !matches!(pieces.first(), Some(Piece::Heading(1, _))) {
            body.xml
                .push_str("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>\n");
        }
    }
    let mut notes: &[String] = &[];
    for piece in pieces {
        match piece {
            // Real footnotes, at the foot of the page (footnotes.xml).
            Piece::Notes(n) => notes = n,
            Piece::Heading(d, t) => body.heading(*d, t),
            Piece::Separator => body.para("Separator", &opts.scene_separator, false),
            Piece::Body(md) => {
                for b in blocks(md) {
                    match b {
                        // A heading typed in the text sits one level below
                        // the binder headings, as in HTML.
                        Block::Heading(level, t) => body.heading(level + 1, t),
                        Block::Rule => body.para("Separator", "* * *", false),
                        Block::Quote(t) => body.para("Quote", &t, true),
                        Block::Para(t) => {
                            let style = if body.fresh {
                                "FirstParagraph"
                            } else {
                                "Normal"
                            };
                            body.para(style, &t, true);
                        }
                    }
                }
            }
        }
    }
    // An empty body is invalid in some readers.
    if body.xml.is_empty() {
        body.para("Normal", "", false);
    }

    let document = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n\
         <w:document xmlns:w=\"{W}\"><w:body>\n{}\
         <w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/>\
         <w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>\
         </w:sectPr></w:body></w:document>\n",
        body.xml
    );
    let created = p.meta.created.format("%Y-%m-%dT%H:%M:%SZ");
    let modified = p.meta.modified.format("%Y-%m-%dT%H:%M:%SZ");
    let core = format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:title>{}</dc:title><dc:creator>{}</dc:creator>
<dcterms:created xsi:type="dcterms:W3CDTF">{created}</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">{modified}</dcterms:modified>
</cp:coreProperties>
"#,
        esc(&p.meta.title),
        esc(&p.meta.author)
    );

    let mut z = ZipWriter::new(p.meta.modified);
    z.add("[Content_Types].xml", CONTENT_TYPES.as_bytes());
    z.add("_rels/.rels", RELS.as_bytes());
    z.add("docProps/core.xml", core.as_bytes());
    z.add("word/_rels/document.xml.rels", DOC_RELS.as_bytes());
    z.add("word/styles.xml", STYLES.as_bytes());
    z.add("word/document.xml", document.as_bytes());
    z.add("word/footnotes.xml", footnotes_xml(notes).as_bytes());
    z.finish()
}

#[derive(Default)]
struct Body {
    xml: String,
    /// The next paragraph follows a heading or break, so isn't indented.
    fresh: bool,
}

impl Body {
    fn heading(&mut self, depth: usize, text: &str) {
        self.para(&format!("Heading{}", depth.clamp(1, 3)), text, false);
    }

    /// One paragraph. With `markdown`, `*emphasis*` becomes bold/italic runs.
    fn para(&mut self, style: &str, text: &str, markdown: bool) {
        self.xml.push_str(&format!(
            "<w:p><w:pPr><w:pStyle w:val=\"{style}\"/></w:pPr>"
        ));
        if markdown {
            for s in spans(text) {
                run(&mut self.xml, &s.text, s.bold, s.italic);
            }
        } else {
            run(&mut self.xml, text, false, false);
        }
        self.xml.push_str("</w:p>\n");
        self.fresh = !matches!(style, "Normal" | "FirstParagraph");
    }
}

/// The footnotes part: Word's two separators, then one footnote per note
/// (ids match the numbers in the text).
fn footnotes_xml(notes: &[String]) -> String {
    let mut x = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:footnotes xmlns:w=\"{W}\">\n\
         <w:footnote w:type=\"separator\" w:id=\"-1\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:separator/></w:r></w:p></w:footnote>\n\
         <w:footnote w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>\n"
    );
    for (i, note) in notes.iter().enumerate() {
        x.push_str(&format!(
            "<w:footnote w:id=\"{}\"><w:p><w:pPr><w:pStyle w:val=\"FootnoteText\"/></w:pPr>\
             <w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:footnoteRef/></w:r>",
            i + 1
        ));
        run(&mut x, " ", false, false);
        for s in spans(note) {
            run(&mut x, &s.text, s.bold, s.italic);
        }
        x.push_str("</w:p></w:footnote>\n");
    }
    x.push_str("</w:footnotes>\n");
    x
}

/// A run of text; note markers in it become footnote references.
fn run(xml: &mut String, text: &str, bold: bool, italic: bool) {
    if text.contains(crate::footnotes::OPEN) {
        for (t, n) in crate::footnotes::split(text) {
            plain_run(xml, &t, bold, italic);
            if let Some(n) = n {
                xml.push_str(&format!(
                    "<w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:footnoteReference w:id=\"{n}\"/></w:r>"
                ));
            }
        }
        return;
    }
    plain_run(xml, text, bold, italic);
}

fn plain_run(xml: &mut String, text: &str, bold: bool, italic: bool) {
    if text.is_empty() {
        return;
    }
    xml.push_str("<w:r>");
    if bold || italic {
        xml.push_str("<w:rPr>");
        if bold {
            xml.push_str("<w:b/>");
        }
        if italic {
            xml.push_str("<w:i/>");
        }
        xml.push_str("</w:rPr>");
    }
    xml.push_str(&format!(
        "<w:t xml:space=\"preserve\">{}</w:t></w:r>",
        esc(text)
    ));
}

#[cfg(test)]
mod tests {
    use crate::compile::{compile_file, CompileOptions, Format};
    use crate::model::{NodeKind, Project, RootRole};

    #[test]
    fn document() {
        let mut p = Project::new("Book", "Me");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(s1, "One **bold** and _it_.\n\nTwo.\n\n> Quoted".into())
            .unwrap();
        let s2 = p.add_node(ch, None, NodeKind::Text, "S2").unwrap();
        p.set_text(s2, "Three.".into()).unwrap();
        let opts = CompileOptions {
            format: Format::Docx,
            ..Default::default()
        };
        let bytes = compile_file(&p, &opts);
        assert_eq!(&bytes[..2], b"PK");
        let s = String::from_utf8_lossy(&bytes);
        for part in [
            "[Content_Types].xml",
            "word/document.xml",
            "word/styles.xml",
        ] {
            assert!(s.contains(part), "missing {part}");
        }
        assert!(s.contains(
            "<w:pStyle w:val=\"Title\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Book</w:t>"
        ));
        assert!(s.contains("<w:pStyle w:val=\"Heading1\"/>"));
        assert!(
            s.contains("<w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">bold</w:t></w:r>")
        );
        assert!(s.contains("<w:r><w:rPr><w:i/></w:rPr><w:t xml:space=\"preserve\">it</w:t></w:r>"));
        // First paragraph after the chapter heading isn't indented; the next is.
        let first = s
            .find("FirstParagraph\"/></w:pPr><w:r><w:t xml:space=\"preserve\">One ")
            .unwrap();
        let second = s
            .find("Normal\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Two.")
            .unwrap();
        assert!(first < second);
        assert!(s.contains("Quote\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Quoted"));
        // After a scene break, back to an unindented paragraph.
        assert!(s.contains("Separator\"/></w:pPr><w:r><w:t xml:space=\"preserve\">* * *</w:t></w:r></w:p>\n<w:p><w:pPr><w:pStyle w:val=\"FirstParagraph\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Three."));
    }
}
