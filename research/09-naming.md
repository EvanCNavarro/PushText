# 09 — Naming: candidate generation and availability verification

**Date:** 2026-08-22
**Product:** local-first, offline push-to-talk dictation utility for macOS. Hold a key, speak, cleaned
text lands in the frontmost app. Apple SpeechAnalyzer + Apple Foundation Models, all on-device.
Menu-bar app, GitHub + Sparkle, solo dev (github.com/EvanCNavarro).
**Sibling for style:** `TermTile` — short, concrete, compound, no cutesy misspellings.
**Killed working name:** `Mumbler` — 2 Mac App Store apps, OccamBox asserting `Mumbler®`,
`github.com/Mumbler` taken, and `Mumble Dictation` (heymumble.com) being the identical product.

---

## 0. Method, and the detectors I battle-tested first

Every check below was run. Nothing here is asserted from intuition. Per Tenet 1, each detector was
made to go **red on purpose** before its green was trusted.

| Detector | Battle-test | Result | Verdict |
|---|---|---|---|
| `curl github.com/<name>` | `zzqqxxnotarealuser99` vs `EvanCNavarro` | `404` vs `200` | **Trustworthy** |
| Homebrew cask API | `notarealcask99xyz` vs `rectangle` vs `aside` | `404` vs `200` vs `200` | **Trustworthy** |
| iTunes Search API (`entity=macSoftware`) | `zzqqxxnotarealapp99` → `resultCount=0`; `Xcode` → 3; `Bear` → 3 | discriminates | **Trustworthy but FUZZY** (see below) |
| My `\b<name>\b` regex over App Store names | `bear` → `FILTER FIRED: Bear: Markdown Notes` | fires | **Trustworthy** |
| Verisign RDAP (`.com`) | `google.com`=200 (created 1997-09-15), `zzqqxxnotreal9988.com`=404 | correct | **Trustworthy** |
| `rdap.org` proxy | `blurt.app` → **000** though blurt.app serves a live site | **FALSE NEGATIVE** | **REJECTED — discarded all its results** |
| `www.registry.google/rdap` for `.app` | `blurt.app` → **404**, `quietpad.app` → **404**, both demonstrably live | **FALSE NEGATIVE** | **REJECTED — wrong endpoint** |
| IANA-bootstrap RDAP for `.app` (`https://pubapi.registry.google/rdap/`) | `blurt.app`=200, `quietpad.app`=200, `zzqqxxnotreal9988.app`=404 | correct | **Trustworthy** |

Two of the three `.app` registry endpoints I tried returned 404 for domains that are demonstrably
registered and serving live sites. **Had I trusted either, I would have reported `latch.app` as
available when it has been registered since 2019-07-30.** The IANA bootstrap file
(`https://data.iana.org/rdap/dns.json`) gave the correct authority.

**A second self-caught error:** my first domain-title sweep reused a stale `/tmp/_p.html` when `curl`
failed, so `tacit.com`, `deft.app`, `hushpad.com` and `drawl.app` were each labelled with the
*previous* domain's `<title>`. Caught because "DOOR Smarter Access" appeared twice. Re-run clean.

**A control I planted:** `terspad` — a nonsense string I never intended to use — returned
`gh=404 .app=404 .com=404 brew=404 MAS=[] GH=[]`, i.e. a perfect clean sweep. **This means "all
channels clear" is the expected result for any invented compound and is NOT by itself a
distinguishing signal.** For compounds the real risk lives in the *root word*, not the compound. I
weighted accordingly.

---

## 1. Candidates generated (36 tested, brief asked for 10–14)

Constraints applied: 1–2 syllables, ≤~9 chars, pronounceable, spellable on first hearing, no
misspelled-word branding, and **no** `whisper / voice / dictate / flow / speak / talk / echo /
scribe` roots.

Ordinary English words used obliquely (≥3 required): `Latch`, `Tacit`, `Aside`, `Blurt`, `Patter`,
`Drawl`, `Deft`, `Terse`, `Offhand`, `Jot`, `Nib`, `Spiel`, `Aloud`, `Idiom`, `Argot`, `Parlance`.

---

## 2. KILLED — with the evidence that killed each

### 2.1 Fatal — collision in the exact product category

#### `Jot` — IDENTICAL PRODUCT. The Mumbler failure, repeated.
`https://jot-transcribe.com/`, fetched:
> Tagline: **"Speak, and it's wrıtten."**
> Mac (Apple Silicon, macOS 15+): **Direct download or Homebrew**. iPhone: App Store.
> "Your voice is turned into text right on your Mac — instantly, and completely private."
> Default hotkey ⌥space, which can toggle or **"hold for push-to-talk."**
> "Press your hotkey from any app" · "Text appears pasted at your cursor" · "Works in every app"
> with a global hotkey · **"Rewrite by voice" using on-device AI** · "No cloud. No account. No telemetry."

Also `Jot Transcribe` on the App Store (`apps.apple.com/us/app/jot-transcribe/id6766447330`). This is
the same app, on the same platform, with the same on-device LLM cleanup, distributed through the same
Homebrew channel. Absolutely dead.

#### `Sotto` — two direct dictation repos, and the same etymology I was reaching for
GitHub repo search, real star counts:
```
  25 stars  mkbula/sotto  :: Local speech-to-text transcription app for Linux using Whisper models.
  18 stars  YFrtn/sotto   :: Voice dictation, sotto voce — on-device speech-to-text for macOS (RU/EN, MLX, Qwen3 ASR)
```
`YFrtn/sotto` is on-device macOS voice dictation and reaches for *sotto voce* for the same reason I
did. Dead.

