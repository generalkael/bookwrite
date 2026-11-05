//! Character name generator.
//!
//! Real-world styles combine common given names and surnames from built-in
//! lists; the fantasy style builds names from syllables. Generation is
//! seeded, so tests (and "show me that list again") are repeatable.

use serde::Serialize;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Gender {
    Any,
    Feminine,
    Masculine,
}

impl Gender {
    pub fn parse(s: &str) -> Self {
        match s {
            "feminine" | "f" => Self::Feminine,
            "masculine" | "m" => Self::Masculine,
            _ => Self::Any,
        }
    }
}

struct Style {
    id: &'static str,
    label: &'static str,
    feminine: &'static [&'static str],
    masculine: &'static [&'static str],
    surnames: &'static [&'static str],
}

const STYLES: &[Style] = &[
    Style {
        id: "english",
        label: "English",
        feminine: &[
            "Alice",
            "Amelia",
            "Beatrice",
            "Charlotte",
            "Clara",
            "Edith",
            "Eleanor",
            "Eliza",
            "Emily",
            "Florence",
            "Grace",
            "Harriet",
            "Iris",
            "Isabel",
            "Ivy",
            "Jane",
            "Lucy",
            "Mabel",
            "Margaret",
            "Matilda",
            "Rose",
            "Ruth",
            "Sarah",
            "Violet",
            "Winifred",
        ],
        masculine: &[
            "Albert",
            "Arthur",
            "Benjamin",
            "Charles",
            "Edmund",
            "Edward",
            "Frederick",
            "George",
            "Harry",
            "Henry",
            "Hugh",
            "Jack",
            "James",
            "John",
            "Joseph",
            "Oliver",
            "Oscar",
            "Peter",
            "Robert",
            "Samuel",
            "Thomas",
            "Walter",
            "William",
            "Alfred",
            "Lewis",
        ],
        surnames: &[
            "Ashdown",
            "Barker",
            "Blackwood",
            "Carter",
            "Clarke",
            "Cooper",
            "Fairfax",
            "Fletcher",
            "Hale",
            "Harper",
            "Hawthorne",
            "Kendall",
            "Lowell",
            "Marsh",
            "Mercer",
            "Pemberton",
            "Price",
            "Radcliffe",
            "Sayer",
            "Shaw",
            "Thornton",
            "Turner",
            "Webb",
            "Whitlock",
            "Wren",
        ],
    },
    Style {
        id: "celtic",
        label: "Irish & Scottish",
        feminine: &[
            "Aisling",
            "Bridget",
            "Caitriona",
            "Ciara",
            "Deirdre",
            "Eilidh",
            "Fiona",
            "Grainne",
            "Isla",
            "Kirsty",
            "Maeve",
            "Mairi",
            "Morag",
            "Niamh",
            "Orla",
            "Roisin",
            "Saoirse",
            "Shona",
            "Sinead",
            "Una",
        ],
        masculine: &[
            "Aidan", "Angus", "Callum", "Cian", "Colm", "Conall", "Declan", "Donal", "Eamon",
            "Euan", "Fergus", "Finlay", "Hamish", "Lachlan", "Niall", "Oisin", "Padraig", "Ronan",
            "Ruairi", "Tadhg",
        ],
        surnames: &[
            "Brennan",
            "Buchanan",
            "Cameron",
            "Doherty",
            "Drummond",
            "Farrell",
            "Fraser",
            "Gallagher",
            "Keane",
            "Kennedy",
            "MacLeod",
            "MacRae",
            "Munro",
            "Murray",
            "O'Brien",
            "O'Connell",
            "Quinn",
            "Ross",
            "Sinclair",
            "Sweeney",
        ],
    },
    Style {
        id: "nordic",
        label: "Nordic",
        feminine: &[
            "Astrid", "Brynja", "Dagny", "Eira", "Freya", "Greta", "Gudrun", "Hedda", "Hilde",
            "Ingrid", "Kari", "Liv", "Malin", "Ragna", "Runa", "Sigrid", "Solveig", "Thora",
            "Tove", "Ylva",
        ],
        masculine: &[
            "Anders", "Arne", "Bjorn", "Eirik", "Erland", "Gunnar", "Halvard", "Haakon", "Ivar",
            "Knut", "Leif", "Magnus", "Nils", "Olav", "Rune", "Sigurd", "Sten", "Torvald", "Ulf",
            "Vidar",
        ],
        surnames: &[
            "Aasen",
            "Berg",
            "Dahl",
            "Eklund",
            "Halvorsen",
            "Haugen",
            "Holm",
            "Jansson",
            "Karlsen",
            "Lindqvist",
            "Lund",
            "Moberg",
            "Nygaard",
            "Strand",
            "Sundberg",
            "Tveit",
            "Vik",
            "Wahl",
            "Ostby",
            "Sandvik",
        ],
    },
    Style {
        id: "slavic",
        label: "Slavic",
        feminine: &[
            "Agata", "Alina", "Danica", "Darya", "Halina", "Irina", "Jelena", "Katya", "Lidia",
            "Milena", "Mira", "Nadia", "Olena", "Rada", "Svetlana", "Tamara", "Vera", "Yelena",
            "Zofia", "Zora",
        ],
        masculine: &[
            "Aleksei",
            "Bogdan",
            "Borys",
            "Dmitri",
            "Goran",
            "Ivan",
            "Jaroslav",
            "Kazimir",
            "Lev",
            "Miroslav",
            "Nikolai",
            "Oleg",
            "Pavel",
            "Radek",
            "Stanislav",
            "Tomasz",
            "Vadim",
            "Viktor",
            "Yuri",
            "Zoran",
        ],
        surnames: &[
            "Babic",
            "Dvorak",
            "Horvat",
            "Kovac",
            "Kowalski",
            "Lebedev",
            "Markovic",
            "Novak",
            "Orlov",
            "Petrov",
            "Popescu",
            "Sokolov",
            "Volkov",
            "Wisniewski",
            "Zielinski",
            "Kozlov",
            "Jankovic",
            "Pavlov",
            "Vasko",
            "Morozov",
        ],
    },
    Style {
        id: "romance",
        label: "Italian, Spanish & French",
        feminine: &[
            "Adele",
            "Bianca",
            "Camille",
            "Carmen",
            "Celeste",
            "Elena",
            "Estelle",
            "Giulia",
            "Ines",
            "Isabela",
            "Lucia",
            "Margaux",
            "Marisol",
            "Paloma",
            "Rosa",
            "Serafina",
            "Simone",
            "Sofia",
            "Valentina",
            "Vivienne",
        ],
        masculine: &[
            "Adrien",
            "Alejandro",
            "Antonio",
            "Bastien",
            "Dante",
            "Diego",
            "Enzo",
            "Esteban",
            "Gaspard",
            "Javier",
            "Julien",
            "Lorenzo",
            "Luca",
            "Marco",
            "Mateo",
            "Rafael",
            "Raoul",
            "Silvio",
            "Tomas",
            "Vincent",
        ],
        surnames: &[
            "Albani",
            "Barbieri",
            "Beaumont",
            "Castillo",
            "Delacroix",
            "Esposito",
            "Ferrante",
            "Fontaine",
            "Galvez",
            "Lambert",
            "Marchetti",
            "Moreau",
            "Navarro",
            "Ortega",
            "Rinaldi",
            "Rousseau",
            "Salvatore",
            "Serrano",
            "Valois",
            "Vidal",
        ],
    },
];

