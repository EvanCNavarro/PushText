# Apple `SpeechAnalyzer` / `SpeechTranscriber` — macOS 26 "Tahoe" on-device STT

**Research date:** 2026-08-22
**Researcher:** Claude (subagent), for the `mumbler` project

---

## 0. Verification status — read this first

### What I could actually run on this machine

This machine **cannot compile or run any macOS 26 code**. Verified by running:

```
$ sw_vers
ProductName:		macOS
ProductVersion:		15.1
BuildVersion:		24B83

$ xcodebuild -version
Xcode 16.2
Build version 16C5032a

$ swift --version
Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)
Target: arm64-apple-macosx15.0

$ ls /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/
MacOSX.sdk
MacOSX15.2.sdk
MacOSX15.sdk
```

**No macOS 26 SDK is present.** The newest SDK is 15.2.

I further confirmed the new Swift API is genuinely absent from the installed SDK, not merely
unbuilt. Grepping the shipped `Speech.swiftinterface`:

```
$ grep -cE "SpeechAnalyzer|SpeechTranscriber|AssetInventory" \
    .../MacOSX.sdk/System/Library/Frameworks/Speech.framework/Versions/A/Modules/\
Speech.swiftmodule/arm64e-apple-macos.swiftinterface
0
```

The only public Swift types in that interface are the WWDC23 custom-language-model helpers
(`SFCustomLanguageModelData`, `PhraseCountGenerator`, `Template`, …).

The `Speech.tbd` stub library *does* export symbols matching `SpeechAnalyzer` — but they are the
**legacy Objective-C private/SPI class `SFSpeechAnalyzer`**, not the new Swift `SpeechAnalyzer`:

```
$ grep -oE '[A-Za-z0-9_$]*SpeechAnalyzer[A-Za-z0-9_$]*' .../Speech.tbd | sort -u
SFSpeechAnalyzer
SFSpeechAnalyzerConfiguration
SFSpeechAnalyzerLanguageDetectorOptions
SFSpeechAnalyzerOptions
SFSpeechAnalyzerOptionsLoggingInfo
SFSpeechAnalyzerOptionsPowerContext
SFSpeechAnalyzerTranscriberOptions
_$sSo16SFSpeechAnalyzerC6SpeechEABycfC
...
```

Public headers present in the 15.x SDK are all legacy:
`SFErrors.h`, `SFSpeechLanguageModel.h`, `SFSpeechRecognitionMetadata.h`, `SFSpeechRecognitionRequest.h`,
`SFSpeechRecognitionResult.h`, `SFSpeechRecognitionTask.h`, `SFSpeechRecognitionTaskHint.h`,
`SFSpeechRecognizer.h`, `SFTranscription.h`, `SFTranscriptionSegment.h`, `SFVoiceAnalytics.h`.

### Consequence for every claim below

| Marker | Meaning |
|---|---|
| **[DOC]** | Read from Apple's official documentation JSON API (`developer.apple.com/tutorials/data/...json`) or the WWDC25 session. Authoritative on *shape*, not on *behavior*. |
| **[CODE]** | Read from real open-source Swift that compiles against the macOS 26 SDK. Strong evidence the API shape is real and usable; I did not run these programs. |
| **[LOCAL]** | I ran a command on **this macOS 15.1 machine** and pasted the output. Only valid for legacy-API and system-layout claims. |
| **[REPORT]** | A developer's or vendor's claim (forum, blog, benchmark). Second-hand. |
| **UNVERIFIED** | I could not confirm it from any of the above. |

**Nothing in this document is a runtime result on macOS 26.** I never executed `SpeechAnalyzer`.
Every behavioral claim is documentation, other people's source code, or other people's reports.

---

## 1. `SpeechAnalyzer` + `SpeechTranscriber` — exact API surface

Source: Apple documentation JSON, fetched 2026-08-22.

### 1.1 `SpeechAnalyzer` [DOC]

```swift
final actor SpeechAnalyzer
```

Note it is an **`actor`**, not a class. Availability: **iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0,
macOS 26.0, tvOS 26.0, visionOS 26.0**. Not marked beta. **watchOS is absent** from the platform list.

Abstract: *"Analyzes spoken audio content in various ways and manages the analysis session."*

Full member list, verbatim from the docs:

**Creating an analyzer**
```swift
convenience init(modules: [any SpeechModule], options: SpeechAnalyzer.Options?)

convenience init<InputSequence>(
    inputSequence: InputSequence,
    modules: [any SpeechModule],
    options: SpeechAnalyzer.Options?,
    analysisContext: AnalysisContext,
    volatileRangeChangedHandler: sending ((CMTimeRange, Bool, Bool) -> Void)?
)

convenience init(
    inputAudioFile: AVAudioFile,
    modules: [any SpeechModule],
    options: SpeechAnalyzer.Options?,
    analysisContext: AnalysisContext,
    finishAfterFile: Bool,
    volatileRangeChangedHandler: sending ((CMTimeRange, Bool, Bool) -> Void)?
) async throws

struct Options
```

**Managing modules**
```swift
func setModules([any SpeechModule]) async throws
var modules: [any SpeechModule]
```

**Performing analysis** (pull model — you await completion)
```swift
func analyzeSequence<InputSequence>(InputSequence) async throws -> CMTime?
func analyzeSequence(from: AVAudioFile) async throws -> CMTime?
```

**Performing autonomous analysis** (push model — returns immediately, analysis runs in background)
```swift
func start<InputSequence>(inputSequence: InputSequence) async throws
func start(inputAudioFile: AVAudioFile, finishAfterFile: Bool) async throws
```

**Finalizing and cancelling results**
```swift
func cancelAnalysis(before: CMTime)
func finalize(through: CMTime?) async throws
```

**Finishing analysis**
```swift
func cancelAndFinishNow() async
func finalizeAndFinishThroughEndOfInput() async throws
func finalizeAndFinish(through: CMTime) async throws
func finish(after: CMTime) async throws
```

**Determining audio formats**
```swift
static func bestAvailableAudioFormat(compatibleWith: [any SpeechModule]) async -> AVAudioFormat?
static func bestAvailableAudioFormat(compatibleWith: [any SpeechModule],
                                     considering: AVAudioFormat?) async -> AVAudioFormat?
```

**Improving responsiveness**
```swift
func prepareToAnalyze(in: AVAudioFormat?) async throws
func prepareToAnalyze(in: AVAudioFormat?,
                      withProgressReadyHandler: sending ((Progress) -> Void)?) async throws
```

**Monitoring analysis**
```swift
func setVolatileRangeChangedHandler(sending ((CMTimeRange, Bool, Bool) -> Void)?)
var volatileRange: CMTimeRange?
```

**Managing contexts**
```swift
func setContext(AnalysisContext) async throws
var context: AnalysisContext
```

#### `SpeechAnalyzer.Options` [DOC]

```swift
struct Options
init(priority: TaskPriority, modelRetention: SpeechAnalyzer.Options.ModelRetention)
init(priority: TaskPriority, modelRetention: SpeechAnalyzer.Options.ModelRetention,
     ignoresResourceLimits: Bool)

enum ModelRetention            // "A model caching strategy."
let ignoresResourceLimits: Bool
let modelRetention: SpeechAnalyzer.Options.ModelRetention
let priority: TaskPriority
```

`ignoresResourceLimits` — *"A Boolean value that indicates whether this analyzer ignores predefined
system resource limits."* This is the knob for long-running/batch work. I could not fetch the
`ModelRetention` case list (its doc slug 404s); the cases are **UNVERIFIED**.

### 1.2 `SpeechTranscriber` [DOC]

```swift
final class SpeechTranscriber        // a class, not an actor
```

Availability: **iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS 26.0**. Abstract: *"A speech-to-text
transcription module that's appropriate for normal conversation and general purposes."*

```swift
// Creating a transcriber
convenience init(locale: Locale, preset: SpeechTranscriber.Preset)
convenience init(locale: Locale,
                 transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>,
                 reportingOptions:     Set<SpeechTranscriber.ReportingOption>,
                 attributeOptions:     Set<SpeechTranscriber.ResultAttributeOption>)

// Checking device support
static var isAvailable: Bool          // "given the device's hardware and capabilities"

// Checking locale support
static var installedLocales: [Locale]     // async
static var supportedLocales: [Locale]     // { get async } — "empty if the device does not support the transcriber"
static func supportedLocale(equivalentTo: Locale) async -> Locale?

// Getting results
var results: some Sendable & AsyncSequence<SpeechTranscriber.Result, any Error>
struct Result
```

Note the option parameters are **`Set<...>` of enums**, not `OptionSet`s.

#### Option enums [DOC]

```swift
enum SpeechTranscriber.ReportingOption {
    case alternativeTranscriptions  // include alternatives in addition to the most likely transcription
    case fastResults                // "Biases the transcriber towards responsiveness, yielding
                                    //  faster but also less accurate results."
    case volatileResults            // "Provides tentative results for an audio range in addition
                                    //  to the finalized result."
}

enum SpeechTranscriber.ResultAttributeOption {
    case audioTimeRange             // time-code attributes in the AttributedString
    case transcriptionConfidence    // confidence attributes in the AttributedString
}

enum SpeechTranscriber.TranscriptionOption {
    case etiquetteReplacements      // "Replaces certain words and phrases with a redacted form."
}
```

`etiquetteReplacements` is the profanity filter (`yap` exposes it as `--censor`) [CODE].

#### `SpeechTranscriber.Preset` [DOC]

```swift
struct Preset
init(transcriptionOptions:..., reportingOptions:..., attributeOptions:...)

static let transcription
static let transcriptionWithAlternatives
static let timeIndexedTranscriptionWithAlternatives
static let progressiveTranscription
static let timeIndexedProgressiveTranscription

var attributeOptions:     Set<SpeechTranscriber.ResultAttributeOption>
var reportingOptions:     Set<SpeechTranscriber.ReportingOption>
var transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>
```