#### `Patter` — two live speech products
- `github.com/PatterAI/Patter` — "Open-source voice-AI SDK… unified API for the entire voice AI
  pipeline — speech-to-text, AI reasoning, text-to-speech, and telephony." Site: `getpatter.com`.
- `PatterAI: Communication Skills` on the App Store (`id6745208857`) — AI speech coach giving
  "detailed speech feedback… detecting vocal clarity."

Both squarely in speech. Dead.

#### `Larynx` — 829-star TTS engine in the local/offline voice space
```
 829 stars  rhasspy/larynx  :: End to end text to speech system using gruut and onnx
  13 stars  junioteixeira/Larynx :: Software para reconhecimento de fala para texto
  12 stars  rhasspy/larynx_old   :: Text to speech system based on MozillaTTS and gruut
```
Rhasspy is *the* offline-voice-assistant project. Dead.

#### `Aloud` — speech category, saturated
Mac App Store: `Aloud: Voice Journal & Diary`, `Read Aloud - Text to speech`,
`Narrly: Read Aloud PDF & Text`, `Cadence: Read Aloud`. GitHub `ken107/read-aloud` = **1730 stars**.
`aloud.app` is parked on afternic. Dead.

### 2.2 Fatal — collision in macOS / developer tooling

#### `Aside` — a shipping Mac app on the same distribution channel
```json
{ "token": "aside", "name": ["Aside"], "desc": "Web browser with built-in AI assistant",
  "homepage": "https://aside.com/",
  "url": "https://releases.aside.com/dev-updater/Aside-1.0.813.1.dmg" }
```
A live AI Mac app shipping via Homebrew cask — the exact channel this app will use. Also
`google/aside` (436 stars, Apps Script tooling). Dead.

#### `Nib` — `.nib` is a core macOS/Cocoa filetype
Interface Builder files are literally `.nib`. Naming a macOS app "Nib" is unsearchable for its own
audience. Plus `stylus/nib` (1884 stars) and `akosma/nib2objc` (1131 stars). Dead.

#### `Parlance` — a macOS developer-tools family already owns the name
Mac App Store: `Parlance Browser`, `Parlance for Xcode`, `Parlance: Accessibility Audit`. Plus
`parlance/ctcdecode` (858 stars — and it is a **CTC decoder for speech recognition**, so it is a
speech collision too). Dead twice over.

#### `Parley` — 705-star Rust text-layout library
`linebender/parley` (705 stars) — "Rich text layout library", a load-bearing dependency across the
Rust GUI ecosystem. A Mac text utility named Parley collides in developer mindshare. Dead.

#### `Tacit` — 1883-star CSS framework, plus backwards semantics
`yegor256/tacit` (1883 stars) — "CSS framework for dummies". Also `tacit.com` is a live company
(Akamai-hosted) and `tacit.app` is registered (2020-09-19, DomainCostClub) and parked. Separately:
*tacit* means **unspoken**, which is the wrong meaning for a dictation app. Dead.

#### `Terse` — `Terse Editor` already ships on the Mac App Store
```
   Terse Editor  [Nadzeya Yashchuk] (Productivity)
```
A macOS Productivity text editor named Terse. Too close. Dead.

#### `HushKey` — live Mac App Store app
`apps.apple.com/mt/app/hushkey/id6446700796` — "decentralized password and identity manager…
requires macOS 11.0 or later and a Mac with Apple M1 chip or later." Same platform, same name. Also
`github.com/hushkey-app` exists. Dead.

#### `HoldKey` — keyboard-input utility, the adjacent category
`holdkey.eu` — "Extended keyboard software, No more Alt Codes" (Windows). Also
`cryz-dev/holdkey` — "macOS menu bar utility for horizontal mouse locking while editing keyframes".
A push-to-talk *key* utility colliding with an existing *keyboard-input* utility is the wrong kind of
confusion. `holdkey.com` is parked on afternic. Dead.

#### `Lilt` — `lilt.com` is a major AI translation/localization company
Language-technology adjacency, well-funded brand. `lilt.app` parked on afternic. Dead.

#### `Spiel` — taken on every channel
`github.com/spiel` = 200; `spiel.com` live on AWS; `spiel.app` on Google Cloud DNS. Dead.

#### `Argot` — audio-space collision + unspellable on first hearing
`mourednik/argotlunar` (194 stars) — "Surreal transformations of **audio streams**". And a listener
hearing "ar-go" will not type `argot`. Dead.

#### `Idiom` — language-learning adjacency, weak fit
No speech collision, but Mac App Store surfaces language-learning apps and `idiomatic.js` is
25730 stars. Weak name for a dictation tool regardless. Dropped.

### 2.3 Killed on brand-confusion / homophone grounds

#### `Drawl` — the `.com` is a **drawing** product
```
drawl.com -> HTTP 200  <title>Drawl - For the Love of Drawing</title>
```
"Drawl" spoken aloud is heard as "draw" + a trailing L; the person who hears it types `draw`. A
drawing product already owning `drawl.com` makes that failure mode concrete. Dead on spellability.

#### `QuietPad` — a writing app already owns `quietpad.app`
```
quietpad.app -> HTTP 200  <title>Quietpad — A quiet place to write</title>
```
Live writing product. Dead.

