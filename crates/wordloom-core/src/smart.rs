//! Smart punctuation: “curly quotes”, apostrophes’, em dashes — and
//! ellipses…, the way a typeset book has them.
//!
//! The editor converts as you type (EditorView.qml uses the same rules);
//! [`smarten`] converts existing text, e.g. a pasted or imported chapter.
//! Scene-break lines (`---`, `* * *`) and inline comments are left alone.

/// Whether a quote between `prev` and `next` opens rather than closes.
/// After a dash it depends on what follows: `—"Yes"` opens, but the cut-off
/// speech in `"Wait—"` closes.
pub fn opens(prev: Option<char>, next: Option<char>) -> bool {
    match prev {
        None => true,
        Some('—' | '–' | '-') => next.is_some_and(char::is_alphanumeric),
        Some(c) => c.is_whitespace() || matches!(c, '(' | '[' | '{' | '“' | '‘' | '/'),
    }
}

fn smarten_line(line: &str, out: &mut String) {
    // A scene break is only *, - or _ (and spaces): keep it as typed.
    let t = line.trim();
    if t.len() >= 3 && t.chars().all(|c| matches!(c, '*' | '-' | '_' | ' ')) {
        out.push_str(line);
        return;
    }
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    let mut in_comment = false;
    while i < chars.len() {
        let c = chars[i];
        let rest = |s: &str| {
            chars[i..]
                .iter()
                .take(s.chars().count())
                .copied()
                .eq(s.chars())
        };
        if !in_comment && rest(crate::comments::OPEN) {
            in_comment = true;
        } else if in_comment && rest(crate::comments::CLOSE) {
            in_comment = false;
            out.push_str(crate::comments::CLOSE);
            i += 3;
            continue;
        }
        if in_comment {
            out.push(c);
            i += 1;
            continue;
        }
        let prev = out.chars().next_back();
        let next = chars.get(i + 1).copied();
        match c {
            '"' => out.push(if opens(prev, next) { '“' } else { '”' }),
            '\'' => out.push(if opens(prev, next) { '‘' } else { '’' }),
            '-' if chars.get(i + 1) == Some(&'-') => {
                // "--" or "---" in prose: an em dash.
                let mut n = 2;
                while chars.get(i + n) == Some(&'-') {
                    n += 1;
                }
                out.push('—');
                i += n;
                continue;
            }
            '.' if chars.get(i + 1) == Some(&'.') && chars.get(i + 2) == Some(&'.') => {
                out.push('…');
                i += 3;
                continue;
            }
            _ => out.push(c),
        }
        i += 1;
    }
}

/// `text` with straight quotes, double hyphens and three dots replaced.
pub fn smarten(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for (k, line) in text.split('\n').enumerate() {
        if k > 0 {
            out.push('\n');
        }
        smarten_line(line, &mut out);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_and_apostrophes() {
        assert_eq!(smarten("\"Don't,\" she said."), "“Don’t,” she said.");
        assert_eq!(
            smarten("He said 'no' (\"never\")."),
            "He said ‘no’ (“never”)."
        );
        assert_eq!(smarten("\"Wait—\"\n\"What?\""), "“Wait—”\n“What?”");
        assert_eq!(smarten("the '90s"), "the ‘90s");
        assert_eq!(smarten("She paused—\"Yes.\""), "She paused—“Yes.”");
    }

    #[test]
    fn dashes_and_ellipses() {
        assert_eq!(smarten("Then--nothing... Or---"), "Then—nothing… Or—");
        assert_eq!(smarten("a - b"), "a - b");
        assert_eq!(smarten("well-known"), "well-known");
    }

    #[test]
    fn leaves_scene_breaks_and_comments() {
        assert_eq!(
            smarten("One.\n\n---\n\n* * *\n\nTwo."),
            "One.\n\n---\n\n* * *\n\nTwo."
        );
        assert_eq!(
            smarten("\"Hi\" {>>check \"this\" -- ok<<} \"yes\""),
            "“Hi” {>>check \"this\" -- ok<<} “yes”"
        );
    }

    #[test]
    fn already_smart_text_is_unchanged() {
        let t = "“Don’t—” she said… ‘fine’.";
        assert_eq!(smarten(t), t);
    }
}