Apple's own table of what each preset turns on:

| Preset | volatileResults | fastResults | alternativeTranscriptions | audioTimeRange |
|---|---|---|---|---|
| `transcription` | No | No | No | No |
| `transcriptionWithAlternatives` | No | No | Yes | No |
| `timeIndexedTranscriptionWithAlternatives` | No | No | Yes | Yes |
| `progressiveTranscription` | **Yes** | **Yes** | No | No |
| `timeIndexedProgressiveTranscription` | **Yes** | **Yes** | No | **Yes** |

> **Gotcha, [DOC]:** the two "progressive" (live) presets enable `fastResults`, which Apple's own
> docs describe as *"less accurate."* If you want live volatile results at full accuracy, do not use
> the preset — build the option sets yourself with `volatileResults` but **without** `fastResults`.

Apple's docs also show preset arithmetic, verbatim:

```swift
let preset = SpeechTranscriber.Preset.timeIndexedTranscriptionWithAlternatives
let transcriber = SpeechTranscriber(
    locale: Locale.current,
    transcriptionOptions: preset.transcriptionOptions.union([.etiquetteReplacements])
    reportingOptions: preset.reportingOptions.subtracting([.alternativeTranscriptions])
    attributeOptions: preset.attributeOptions
)
```

*(That snippet is missing two commas — a typo in Apple's own documentation, reproduced as-is.)*

> **Naming discrepancy:** the WWDC25 session names presets `.offlineTranscription` and
> `.progressiveLiveTranscription`; the shipping docs name them `.transcription` and
> `.progressiveTranscription`. The WWDC names were beta-era. `argmaxinc/apple-speechanalyzer-cli-example`'s
> README still documents the old names [REPORT]. Use the doc names.

### 1.3 `SpeechTranscriber.Result` [DOC]

```swift
struct Result
```

Abstract: *"A phrase or passage of transcribed speech. The phrases are sent in order."*
Discussion: *"If the transcriber is configured to send volatile results, each phrase is sent one or
more times as the interpretation gets better and better until it is finalized."*

```swift
// Getting transcriptions
var text: AttributedString              // "The most likely interpretation of the audio in this range."
let alternatives: [AttributedString]    // "All the alternative interpretations of the audio in this
                                        //  range. The interpretations are in descending order of likelihood."

// Working with transcriptions
struct TimeRangeAttribute               // "The time range in the source audio corresponding to the
                                        //  associated transcription text."
struct ConfidenceAttribute              // "A confidence level (0–1) of the associated transcription text."
func rangeOfAudioTimeRangeAttributes(intersecting: CMTimeRange) -> Range<AttributedString.Index>?

// Getting audio range
var range: CMTimeRange                  // "The audio input range that this result applies to."

// Getting finalization state
var isFinal: Bool                       // "Whether this result is final at the time it is produced."
var resultsFinalizationTime: CMTime     // "The audio input time up to which results from this module
                                        //  have been finalized (after this result). The module's
                                        //  results are final up to but not including this time."
```

**Answering the brief's questions directly:**
- **Alternatives:** yes — `Result.alternatives: [AttributedString]`, descending likelihood, gated by
  `.alternativeTranscriptions`.
- **Confidence:** yes — a per-run **attribute** on the `AttributedString`, 0–1, gated by
  `.transcriptionConfidence`. Not a scalar on `Result`.
- **`.audioTimeRange`:** an `AttributeScope` run attribute carrying `CMTimeRange`, gated by
  `.audioTimeRange`. Read it per-run off the `AttributedString`, e.g. `sentence.audioTimeRange` [CODE, `yap`].
- **Volatile vs final:** `isFinal`. Volatile results are re-sent for the same audio range until
  finalized. `resultsFinalizationTime` is the watermark — everything strictly before it is settled.

### 1.4 `SpeechModule` protocol [DOC]

```swift
protocol SpeechModule : AnyObject, Sendable {
    var availableCompatibleAudioFormats: [AVAudioFormat] { get }
    associatedtype Result : SpeechModuleResult, Sendable
    associatedtype Results : Sendable, AsyncSequence
    var results: Self.Results { get }
}
```

`SpeechTranscriber` and `DictationTranscriber` both conform. `SpeechAnalyzer(modules:)` takes
`[any SpeechModule]`, so the design anticipates additional analysis modules.

### 1.5 `AnalyzerInput` [DOC]

```swift
struct AnalyzerInput   // "Time-coded audio data."

init(buffer: CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>)
init(buffer: AVAudioPCMBuffer)
init(buffer: AVAudioPCMBuffer, bufferStartTime: CMTime?)   // for discontiguous audio

let bufferStartTime: CMTime?
let bufferDuration:  CMTime
let bufferFormat:    AVAudioFormat
var buffer:          AVAudioPCMBuffer   // "A new copy of the audio data for this input."
```

Two load-bearing sentences from the docs:

> *"The audio data must have an audio format that is supported by the analyzer's modules; **the
> analyzer does not perform audio conversion.**"*

> *"The audio format may differ from one `AnalyzerInput` object to the next. If the new audio format
> is supported by the modules, the modules will be reconfigured as needed."*

**You must convert the mic buffers yourself.** See §4.

### 1.6 `AnalysisContext` [DOC]

```swift
final class AnalysisContext            // "Contextual information that may be shared among analyzers."
init()
var contextualStrings: [AnalysisContext.ContextualStringsTag : [String]]
    // "Words or phrases, grouped by tag, that should be recognized even if they are not in the
    //  system vocabulary."
struct ContextualStringsTag
var userData: [AnalysisContext.UserDataTag : any Sendable]
struct UserDataTag
```

This is the successor to `SFSpeechRecognitionRequest.contextualStrings`. **Caveat:** a forum
responder states `AnalysisContext` contextual-vocabulary biasing works with `DictationTranscriber`
but *not* with `SpeechTranscriber` [REPORT — forum thread 818005]. Argmax independently reports that
SpeechAnalyzer *"lacks the Custom Vocabulary feature"* of the predecessor API [REPORT]. Treat
custom vocabulary on `SpeechTranscriber` as **UNVERIFIED and probably absent**.

### 1.7 Input shape — `AsyncStream`

The streaming input is any `AsyncSequence` of `AnalyzerInput`. Both production repos I read use
`AsyncStream` explicitly:

```swift
let (inputSequence, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
try await analyzer.start(inputSequence: inputSequence)
// ... later, per audio buffer:
inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
// ... at end:
inputContinuation.finish()
try await analyzer.finalizeAndFinishThroughEndOfInput()
```
[CODE — `finnvoor/yap`, `Sources/yap/Dictate.swift`]

`start(...)` vs `analyzeSequence(...)`: `start` is fire-and-forget (returns once analysis is
running; you consume `transcriber.results` concurrently). `analyzeSequence` awaits the whole
sequence and returns the last sample's `CMTime?`, which you then pass to
`finalizeAndFinish(through:)`. Use `start` for live mic; `analyzeSequence`/`start(inputAudioFile:)`
for files.

---

## 2. Model asset lifecycle

### 2.1 `AssetInventory` [DOC]

```swift
final class AssetInventory   // "Manages the assets that are necessary for transcription or other analyses."
```
Availability: iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS **26.0**.

```swift
// Downloading and installing assets
static func assetInstallationRequest(supporting: [any SpeechModule]) async throws
    -> AssetInstallationRequest?

// Managing allocations
static func reserve(locale: Locale) async throws -> Bool
static func release(reservedLocale: Locale) async -> Bool
static var reservedLocales: [Locale]
static var maximumReservedLocales: Int

// Checking asset status
static func status(forModules: [any SpeechModule]) async -> AssetInventory.Status
enum Status
```

`AssetInventory.Status` cases, verbatim:

| case | meaning |
|---|---|
| `.unsupported` | "The module will not work with its configuration." |
| `.supported` | "The module can work with its configuration, but the assets will need to be downloaded." |
| `.installed` | "…downloaded and installed on the device, and the module is ready for use." |
| `.downloading` | "…currently downloading the assets, or waiting for conditions to improve and continue downloading later." |

`maximumReservedLocales`: *"the largest allowed count of `reservedLocales`. The value may vary
between devices according to storage space."* The exact number is **UNVERIFIED** — read it at runtime.

### 2.2 ⚠️ WWDC-beta → release API rename [DOC, verified by 404]

The WWDC25 session and every blog derived from it show:

```swift
let allocated = await AssetInventory.allocatedLocales      // ← DOES NOT EXIST in the shipping API
await AssetInventory.deallocate(locale: locale)            // ← DOES NOT EXIST in the shipping API
```

Both 404 on Apple's live documentation API, while the replacements return 200:

```
assetinventory/allocatedlocales        -> HTTP 404
assetinventory/deallocate(locale:)     -> HTTP 404
assetinventory/maximumreservedlocales  -> HTTP 200
```

The shipping names are **`reservedLocales`** and **`release(reservedLocale:)`**. `finnvoor/yap`
uses the shipping names [CODE]. **Any tutorial showing `allocatedLocales`/`deallocate` is stale.**

### 2.3 `AssetInstallationRequest` [DOC]

```swift
@objc final class AssetInstallationRequest
func downloadAndInstall() async throws
var progress: Progress          // (used by yap; see below)
```

> *"You do not create instances of this type directly; obtain them from
> `assetInstallationRequest(supporting:)`."*
> *"The system consolidates download and installation requests; you may obtain several of these
> instances and call `downloadAndInstall()` several times **without causing redundant downloads**."*

`assetInstallationRequest(supporting:)` returns **`nil` when nothing needs downloading** — that is the
"already installed" signal, and it is why the call is safe to make unconditionally [DOC + CODE].

Progress reporting is via KVO-ish polling of `request.progress.fractionCompleted`; `yap` polls it on
a 0.1 s loop in a sibling task while awaiting `downloadAndInstall()` [CODE].

### 2.4 The canonical lifecycle [CODE — `finnvoor/yap`]

```swift
guard SpeechTranscriber.isAvailable else { throw ... }

let supportedLocales = await SpeechTranscriber.supportedLocales
guard supportedLocales.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
else { throw ... }

for locale in await AssetInventory.reservedLocales {
    await AssetInventory.release(reservedLocale: locale)
}
try await AssetInventory.reserve(locale: locale)

let transcriber = SpeechTranscriber(locale: locale, ...)
let modules: [any SpeechModule] = [transcriber]

let installedLocales = await SpeechTranscriber.installedLocales
if !installedLocales.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
    if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
        try await request.downloadAndInstall()
    }
}
```

Two things to copy from this:
1. **Compare locales by `identifier(.bcp47)`, never by `Locale ==`.** Apple's docs and a forum
   answer both say arbitrary `Locale` values won't compare equal to the ones in `supportedLocales`;
   `supportedLocale(equivalentTo:)` exists precisely for this [DOC + REPORT].
2. **Release before reserving.** `yap` releases every existing reservation before reserving the one
   it wants, because reservations are capped at `maximumReservedLocales`.

Firefox iOS takes the other approach — `supportedLocale(equivalentTo:)` to normalize, then install —
and never reserves at all [CODE]:

```swift
private func resolveLocale(with currentLocale: Locale) async throws -> Locale {
    if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: currentLocale) {
        return supported
    } else { throw SpeechError.unableToSupportLocale }
}
```

### 2.5 Supported locales

Reported list (42 locales) [REPORT — Itsuki, Medium, Jul 2026]:

```
ar_SA da_DK de_AT de_CH de_DE en_AU en_CA en_GB en_IE en_IN en_NZ en_SG en_US en_ZA
es_CL es_ES es_MX es_US fi_FI fr_BE fr_CA fr_CH fr_FR he_IL it_CH it_IT ja_JP ko_KR
ms_MY nb_NO nl_BE nl_NL pt_BR ru_RU sv_SE th_TH tr_TR vi_VN yue_CN zh_CN zh_HK zh_TW
```

I did not verify this list against a device. It is OS-version-dependent — Apple adds locales in
point releases. **Always read `SpeechTranscriber.supportedLocales` at runtime.**

### 2.6 Where assets live on disk, and how big — LARGELY UNVERIFIED

**What Apple says [DOC/WWDC]:** *"The model is retained in system storage and does not increase the
download or storage size of your application, nor does it increase the run-time memory size."*
Models are downloaded and updated by the OS, outside the app's memory space.

**Exact path and per-locale byte size: UNVERIFIED.** I found no authoritative source, and I cannot
inspect a macOS 26 machine.

What I *can* show is the delivery mechanism, from **this macOS 15.1 box** [LOCAL] — Apple ships ASR
models as MobileAssets under `/System/Library/AssetsV2/`:

```
$ ls /System/Library/AssetsV2/ | grep -iE "speech|siri|asr|dictation"
com_apple_MobileAsset_SpeechEndpointMacOSAssets
com_apple_MobileAsset_SpeechTranslationAssets2 ... Assets7
com_apple_MobileAsset_Trial_Siri_SiriUnderstandingAsrAssistant
com_apple_MobileAsset_UAF_Siri_UnderstandingASRHammer
com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition
...

$ du -sh /System/Library/AssetsV2/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition
 85M	/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition

$ find .../com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition -maxdepth 2
.../purpose_auto
.../purpose_auto/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition.xml
.../purpose_auto/9f24650fffa24d57ca9214f1523363f3fa36ab1e.asset
```

**Read that carefully:** 85 MB is the *legacy Siri/dictation ASR asset on macOS 15.1*. It is **not**
the `SpeechTranscriber` model, and it is **not** evidence of the macOS 26 model's size. It only
establishes that (a) the MobileAsset/`AssetsV2` mechanism is the delivery channel Apple uses for
on-device ASR, and (b) an order of magnitude of "tens to low hundreds of MB" is plausible. Do not
quote a size to a user without measuring it on a real macOS 26 machine.

### 2.7 Offline behavior, one-time-ness

- **Download is per-locale and one-time.** Once a locale's assets are installed, `installedLocales`
  contains it, `assetInstallationRequest(supporting:)` returns `nil`, and transcription runs with no
  network [DOC].
- **Transcription itself is fully on-device** — no server round-trip, unlike `SFSpeechRecognizer`'s
  default path [DOC/WWDC].
- **Offline with assets missing:** `downloadAndInstall()` throws. Reported error text includes
  `"transcription.ar asset not found after attempted download"` and status stuck at `.downloading`
  from an earlier attempt [REPORT — forum].
- **The OS updates models on its own.** You get accuracy improvements for free, but you also cannot
  pin a model version — a source of silent behavior change across point releases.
- **Assets can be pre-seeded outside your app.** One developer notes speech assets were obtained via
  the system's **Live Captions** feature rather than through his app [REPORT — `SwiftCaptionTesting`].
  So a user may already have them, or may have them arrive from an unrelated system feature.

---

## 3. Deployment requirements

### 3.1 Minimum OS — macOS 26.0 [DOC]

Every new type is annotated `macOS 26.0` (also iOS/iPadOS/Mac Catalyst/tvOS/visionOS 26.0). Not beta.

**watchOS is not in `SpeechAnalyzer`'s platform list.** `DictationTranscriber` is available on
iOS/iPadOS/Mac Catalyst/macOS/visionOS 26.0 — note **no tvOS** for `DictationTranscriber`, whereas
`SpeechTranscriber` *does* list tvOS. The two modules have genuinely different platform matrices.

Real code gates it as:
```swift
@available(iOS 26.0, *)                      // firefox-ios
guard #available(macOS 26, *) else { throw ServiceError.unsupportedOS }   // VoiceInk
platforms: [.macOS("26")]                    // yap's Package.swift
```
[CODE — all three repos]

### 3.2 Apple silicon only? — effectively yes on Mac, but the real gate is the Neural Engine

**There is no `isAppleSilicon` check in the API.** The gate is `SpeechTranscriber.isAvailable`, whose
doc says: *"A Boolean value that indicates whether this module is available **given the device's
hardware and capabilities**."*

Evidence about what that means:
- macOS 26 Tahoe does not run on Intel Macs at all beyond a narrow set, and Apple Intelligence-class
  on-device ML on Mac is Apple-silicon-only [REPORT].
- On iOS, `isAvailable` returns `false` on **8-core Neural Engine** devices (iPhone 11 / 11 Pro /
  11 Pro Max / SE 2nd gen, i.e. A13) and `true` from A14/16-core-ANE devices onward. A forum
  responder's hypothesis: *"SpeechTranscriber uses a model size that requires the throughput of a
  16-core Neural Engine to meet real-time latency requirements"* [REPORT — forum thread 806765].
- On unsupported hardware, **`supportedLocales` also returns `[]`**, and Apple's own doc for
  `supportedLocales` says: *"This array is empty if the device does not support the transcriber."*
  So an empty locale list is a hardware signal, not a download signal [DOC + REPORT].
- **The iOS Simulator does not support it** — *"SpeechTranscriber relies on the Neural Engine for
  on-device inference, and the Simulator does not emulate the ANE"* [REPORT]. Assume the same
  hazard for any ANE-less environment; I have not tested a macOS 26 VM. **UNVERIFIED for macOS VMs.**

**Practical rule:** branch on `SpeechTranscriber.isAvailable`, never on chip family. Have a fallback.

### 3.3 Does it require Apple Intelligence to be ENABLED? — No [DOC/WWDC + REPORT]

This is contradicted across blogs, so here is the evidence chain:

- **WWDC25 session 277 states there are no user settings to satisfy** — users do **not** need to
  enable Siri or keyboard dictation. Apple frames model management as automatic and invisible [DOC/WWDC].
- The forum thread specifically about `isAvailable` returning false **never mentions Apple
  Intelligence**; the diagnosis is entirely Neural Engine core count [REPORT — thread 806765].
- Apple's `Speech` framework documentation contains no Apple Intelligence gate, entitlement, or
  eligibility check. `AssetInventory` handles its own assets independently of the Apple Intelligence
  model catalog [DOC].
- Contrast: `FoundationModels` (the on-device LLM) *does* require Apple Intelligence. The WWDC
  session pipes SpeechAnalyzer output *into* FoundationModels — they are separate subsystems, and
  that adjacency is the likely source of the blog confusion.

At least one blog asserts *"the Apple Intelligence framework enabled on the system"* is required
[REPORT — siliconreport.com]. **I judge that claim unsupported**, but I could not run the negative
test (disable Apple Intelligence on macOS 26 and call `isAvailable`). Marking:
**Apple Intelligence NOT required — high confidence, UNVERIFIED by execution.**

### 3.4 Entitlement? — none found [DOC]

I found **no entitlement** for `Speech`/`SpeechAnalyzer` in Apple's documentation, in any of the six
open-source repos I read, or in any forum thread. `finnvoor/yap` ships as a Homebrew-installed SPM
executable with **no entitlements file, no provisioning profile, and no Info.plist at all** [CODE].

If an entitlement were required, that binary could not work. **Conclusion: no entitlement.**
(Standing caveat: sandboxed App Store apps still need the sandbox *capability* for the microphone —
see 3.6 — but that is an audio-input capability, not a Speech one.)

### 3.5 Does it work in a non-sandboxed SPM-built binary? — Yes, demonstrably [CODE]

`finnvoor/yap` is the proof. Its `Package.swift`:

```swift
// swift-tools-version: 6.1
let package = Package(
    name: "yap",
    platforms: [.macOS("26")],
    products: [ .executable(name: "yap", targets: ["yap"]) ],
    dependencies: [ swift-argument-parser, Noora, swift-sdk (MCP) ],
    targets: [ .executableTarget(name: "yap", dependencies: [...]) ]
)
```

A plain `.executableTarget`, `import Speech`, `brew install yap`. It does both file transcription
and **live mic dictation** (`yap dictate`). No `.app` bundle, no sandbox, no plist.

For a `.app` you build yourself with SPM + a hand-rolled bundle: same conclusion, plus you now have
a plist to fill in (§3.6). I have **not** verified App Store review behavior. **UNVERIFIED.**

### 3.6 Info.plist keys

**`NSMicrophoneUsageDescription` — required.** Any process that opens the mic through `AVAudioEngine`
triggers macOS TCC. In a bundled app, TCC reads this key; absent, the app is killed on first mic
access. Not specific to Speech.

**`NSSpeechRecognitionUsageDescription` — almost certainly NOT required for `SpeechAnalyzer`.**
This is where I disagree with most blog write-ups, which assert both keys are needed. The evidence:

- That key exists to gate **`SFSpeechRecognizer`**, whose authorization flow is
  `SFSpeechRecognizer.requestAuthorization(_:)` returning an `SFSpeechRecognizerAuthorizationStatus`.
  The new API has **no equivalent authorization call anywhere in its documented surface** [DOC].
- **Firefox iOS's `SpeechAnalyzerEngine.prepare()` requests only microphone permission** [CODE]:
  ```swift
  func prepare() async throws {
      try await authorizer.requestMicrophonePermission()
      try audioManager.configureAudioSession()
  }
  ```
  No speech-recognition authorization request. This is shipping Mozilla code.
- **`yap` has no Info.plist at all** and its only permission error is about the microphone [CODE]:
  ```swift
  case .microphonePermissionDenied:
      "Microphone permission is required. Grant it to your terminal app in
       System Settings > Privacy & Security > Microphone, then restart the terminal."
  ```
- Mechanically this makes sense: the old key existed because audio could be **sent to Apple's
  servers**. `SpeechAnalyzer` never leaves the device, so there is nothing extra to consent to.

**Recommendation:** ship `NSMicrophoneUsageDescription`. Add `NSSpeechRecognitionUsageDescription`
only if you also keep an `SFSpeechRecognizer` fallback path (§5) — in which case you need it anyway,
and it costs nothing. **UNVERIFIED by execution** either way.

**App Sandbox:** if sandboxed, enable `com.apple.security.device.audio-input` (Xcode: Signing &
Capabilities → App Sandbox → Hardware → Audio Input). No Speech-specific sandbox key exists.

### 3.7 Summary table

| Requirement | Verdict | Confidence |
|---|---|---|
| macOS 26.0+ | Required | **[DOC]** certain |
| Apple silicon | Effectively required on Mac | **[REPORT]** high |
| 16-core Neural Engine (A14+ class) | Required — gate on `isAvailable` | **[REPORT]** high |
| Apple Intelligence enabled | **NOT** required | high, unexecuted |
| Entitlement | None | high |
| Non-sandboxed SPM binary | Works | **[CODE]** demonstrated |
| `NSMicrophoneUsageDescription` | Required (for mic input, bundled apps) | high |
| `NSSpeechRecognitionUsageDescription` | **Not** required for SpeechAnalyzer | medium-high |
| Sandbox audio-input capability | Required if sandboxed | high |
| Network | Only for the one-time per-locale model download | **[DOC]** certain |

---

## 4. Audio input contract

### 4.1 The rule

> *"The audio data must have an audio format that is supported by the analyzer's modules; **the
> analyzer does not perform audio conversion.**"* [DOC — `AnalyzerInput`]

So the contract is:

1. Build your modules.
2. `let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)`
   — returns `AVAudioFormat?`, **`nil` means give up**.
3. Tap `AVAudioEngine.inputNode` at its *native* format.
4. Convert every buffer native → `targetFormat` with `AVAudioConverter`.
5. `inputContinuation.yield(AnalyzerInput(buffer: converted))`.

**The concrete sample rate / channel count / interleaving is not documented and is device-dependent.
Do not hardcode 16 kHz.** Ask `bestAvailableAudioFormat` at runtime. There is also
`SpeechModule.availableCompatibleAudioFormats: [AVAudioFormat]` if you need to inspect the whole set,
and `bestAvailableAudioFormat(compatibleWith:considering:)` to bias toward a format you already have.
**The actual returned format on macOS 26 is UNVERIFIED — I could not run it.**

### 4.2 The buffer-conversion pattern that ships

Verbatim from `finnvoor/yap`, `Sources/yap/Dictate.swift` [CODE] — note the tap uses `format: nil`
(native) and `bufferSize: 4096`:

```swift
inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [self] buffer, _ in
    handleBuffer(buffer)
}

private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
    let frameCapacity = AVAudioFrameCount(
        ceil(Double(buffer.frameLength) * targetFormat.sampleRate / converter.inputFormat.sampleRate)
    )
    guard frameCapacity > 0 else { return }
    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                 frameCapacity: frameCapacity) else { return }

    var error: NSError?
    nonisolated(unsafe) var consumed = false
    nonisolated(unsafe) let sourceBuffer = buffer
    converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
        if consumed { outStatus.pointee = .noDataNow; return nil }
        consumed = true
        outStatus.pointee = .haveData
        return sourceBuffer
    }

    if error == nil, convertedBuffer.frameLength > 0 {
        inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
    }
}
```

Three details worth stealing:
- The `frameCapacity` **must** be scaled by the sample-rate ratio and rounded **up**, or
  `AVAudioConverter` silently truncates.
- The one-shot `consumed` flag is the correct `AVAudioConverterInputBlock` idiom for
  "I have exactly one buffer" — returning the same buffer twice duplicates audio.
- `guard inputFormat.sampleRate > 0` at construction is `yap`'s microphone-permission-denied
  detection: a denied mic yields a 0 Hz input format rather than an error.

### 4.3 `bufferStartTime` and discontiguity

`AnalyzerInput(buffer:)` lets the analyzer assume contiguity. Use
`AnalyzerInput(buffer:bufferStartTime:)` when audio has gaps (seeking, pausing, replaying a file).

> **Gotcha [REPORT — forum 818005]:** `bufferStartTime` *"must be monotonically increasing and
> consistent with actual audio duration. Gaps or overlaps cause silent failures or nilError."*
> The same thread reports buffers **smaller than 4096 frames occasionally trigger the error**, with a
> recommendation of ~8192 frames, and that **exact** format matching (interleaved vs non-interleaved,
> channel layout) matters — *"even subtle mismatches can cause nilError."*

### 4.4 `prepareToAnalyze(in:)`

Firefox iOS calls `try await analyzer.prepareToAnalyze(in: targetFormat)` **before**
`start(inputSequence:)` [CODE]. Apple files it under "Improving responsiveness" — it warms the model
so the first utterance isn't slow. For a dictation tool where time-to-first-word is the whole
product, call it (ideally at app launch / hotkey-arm, not at record time).

---

## 5. Versus legacy `SFSpeechRecognizer`

### 5.1 What I verified locally about the legacy API [LOCAL]

From this machine's `MacOSX.sdk` headers:

```objc
// SFSpeechRecognitionRequest.h
// If true, speech recognition will not send any audio over the Internet
// This will reduce accuracy but enables certain applications where it is
// inappropriate to transmit user speech to a remote service.
// Default is false
@property (nonatomic) BOOL requiresOnDeviceRecognition API_AVAILABLE(ios(13), macos(10.15), tvos(18));

@property (nonatomic) BOOL addsPunctuation API_AVAILABLE(ios(16), macos(13), tvos(18));
@property (nonatomic, copy) NSArray<NSString *> *contextualStrings;
@property (nonatomic) BOOL shouldReportPartialResults;
@property (nonatomic, copy, nullable) SFSpeechLanguageModelConfiguration *customizedLanguageModel
    API_AVAILABLE(ios(17), macos(14), tvos(18));
```

Two things fall out of Apple's own comment that matter for `mumbler`:

1. **`requiresOnDeviceRecognition` defaults to `false`** — the legacy API **sends your audio to
   Apple by default**. You must opt out explicitly.
2. **Apple states on-device mode "will reduce accuracy."** So the legacy fully-offline path is, by
   Apple's own admission, the *worse* of the two legacy modes.

And a trap I found by reading the header rather than the docs:

```objc
// SFSpeechRecognizer.h
// True if this recognition can handle requests with requiresOnDeviceRecognition set to true
@property (nonatomic) BOOL supportsOnDeviceRecognition API_AVAILABLE(ios(13), tvos(18));
```

**`supportsOnDeviceRecognition` is annotated `ios(13), tvos(18)` — there is no `macos(...)`.** The
capability-check property for on-device recognition is **not available on macOS**. You can set
`requiresOnDeviceRecognition = true` (that one *is* `macos(10.15)`) but you cannot ask beforehand
whether it will work. That is a real, verified sharp edge for a macOS-15 fallback.

Also verified: `SFSpeechErrorDomain` (`macos(14)+`) has a very thin error enum —
`InternalServiceError = 1`, `AudioReadFailed = 2`, `UndefinedTemplateClassName = 7`,
`MalformedSupplementalModel = 8`, `Timeout = 10`. No error case for throttling or duration limits;
those surface as opaque `kAFAssistantErrorDomain` / `kLSRErrorDomain` codes [REPORT].

### 5.2 Comparison

| | `SFSpeechRecognizer` (macOS 10.15+) | `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+) |
|---|---|---|
| **Introduced** | iOS 10 / macOS 10.15 | iOS 26 / macOS 26 |
| **Network** | **Server by default**; on-device only via `requiresOnDeviceRecognition = true` | **Always on-device.** No server mode. |
| **Duration limit** | ~1 minute per request (documented; reportedly looser on macOS files) [REPORT] | None documented — designed for long-form: lectures, meetings, conversations [DOC] |
| **Throttling** | Yes — undocumented daily/rate limits on the server path; `kAFAssistantErrorDomain` errors [REPORT] | N/A |
| **Capability probe on macOS** | `supportsOnDeviceRecognition` **unavailable on macOS** [LOCAL] | `SpeechTranscriber.isAvailable` [DOC] |
| **API style** | ObjC, delegate + completion handlers | Swift-native `actor`, `async`/`await`, `AsyncSequence` |
| **Result type** | `SFTranscription` / `SFTranscriptionSegment`, plain `String` | `AttributedString` with time-range + confidence run attributes |
| **Alternatives** | `SFSpeechRecognitionResult.transcriptions` | `Result.alternatives: [AttributedString]` |
| **Partial results** | `shouldReportPartialResults` | `.volatileResults` + `isFinal` + `resultsFinalizationTime` |
| **User settings** | Requires user speech-recognition authorization | No authorization call in the API [DOC] |
| **Custom vocabulary** | `contextualStrings`, `SFSpeechLanguageModelConfiguration` (macOS 14+) | `AnalysisContext.contextualStrings` — **reportedly ineffective on `SpeechTranscriber`** [REPORT] |
| **Model storage** | System | System; explicit lifecycle via `AssetInventory` |
| **Hardware floor** | Any Mac | Apple silicon + 16-core-class ANE |
| **Deprecated?** | **No** — not deprecated in the macOS 26 SDK [REPORT] | — |

### 5.3 Is `SFSpeechRecognizer` a viable macOS 15 fallback?

**Yes, and it is the only Apple-native option** — it is the sole speech-recognition API in the
macOS 15.x SDK on this machine, and it is **not deprecated** in the macOS 26 SDK, so one codebase can
carry both paths behind `#available(macOS 26, *)`.

Caveats, in order of how much they'll hurt a dictation tool:

1. **The ~1-minute-per-request limit.** For push-to-talk dictation this is usually fine; for
   meeting-length capture you must chunk and stitch, and stitching across chunk boundaries loses
   context and produces seam artifacts.
2. **On-device mode is less accurate by Apple's own header comment**, and you can't probe support for
   it on macOS (§5.1). You must set `requiresOnDeviceRecognition = true` and handle failure at
   runtime — or accept sending user audio to Apple, which for a local-first dictation tool is
   probably disqualifying.
3. **Server-path throttling** is real and undocumented [REPORT].
4. **Plain `String` output**, no per-word timings without `SFTranscriptionSegment` bookkeeping, no
   confidence attributes.

Third parties routinely reach for **WhisperKit / Parakeet (CoreML on the ANE)** instead of
`SFSpeechRecognizer` for the pre-26 tier — `Muesli` ships Apple Speech *and* Parakeet TDT, Whisper
via WhisperKit, and others, gating Apple Speech to "system-managed on macOS 26+" [CODE/REPORT].
That is the realistic architecture if macOS 15 quality matters.

**On this machine specifically:** you can develop and test the `SFSpeechRecognizer` path today. You
cannot compile the `SpeechAnalyzer` path at all until Xcode 26 with the macOS 26 SDK is installed.

---

## 6. Real-world reports and open-source implementations

### 6.1 Benchmarks

**Argmax (WhisperKit vendor), M4 Mac mini, macOS 26 Beta Seed 1**, on a random 10% subset of
`earnings22` (~12 h of English earnings-call conversation) [REPORT]:

| Engine | WER | Speed factor |
|---|---|---|
| **Apple SpeechAnalyzer** | **14.0** | **70** |
| WhisperKit `openai/whisper-base.en` | 15.2 | 111 |
| WhisperKit `openai/whisper-small.en` | 12.8 | 35 |
| Argmax Pro SDK `nvidia/parakeet-v2` | 11.7 | 359 |

Read: SpeechAnalyzer sits **between** Whisper base and small on accuracy, at roughly **2× the speed
of whisper-small**. It is beaten on both axes by Parakeet. Argmax is not a neutral party — they sell
the competing SDK — but this is the only WER table I found with a stated dataset and hardware.

Argmax's stated limitation of SpeechAnalyzer: it *"lacks the Custom Vocabulary feature"* of the
predecessor API, *"resulting in notably lower keyword recognition accuracy."*

**MacRumors / Daring Fireball (June 2025)** [REPORT]: a CLI built on SpeechAnalyzer processed a 7 GB
video **2.2× faster than MacWhisper's Large V3 Turbo**, *"with no noticeable difference in
transcription quality."* Anecdotal, no dataset.

**Latency:** I found **no published end-to-end latency measurement for SpeechAnalyzer.**
`Muesli`'s README quotes **~0.13 s** dictation latency — but that is for **Parakeet TDT**, not Apple
Speech, in the same app. Do not attribute it to SpeechAnalyzer. **UNVERIFIED.**

The nearest qualitative datapoint: `edmistond/SwiftCaptionTesting` reports his SpeechAnalyzer live
captioning is *"nearly (but not quite) as accurate as Apple's built in live transcription,"*
attributing the gap to his own audio buffering rather than the framework [REPORT].

### 6.2 Open-source Swift repos using `SpeechAnalyzer`

GitHub code search for `SpeechAnalyzer SpeechTranscriber language:swift` returned
**`total_count: 1158`** on 2026-08-22. Six I actually read or inspected:

#### (1) `finnvoor/yap` — the best reference for a CLI / streaming mic
- `Sources/yap/Dictate.swift` — **live mic → SpeechAnalyzer**, plus a `MicrophoneCapture` class with
  the `AVAudioConverter` pattern (§4.2). This is the single most useful file for `mumbler`.
- `Sources/yap/TranscriptionEngine.swift` — file transcription via
  `analyzer.start(inputAudioFile:finishAfterFile: true)`.
- `Sources/yap/Transcribe.swift`, `Sources/yap/Listen.swift` — CLI subcommands.
- `Package.swift` — `platforms: [.macOS("26")]`, plain `.executableTarget`, **no Info.plist, no
  entitlements, no sandbox**. Homebrew-installable (`brew install yap`).
- Pattern worth stealing: SRT/VTT/JSON output built from `.audioTimeRange` attributes, with
  `splitAtTimeGaps(threshold: 1.5)` and `sentences(maxLength:)` helpers over `AttributedString`.
- Also: releases all `reservedLocales` before reserving one.

#### (2) `mozilla-mobile/firefox-ios` — the best reference for app architecture
- `BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/SpeechAnalyzerEngine.swift`
- `@available(iOS 26.0, *) @MainActor final class SpeechAnalyzerEngine: TranscriptionEngine`
- Configuration: `reportingOptions: [.volatileResults, .fastResults]`,
  `attributeOptions: [.transcriptionConfidence]`.
- Calls `prepareToAnalyze(in: targetFormat)` before `start(inputSequence:)`.
- Uses `supportedLocale(equivalentTo:)` for locale normalization.
- `prepare()` requests **only microphone permission** — key evidence for §3.6.
- Ordered teardown in `stop()`: stop engine → `inputContinuation.finish()` →
  `finalizeAndFinishThroughEndOfInput()` → nil out tasks/objects.
- Behind a `TranscriptionEngine` protocol so a non-26 engine can be swapped in. Copy this shape.

#### (3) `Beingpax/VoiceInk` — the best reference for error handling
- `VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift`
- Gates with `guard #available(macOS 26, *)` **and** a compile-time flag
  `#if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER`, so the project still builds on older SDKs.
  Directly relevant to `mumbler`, which is on a 15.x SDK today.
- Consumes `AssetInventory.Status` exhaustively (`.unsupported`/`.supported`/`.downloading`/`.installed`)
  with `@unknown default`.
- Has a dedicated `assetReservationFailed` error — reservation genuinely fails in the field.
- **Wraps result-stream consumption in a timeout**:
  ```swift
  let resultTimeout = max(20.0, audioDuration * 4.0 + 10.0)
  finalTranscription = try await waitForResultStream(resultTask, timeout: resultTimeout)
  ```
  with `case resultStreamTimedOut = "Apple Speech did not finish returning transcription results."`
  A shipping app found it necessary to defend against `transcriber.results` never completing.
- On any failure: `resultTask.cancel()` then `await analyzer.cancelAndFinishNow()`.

#### (4) `argmaxinc/apple-speechanalyzer-cli-example` — minimal file+live CLI
- macOS 26.0+, `swift build -c release`, `--input-audio-path`, `--locale`, `--live`.
- README still documents beta preset names `.offlineTranscription` / `.progressiveLiveTranscription`.

#### (5) `edmistond/SwiftCaptionTesting` — live captioning POC, honest about bugs
- `SpeechAnalyzerManager.swift`. Reports volatile/final duplication (§7), audio-routing losses in
  Tahoe, self-describes as not production-ready.

#### (6) `Muesli-HQ/muesli` — production macOS dictation app, multi-engine
- Lists Apple Speech as *"system-managed on macOS 26+"* alongside Parakeet TDT, Nemotron 3.5,
  WhisperKit Whisper variants. The architectural lesson: a serious macOS dictation product treats
  Apple Speech as **one provider among several**, not the only one.

Others surfaced but not read: `Sentient-OS-Labs/sentient-os`, `matthartman/ghost-pepper`
(has `GhostPepperTests/SpeechTranscriberTests.swift` — rare test coverage),
`jubishop/podhaven`, `TypeWhisper/typewhisper-mac`, `WyattBlue/auto-editor` (`src/ae_speech.swift`),
`makepad/makepad` (`libs/voice/swift/speech_bridge.swift` — Rust FFI bridge),
`fastrepl/anarlog` (`crates/transcribe-speechanalyzer/swift-lib/src/lib.swift` — also Rust FFI),
`itsthisjustin/Liquid-Speech` (Flutter plugin), `FI-153/wyoming-apple-speech` (Home Assistant).

> For `mumbler`, the two FFI bridges (`makepad`, `anarlog`) are the templates if you ever want a
> Rust or non-Swift host process driving SpeechAnalyzer.

---

## 7. Known bugs, gotchas, and forum complaints

### 7.1 `start(inputSequence:)` fails with `nilError` [REPORT — forum thread 818005]

The highest-severity open issue for a streaming use case like `mumbler`.

```
_GenericObjCError domain=Foundation._GenericObjCError code=0 detail=nilError
```

Reporter's environment: **macOS 26.3 (25D122), Xcode 26.3, Swift 6.2.4, Apple silicon.**
Feedback filed as **FB22149971**. The offline path `start(inputAudioFile:finishAfterFile:)` works on
the same audio; only the streaming path fails. Swapping in `DictationTranscriber` did not help.
**No Apple DTS reply in the thread.**

Community-suggested causes, all worth designing around:
1. The `AVAudioFormat` of your `AnalyzerInput` buffers must **exactly** match
   `bestAvailableAudioFormat()` — interleaved vs non-interleaved and channel layout included.
2. Buffers **< 4096 frames** occasionally trigger it; ~8192 frames recommended.
3. `bufferStartTime` must be **monotonically increasing** and consistent with real duration.
4. **Live capture is more reliable than replaying a file through the streaming path** — plausibly
   because live audio is naturally correctly paced.

### 7.2 Locale errors are the most common complaint [REPORT]

- `"SpeechTranscriber cannot be initialized with an unsupported locale: en_US (fixed en_US)"`
- `"Cannot use modules with unallocated locales [en_US (fixed en_US)]"` — you constructed the
  transcriber without calling `AssetInventory.reserve(locale:)` first, or you reserved a `Locale`
  that isn't `==` the one the module resolved to.
- **Fix:** always route through `SpeechTranscriber.supportedLocale(equivalentTo:)`, and compare with
  `identifier(.bcp47)` — never `Locale ==`. The "(fixed …)" in the message is Locale's internal
  normalization leaking, which is exactly why identity comparison fails.

### 7.3 Asset download failures [REPORT]

- `"transcription.ar asset not found after attempted download"` — `downloadAndInstall()` succeeds but
  the asset isn't there. Reported for Arabic; possibly locale-specific.
- `AssetInventory.status(forModules:)` can return `.downloading` **left over from an earlier
  attempt**, so status is not a reliable readiness gate on its own.
- `VoiceInk` ships a distinct `assetReservationFailed` user-facing error, implying reservation
  failures happen in production.
- Assets may arrive from **outside your app** — e.g. the system's Live Captions feature. Never assume
  your download call is the only thing that installs them.

### 7.4 Results not finalizing / stream hangs [REPORT — CODE-corroborated]

`VoiceInk` wraps `for try await result in transcriber.results` in an explicit timeout of
`max(20.0, audioDuration * 4.0 + 10.0)` seconds with a `resultStreamTimedOut` error. That defense
does not get written unless the stream hangs in the field. **Add a timeout.**

### 7.5 Volatile/final duplication [REPORT — `SwiftCaptionTesting`]

*"volatile results duplicating the most recent finalized result briefly, particularly toward the end
of a sentence segment."* The author isn't sure whether it's his bug or the framework's.

**Design implication:** do **not** append volatile text to your transcript. Keep two buffers —
`finalizedTranscript` (append-only, from `isFinal == true`) and `volatileTranscript` (replaced
wholesale each time) — and render `finalized + volatile`. This is exactly what the WWDC sample does:

```swift
if result.isFinal {
    finalizedTranscript += text
    volatileTranscript = ""
} else {
    volatileTranscript = text          // replaced, never appended
}
```

Use `resultsFinalizationTime` if you need a precise watermark rather than trusting `isFinal` alone.

### 7.6 Hardware/simulator availability surprises [REPORT — thread 806765]

- `isAvailable == false` on 8-core-ANE devices; `supportedLocales == []` on the same devices, so an
  empty locale list is a **hardware** signal, not a download signal.
- **Not supported in the iOS Simulator** (no ANE emulation). Use conditional compilation to fall back
  to `SFSpeechRecognizer` for simulator builds.
- **UNVERIFIED for macOS:** whether a macOS 26 VM (no ANE passthrough) reports `isAvailable == false`.
  If `mumbler` has CI, assume it does and gate accordingly.

### 7.7 macOS 26.x point-release quality [REPORT]

- A forum thread titled *"Please, Apple. I am begging you. Fix the broken Text-To-Speech in macOS"*
  (thread 818500) claims *"every new build of macOS 26 further breaks some part of text-to-speech or
  voice control."* That is about **TTS/Voice Control**, not `SpeechAnalyzer` — do not conflate them.
- `SwiftCaptionTesting` reports **audio loss bugs in Tahoe around "audio routing and virtual
  devices"** — relevant if `mumbler` ever taps system audio via a virtual device (BlackHole etc.).
- The `nilError` report above is against **macOS 26.3**, i.e. the streaming bug survived at least
  three point releases.
- **I found no specific, confirmed SpeechAnalyzer regression tied to a named point release.**
  **UNVERIFIED.**

### 7.8 The stale-tutorial trap

Because so much writing predates the release API, watch for these dead names:
- `AssetInventory.allocatedLocales` → **`reservedLocales`**
- `AssetInventory.deallocate(locale:)` → **`release(reservedLocale:)`**
- `.offlineTranscription` → **`.transcription`**
- `.progressiveLiveTranscription` → **`.progressiveTranscription`**

All four old names 404 or are absent from the shipping documentation.

### 7.9 Custom vocabulary probably doesn't work on `SpeechTranscriber`

`AnalysisContext.contextualStrings` exists, but a forum responder says biasing works with
`DictationTranscriber` and *not* `SpeechTranscriber`, and Argmax independently says SpeechAnalyzer
lacks custom vocabulary [REPORT ×2, independent]. If `mumbler` needs domain terms (names, jargon,
code identifiers) recognized reliably, **budget for post-hoc correction** — a fuzzy-match personal
dictionary, which is exactly what `Muesli` does (Jaro-Winkler over a user word list).

---

## 8. Reference implementation — streaming mic → `SpeechTranscriber` → text

> # ⚠️ UNCOMPILED — NOT RUN — NOT VERIFIED
>
> **This code has never been compiled.** This machine is macOS 15.1 / Xcode 16.2 / Swift 6.0.3 with
> no macOS 26 SDK (§0), so `import Speech` here would not even resolve `SpeechAnalyzer`.
>
> It is synthesized from Apple's documented signatures (§1) and from patterns in
> `finnvoor/yap` and `mozilla-mobile/firefox-ios`, which **do** compile against the macOS 26 SDK.
> The API shape is well-grounded; **typos, actor-isolation diagnostics, and Swift 6 `Sendable`
> errors are likely** and must be resolved against a real compiler.
>
> Treat every line as a hypothesis until Xcode 26 says otherwise.

### `Package.swift`

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MumblerDictation",
    platforms: [.macOS("26")],          // hard floor; SpeechAnalyzer does not exist before this
    products: [.executable(name: "mumbler-dictate", targets: ["MumblerDictation"])],
    targets: [.executableTarget(name: "MumblerDictation")]
)
```

*(A plain non-sandboxed SPM executable with no Info.plist and no entitlements is a demonstrated
working configuration — that is exactly how `finnvoor/yap` ships. §3.5.)*

### `Dictation.swift`

```swift
import AVFoundation
import Foundation
import Speech