#### `Blurt` (bare) — no dictation collision, but the root is crowded
- `blurt.app` → `<title>Blurt | Write better & more.</title>` — a **distraction-free writing tool**
  with Crunchbase, BetaList and Product Hunt presence. Uncomfortably adjacent (it also produces prose).
- `blurt.com` → 114-byte afternic parking stub (registered, for sale, no product).
- App Store: `Blurt: Blurting Study Method` (id6745759423) — and users "**speak** or type everything
  they remember"; `Blurt - Blurt It Out!` (id467439839); `Blurtr: Study & Blurt` (id6747290884).
- A Steem-fork blockchain/social network: `blurtkey.com` → `<title>BlurtKey - Native Mobile Wallet for Blurt</title>`.
- `github.com/blurt` = 200 (individual, 6 repos).

No collision in dictation, but the bare word is not ownable. **Killed as a standalone; the root
survives only inside a compound.** This also kills `BlurtKey` outright (the Blurt blockchain wallet
already uses that exact string).

#### `Latch` (bare) — trademark + domain story both bad
- `latch.com` → 301 → `door.com/?from=latch`, "DOOR Smarter Access and Building Intelligence" —
  formerly Latch Inc.
- **`latch.app` is REGISTERED (created 2019-07-30T19:45:17Z)** despite having *no* A and *no* NS
  records. My DNS check said NXDOMAIN; RDAP said registered. This is exactly the
  registered-but-undelegated case, and it is why DNS alone is not proof.
- Trademark (**not legal advice**): `LATCH`, LATCH SYSTEMS, INC., Reg. No. 4961853, Ser. No.
  86837452 — covers locks/keys **and** "design and development of computer hardware and software".
  A second `LATCH` application, Ser. No. 97225082 (filed 2022-01-18), covers SaaS consulting.
- `latchbio/latch` = 173 stars; `imbue-ai/latchkey` = 122 stars; `github.com/latch` is a taken Org.

No speech collision, but a live mark reaching into software plus a lost `.app` plus a well-known
smart-lock brand. Dead.

#### `LowKey` / `Offhand` / `HushBar` / `HushNote` / `QuietKey` / `HushTap` — domains or App Store gone
- `LowKey`: `Low Key` on the Mac App Store; `lowkey.app` and `lowkey.com` both registered (RDAP 200).
- `Offhand`: `offhand.app` and `offhand.com` both registered (RDAP 200); `github.com/offhand` taken.
- `HushBar`: `hushbar.app` and `hushbar.com` both registered (RDAP 200).
- `HushNote`: **`HushNote` is on the Mac App Store**; `hushnote.com` registered; two GitHub repos (27★, 24★).
- `QuietKey`: `quietkey.app` and `quietkey.com` both registered (RDAP 200); Mac App Store returns
  the keyboard-sound cluster (`Klack`, `KeyBell`, `MuteKey`) — adjacent category.
- `HushTap`: `hushtap.com` registered; `4xeoz/hushtap` exists; weak name.

#### `Deft` (bare) — clean on category, but both domains gone
`deft.com` live (141.193.213.10/11); `deft.app` registered and delegated to porkbun;
`github.com/deft` taken. No dictation or speech collision found. Survives on category, loses on
namespace. Compound `DeftBar` / `DeftPad` are clean (below).

---

## 3. SURVIVORS — full evidence table

Legend: GH = `curl -s -o /dev/null -w "%{http_code}" -L https://github.com/<name>` ·
`.app` via IANA-bootstrap RDAP `https://pubapi.registry.google/rdap/domain/<n>.app` ·
`.com` via `https://rdap.verisign.com/com/v1/domain/<n>.com` · brew via
`https://formulae.brew.sh/api/cask/<n>.json` · MAS via
`https://itunes.apple.com/search?term=<n>&entity=macSoftware&country=us`.
**404 = unregistered/absent = good.**

| Name | GH handle | `.app` | `.com` | brew | Mac App Store exact hit | Top GitHub repo (real stars) |
|---|---|---|---|---|---|---|
| **HushPad** | 200 (empty user, 0 repos) | **404 free** | 200 — registered 2011-03-29, parked at atomregistrar | 404 | none | `Afnankazi/Hushpad` — **1 star** |
| **BlurtBar** | **404 free** | **404 free** | **404 free** | 404 | none | **none — zero repos** |
| **BlurtPad** | **404 free** | **404 free** | **404 free** (`whois`: `No match for domain "BLURTPAD.COM"`) | 404 | none | **none — zero repos** |
| **DeftBar** | **404 free** | **404 free** | **404 free** | 404 | none | **none** |
| **DeftPad** | **404 free** | **404 free** | **404 free** | 404 | none | **none** |
| **TacitPad** | **404 free** | **404 free** | **404 free** | 404 | none | **none — zero repos** |
| **TacitBar** | **404 free** | **404 free** | **404 free** | 404 | none | **none** |
| **BlurtDock** | **404 free** | **404 free** | **404 free** | 404 | none | **none** |
| *(control)* `terspad` | 404 | 404 | 404 | 404 | none | none |

The App Store `resultCount` was non-zero for most queries, but the API is fuzzy — `Xcode` returns
`Apple Developer`/`TestFlight`, `deft` returns eight racing games (matching "drift"). I therefore
dumped every `trackName` rather than trusting `resultCount`, and read them by eye. The only exact-word
hits across all candidates were `Terse Editor`, `HushNote`, `Low Key`, `PromptLatch`/`LatchCast`/
`Loglatch`, and `Hushkey`.

