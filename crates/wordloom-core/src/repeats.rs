//! Repeated words ("echoes"): the same word used again a few words later in
//! one paragraph, like “the door … the door”. The editor tints them so they
//! stand out while revising (View ▸ Highlight Repeated Words).
//!
//! Only words of four letters or more count, and not common ones (“that”,
//! “said”, “would”), nor capitalised words, so names and sentence starts are
//! left alone. Matching ignores case and curly versus straight apostrophes.
//! Text inside `{>> comments <<}` is skipped.

use std::collections::HashMap;

/// How far apart, in words, two uses may be and still count as a repeat.
pub const WINDOW: usize = 40;

const COMMON: &[&str] = &[
    "about",
    "above",
    "after",
    "again",
    "against",
    "almost",
    "along",
    "also",
    "although",
    "always",
    "another",
    "anything",
    "around",
    "aren't",
    "away",
    "back",
    "be",
    "became",
    "because",
    "become",
    "been",
    "before",
    "behind",
    "being",
    "below",
    "between",
    "both",
    "came",
    "can't",
    "cannot",
    "come",
    "could",
    "could've",
    "couldn't",
    "didn't",
    "does",
    "doesn't",
    "doing",
    "done",
    "don't",
    "down",
    "during",
    "each",
    "either",
    "else",
    "enough",
    "even",
    "ever",
    "every",
    "from",
    "gave",
    "give",
    "going",
    "gone",
    "good",
    "got",
    "hadn't",
    "hasn't",
    "have",
    "haven't",
    "having",
    "he'd",
    "he's",
    "her",
    "here",
    "hers",
    "herself",
    "himself",
    "into",
    "isn't",
    "it's",
    "itself",
    "just",
    "know",
    "knew",
    "like",
    "little",
    "look",
    "looked",
    "made",
    "make",
    "many",
    "might",
    "more",
    "most",
    "much",
    "must",
    "myself",
    "never",
    "next",
    "nothing",
    "once",
    "only",
    "onto",
    "other",
    "others",
    "ourselves",
    "over",
    "perhaps",
    "quite",
    "rather",
    "really",
    "said",
    "same",
    "says",
    "seemed",
    "shall",
    "she'd",
    "she's",
    "should",
    "shouldn't",
    "since",
    "some",
    "something",
    "still",
    "such",
    "take",
    "than",
    "that",
    "that's",
    "their",
    "theirs",
    "them",
    "themselves",
    "then",
    "there",
    "there's",
    "these",
    "they",
    "they'd",
    "they're",
    "they've",
    "thing",
    "things",
    "this",
    "those",
    "though",
    "through",
    "thought",
    "till",
    "told",
    "too",
    "took",
    "toward",
    "towards",
    "under",
    "until",
    "upon",
    "very",
    "want",
    "wanted",
    "wasn't",
    "we'd",
    "we're",
    "we've",
    "well",
    "went",
    "were",
    "weren't",
    "what",
    "what's",
    "when",
    "where",
    "whether",
    "which",
    "while",
    "will",
    "with",
    "within",
    "without",
    "won't",
    "would",
    "would've",
    "wouldn't",
    "yes",
    "you'd",
    "you're",
    "you've",
    "your",
    "yours",
    "yourself",
];

fn is_word_char(c: char) -> bool {
    c.is_alphabetic() || c == '\'' || c == '\u{2019}'
}

/// The repeated words in one paragraph, as UTF-16 `[start, end)` ranges
/// (what Qt's text positions use), in order. Both (all) uses of a repeated
/// word are included.
pub fn repeats(text: &str, window: usize) -> Vec<(usize, usize)> {
    let skip = crate::comments::ranges(text);
    // (lower-case word, start, end) in UTF-16 units.
    let mut words: Vec<(String, usize, usize)> = Vec::new();
    let mut u16pos = 0;
    let mut chars = text.char_indices().peekable();
    while let Some((b, c)) = chars.next() {
        if !c.is_alphabetic() {
            u16pos += c.len_utf16();
            continue;
        }
        let start = u16pos;
        let mut word = String::new();
        word.push(c);
        u16pos += c.len_utf16();
        while let Some(&(_, d)) = chars.peek() {
            if !is_word_char(d) {
                break;
            }
            word.push(d);
            u16pos += d.len_utf16();
            chars.next();
        }
        let in_comment = skip.iter().any(|&(s, e)| b >= s && b < e);
        // Trailing apostrophes (closing quotes) aren't part of the word.
        let trimmed = word.trim_end_matches(['\'', '\u{2019}']);
        let end = start + trimmed.encode_utf16().count();
        if !in_comment {
            words.push((trimmed.replace('\u{2019}', "'"), start, end));
        }
    }
    let counts = |w: &str| {
        let letters = w.chars().filter(|c| c.is_alphabetic()).count();
        letters >= 4
            && !w.chars().next().is_some_and(char::is_uppercase)
            && !COMMON.contains(&w.to_lowercase().as_str())
    };
    let mut last: HashMap<String, usize> = HashMap::new();
    let mut hit = vec![false; words.len()];
    for (i, (w, _, _)) in words.iter().enumerate() {
        if !counts(w) {
            continue;
        }
        let key = w.to_lowercase();
        if let Some(&j) = last.get(&key) {
            if i - j <= window {
                hit[i] = true;
                hit[j] = true;
            }
        }
        last.insert(key, i);
    }
    words
        .iter()
        .zip(hit)
        .filter(|(_, h)| *h)
        .map(|((_, s, e), _)| (*s, *e))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn found(text: &str) -> Vec<String> {
        let units: Vec<u16> = text.encode_utf16().collect();
        repeats(text, WINDOW)
            .into_iter()
            .map(|(s, e)| String::from_utf16(&units[s..e]).unwrap())
            .collect()
    }

    #[test]
    fn marks_both_uses_of_a_nearby_repeat() {
        assert_eq!(
            found("She opened the door. Behind the door was another door."),
            ["door", "door", "door"]
        );
    }

    #[test]
    fn short_common_and_capitalised_words_are_left_alone() {
        assert!(found("It was what it was. He said that he said that.").is_empty());
        assert!(found("Mara ran. Mara stopped.").is_empty());
        // Case-insensitive otherwise: a lower-case use pairs with its echo.
        assert_eq!(found("lantern light, lantern dark"), ["lantern", "lantern"]);
    }

    #[test]
    fn far_apart_uses_are_not_repeats() {
        let filler = "and so on ".repeat(20); // 60 words between
        assert!(found(&format!("the harbour {filler} the harbour")).is_empty());
        assert_eq!(found("the harbour and the harbour").len(), 2);
    }

    #[test]
    fn apostrophes_comments_and_utf16_offsets() {
        // Curly and straight apostrophes match; a closing quote isn't part of the word.
        assert_eq!(
            found("the keeper’s lamp, the keeper's lamp’"),
            ["keeper’s", "lamp", "keeper's", "lamp"]
        );
        assert!(found("storm {>>storm<<} calm").is_empty());
        // An emoji is two UTF-16 units; offsets after it still line up.
        assert_eq!(found("🌊 tide, 🌊 tide"), ["tide", "tide"]);
    }
}