// MARK: - Errors

enum DictationError: Error, LocalizedError {
    case transcriberUnavailable
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
    case microphoneDenied
    case converterUnavailable
    case resultsTimedOut

    var errorDescription: String? {
        switch self {
        case .transcriberUnavailable:
            // isAvailable == false means the hardware can't run it (pre-A14-class Neural Engine,
            // Intel Mac, likely a VM). It is NOT a "download the model" signal. §3.2
            "On-device speech transcription is not available on this hardware."
        case .unsupportedLocale(let id):
            "Locale \"\(id)\" is not supported by SpeechTranscriber."
        case .noCompatibleAudioFormat:
            "No compatible analyzer audio format is available."
        case .microphoneDenied:
            "Microphone access is required. Grant it in System Settings > Privacy & Security > Microphone."
        case .converterUnavailable:
            "Could not build an AVAudioConverter from the input format to the analyzer format."
        case .resultsTimedOut:
            "The transcriber stopped returning results."
        }
    }
}

// MARK: - What we hand back to the UI

/// Keep finalized and volatile text SEPARATE. Volatile results are re-sent for the same audio
/// range and are known to briefly duplicate the tail of the last finalized result (§7.5).
/// Append only on `isFinal`; REPLACE the volatile buffer wholesale.
struct DictationSnapshot: Sendable {
    var finalized: AttributedString = ""
    var volatile:  AttributedString = ""
    var combined: AttributedString { finalized + volatile }
}