### Trademark (NOT legal advice — see §5)
- **HUSHPAD**, Ser. No. 86808922 (Justia) — Blenditup Foods, filed Nov 2015, for *"a rubber molded
  support base to reduce noise for blenders."* Status **602 — Abandoned, Failure To Respond**, dated
  2016-09-28. Also non-software `Hush Pad` products (Technoflex anti-vibration pads, Vitamix blender
  pads). **No software mark found.**
- **BlurtBar / BlurtPad / DeftBar / TacitPad** — no marks surfaced. These are invented compounds; per
  the `terspad` control, absence here is expected and weak evidence.
- **LATCH** — Reg. 4961853 (LATCH SYSTEMS, INC.) reaching into software development services; a
  contributing reason `Latch` was killed.

---

## 4. THE THREE FINALISTS

### 1. `HushPad` — recommended
**Pitch:** *hush* (nothing leaves the Mac — the whole product thesis) + *pad* (where the text lands).
Two syllables, seven characters, zero spelling ambiguity on first hearing, and the only name here
whose meaning states the differentiator rather than the mechanic. Reads as a sibling of `TermTile`:
two concrete morphemes, no misspelling, no suffix cliché.

**Evidence:** `hushpad.app` unregistered (RDAP 404 on the battle-tested endpoint). No Mac App Store
app. No Homebrew cask. No speech, dictation, audio or dev-tools collision found. Only trademark is an
**abandoned 2016** mark for a blender noise pad. Highest-starred GitHub repo of that name:
`Afnankazi/Hushpad` at **1 star**.

**Single strongest remaining risk:** the `Hush` *prefix* is an active naming pattern on this exact
platform — `Hushkey` (Mac App Store, password manager) and `HushNote` (Mac App Store, notes) both
ship today, and `hushbar.com`/`hushtap.com` are already taken. `HushPad` itself is clear, but you are
joining a crowded prefix family and will not own the word "Hush". Secondary: `hushpad.com` has been
registered since 2011 and sits with a domain broker, so the `.com` is a purchase, not a registration.

### 2. `BlurtBar` — recommended
**Pitch:** the most literal description of the product act — you hold a key and *blurt*, and it lives
in the menu *bar*. Structurally the closest parallel to `TermTile`: a verb-ish concrete root plus the
macOS surface it inhabits, exactly as `TermTile` pairs the domain with the behaviour.

**Evidence:** the cleanest sweep of any candidate — `github.com/blurtbar` **404**, `blurtbar.app`
**404**, `blurtbar.com` **404**, Homebrew **404**, no Mac App Store hit, and **zero** GitHub repos
matching the name in any search mode.

**Single strongest remaining risk:** the `Blurt` root is genuinely crowded even though nothing in it
is dictation — `blurt.app` is a live distraction-free **writing tool** ("Write better & more.", with
Crunchbase/Product Hunt/BetaList presence), and a Blurt blockchain ecosystem ships a `BlurtKey`
wallet at `blurtkey.com`. None of these is your category, but "Blurt" is a noisy search term and the
writing-tool adjacency means a user who half-remembers your name may land on a competitor for
attention. You would own `BlurtBar`; you would never own `Blurt`.

### 3. `DeftBar` — recommended as the diverse third
**Pitch:** *deft* — quick, neat, skilled — describes what the Foundation Models cleanup pass actually
does to your speech, and does it without touching any of the saturated speech roots. Plus the menu
*bar*. One of only two finalist roots with no crowded family behind it.

**Evidence:** `github.com/deftbar` **404**, `deftbar.app` **404**, `deftbar.com` **404**, Homebrew
**404**, no Mac App Store hit, no GitHub repos. The bare word `Deft` returned **no speech,
dictation, transcription or audio product** in search — its only problem was that `deft.com` and
`deft.app` are taken by unrelated parties, which the compound sidesteps.

**Single strongest remaining risk:** it is the weakest *semantic* fit of the three — "deft" says
nothing about speech, text, or privacy, so the name carries no explanation and must be taught
entirely by the product page. Secondary: `deft` is phonetically near `draft` and `deaf`, and "deaf"
in a speech-input product's name space is an unfortunate near-miss to have to live with.

**Clean alternates, equally available, ranked lower on name quality:** `BlurtPad` (identical clean
sweep to `BlurtBar`, `.com` confirmed unregistered by `whois`; loses only because "-Pad" doesn't name
the menu-bar form factor), `TacitPad` and `TacitBar` (fully clean, but *tacit* means **unspoken**,
which is backwards for a dictation app), `DeftPad`, `BlurtDock`.

---

## 5. What this check could not see

Named honestly, because every one of these is a real hole:

1. **Trademark search here is a web search, not a trademark search, and is NOT legal advice.** I could
   not reach USPTO programmatically — `tmsearch.uspto.gov/api-v1-0-0/tmsearch` returned
   `<Error><Code>NoSuchKey</Code></Error>` HTTP 404 and the POST endpoint returned HTTP 405
   `MethodNotAllowed`. Everything in §3 is second-hand via Justia/Trademarkia surfaced through a
   search engine. **I did not search TESS or the live USPTO index. I did not search common-law
   (unregistered) marks at all, and common-law rights are what a small Mac app most often trips
   over.** I did not check EUIPO, UKIPO, or any non-US registry. A clean result here is not clearance.
