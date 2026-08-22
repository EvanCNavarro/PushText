# 07 — Murmur author's blog post: both prompts verbatim + build narrative

Companion write-up to the video (see `03-murmur-repo.md` §4) by the repo's author, Pat Simmons.

- **URL requested:** `https://aiformortals.co/blog/clone-wispr-flow-with-claude-code`
- **Resolved to:** `https://www.aiformortals.co/blog/clone-wispr-flow-with-claude-code` (301 → www)
- **Fetched:** 2026-08-22, HTTP 200, 70,774 bytes of HTML
- **Title:** "How I Cloned Wispr Flow With Claude Code"
- **Byline / read time:** "AI for Mortals · 6 min"
- **Method:** raw `curl` + local HTML parse. **No summarizer was used** — the prompts below are
  extracted from the page's four `<pre>` elements and reproduced byte-for-byte. (The page contains
  each prompt twice — once server-rendered, once in a modal — so 4 blocks resolve to **2 unique
  prompts**, confirmed identical to each other.)

---

## 1. Both prompts, verbatim

### Prompt 1 — the architecture / spec prompt

Labelled on the page as **"Initial prompt"**. This is the one that exists **only** in the blog; it
is not in the repo.

```
I want to clone Whispr flow look up what this is I basically want it to be a push to talk dictation app

What would you recommend for architecture based on my machine. We'll start with the skeleton then build this out into a proper MacOS application and add some cool branding
```

That is the **entire** prompt — 276 characters, two sentences, one typo ("Whispr"), no punctuation
discipline, no architecture, no constraints. The whole macOS skeleton came out of this.

His framing of it, verbatim from the prose:

> I did not tell it how to build anything. I told it what I wanted, asked it to go look the product
> up, and asked what it would recommend for my machine.

> Start this way. Say what you want, let the model do the research and propose the shape, get to
> something that runs, then layer the real application on top once the skeleton works.

### Prompt 2 — the interface / design prompt

Labelled **"The interface prompt (full)"**. 3,591 characters. This is the same text as the repo's
`prompt-design.txt` (see §5).

```
Now turn this into a proper macOS application.

Not a menu bar utility. A real app: dock icon, app menu, a standard resizable window, a Settings window on Cmd+comma, and a double-clickable .app I can keep in Applications. Drop LSUIElement.

Keep a menu bar item as well, for status and the hotkey while I'm working in another app - but it is secondary now, not the whole interface.

The main window holds:
- Past transcriptions, searchable, with copy on each one.
- The live level meter while recording.
- Start and stop.
- A Dictionary.

Settings holds the hotkey and the model.

THE DICTIONARY

A place I can teach it words it keeps getting wrong - names, jargon, product names, the people I work with. Add, edit, delete, and search. It should persist and be editable as a plain file as well as in the UI.

Two entry types:

1. A word or phrase I want it to know. "Anthropic", "Vercel", "Supabase".
2. A correction pair - when you hear X, write Y. "cloud code" becomes "Claude Code".

Implement both mechanisms, because one alone is not enough:

First, bias the engine before it transcribes. Pass my dictionary words to the speech engine as context so it leans toward producing them - whatever the engine supports for this. Keep the list short when you pass it; long context makes these models drift and invent text on quiet audio.

Second, run a correction pass on the text afterward. Whole-word, case-insensitive, longest match first. This is the guaranteed path - biasing is a nudge, not a promise, and it will not catch everything.

The correction pass must handle words the model glues together. If I add "Claude Code" it has to catch "CloudCode" and "Cloud-Code", not just the spaced version. Match on optional whitespace or hyphen between the parts.

Be careful not to corrupt real words. A correction for "Claude Code" must never touch "Cloudflare" or the ordinary word "cloud". Require the full pattern, and show me a warning in the UI if an entry I add looks like it would match something common.

In the transcription history, show me when a correction fired and what it changed, so I can tell whether the dictionary is doing anything.

Before you write any of it, define a design system and write it down as tokens I can point at later - color, type scale, spacing, corner radius, border, shadow, motion. Every view pulls from those tokens. No one-off values in the components.

The direction is 1980s tape recorder. Portable field recorders and cassette decks - Sony TC-D5, Marantz PMD, Nakamichi, Braun. What that means concretely:

Brushed aluminum and matte plastic surfaces. A muted palette - warm greys, off-black, cream, silver. One accent only: the red of a record light. Amber or green for level indicators.

Physical controls. Buttons that look pressed rather than tinted. Real depth, hard edges, visible seams between panels.

Silkscreen-style labels. Small, uppercase, tightly tracked, in a neutral grotesque. Segmented or monospaced numerals for counters and timings.

The recording indicator is a VU meter with a needle, not a progress bar. Level and waveform read as analog instrumentation.

Restraint over decoration. This should look like equipment, not like a theme.

Do not use neon, vaporwave, synthwave, purple-and-pink gradients, glowing text, chrome lettering, or grid horizons. That whole aesthetic is overused and it is not what I am asking for. This is the sober, industrial side of the eighties.

Show me the design tokens first and let me approve them before you build the views.

The engine stays exactly as it is. This is the interface layer only.
```