// MARK: - The pipeline

@available(macOS 26.0, *)
actor DictationSession {

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var capture: MicrophoneCapture?
    private var resultsTask: Task<Void, Never>?

    // ---------------------------------------------------------------------
    // 1. Preflight: hardware, locale, assets
    // ---------------------------------------------------------------------

    /// Resolve a locale the transcriber will actually accept, and make sure its model is installed.
    ///
    /// NEVER compare `Locale` values with `==` — the transcriber normalizes them internally and
    /// identity comparison fails with errors like `unsupported locale: en_US (fixed en_US)` (§7.2).
    /// Compare `identifier(.bcp47)`, or better, use `supportedLocale(equivalentTo:)`.
    static func prepareLocale(
        _ requested: Locale = .current,
        onDownloadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Locale {

        guard SpeechTranscriber.isAvailable else { throw DictationError.transcriberUnavailable }

        // On unsupported hardware this returns [] — a second, redundant signal. §3.2
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw DictationError.unsupportedLocale(requested.identifier)
        }

        // Reservations are capped by `AssetInventory.maximumReservedLocales`, which varies by
        // device storage. Release what we hold before claiming a new one. (yap does exactly this.)
        for held in await AssetInventory.reservedLocales {
            _ = await AssetInventory.release(reservedLocale: held)
        }
        _ = try await AssetInventory.reserve(locale: locale)

        // Build a throwaway module purely to ask the asset system what it needs.
        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }

        if !isInstalled {
            // Returns nil when nothing needs downloading. The system de-dupes concurrent
            // requests, so calling this unconditionally is safe.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                if let onDownloadProgress {
                    // `progress` is a plain Foundation.Progress; poll it alongside the download.
                    let progress = request.progress
                    let poller = Task {
                        while !Task.isCancelled, !progress.isFinished {
                            onDownloadProgress(progress.fractionCompleted)
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                    defer { poller.cancel() }
                    try await request.downloadAndInstall()
                } else {
                    try await request.downloadAndInstall()
                }
            }
        }
        return locale
    }

    // ---------------------------------------------------------------------
    // 2. Start streaming
    // ---------------------------------------------------------------------

    /// Streams transcription updates. Each yielded snapshot is the complete current state.
    func start(locale: Locale) async throws -> AsyncThrowingStream<DictationSnapshot, Error> {

        // macOS TCC. In a bundled .app this needs NSMicrophoneUsageDescription in Info.plist
        // (and the audio-input sandbox capability if sandboxed). A plain CLI inherits the
        // terminal's grant instead. §3.6
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw DictationError.microphoneDenied
        }

        // Options, hand-rolled rather than via a preset. Deliberate:
        //   .volatileResults  -> live partial text
        //   NOT .fastResults  -> the `.progressiveTranscription` preset turns fastResults ON, and
        //                        Apple's own docs call it "less accurate". For dictation we want
        //                        the accuracy. Add .fastResults back if latency is unacceptable. §1.2
        //   .audioTimeRange   -> per-run CMTimeRange, needed for any timestamped output
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],                 // add .etiquetteReplacements to censor
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer

        // THE analyzer decides the format. We convert to it. It does not convert for us. §4.1
        // Never hardcode a sample rate here.
        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        else { throw DictationError.noCompatibleAudioFormat }

        // Warms the model so the first word isn't slow. Ideally call this earlier still —
        // at app launch or when the hotkey is armed, not when the user starts speaking. §4.4
        try await analyzer.prepareToAnalyze(in: targetFormat)

        let (inputSequence, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = inputContinuation

        // `start` is fire-and-forget: it returns as soon as analysis is running, and we consume
        // `transcriber.results` concurrently. (`analyzeSequence` is the awaiting variant, for files.)
        try await analyzer.start(inputSequence: inputSequence)

        let capture = try MicrophoneCapture(targetFormat: targetFormat,
                                            continuation: inputContinuation)
        self.capture = capture
        try capture.start()

        return AsyncThrowingStream { outer in
            self.resultsTask = Task { [weak self] in
                var snapshot = DictationSnapshot()
                do {
                    for try await result in transcriber.results {
                        if result.isFinal {
                            snapshot.finalized += result.text
                            snapshot.volatile = ""        // clear, don't append — §7.5
                        } else {
                            snapshot.volatile = result.text  // REPLACE wholesale
                        }
                        outer.yield(snapshot)
                    }
                    outer.finish()
                } catch {
                    outer.finish(throwing: error)
                }
                _ = self
            }
            outer.onTermination = { _ in self.resultsTask?.cancel() }
        }
    }

    // ---------------------------------------------------------------------
    // 3. Stop — order matters
    // ---------------------------------------------------------------------

    /// Ordering copied from firefox-ios: stop the mic, close the input stream, THEN finalize.
    /// Finalizing before the stream is closed can leave the analyzer waiting for more audio.
    func stop() async throws {
        capture?.stop()
        capture = nil

        inputContinuation?.finish()
        inputContinuation = nil

        // Defensive timeout: a shipping app (VoiceInk) found `results` can hang. §7.4
        let finalize = Task { [analyzer] in
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        }
        let guardTask = Task {
            try await Task.sleep(for: .seconds(15))
            throw DictationError.resultsTimedOut
        }
        do {
            try await finalize.value
            guardTask.cancel()
        } catch {
            finalize.cancel()
            await analyzer?.cancelAndFinishNow()
            throw error
        }

        resultsTask = nil
        transcriber = nil
        analyzer = nil
    }

    /// Abandon everything immediately, discarding pending results.
    func cancel() async {
        capture?.stop(); capture = nil
        inputContinuation?.finish(); inputContinuation = nil
        resultsTask?.cancel(); resultsTask = nil
        await analyzer?.cancelAndFinishNow()
        transcriber = nil; analyzer = nil
    }
}