2. **The Mac App Store API is fuzzy and I only read the top 8.** `Xcode` returns `Apple Developer`;
   `deft` returns racing games. A quiet, low-ranking, exact-name app could sit below the cut and I
   would not have seen it. I also only queried the **US** storefront (`country=us`) and only
   `entity=macSoftware` — an iOS-only or a non-US app with the same name is invisible to this check.
   Notably, the `Blurt` iOS apps only appeared via web search, **not** via my macSoftware query.
3. **An unregistered domain is not a reserved one, and the checks are point-in-time.** `hushpad.app`,
   `blurtbar.app` and `blurtbar.com` were free at the moment of the RDAP call on 2026-08-22. Nothing
   holds them. Conversely, DNS silence proved unreliable in the other direction: `latch.app` had no A
   and no NS record yet has been registered since 2019 — **so for every name here, "no DNS" would
   have been a false positive had I not gone to RDAP.** I used RDAP for `.app` and `.com` only;
   `.io`, `.dev`, `.sh` and the rest are unchecked.
4. **A quiet-but-live competitor may not rank.** `Mumble Dictation` was found last round only because
   someone searched for it directly. This category has a long tail of solo-dev menu-bar dictation apps
   shipping on Gumroad, Ko-fi, itch.io, Setapp and personal sites that no keyword search surfaces —
   I saw `Stenotype` and `whisper-dictation` on Gumroad purely incidentally. **A name being absent
   from my searches is evidence of low prominence, not of non-existence.**
5. **GitHub repo search matched on name only, and star count is a proxy for relevance, not for
   conflict.** A zero-star repo with the exact name and an active author is a real collision my
   ranking under-weights. I did not search GitLab, Codeberg, SourceForge, npm, PyPI, crates.io or
   Homebrew *formulae* (only casks).
6. **App-name confusion is a judgement call I made, not a measurement.** I killed `Drawl` on a
   predicted mishearing and `Aside` on category adjacency. Those are my opinions about how a user
   would behave; I ran no user test and have no data behind either.
7. **The `terspad` control means the clean sweeps prove less than they look like.** Any invented
   compound passes every automated check. For `BlurtBar`, `BlurtPad`, `DeftBar` and `TacitPad`, the
   automated greens are close to uninformative — the actual risk sits in the root word's crowding,
   which only the manual reading in §2 addresses.
8. **Social handles were not checked at all** — no X/Twitter, Bluesky, Mastodon, Reddit, Discord, or
   Product Hunt namespace. Nor was the App Store *seller* name namespace, which matters if this ever
   ships through the Mac App Store rather than GitHub + Sparkle.
9. **`whois` was largely unusable.** The `.app` TLD queries hung until the command hit its 2-minute
   timeout, returning nothing for six of seven domains. Only `blurtpad.com` produced a usable
   `No match for domain "BLURTPAD.COM"`. All other registration claims rest on RDAP alone.

---

# Batch 2 — plain register

**Date:** 2026-08-22 (same session)
**Why:** Bobby rejected batch 1's register. His own proposals — `VoCap`, `AudioCapture`, `VoiceText` —
read as plain, literal, utility-like, does-what-it-says. Not evocative, not coined, not oblique.
Batch 1's `Blurt`/`Hush`/`Deft` family is out.