const FANTASY_START: &[&str] = &[
    "Ae", "Al", "Ar", "Bel", "Bran", "Cael", "Dor", "El", "Fen", "Gal", "Il", "Ka", "Lor", "Mae",
    "Nim", "Or", "Ryn", "Sel", "Tha", "Ul", "Vae", "Yr", "Zan", "Ere", "Myr",
];
const FANTASY_MID: &[&str] = &[
    "", "", "a", "e", "i", "o", "an", "ar", "el", "en", "ir", "or", "ri", "va", "the", "da",
];
const FANTASY_END_F: &[&str] = &[
    "a", "ia", "elle", "wen", "ys", "ira", "eth", "anna", "is", "lyn", "wyn", "ae",
];
const FANTASY_END_M: &[&str] = &[
    "or", "an", "ric", "us", "ion", "ath", "en", "dor", "mir", "wald", "orn", "ek",
];
const FANTASY_HOUSE: &[&str] = &[
    "Ashfall",
    "Blackthorn",
    "Brightwater",
    "Duskmere",
    "Emberly",
    "Frosthollow",
    "Greymantle",
    "Highcrest",
    "Ironwood",
    "Mistvale",
    "Moonbrook",
    "Ravenhold",
    "Silverleaf",
    "Stormwatch",
    "Thornfield",
    "Winterbourne",
];

#[derive(Serialize)]
pub struct StyleInfo {
    pub id: &'static str,
    pub label: &'static str,
}

/// The styles to offer, real-world first, then "fantasy".
pub fn styles() -> Vec<StyleInfo> {
    let mut out: Vec<StyleInfo> = STYLES
        .iter()
        .map(|s| StyleInfo {
            id: s.id,
            label: s.label,
        })
        .collect();
    out.push(StyleInfo {
        id: "fantasy",
        label: "Fantasy (invented)",
    });
    out
}