// MARK: - Microphone capture + format conversion

/// Taps the input node at its NATIVE format and converts each buffer to the analyzer's format.
/// `AnalyzerInput` docs: "the analyzer does not perform audio conversion." §4.1
///
/// Format mismatch — including interleaved-vs-non-interleaved and channel layout — is the
/// leading suspected cause of the streaming `nilError`. §7.1
final class MicrophoneCapture: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    init(targetFormat: AVAudioFormat,
         continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        self.targetFormat = targetFormat
        self.continuation = continuation

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        // A denied microphone shows up as a 0 Hz format rather than a thrown error. (yap's trick.)
        guard nativeFormat.sampleRate > 0 else { throw DictationError.microphoneDenied }

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw DictationError.converterUnavailable
        }
        self.converter = converter

        // `format: nil` == tap at the node's native format. 8192 frames: the forum thread reports
        // buffers under 4096 frames occasionally trigger nilError; larger is safer. §7.1
        input.installTap(onBus: 0, bufferSize: 8192, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
    }

    func start() throws {
        engine.prepare()
        do { try engine.start() } catch { throw DictationError.microphoneDenied }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        // Scale capacity by the sample-rate ratio and round UP, or AVAudioConverter truncates.
        let ratio = targetFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return }

        var error: NSError?
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let source = buffer

        // One-shot input block: hand over exactly one buffer, then report .noDataNow.
        // Returning `source` twice would duplicate audio.
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return source
        }

        guard error == nil, out.frameLength > 0 else { return }

        // AnalyzerInput(buffer:) assumes contiguity with the previous input — correct for a live
        // mic. Use AnalyzerInput(buffer:bufferStartTime:) only for discontiguous audio, and then
        // keep bufferStartTime monotonically increasing and duration-consistent. §4.3
        continuation.yield(AnalyzerInput(buffer: out))
    }
}
```

### `main.swift` — minimal driver

```swift
import Foundation