---

## 2. Build / process narrative worth stealing

### The sequencing, in his words

Two prompts, in this order, with a deliberate gap between them:

1. **Skeleton first, from a vague prompt.** Don't specify architecture — make the model research the
   product and propose the shape. Get something that *runs*.
2. **Then layer the real application on top**, with the engine frozen: *"The engine stays exactly as
   it is. This is the interface layer only."*

### The single most transferable trick — he did not write prompt 2 himself

> I did not write this prompt cold. **I opened a separate Claude session that already knew the project
> and asked it what prompt I should give.** Then I added the design direction myself, because I did
> not want another purple gradient voice app.

So prompt 2 is **model-authored spec + human-authored taste**. That explains the tonal split inside it:
the dictionary section reads like engineering spec (it already knows about biasing drift, glued words,
`Cloudflare` false positives) because a model that had read the codebase wrote it; the 1980s-tape-deck
section reads like a person, because it is.

### His own two reusable lessons, verbatim

> Two things in that prompt are worth reusing. **Asking for design tokens before any views get written**
> keeps the app visually consistent instead of drifting per screen. And **naming what you do not want is
> as useful as naming what you do.** I banned neon, vaporwave, synthwave and purple-and-pink gradients
> explicitly, because that is where these models go by default.

### What Claude did vs. what he did

