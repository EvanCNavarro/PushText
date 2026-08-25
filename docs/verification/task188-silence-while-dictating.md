# Task 188 - Silencing the Mac while dictating

Measured 2026-08-25 on macOS 26.6.2.

Bobby: *"can you have thing deafen or have an option for that, like to deafen the computer while
recording"*.

---

## 1. Why it is worth having

Whatever is playing keeps playing while you dictate. On a laptop the speakers are inches from the
microphone, so music becomes part of the audio the transcriber is asked to make sense of.

## 2. The feature is three lines. The hazard is everything else.

An app that mutes the Mac and is then killed leaves someone's machine silent **with no visible
cause**, and nobody connects that to a dictation utility. This repo already refuses to write the
Globe-key SPI for exactly that reason (#176) - the difference here is that we own the restore, so it
has to be durable rather than hopeful.

Three defences:

1. `restore()` runs from EVERY exit - the normal end, cancel, failure, and the watchdog. Restoring
   only on the happy path leaves the Mac silent on precisely the paths that fire when something has
   already gone wrong.
2. It restores the **prior** state, not "unmuted". Somebody dictating on a deliberately silent Mac
   must not get a surprise noise when they let go of the key.
3. The intent is written to disk **before** the mute, and `recoverIfInterrupted()` at launch gives
   the sound back after a crash.

## 3. Six plants, and the one that found a gap in the tests

| plant | result |
|---|---|
| restore to unmuted rather than prior | **FAIL** |
| recovery fires with no reason to | **FAIL** |
| forget to restore on CANCEL | **FAIL** |
| silence regardless of the setting | **FAIL** |
| mute BEFORE recording the intent | **passed** |

That last one is the interesting failure. Reversing those two lines only matters if the process dies
*in that window*, and no test kills a process mid-call - so every existing assertion held.

The fix was not a better argument, it was a different assertion: the fake output now reads the flag
**at the moment the speaker is muted**, so the sequence itself is checked. Re-planted, it fires.

The key it reads is duplicated in the test rather than imported from `DictationMuter`. Importing it
would make the test agree with whatever the code does - the same tautology that let an icon
assertion pass earlier today (#164).

## 4. Default OFF, and that is not a taste call

`soundEnabled` defaults ON because the cues are feedback the user asked for by installing a
push-to-talk tool. This defaults OFF: silencing someone's audio without being asked is a surprise,
and a surprise involving their speakers is worse than one involving a tone.

## 5. What this does NOT show

`CoreAudioOutput` is never exercised by a test - every test uses a fake. Muting the real default
output device in a test would silence the developer's Mac and, if the test crashed, leave it that
way. That is the exact hazard this file is about, so the real device is driven only by the running
app.

The consequence is honest and worth stating: **the CoreAudio calls themselves are unverified by the
suite.** What is verified is every decision around them - when to mute, what to restore, and that a
crash is repaired.

Nobody has confirmed that muting actually keeps music out of a transcript. That is a measurable claim
(`PUSHTEXT_TRANSCRIBE_PROBE` with audio playing) and it is not measured here; the feature is offered
as an option rather than as a promise about transcript quality.