guard #available(macOS 26.0, *) else {
    FileHandle.standardError.write(Data("Requires macOS 26 or later.\n".utf8))
    exit(1)
}

let locale = try await DictationSession.prepareLocale(.current) { fraction in
    FileHandle.standardError.write(Data("Downloading model: \(Int(fraction * 100))%\r".utf8))
}

let session = DictationSession()
let stream = try await session.start(locale: locale)

signal(SIGINT) { _ in Task { await session.cancel(); exit(0) } }

for try await snapshot in stream {
    // Redraw the whole line: volatile text is replaced, not appended.
    print("\u{1B}[2K\r" + String(snapshot.combined.characters), terminator: "")
    fflush(stdout)
}
print()
try await session.stop()
```

### Reading `.audioTimeRange` off the attributed string

```swift
// With attributeOptions: [.audioTimeRange], each run of result.text carries a CMTimeRange.
for run in result.text.runs {
    if let range = run.audioTimeRange {           // SpeechTranscriber.Result.TimeRangeAttribute
        let words = String(result.text[run.range].characters)
        print("[\(range.start.seconds)–\(range.end.seconds)] \(words)")
    }
}
// There is also:
//   result.range                                  -> CMTimeRange for the whole result
//   result.resultsFinalizationTime                -> watermark; results final BEFORE this time
//   result.rangeOfAudioTimeRangeAttributes(intersecting:) -> map a CMTimeRange back to string indices
// The exact AttributeScope key spelling is UNVERIFIED — confirm against the real SDK.
```

### Before this compiles, verify against the real SDK

1. **`ModelRetention` cases** — undocumented; needed only if you pass `SpeechAnalyzer.Options`.
2. **The `AttributedString` attribute key spelling** for `audioTimeRange` / `transcriptionConfidence`.
   `yap` uses `sentence.audioTimeRange` [CODE], so a property of that name exists on some extension,
   but I have not confirmed the scope declaration.
3. **Actor isolation.** `SpeechTranscriber` is a `final class` (not Sendable-by-inheritance);
   `SpeechAnalyzer` is an `actor`. The `Task { }` capture of `transcriber` in `start(...)` is the
   most likely Swift 6 diagnostic. firefox-ios sidesteps it by being `@MainActor` throughout —
   consider copying that instead of my `actor`.
4. **`AssetInventory.reserve` returns `Bool`** — I discard it with `_ =`. Decide whether a `false`
   return should be fatal (VoiceInk treats reservation failure as a user-facing error).
5. **`request.progress`** — documented on `AssetInstallationRequest` in the WWDC sample and used by
   `yap`; confirm it is public API and not just a beta artifact.

---

## 9. Recommendation for `mumbler`

1. **Two-tier architecture, decided now.** Put a `TranscriptionEngine` protocol at the boundary
   (firefox-ios's shape). Tier 1 = `SpeechAnalyzer` on macOS 26+; tier 2 = whatever you choose for
   macOS 15. Gate with `#available(macOS 26, *)` **plus** a compile-time flag like VoiceInk's
   `ENABLE_NATIVE_SPEECH_ANALYZER`, so the project keeps building on the 15.2 SDK you have today.