/// xorshift64*: small, fast and good enough for picking names.
struct Rng(u64);

impl Rng {
    fn new(seed: u64) -> Self {
        Self(seed.max(1))
    }
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn pick<'a>(&mut self, list: &[&'a str]) -> &'a str {
        list[(self.next() % list.len() as u64) as usize]
    }
    fn coin(&mut self) -> bool {
        self.next() & 1 == 1
    }
}

/// `count` distinct full names in `style` (an id from [`styles`]; unknown
/// ids fall back to English).
pub fn generate(style: &str, gender: Gender, count: usize, seed: u64) -> Vec<String> {
    let mut rng = Rng::new(seed);
    let mut out: Vec<String> = Vec::new();
    let mut tries = 0;
    while out.len() < count && tries < count * 50 {
        tries += 1;
        let feminine = match gender {
            Gender::Feminine => true,
            Gender::Masculine => false,
            Gender::Any => rng.coin(),
        };
        let name = if style == "fantasy" {
            let mut given = String::from(rng.pick(FANTASY_START));
            join(&mut given, rng.pick(FANTASY_MID));
            join(
                &mut given,
                rng.pick(if feminine {
                    FANTASY_END_F
                } else {
                    FANTASY_END_M
                }),
            );
            format!("{given} {}", rng.pick(FANTASY_HOUSE))
        } else {
            let s = STYLES.iter().find(|s| s.id == style).unwrap_or(&STYLES[0]);
            let given = rng.pick(if feminine { s.feminine } else { s.masculine });
            format!("{given} {}", rng.pick(s.surnames))
        };
        if !out.contains(&name) {
            out.push(name);
        }
    }
    out
}

fn is_vowel(c: char) -> bool {
    matches!(c.to_ascii_lowercase(), 'a' | 'e' | 'i' | 'o' | 'u' | 'y')
}

/// Append a syllable, dropping its leading vowels where they would double
/// a letter ("Aee…") or make three vowels in a row ("Uleia…").
fn join(name: &mut String, part: &str) {
    let mut part = part;
    while let (Some(last), Some(first)) = (name.chars().last(), part.chars().next()) {
        let trailing = name.chars().rev().take_while(|c| is_vowel(*c)).count();
        let doubled = last.eq_ignore_ascii_case(&first);
        if is_vowel(first)
            && (doubled
                || trailing + 1 >= 3
                || (trailing >= 1 && is_vowel(last) && part.chars().nth(1).is_some_and(is_vowel)))
        {
            part = &part[first.len_utf8()..];
        } else {
            break;
        }
    }
    name.push_str(part);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn styles_and_generation() {
        let ids: Vec<_> = styles().iter().map(|s| s.id).collect();
        assert_eq!(ids.last(), Some(&"fantasy"));
        for id in &ids {
            let names = generate(id, Gender::Any, 12, 42);
            assert_eq!(names.len(), 12, "{id}");
            let unique: std::collections::HashSet<_> = names.iter().collect();
            assert_eq!(unique.len(), 12, "{id} has duplicates");
            assert!(names
                .iter()
                .all(|n| n.split(' ').count() == 2 && !n.starts_with(' ')));
        }
        // Same seed, same list; a different seed gives a different one.
        assert_eq!(
            generate("nordic", Gender::Any, 8, 7),
            generate("nordic", Gender::Any, 8, 7)
        );
        assert_ne!(
            generate("nordic", Gender::Any, 8, 7),
            generate("nordic", Gender::Any, 8, 8)
        );
        // Gender picks from the right list.
        let s = &STYLES[0];
        for n in generate("english", Gender::Feminine, 10, 3) {
            assert!(s.feminine.contains(&n.split(' ').next().unwrap()));
        }
        for n in generate("english", Gender::Masculine, 10, 3) {
            assert!(s.masculine.contains(&n.split(' ').next().unwrap()));
        }
        // Fantasy names never stack three vowels or double one at a join.
        for g in [Gender::Feminine, Gender::Masculine] {
            for n in generate("fantasy", g, 60, 12345) {
                let given: Vec<char> = n
                    .split(' ')
                    .next()
                    .unwrap()
                    .to_lowercase()
                    .chars()
                    .collect();
                assert!(
                    !given.windows(3).any(|w| w.iter().all(|c| is_vowel(*c))),
                    "{n}"
                );
            }
        }
        let mut s = String::from("Ae");
        join(&mut s, "ewyn");
        assert_eq!(s, "Aewyn");
        // Unknown style falls back to English.
        assert_eq!(
            generate("klingon", Gender::Any, 3, 1),
            generate("english", Gender::Any, 3, 1)
        );
    }
}
