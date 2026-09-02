# A Sparkle update actually installed, and the grants survived it (#240)

#240 recorded that nothing in this project had ever exercised Sparkle's **installer** - only its
inputs. Its trigger was "the next release published while an older PushText is installed on a real
Mac". v0.6.10 fired it.

## The baseline, captured before the tag

Recorded at 2026-08-31T20:03:48Z, deliberately **before** pushing the tag, because it cannot be
recovered afterwards:

| | before |
|---|---|
| app version | 0.6.9 |
| build | 145 |
| Sparkle | 2.9.3 |

## After

| | before | after |
|---|---|---|
| app version | 0.6.9 | **0.6.10** |
| build | 145 | **149** |
| Sparkle | 2.9.3 | **2.9.6** |

## That the INSTALLER ran, not just that the version changed

Four independent facts, no one of which is sufficient alone:

1. **Timing.** The app was 0.6.9 at 16:03:48 local. v0.6.10 published at 16:07:57. The running
   process started at 16:18:28 - ten minutes after publication, on a bundle nobody downloaded by
   hand.
2. **The process restarted.** `ps -o lstart` gives `Mon Aug 31 16:18:28`, which is the relaunch, not
   the login session.
3. **Sparkle showed its alert.** `defaults read dev.ecn.apps.pushtext` carries
   `"NSWindow Frame SUUpdateAlert2" = "589 525 554 402 0 0 1728 1084"`. That key exists only because
   Sparkle's update dialog was displayed and its frame saved.
4. **Sparkle is checking on its own.** `SULastCheckTime = 2026-09-02 00:09:56 +0000`, matching the
   log's own check line.

**The honest limit on fact 3:** that defaults key carries no timestamp, so it proves the update alert
has been shown at *some* point, not specifically for 0.6.10. It corroborates the other three rather
than standing alone. Nobody watched the install happen - what is recorded here is its result plus
four traces it left. Observing the progress bar and the relaunch directly would have been
conclusive; that opportunity is gone until the next release.

## The TCC question, which was the real risk

A bundle swap is where Accessibility and Input Monitoring grants break, because TCC binds to the
app's designated code requirement - and the failure is invisible until the next key press.

The designated requirement is **byte-identical** across the update:

    designated => identifier "dev.ecn.apps.pushtext" and anchor apple generic
    and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
    and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
    and certificate leaf[subject.OU] = XG9SBNWNXT

**But a matching string is a prediction, not a result.** The result is that the updated app has since
performed all three permission-gated operations, in one dictation on 2026-09-01 at 20:09, hours after
the swap and with nothing re-granted:

    hotkey edge=pressed            <- event tap: Input Monitoring
    transcript chars=131 ...       <- microphone capture
    injected chars=126 ...         <- synthetic Command-V: Accessibility

That is the answer #240 asked for. Not "the requirement looks the same", but "the app did the three
things the grants gate, after the swap".

## What this does not cover

- **Delta updates.** Our appcast ships a plain zip; the delta path is still unexercised, and 2.9.5's
  symlink hardening lives there.
- **A failed or interrupted install.** Only the happy path ran.
- **The update alert appearing unprompted for THIS version**, per the limit on fact 3 above.

## Bearing on #237

v0.6.10 existed to carry Sparkle 2.9.3 -> 2.9.6. The updater that performed this install was **2.9.3**
- an app updates itself using the Sparkle it currently ships. So 2.9.6's installer code is what will
run for the *next* update, and remains unexercised here. Worth stating plainly, because "we shipped
2.9.6 and an update worked" would otherwise read as evidence about 2.9.6 that it is not.