2. **You cannot start on the SpeechAnalyzer path.** No macOS 26 SDK on this machine (§0). Either
   install Xcode 26 / upgrade to Tahoe, or build the tier-2 engine and the protocol first.
3. **For tier 2, `SFSpeechRecognizer` is workable but weak** — 1-minute requests, server-by-default,
   less-accurate on-device mode, and no way to probe on-device support on macOS (§5.1). If quality
   matters on macOS 15, WhisperKit/Parakeet is the honest answer, as `Muesli` concluded.
4. **Runtime-gate on `SpeechTranscriber.isAvailable`**, never on chip family or OS version alone.
5. **Design for the volatile/final split from day one** (§7.5) — retrofitting it after you've been
   appending volatile text is painful.
6. **Add a timeout around `transcriber.results`** (§7.4). A shipping app needed one.
7. **Assume no custom vocabulary** (§7.9). If `mumbler` needs jargon, plan a post-hoc fuzzy-match
   dictionary.
8. **Before writing much code, re-verify §7.1** — the `nilError` on `start(inputSequence:)` was open
   against macOS 26.3, and streaming mic input is precisely `mumbler`'s use case. Build the smallest
   possible mic→transcriber spike first and confirm it works on your target OS build before
   committing to the architecture.

---

## Sources

### Apple official — documentation JSON API (fetched 2026-08-22, HTTP 200 unless noted)
1. https://developer.apple.com/documentation/speech/speechanalyzer
2. https://developer.apple.com/documentation/speech/speechtranscriber
3. https://developer.apple.com/documentation/speech/speechtranscriber/result
4. https://developer.apple.com/documentation/speech/speechtranscriber/preset
5. https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption
6. https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption
7. https://developer.apple.com/documentation/speech/speechtranscriber/transcriptionoption
8. https://developer.apple.com/documentation/speech/speechtranscriber/isavailable
9. https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocales
10. https://developer.apple.com/documentation/speech/speechanalyzer/options
11. https://developer.apple.com/documentation/speech/analyzerinput
12. https://developer.apple.com/documentation/speech/speechmodule
13. https://developer.apple.com/documentation/speech/analysiscontext
14. https://developer.apple.com/documentation/speech/assetinventory
15. https://developer.apple.com/documentation/speech/assetinventory/status
16. https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales
17. https://developer.apple.com/documentation/speech/assetinstallationrequest
18. https://developer.apple.com/documentation/speech/dictationtranscriber
19. https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app
20. https://developer.apple.com/documentation/speech — framework root
21. https://developer.apple.com/documentation/speech/assetinventory/allocatedlocales — **HTTP 404** (proves the beta rename)
22. https://developer.apple.com/documentation/speech/assetinventory/deallocate(locale:) — **HTTP 404** (same)
23. https://developer.apple.com/documentation/speech/sfspeechrecognizer
24. https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
25. https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription

### Apple official — WWDC
26. https://developer.apple.com/videos/play/wwdc2025/277/ — "Bring advanced speech-to-text to your app with SpeechAnalyzer" (WWDC25 session 277)
27. https://www.youtube.com/watch?v=0m6dimDDj8M — same session, video
28. https://gist.github.com/auramagi/9c040c2233dfe71c24c76942e186f788 — community transcripts of all WWDC 2025 sessions

### Apple Developer Forums
29. https://developer.apple.com/forums/thread/818005 — `start(inputSequence:)` nilError, macOS 26.3, FB22149971
30. https://developer.apple.com/forums/thread/806765 — `SpeechTranscriber not supported` / Neural Engine core count / Simulator
31. https://developer.apple.com/forums/thread/790108 — SpeechAnalyzer WWDC sample app thread (locale + asset errors)
32. https://developer.apple.com/forums/thread/801197 — SpeechTranscriber availability on iPad models
33. https://developer.apple.com/forums/thread/807739 — SpeechTranscriber supported devices
34. https://developer.apple.com/forums/tags/speech — Speech tag index
35. https://developer.apple.com/forums/thread/818500 — macOS 26 TTS/Voice Control degradation (adjacent, not SpeechAnalyzer)

### Open-source Swift (code read directly via the GitHub API)
36. https://github.com/finnvoor/yap — `Sources/yap/Dictate.swift`, `TranscriptionEngine.swift`, `Package.swift`, `README.md`
37. https://github.com/mozilla-mobile/firefox-ios — `BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/SpeechAnalyzerEngine.swift`
38. https://github.com/Beingpax/VoiceInk — `VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift`
39. https://github.com/argmaxinc/apple-speechanalyzer-cli-example — README
40. https://github.com/edmistond/SwiftCaptionTesting — README (volatile/final duplication, Tahoe audio-routing bugs)
41. https://github.com/Muesli-HQ/muesli — README (multi-engine production macOS dictation app)
42. https://github.com/topics/speechanalyzer — repo index

### Benchmarks / press / write-ups
43. https://www.argmaxinc.com/blog/apple-and-argmax — WER + speed table, earnings22, M4 Mac mini
44. https://www.macrumors.com/2025/06/18/apple-transcription-api-faster-than-whisper/
45. https://daringfireball.net/linked/2025/06/19/apples-new-foundation-model-speech-apis-outpace-whisper-for-transcription
46. https://9to5mac.com/2025/06/18/apple-devices-offer-amazing-speech-to-text-transcription-in-developer-betas-shows-test/
47. https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer
48. https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide
49. https://appcircle.io/blog/wwdc25-bring-advanced-speech-to-text-capabilities-to-your-app-with-speechanalyzer
50. https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo
51. https://medium.com/@itsuki.enjoy/swift-speechtranscriber-support-multi-language-without-manual-locale-switching-b626b547bd74 — the 42-locale list
52. https://www.theswift.dev/posts/transcribe-audio-with-speechanalyzer-in-swift/
53. https://www.siliconreport.com/apple-launches-on-device-speechanalyzer-api-beating-whisper-small-on-speed-and-accuracy-4cf2a0b7 — **source of the disputed "Apple Intelligence required" claim**
54. https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer — **HTTP 403, could not read**

### Local machine (macOS 15.1 — legacy API and system layout only)
55. `/Applications/Xcode.app/.../SDKs/` listing; `Speech.framework/Headers/*.h`;
    `Speech.framework/.../arm64e-apple-macos.swiftinterface`; `Speech.tbd`;
    `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition`

---

## What I could not verify

Ordered by how much it would hurt to be wrong.

1. **Anything at runtime on macOS 26.** No SDK, no OS. I never constructed a `SpeechAnalyzer`, never
   transcribed a syllable, never saw a real `Result`. Every behavioral statement above is
   documentation, someone else's source, or someone else's report. This is the root caveat and it
   subsumes most of what follows.

2. **The actual `AVAudioFormat` returned by `bestAvailableAudioFormat`** — sample rate, channel
   count, interleaving, common format. Completely undocumented and I could not query it. My
   reference implementation is written to never assume; do not let a hardcoded 16000 creep in.

3. **Per-locale model download size, and the on-disk path.** No authoritative source anywhere. The
   85 MB I measured is the **legacy Siri ASR MobileAsset on macOS 15.1**, a different artifact on a
   different OS. It bounds nothing. If you need a real number, `du -sh` it on a Tahoe machine before
   and after a locale install.

4. **Whether Apple Intelligence must be enabled.** I argue no, from the WWDC session, the absence of
   any gate in the docs, and a forum thread that diagnoses `isAvailable == false` purely as Neural
   Engine core count. But one blog asserts yes, and **I could not run the negative test** (disable
   Apple Intelligence, call `isAvailable`). High confidence, zero execution.

5. **Whether `NSSpeechRecognitionUsageDescription` is required.** I argue no — firefox-ios requests
   only mic permission, `yap` has no plist at all, and the new API has no authorization call. But
   several blogs say yes, and I could not test a bundled `.app` on macOS 26. Medium-high confidence.
   The cheap hedge (ship both keys) costs nothing.

6. **`SpeechAnalyzer.Options.ModelRetention` cases.** Doc slug 404s. Unknown.

7. **The exact `AttributedString` attribute-scope key spelling** for `audioTimeRange` and
   `transcriptionConfidence`. `yap` uses `.audioTimeRange` as a property, so something of that name
   exists, but I did not see the scope declaration.

8. **`AssetInstallationRequest.progress` as public API.** Used by `yap` and shown in the WWDC sample,
   and `AssetInstallationRequest`'s doc page lists only `downloadAndInstall()` under its topic
   sections — `progress` did not appear in the member list I parsed. It may be inherited,
   undocumented, or beta-era. Confirm before depending on download progress UI.

9. **`maximumReservedLocales`' actual value** on any device. Docs say it varies with storage.

10. **The 42-locale `supportedLocales` list.** Single secondary source (a Medium post), and it is
    OS-version-dependent by construction. Read it at runtime.

11. **Whether `SpeechTranscriber` works in a macOS 26 VM** (no ANE passthrough). Known false in the
    iOS Simulator; unknown for macOS virtualization. Matters if `mumbler` gets CI.

12. **Any specific SpeechAnalyzer regression tied to a named macOS 26 point release.** I found none.
    The `nilError` report is *against* 26.3, which shows the bug persisted, but that is not the same
    as a regression introduced by 26.x.

13. **Whether `AnalysisContext.contextualStrings` actually biases `SpeechTranscriber`.** Two
    independent sources say it does not (one forum responder, one vendor). Neither is Apple. Test it
    before either relying on it or writing it off.

14. **App Store review behavior** for a SpeechAnalyzer app — entitlements, privacy-manifest entries,
    or usage-description enforcement. Not researched.

15. **`callstack.com`'s write-up** returned HTTP 403 and could not be read. It may contain latency
    numbers and plist details that would have settled items 2, 3, and 5.

16. **Real latency figures for SpeechAnalyzer.** None published that I could find. The ~0.13 s figure
    circulating from `Muesli` is **Parakeet TDT**, not Apple Speech, and must not be quoted as such.