**Pre-killed by the coordinator, not re-checked here:** `VoCap` (github.com/vocap 200; vocap.app +
vocap.com both RDAP 200; `VocaHQ/vocaphone` is on-device voice dictation) · `VoiceText`
(voicetext.app + voicetext.com registered; VoiceText is HOYA's shipping commercial TTS) ·
`AudioCapture` (an Android API class name — killed on collision, not availability).

**Target band:** more ownable than `AudioCapture` (an OS API identifier), less coined than `TermTile`.
Compounds of two ordinary words. Describing the ACTION (hold key, speak, text appears) or the BENEFIT
(instant, local, no network) — **not** "voice to text", which is the commodity stage Apple provides.

**Added hard kills for this batch:** any existing OS/SDK API identifier · anything used by a
dictation, transcription, TTS or voice-AI product · anything whose **root word** has a shipping
product in speech/audio.

## B2.0 — Method corrections and detector battle-tests

**Correction to batch 1, in my favour of the coordinator:** I reported that `rdap.org` was a broken
detector because `blurt.app` returned `000`. That diagnosis was **wrong**. Re-run with a longer
timeout:

```
### RE-BATTLE-TEST rdap.org WITH -L ###
  blurt.app                  HTTP 200
  quietpad.app               HTTP 200
  google.com                 HTTP 200
  zzqqxxnotreal9988.app      HTTP 404
  zzqqxxnotreal9988.com      HTTP 404
```

`rdap.org` is correct and is used throughout batch 2. The batch-1 `000` was **my `--max-time 15`
firing**, not a wrong endpoint. A timeout rendered as `000` and I read it as "not registered" —
the same failure mode as a green that was never made to go red. Batch 1's *conclusions* stand
(they were taken from the IANA-bootstrap endpoint, which I re-confirmed here at 200/200/404), but
its accusation against `rdap.org` was unfounded.

**Planted control string:** `grelbtype` — a nonsense word I never intended to use.

```
grelbtype   gh=404  .app=404  .com=404  brew=404  MAS=[GraalOnline Worlds]  repos=none
```

Control behaves as designed: an invented compound sweeps clean on every automated channel, and the
App Store still returns fuzzy noise (`GraalOnline Worlds`) at `resultCount>0`. **So "all four checks
came back 404" is the expected result for any invented string and carries almost no information.**
Every real verdict below therefore rests on the *repo descriptions*, *cask descriptions* and *web
searches*, not on the status codes.

## B2.1 — Candidates and full mechanical results

`gh` = `curl -sL -o /dev/null -w '%{http_code}' https://github.com/<n>` · `.app`/`.com` =
`curl -sL --max-time 25 https://rdap.org/domain/<n>.<tld>` (**404 = unregistered = good**) ·
`brew` = `formulae.brew.sh/api/cask/<n>.json` · MAS = iTunes Search API, `entity=macSoftware`,
`country=us`.

```
pushtype     gh=200  .app=404  .com=200  brew=404  MAS=[Typist ; ClickClack - Typing Trainer ; Type to Learn ; TYPER]
holdtype     gh=200  .app=200  .com=200  brew=404  MAS=[Typist ; Animal Typing - Lite ; 550 Royalty Free Fonts]
holdtext     gh=404  .app=404  .com=200  brew=404  MAS=[Notepad - Text Editor ; Transcribe voice to text - Jot ; TextSniper]
presstext    gh=404  .app=404  .com=200  brew=404  MAS=[Newsify: RSS Reader ; Reeder Classic. ; Fiery Feeds: News Reader]
localtype    gh=404  .app=404  .com=200  brew=404  MAS=[]
quiettype    gh=200  .app=404  .com=200  brew=404  MAS=[Loud Typer ; It Makes Noise]
typeless     gh=200  .app=200  .com=200  brew=200  MAS=[PromptKit - AI Prompt Manager]
instanttype  gh=404  .app=404  .com=200  brew=404  MAS=[Typist ; Animal Typing - Lite ; Typing Land]
directtype   gh=404  .app=404  .com=200  brew=404  MAS=[Letterforms - Font Maker ; Touch Typer ; OpenDyslexic]
textkey      gh=200  .app=404  .com=200  brew=404  MAS=[Master of Typing: Tutor ; LazyBoard ; Key Codes]
desktype     gh=404  .app=404  .com=200  brew=404  MAS=[DeskWidgets ; Desk Remote Control ; Standly]
nocloud      gh=200  .app=200  .com=000  brew=404  MAS=[Transmit 5 ; TeraBox ; CloudMounter]
pushtext     gh=404  .app=404  .com=200  brew=404  MAS=[AI Chat & AI Chatbot Assistant ; Textdrip ; Rocket Typist]
keytotext    gh=404  .app=404  .com=404  brew=404  MAS=[AI Scanner : Image to Text ; Textify ; Tot]
holdentry    gh=404  .app=404  .com=200  brew=404
keytext      gh=200  .app=200  .com=200  brew=404
taptext      gh=200  .app=404  .com=000  brew=404
droptext     gh=404  .app=200  .com=200  brew=404
localtext    gh=200  .app=404  .com=200  brew=404
quicktext    gh=200  .app=200  .com=200  brew=404
cleantext    gh=200  .app=200  .com=000  brew=404
tidytext     gh=404  .app=000  .com=200  brew=404
crisptext    gh=404  .app=404  .com=200  brew=404
presswrite   gh=404  .app=404  .com=200  brew=404
pushwrite    gh=404  .app=404  .com=200  brew=404
textpress    gh=200  .app=404  .com=200  brew=404
grelbtype    gh=404  .app=404  .com=404  brew=404   <- planted control
```

## B2.2 — FATAL KILLS: five candidates are the identical product

This is the batch-2 headline. **The plain, literal register is where this entire category has already
concentrated its naming.** Five of the twelve initial candidates are live dictation products.

### `Typeless` — a shipping competitor, distributed by Homebrew cask
Caught by the **Homebrew check, not by web search.** `formulae.brew.sh/api/cask/typeless.json`:
```json
{ "token": "typeless", "name": ["Typeless"],
  "desc": "AI voice dictation that turns speech into polished text",
  "homepage": "https://typeless.com/" }
```
Fetching `typeless.com` confirms it:
> Tagline: **"Speak, don't type"** · macOS, Windows, iOS, Android · "zero cloud data retention",
> "on-device history storage" · Removes filler words like "um," "uh," and "you know" · Auto-edits when
> you change your mind mid-sentence · Auto-formats spoken lists, steps, and key points

"Turns speech into polished text" with on-device filler-word removal *is* this product's spec sheet.
Same Homebrew distribution channel. Dead — and it owns `typeless.com`.

### `HoldType` — a byte-for-byte description of this app, and it owns the GitHub org
```
21★ holdtype/holdtype-swift [Native macOS menu bar dictation utility: hold a key, speak, ...]
```
"Native macOS menu bar dictation utility: hold a key, speak" is the brief, verbatim. It holds the
`holdtype` **organization** handle and both `holdtype.app` and `holdtype.com`. Dead.

### `QuietType` — on-device privacy-first voice dictation
```
0★ kimusan/QuietType [A privacy first, on-device, near-realtime voice dictation ap...]
```
Zero stars, but the exact name and the exact positioning. Dead.

### `LocalType` — local voice dictation
```
2★ newwying/localtype [Local, open-source Windows voice dictation — Qwen3-ASR + vLL...]
```
Dead.

### `PushWrite` — local voice input
```
1★ baumanncreative/pushwrite [Local voice input for your system powere...]
```
Dead.

### `InstantType` — collides with a long-established fast-text-entry product
`Instant Text` by **Textware Solutions** (textware.com) — "fast text entry software expanding a few
letters to words and phrases", sold as *Instant Text 7 Pro*. Same category (accelerated text entry),
decades old. `InstantType` vs `Instant Text` is not enough separation. Dead.

## B2.3 — The two saturated families (the real batch-2 finding)

Running the checks surfaced two naming zones that are **already full of shipping speech products**,
which means the hard-kill rule "root word has a shipping product in speech/audio" disqualifies whole
families, not just individual names:

**The `*Type` suffix — at least six shipping speech products:**
`Typeless` (typeless.com) · `VoiceType` (voicetype.com / carelesswhisper.app) · `EmberType`
(embertype.com, surfaced in a dictation search) · `HoldType` (holdtype-swift) · `QuietType`
(kimusan/QuietType) · `LocalType` (newwying/localtype). Anything ending in `-Type` is the seventh
entrant into a family it cannot own.

**The `Hold*` prefix — at least three shipping speech products:**
`Hold to Talk` (holdtotalk.com — "A native Mac dictation app for fast voice-to-text… Mac App Store")
· `HoldSpeak` (listed on AlternativeTo) · `holdtype/holdtype-swift`. This kills **`HoldText`** and
**`HoldEntry`** under the stated rule even though both are mechanically clean (`holdtext`:
gh=404, .app=404, zero repos). They are one word from two shipping competitors.

This is *why* Bobby's preferred register is hard: plain and literal is exactly what every other
developer in this category reached for first.

## B2.4 — Other kills

| Name | Killed by | Evidence |
|---|---|---|
| `PushType` | 285★ project owns the org handle | `285★ pushtype/push_type` — "modern, open source content management system"; `github.com/pushtype` = 200 |
| `KeyToText` | NLP/language-tech collision | `451★ gagan3012/keytotext` — "Keywords to Sentences" |
| `LocalText` | speech collision on the string | `311★ estebanstifli/LocalText2Voice` — local TTS workflow; `github.com/localtext` = 200 |
| `TidyText` | 1202★ text-mining package | `1202★ juliasilge/tidytext` — the canonical R text-mining library |
| `CleanText` | 79★ package + domains gone | `79★ prasanthg3/cleantext`; gh=200, `.app`=200 |
| `QuickText` | 282★ + taken everywhere | `282★ jobisoft/quicktext` (Thunderbird ext); gh/.app/.com all 200 |
| `TextPress` | 200★ + handle taken | `200★ shameerc/TextPress` (PHP blog engine); gh=200 |
| `KeyText` | taken on every channel | gh=200, `.app`=200, `.com`=200 |
| `TextKey` | handle taken + generic i18n identifier | gh=200; `textKey` is a routine localization parameter name |
| `DropText` | both domains registered | `.app`=200, `.com`=200 |
| `TapText` | handle taken | gh=200; `taptext/taptext.github.io` exists |
| `NoCloud` | handle taken + generic industry phrase | gh=200, `.app`=200 |
| `CrispText` | **homophone of a major voice-AI company** | **Krisp** (krisp.ai, Krisp Technologies Inc.) — noise cancellation + real-time transcription + a Voice AI SDK. Also `Crisp IM` (crisp.chat) holds trademarks in messaging. Mechanically clean (gh=404, .app=404) but dead under the root-word rule |
| `PressWrite` | reads as journalism, and a transcription agent exists | `0★ RinStel/PressWriterAgent` — "整合录音转写" (integrates audio transcription); "press"+"write" reads squarely as publishing |
| `DeskType` | `*Type` family (§B2.3) | mechanically clean but the seventh `-Type` |

## B2.5 — API-identifier check (the check that killed `AudioCapture`)

Run deliberately on each survivor, searching the name as a class / framework / method identifier:

- **`DirectType`** — no API identifier found. The nearest hits were Microsoft's `Direct*` family
  (DirectWrite, DirectInput) and Apple WebObjects' `com.apple.client.directtoweb`. **No `DirectType`
  class or symbol exists.** Passes, though the `Direct*` prefix does echo DirectX.
- **`PushText` / `PressText`** — no API identifier found. The search surfaced the W3C **Push API** and
  `PushMessageData.text()`, plus push-notification vendors (Pusher, Pushy, Pushnami, Braze), but
  **no `pushText` or `pressText` method or class** in any documented SDK. Passes — with the caveat in
  §B2.6 that "Push" carries strong push-notification connotation even without a literal collision.
- **`TextKey`** — fails informally: `textKey` is a routine localization/i18n parameter name across
  many frameworks. Too generic to own. (Already killed above on handle availability.)

## B2.6 — FINALISTS

Mac App Store exact-word scan, all four leading names: **`no exact-word hit`** each.
Trademark via Justia (**NOT legal advice** — see §5 of batch 1, which applies unchanged): no
`PRESSTEXT`, `PUSHTEXT`, `CRISPTEXT` or `DIRECTTYPE` mark surfaced. The nearest neighbours returned
were `MIGHTYTEXT`, `YEPTEXT`, `PUSHNAMI`, `PUSHCREW`, `CRISP IM` and `PRESS1LISTING`.

### 1. `PressText` — recommended
**Pitch:** press the key, text appears. The plainest possible statement of the action, using two
ordinary words, and it never says "voice" — so it names the interaction rather than the commodity
transcription stage.
**Evidence:** `github.com/presstext` **404 free** · `presstext.app` **404 free** · Homebrew **404** ·
no Mac App Store exact-word hit · no dictation, transcription, TTS or voice-AI product found · no API
identifier · no trademark surfaced. Highest-starred repo of that name: **1★ `tdh15/pressText`**
(empty description) and `0★ aohanyao/PressTextView`.
**Top risk:** "Press" reads as *the press* — news and publishing. The Mac App Store query for
`presstext` returned `Newsify: RSS Reader`, `Reeder Classic.` and `Fiery Feeds: News Reader`, which is
the semantic neighbourhood the word pulls toward. A reader may parse it as a media/PR tool before a
keyboard tool. `presstext.com` is registered.

### 2. `PushText` — recommended
**Pitch:** push-to-talk, and you get text. Names the defining interaction directly and inherits the
push-to-talk term users already know, without using "talk" in the name.
**Evidence:** `github.com/pushtext` **404 free** · `pushtext.app` **404 free** · Homebrew **404** · no
Mac App Store exact-word hit · no speech product found · **no `pushText` API identifier in any
documented SDK** · no trademark surfaced. Repos of that name: `0★ lixingchao686/PushText` and
`0★ robotmachine/PushText` ("Pushover Pipe for Python3") — both dormant.
**Top risk:** "Push" is overwhelmingly owned by *push notifications* in developer vocabulary — the
W3C Push API, Pusher, Pushy, Pushnami, PushCrew all surfaced in my own searches. A developer seeing
`PushText` in a Homebrew cask list will likely guess SMS or notification tooling before dictation.
`pushtext.com` is registered.

### 3. `DirectType` — recommended with a stated caveat
**Pitch:** the text goes *directly* where you are already typing — no capture window, no transcript
pane, no copy-paste. That is the actual product benefit, stated plainly.
**Evidence:** the cleanest repo evidence of the whole batch — `github.com/directtype` **404 free** ·
`directtype.app` **404 free** · Homebrew **404** · no Mac App Store exact-word hit · **zero GitHub
repos of that name in any search mode** · no `DirectType` API identifier · no trademark surfaced.
**Top risk — and it is a real one:** `-Type` is the saturated suffix of §B2.3. `Typeless`,
`VoiceType`, `EmberType`, `HoldType`, `QuietType` and `LocalType` are all shipping speech products,
so **on a strict reading of the hard-kill rule ("root word has a shipping product in speech/audio")
`DirectType` should be killed alongside `DeskType`.** I have kept it because it collides with none of
them directly and is the most available name tested; but it would be the seventh `-Type` in a family
it can never own, and `Typeless` — the closest of the six — is a direct competitor with the same
Homebrew channel. This is a judgement call, not a measurement, and it is Bobby's to make.

**Alternates, clean but ranked lower:** `HoldText` (mechanically spotless — gh 404, `.app` 404, zero
repos — killed only by the `Hold*` family rule; if that rule is relaxed it is arguably the best name
in the batch, since "hold, and you get text" is the most literal description available),
`DeskType`, `HoldEntry`.

## B2.7 — What batch 2 could not see

Section 5 of batch 1 applies unchanged (no TESS/USPTO access, no common-law marks, fuzzy US-only
App Store search, point-in-time domain checks, GitHub-only repo search, no social handles). Additional
to batch 2:

1. **The `terspad`/`grelbtype` control result is the most important caveat here.** Both nonsense
   strings swept clean on every automated channel. For invented compounds the status codes are close
   to uninformative — which is why five of this batch's kills came from *reading repo and cask
   descriptions*, and none from a status code. Any candidate whose competitor has no GitHub repo, no
   Homebrew cask and poor search ranking would still slip through.
2. **The API-identifier check is a web search, not an index scan.** I did not grep Apple's SDK
   headers, the Android API index, MDN's full symbol list, or any language's standard library. A name
   that is a symbol in an unpopular or undocumented SDK would pass. `AudioCapture` was catchable
   because it is prominent; a rarer identifier would not be.
3. **Homebrew caught `Typeless` when web search did not.** `Typeless` never appeared in any of my
   "best Mac dictation apps" search results across either batch, despite being a multi-platform
   commercial product with its own `.com`. That is direct evidence that the listicle-driven searches
   underpinning most of this report have a real miss rate — and it means other competitors are
   likely still invisible to me. I checked casks but **not** Homebrew *formulae*, and not npm, PyPI,
   crates.io, the Microsoft Store, Setapp, Gumroad or itch.io.
4. **`.com` is registered for every finalist.** `presstext.com`, `pushtext.com` and `directtype.com`
   all return RDAP 200. I did not check who holds them, whether they are parked, or whether they are
   purchasable. Only the `.app` is free in each case.
5. **The two "family saturation" kills are my inference, not a measured collision.** `HoldText`,
   `DeskType` and (arguably) `DirectType` have **no actual collision** — I killed or caveated them on
   the grounds that a crowded prefix/suffix will hurt discoverability and invite confusion. That is a
   marketing judgement with no data behind it, and a reasonable person could overrule it.
6. **I did not verify that the killed products are still live.** `kimusan/QuietType` has 0 stars and
   `newwying/localtype` has 2; both could be abandoned. I treated any exact-name repo describing this
   product as fatal without checking commit recency — deliberately conservative, but it may have
   discarded usable names.
