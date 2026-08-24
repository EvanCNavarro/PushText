# Task 73 - Letting grounding accept an inflection without letting it accept a guess

Measured 2026-08-23 on macOS 26.6.2, driving the real on-device model.

---

## 1. The defect

Grounding compares surface tokens, so it could not tell a grammatical correction from an invention.
From `task68-cleanup-shadow-mode.md`, after the numeral fix 4 of 60 runs still rejected, and one was
not drift:

```
raw:      "The tests with us is locally, but fails in continuous integration."
verdict:  ungroundedContent(token: "fail")
```

The model changed `fails` to `fail` for subject-verb agreement against a plural subject. The word IS
present; only its ending changed.

## 2. A relation, not a stem key - and the first version was wrong

The obvious implementation is a canonical stem: reduce every token and compare keys. **That version
shipped into the working tree and was wrong**, and it took the real model to show it:

```
raw:      "The build is faming on the winter again."
rejected: ungroundedContent(token: "building")
```

`building` should have matched `build`. It did not, because a one-pass suffix strip is not consistent
across a word's own forms: `building` minus `-ing` is `build`, while `build` minus `-d` is `buil`. The
two forms of one word landed on different keys. Reading the code predicted a match; running it
produced a rejection.

Replaced with a **relation** - one token is the other plus a single inflectional ending:

```swift
static func isInflectionPair(_ lhs: String, _ rhs: String) -> Bool {
    guard lhs != rhs else { return true }
    let (base, longer) = lhs.count < rhs.count ? (lhs, rhs) : (rhs, lhs)
    guard base.count >= 4 else { return false }
    return ["s", "es", "ed", "d", "ing"].contains { longer == base + $0 }
}
```

A relation cannot have that defect: it compares the two tokens actually present and never invents an
intermediate form. It also makes nonsense stems free - `agreed` minus `-ed` is `agre`, which is not a
word and so never appears in a transcript to be matched against.

The exact match is still tried first; the relation only runs on the miss path, so nothing that was
grounded before stops being grounded. The matched raw token is still **consumed**, so one raw word
cannot ground two cleaned words.

## 3. Why the base floor is 4, measured rather than chosen

Over `/usr/share/dict/words` (221,702 entries), lowering the floor from 4 to 1 merges **833 further
pairs**, and they are not all inflections:

```
an / and      ai / aid      ad / as      ami / amid
```

Those are distinct words. A false MERGE lets invention past the guard, which is the failure the guard
exists to prevent.

The floor also refuses genuine pairs - `act`/`acting`, `aim`/`aiming`, `air`/`airing` - and that is
the accepted trade. A refusal costs the user the raw transcript, which is already punctuated and
capitalised. A false merge costs them text they never said.

Sampled 40 of the 7,356 dictionary pairs the relation admits at floor 4: **39 are ordinary
inflections** (`lean`/`leaning`, `distress`/`distressed`, `potato`/`potatoes`, `troll`/`trolling`).
The one questionable pair was `cuphea`/`cuphead`.

## 4. The real path, both directions

Driven through `CleanupProbe` against the real `SystemLanguageModel`.

**The near-miss is now accepted - 3 of 3 runs:**

```
raw     = "The tests with us is locally, but fails in continuous integration."
cleaned = "The tests with us are locally, but fail in continuous integration."
changed = true   rejection = none
```

**A guess is still refused - 11 runs of the guess-prone sentence, 5 of which actually guessed, all 5
refused:**

```
ungroundedContent(token: "failing")     x3
ungroundedContent(token: "freezing")
ungroundedContent(token: "famishing")
```

`famishing` is the interesting one: it is close to `faming` and is still refused, because it is not
`faming` plus an ending.

**What these runs do NOT show.** The other 6 runs returned the text unchanged, so the guard was never
exercised in them - `rejection=none` there means the model did not guess, not that the guard passed a
guess. The refusal claim rests on the 5 runs that produced one, plus the unit test that replays the
exact output recorded in `task68`.

## 5. Battle-tested

Three plants, each confirmed detected and then reverted:

| planted regression | caught by |
| --- | --- |
| base floor 4 -> 1 | `an`/`and`, `ai`/`aid`, `act`/`acts` all become inflections |
| stop consuming the matched raw token | `"the request"` grounds `"requests requests"` |
| match on a shared 2-character prefix | `faming`/`failing` and `loss`/`lose` become inflections |

The first plant is the one worth noting. An earlier version of the floor test asserted a VERDICT on
`loss` -> `lose`, passed, and was named for the floor - but it passed because those two words are not
related by any suffix in the list, not because of the floor. Lowering the floor to 1 left it green.
The plant is what exposed that the test's name and its reason had come apart.