| Claude Code | Him |
|---|---|
| Researched Wispr Flow; proposed the six-part architecture | Wrote the two prompts (2nd with a model's help) |
| Chose `SpeechTranscriber` (macOS 26) as default | Supplied the design direction and the ban-list |
| Flagged Parakeet V3 as more accurate, wired it as an alternative | Clicked through the permission dialogs |
| Built the comparison window | Pasted failure logs back in |
| **Raised the Wispr-DB latency caveat unprompted** | Ran the head-to-head |

### The six-part architecture Claude returned (his summary, verbatim list)

> - **Shell** — the app itself, and the little heads-up display with the waveform that pops up while you are talking.
> - **Hotkey** — a CGEvent tap watching for the key you hold. I used fn.
> - **Audio** — the microphone capture.
> - **Speech to text** — the model that turns your voice into words.
> - **Cleanup** — an optional small local model that adds punctuation and cuts the ums.
> - **Injection** — putting the finished text where your cursor is.

Note the rationale he gives for the engine choice — it is a **licensing/cost** argument, not a quality one:

> That choice is the reason this is free. It is on your machine already, so there is no API to call,
> nothing to pay for, and no model to download.

### What went wrong mid-build

Exactly two things, and he frames both as expected rather than exceptional:

1. **Permissions.** Accessibility must be granted by hand. Plus a collision warning:
   > If you already run another dictation app, give this one its own name and its own push-to-talk key
   > so the two do not collide.
   (This is the origin of the "Murmur YouTube" name and the separate bundle ID.)

2. **The silent AX injection failure** — the bug that produced the best code in the repo:
   > Transcription succeeds, the logs say injection succeeded, and nothing lands in your editor. That
   > is an accessibility API silent failure: **Electron apps like Cursor return success and do nothing.
   > Paste the log into Claude and it patches it.**

   The debugging loop is one step: paste the log, get a patch. No bisect, no hypothesis.

---

## 3. In prose but NOT said on camera

Cross-checked against the transcript findings in `03-murmur-repo.md` §4.

**New facts / figures:**
- **"Wispr Flow just raised $280 million at a $2 billion valuation."** Opens the post twice (dek + first
  line). *(His claim, restated here as his. Not independently verified — UNVERIFIED as a fact about Wispr.)*
- **"$15 a month"** — Wispr Flow's price, in the closing paragraph. Not in the on-camera extraction.
- **"about 20 minutes"** — appears in prose as well as on camera; consistent.
- **"6 min"** stated read time; **"complete beginner"** stated audience: *"You do not need to know Swift,
  and you do not need to understand the architecture."*

**A hotkey discrepancy worth noting:** the blog says **"I used fn."** The repo's default is
**Right ⌥** (`PushToTalkKey.rightOption`, `Settings.swift:67`), with `fn` as one of three options. Not a
contradiction — it's configurable — but if we're reproducing his setup, `fn` is what he actually ran.

**A claim that outruns the repo:** *"There is a Windows build under windows/ in C# and Avalonia"* —
but the repo's own `AGENTS.md:18` marks Avalonia as **"(not written yet)"** and `AGENTS.md:21` says the
Windows side is *"a dictionary engine plus a detailed specification — no audio, hotkey, injection or UI
yet. **Do not describe it as working.**"* **The blog describes it as working.** Treat the blog's Windows
claim as **wrong**; the repo's AGENTS.md is the accurate source.

**Caveats stated in prose (all consistent with camera, sharper wording):**
- The Wispr number is inflated, **and Claude flagged it first**:
  > One caveat, and **Claude raised it before I did**: reading Wispr Flow's timing out of its database
  > adds latency that is not really the app's fault, so its number is inflated.
- > Even generously, the gap is small. On accuracy it was closer still.
- > The honest read is that the difference in speed and accuracy is **marginal**. I went with Apple's
  > engine anyway, because it needs no download and works out of the box.
- On the UI: > **Plain.** It got the 1980s recorder feel in outline, and it is **a long way from the
  > reference photos I gave it.** Claude could have done a better job here… The engine underneath is
  > what I actually cared about, and that part is genuinely good.

**No new numbers.** The benchmark table is identical to camera — Parakeet **0.27 s**, Apple
**0.48 s**, Wispr Flow **0.91 s**. Still **no WER, no RTF, no ms figures, no sample size** anywhere in
prose. The README's `~80 ms` / `~110× realtime` / `~66 MB` appear **nowhere** in the blog either —
they remain **UNVERIFIED**.

---

## 4. License / reuse position

**There is no license statement, and no explicit grant.** The repo has no LICENSE file and the blog
adds none. The closest thing to a reuse position is the closing section, verbatim:

> **The repo**
>
> The whole thing is on GitHub: per-simmons/murmur-youtube. macOS is native Swift. There is a Windows
> build under windows/ in C# and Avalonia, using Parakeet, since Apple's engine is macOS only.
> **Hand the repo to Claude Code or Codex and say "set this up on my machine".**

And the sign-off:

> Wispr Flow is still a good product and $15 a month is not much if you want something that works the
> second you install it. **This is for when you would rather own it.**

Read carefully: he invites you to **run** it on your own machine. He never says "take it", "fork it",
"use it in your own project", "MIT", or "public domain". The page also carries a **"Copy for your
agent"** control and per-prompt **"Copy"** buttons — an affirmative invitation to reuse **the prompts**,
which is the strongest reuse signal on the page, and it is about the prompts, not the code.

**Bottom line, unchanged from `03-murmur-repo.md`:** publishing plus "set this up on my machine" is
**not a license**. Default copyright still applies to the code. Our position should stay: **re-implement
from the ideas; do not lift files.** The prompts are a different matter — they are published with copy
buttons and quoted in full here.

---

## 5. `prompt-design.txt` drift check — NONE

Compared `murmur-youtube/prompt-design.txt` against the blog's second `<pre>` block:

```
blog paras: 25   repo paras: 25
IDENTICAL after unwrap+collapse: True
raw char count — blog: 3591   repo: 3591
whitespace-stripped equality: True
```

**Zero drift.** The only difference is presentation: the repo file is hard-wrapped at ~79 columns, the
blog runs each paragraph as one line. Character counts match exactly because a hard wrap swaps a space
for a newline. So `prompt-design.txt` **is** the interface prompt as published, verbatim.

*What this check could not see:* it compares only prompt 2. Prompt 1 has no repo counterpart to drift
against — the blog is its sole source.

---

## 6. Other posts / follow-ups — none on this project

Enumerated `https://www.aiformortals.co/blog`: **21 post slugs**. `clone-wispr-flow-with-claude-code` is
the **only** one about this project. The other 20 are AI-industry news and model comparisons
(Opus 5, Fable 5, Kimi K3, GPT-5.6, Grok Imagine, Seedance, etc.).

One title looked like a possible follow-up — `kimi-k3-fable-5-gpt-56-build-the-same-app` — so I fetched
it: it is **"Kimi K3 vs Fable 5 vs GPT-5.6"**, three one-shot builds of a 3D ocean scene, a scrolling
site and a physics game. Grepped for `murmur` / `dictation` / `wispr` / `push-to-talk`: **zero hits.**
Unrelated.

*Caveat:* `sitemap.xml` returned nothing, so the 21 slugs come from links on the blog index page. An
unlinked or paginated post would not have been seen. No follow-up is **listed**; that is not proof none
exists.

---

## 7. Net-new takeaways for our build

1. **Steal the two-prompt sequencing**: vague research-and-propose prompt → running skeleton → detailed
   spec prompt with the engine explicitly frozen.
2. **Steal the meta-move**: have a session that already knows the codebase draft the next spec prompt,
   then add taste by hand. That is why his second prompt contains engineering constraints a human
   wouldn't have known to write yet.
3. **Steal "design tokens before views"** and **the explicit ban-list**. His own diagnosis is right —
   and note the irony recorded in `03-murmur-repo.md` §3: the shipped HUD still uses a **blue→purple
   gradient**, the exact thing this prompt banned. *Banning it in the prompt was not sufficient.* Enforce
   it with a lint or a token-only rule, not a sentence.
4. **His prompt already encodes the dictionary design we validated in the code** — biasing + guaranteed
   post-pass, short bias list, glued-word matching, `Cloudflare` protection, warn-don't-block, and
   show-what-fired in history. That prompt is a good starting spec for our own dictionary.
5. **Don't repeat his Windows overclaim.** Say what runs.
