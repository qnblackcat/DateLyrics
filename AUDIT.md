# DateLyrics — Code Audit

> **Status:** the items marked ✅ below were changed in the working tree (uncommitted).
> The earlier audit was written before Theos was available; the latest follow-up pass has now
> been compiled successfully for arm64/arm64e.
>
> Fixed: §1.1 ✅ · §1.3 ✅ · §1.5 ✅ · §1.6 ✅ · §4.1 ✅ · §4.3 ✅ · §4.8 ✅ ·
> §5.2 ✅ · §5.3 ✅ · §5.4 ✅ · §6.1 ✅

## 2026-08-08 follow-up

The current working tree has also been compiled successfully for arm64/arm64e with the rootless
Theos package target. The lyric-ingestion path now rejects transcript-only TTML (`itunes:timing="None"`),
rejects all-zero/malformed serialized scores, removes stale memory/disk scores, and suppresses retries
for a known transcript-only Adam ID. SpringBoard clears an active score when its score file disappears.

Paused position changes now publish anchors even for fine scrubs, and meaningful backward paused scrubs
are marked as explicit seeks. Split-line plans are track-scoped and may move backward on a real seek;
normal playback remains monotonic to avoid the old segment-0 snap-back. Debug logging is opt-in again.

The package produced from this pass is `DateLyrics-2.2.1-unsynced-lyrics-filter-v3.deb` in the iCloud
Drive root. The items below that describe the old payload/heartbeat pipeline should be read as historical
notes; the active path is now the Music → anchor/score files → SpringBoard local ticker pipeline.

## 2026-08-08 low-overhead cleanup

The active tree was trimmed without changing the lyric protocol: removed the no-op
`MPNowPlayingInfoCenter` hook and unused MediaRemote declarations, removed the permanently enabled
`UseLocalTiming` branch and the old current-line bridge reset notifications from Preferences. The
`PauseTimeout` control is now a real pause-only timer again: it keeps the last active lyric visible
for the selected delay, then restores the stock date. Widget host discovery is now cached while the host remains
in the view subtree, repeated widget hidden-state writes are guarded, and the Split Long Lines preference
no longer recursively calls the controller to disable ad-libs. The package built successfully for
arm64/arm64e after these changes. SpringBoard now caches a rendered payload per label, invalidating
it on track/payload/preference/system-label changes, so ordinary UIKit layout passes do not rebuild
the same attributed string. The Music request-session handoff and transcript-only negative cache are
also serialized to avoid cross-callback races.

The stock date is shown before the first timed line of a song and whenever a track has no usable score
(including transcript-only/unsupported tracks). Once the first lyric has appeared, normal playback keeps
that last lyric through later instrumental/timing gaps; the date no longer slips back into the lyric slot.
The separate `PauseTimeout` setting still controls what happens after an actual pause.

### Attempted and reverted: snapshot-based line transitions
>
> A rewrite that animated the outgoing line inside a throwaway clipped container
> was tried and **backed out** — on device it left up to four copies of the same
> line on screen at once, far worse than the original occasional glitch.
>
> Why it failed: it inserted a real sibling view into SpringBoard's private date
> view hierarchy. The `_UIAnimatingLabel` is not necessarily a direct child of
> `CSProminentSubtitleDateView`, so the container was parented to whatever internal
> view happened to be in between, and any superseded or non-firing animation left
> its copy behind permanently. Nothing in the teardown path could reliably find
> orphans. **Do not reintroduce extra views into that hierarchy.**
>
> The transition still uses the proven `CATransition` path; reverse seeks now select the
> opposite direction, while the two narrow guards below prevent mid-flight geometry/content races.
> Two narrow guards were kept, both of which only ever *skip* work:
> - `layoutSubviews` will not resize or repaint the label while a transition runs.
> - Syllable updates arriving mid-transition are coalesced into one pending flag
>   rather than repainting, and no longer corrupt `previousDisplayText` when deferred.
>
> ### Root cause of the glitching: Split Long Lines (§4.11, now fixed)
>
> Confirmed on device — the glitch largely disappears with Split Long Lines off.
> Three compounding bugs in `DateLyricsSplitPayloadForLabel`, all fixed:
>
> 1. **Runaway width feedback loop.** Wrap width came from `label.bounds`, but a
>    UILabel's width follows its content. Showing a short segment shrank the label,
>    which re-segmented the line against the smaller width, which selected a
>    different segment, which resized the label again. `CSProminentSubtitleDateView`
>    turned out to hug its content too, which produced a second variant of the same
>    bug: a long line arriving after a short one was wrapped against the leftover
>    narrow width, then re-wrapped when the date view grew — two transitions
>    back to back. The wrap width is now **latched and grow-only**, measured from the
>    date view and capped at screen width, so it becomes constant after the first
>    reading.
> 2. **Re-segmented every tick.** The whole word-wrap was recomputed at syllable
>    rate, so any measurement jitter produced a different segment mid-line, read as
>    a line change, and fired another transition. Now computed once per line and
>    cached in a `DateLyricsSplitPlan` on the label (including a negative result, so
>    short lines aren't re-measured either).
> 3. **Snapped back to segment 0 in timing gaps.** With no active word — line start,
>    instrumental pauses, after the final word — the target index fell back to 0. A
>    long line would advance to segment 2, jump back to segment 0, then advance
>    again. Segment index is now monotonic within a line and resets on `lineId`.
>
> This is a reasoned diagnosis from the code, not a verified one — it has not been
> run on a device.
>
> The same three bugs exist in the preferences preview
> (`amlSegmentIndexForLine:word:` and `amlAttributedTextForLine:word:`), which is
> the third copy of this logic. Left alone for now because its label lives in a
> fixed-size 200×44 title view, so the width loop can't run away there. §5.9 is the
> real fix.

Scope: `DateLyrics.xm` (2440 LOC), `DateLyricsPrefs/DateLyricsRootListController.m` (1413 LOC),
`Makefile`, `control`, `layout/DEBIAN/*`, `DateLyricsPrefs/Resources/Root.plist`.

Severity: **P0** = broken / crashes / data race · **P1** = wrong behavior or perf on hot path ·
**P2** = fragility, duplication, cleanup.

---

## 1. Packaging & rootless

### 1.1 (P0) The permission fix is a symptom patch, not a cause fix
`layout/DEBIAN/postinst` chmods files at install time. The real cause is that the **staging tree**
is produced with a restrictive umask, so every file lands 600/700 inside the `.deb`. Every future
build reintroduces it, and `postinst` only covers the paths it happens to list.

*Fix:* add a staging hook to the top-level `Makefile` so the archive is correct by construction:

```make
before-package::
	@find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR) -type f -exec chmod 644 {} +
	@chmod 755 $(THEOS_STAGING_DIR)/Library/PreferenceBundles/DateLyricsPrefs.bundle/DateLyricsPrefs
	@chmod 755 $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/DateLyrics.dylib
```
Keep `postinst` as a safety net for upgrades over already-broken installs, then delete it in ~2 releases.

### 1.2 (P0) `postinst` misses the two executables
It chmods plists, pngs and `preview.xml` but never the tweak dylib
(`.../DynamicLibraries/DateLyrics.dylib`) or the prefs bundle binary
(`DateLyricsPrefs.bundle/DateLyricsPrefs`). If the umask bug hit those too, ElleKit can't `dlopen`
the tweak and Preferences can't load the bundle principal class — which is exactly the `(null)`
error signature.

*Fix:* add both to `postinst` at `755` / `644` respectively, or rely on 1.1.

### 1.3 (P0) `postrm` shebang doesn't exist on a rootless jailbreak
`layout/DEBIAN/postrm` starts with `#!/bin/bash`. There is no `/bin/bash` on rootless iOS — the
script fails silently on every uninstall, so nothing is ever cleaned up.

*Fix:* `#!/bin/sh` and replace the bash-isms (`[ "$1" == ... ]` → `=`).

### 1.4 (P1) `/var/jb` is hardcoded
`postinst` and `DateLyricsReloadPrefs` both hardcode `/var/jb`. Breaks on roothide (randomized
prefix) and on rootful.

*Fix:* in `postinst` derive the prefix from the script's own location or `$THEOS_PACKAGE_INSTALL_PREFIX`;
in the tweak, use `_dyld_get_image_name()` / `jbroot()` rather than a literal path (and see 5.1 —
you shouldn't be reading the plist by path at all).

### 1.5 (P1) `Version: 2.2` never changes between rebuilds
Every one of the five debs you shipped was `2.2`. Sileo/Zebra treat that as "already installed" and
may skip the install entirely — which is why "fixed" packages appeared not to fix anything.

*Fix:* bump to `2.2.1`, `2.2.2`, … per build, or append `+$(date +%s)` in CI.

### 1.6 (P2) `Depends:` is rootful-flavored
`mobilesubstrate (>= 0.9.5000)` — on Dopamine the provider is `ellekit`.
*Fix:* `Depends: ellekit | mobilesubstrate, preferenceloader, firmware (>= 16.0)`.

### 1.7 (P2) `postrm` walks every app container and `rm -rf`s
Guarded by a `grep` for `"source":"music"`, but it iterates all of
`/var/mobile/Containers/Data/Application/*`. One bad quote away from a very bad day.
*Fix:* resolve the Music container once via `uicache`/`lsappinfo` or just leave the container
directory alone (it dies with the app).

---

## 2. The IPC layer is mostly dead code

### 2.1 (P0) Two of the three transport channels are never written
`DateLyricsPublishPayload()` branches on host:

- SpringBoard → `DateLyricsPersistCurrentLineSharedState()` (bridge file + `CFPreferences[CurrentLyricLine]`)
- otherwise → write to the **local container** path

But every call site of `DateLyricsPublishPayload` lives in `%group DateLyricsPrimary`, which is only
`%init`'d in the **Music** process. So the SpringBoard branch is unreachable: the bridge file at
`/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.current-line.txt` and the
`CurrentLyricLine` preference are **never written by anything**. SpringBoard's
`DateLyricsStoredPayload()` reads three sources of which two are permanently empty.

The tweak works only because `DateLyricsReadPayloadFromMusicContainer()` happens to succeed. Any
change to Music's container path, or SpringBoard losing read access to it, silently kills the tweak
with no fallback — despite there appearing to be two.

*Fix:* pick one channel and delete the other two. Recommended: keep the Music-container file as the
payload store (it's the only one that works) **or** move to a proper channel:
`CPDistributedMessagingCenter` / `NSDistributedNotificationCenter` userInfo, which avoids disk
entirely. Then delete `DateLyricsPersistCurrentLineSharedState`, `kDateLyricsBridgeFilePath`,
`kDateLyricsCurrentLineKey`, and the prefs-read branch of `DateLyricsStoredPayload`.

### 2.2 (P1) Freshness is wall-clock based
`DateLyricsPayloadIsFresh` compares `emittedAt` against `[NSDate date]` with a 6 s window. A clock
adjustment (NTP sync, timezone/DST, user setting the clock) makes every payload permanently stale →
lyrics vanish until the next publish. `gDateLyricsPayloadRevision` already exists for exactly this
purpose and is **never read**.

*Fix:* stamp with `mach_absolute_time()` / `CLOCK_MONOTONIC_RAW` and order by `revision`.

### 2.3 (P1) Disk write per syllable
`DateLyricsPublishPayload` does an atomic `writeToFile:` (tempfile + rename) on **every** payload
change — several times per second during a fast verse — on the media-serving thread. Plus a
`CFNotificationCenterPostNotification` ×2 each time.

*Fix:* coalesce. Publish at most every ~80 ms via a `dispatch_source_timer` on `gLyricsQueue`, and
drop the duplicate legacy `com.82flex.amlyrics.*` notification unless you still need compat.

### 2.4 (P1) One `dispatch_after` per payload for expiry
`DateLyricsSchedulePayloadExpiry` schedules a 6.2 s block for every payload received. At syllable
rate that's ~30 live blocks at all times, each capturing and re-checking global state.

*Fix:* a single re-armable `dispatch_source_t` that you `dispatch_source_set_timer` forward on each
new payload.

### 2.5 (P1) Synchronous file I/O from `layoutSubviews`
`DateLyricsCurrentRenderablePayload()` → `DateLyricsStoredPayload()` → three file reads + a
`CFPreferencesCopyAppValue`, reachable from `CSProminentSubtitleDateView -layoutSubviews` and
`_amlApplyCurrentLyric`. That's disk I/O on SpringBoard's layout path.

*Fix:* only ever read from the in-memory `gDateLyricsCurrentPayload`, which the Darwin-notification
handler refreshes. Never touch the filesystem from a render path.

---

## 3. Music-side hot path

### 3.1 (P0) `NSTimer` scheduled from an arbitrary thread
`-setElapsedTime:playbackRate:` creates `amlTimer` / `amlPauseTimer` with
`scheduledTimerWithTimeInterval:` — which installs on the **calling thread's** run loop. This hook
is called from MediaRemote's delivery thread, which may have no run loop running. When that happens
the timer never fires and lyrics freeze mid-line until the next natural `setElapsedTime:` call.
This is the most likely cause of the intermittent "it just stops" behavior.

*Fix:* replace both timers with `dispatch_source_t` on a dedicated serial queue, or at minimum
`dispatch_async(dispatch_get_main_queue(), …)` around timer creation and add the timer to
`NSRunLoopCommonModes`.

### 3.2 (P0) `pthread_mutex_t` held across a full O(lines × words) scan
Lines 1466–1643 hold `gLyricsCacheMutex` while iterating the entire word-timed lyric set, calling
`DateLyricsGetFilteredLine()` (which allocates a new `DateLyricsTimedLine`, N `DateLyricsTimedWord`s
and a rebuilt `NSMutableString` **per line, per tick**), then also scanning the flat line cache.
A plain pthread mutex has no priority inheritance, so a background parse can block the audio thread.

*Fix, two parts:*
1. Precompute the filtered/adlib-stripped variant **once at parse time** and store both variants in
   the cache keyed by `(storeID, showAdlibs)`. `DateLyricsGetFilteredLine` should not exist on the
   tick path.
2. Replace the mutex with `dispatch_queue` + `dispatch_sync`, or `os_unfair_lock`, and copy the
   line array out under the lock before doing any work on it.

### 3.3 (P1) The word-scan loop is a 180-line inline block
`setElapsedTime:playbackRate:` is ~290 lines with ~20 local accumulators tracking
foreground/background × active/previous/next × range/segment/time. It is very hard to reason about
and is the highest-churn code in the project.

*Fix:* extract a value type:
```objc
typedef struct { NSRange active, trail, focus; NSTimeInterval nextStart; BOOL started, finished; } DLLineState;
static DLLineState DLResolveLineState(DateLyricsTimedLine *line, NSTimeInterval t, BOOL background);
```
Call it twice (fg/bg) and merge. Unit-testable in isolation.

### 3.4 (P1) Session/context captured once, never refreshed
`gSession` and `gRequestContext` are latched from the first `ICURLSession` seen and held as strong
globals forever. If that session is invalidated or the request context's token expires, every
subsequent lyric fetch fails permanently with no recovery.

*Fix:* refresh both on each `enqueueDataRequest:` hook call, and drop the queue's in-flight task
back to pending if `enqueueDataRequest` returns an auth error.

### 3.5 (P1) No HTTP status inspection
The completion handler only checks `error != nil` and whether the body parses. A `401`/`403`
(expired token, no active subscription) is indistinguishable from a malformed TTML — it burns
3 retries with exponential backoff, then gives up.

*Fix:* read the status off `ICURLResponse`; do not retry 4xx, do retry 5xx/timeouts.

### 3.6 (P1) Storefront is derived from device region
`DateLyricsStorefront()` returns `[NSLocale currentLocale].countryCode`. A user in Germany with a US
Apple Music account gets `de` and a 404 on every song.

*Fix:* read the storefront from the `ICMusicKitRequestContext` you already captured, or from
`SSAccountStore`/`ICUserIdentityStore`; fall back to locale only if unavailable.

### 3.7 (P2) `ParseLyricsData` re-enters the hook
On success it dispatches to main and calls `[gCurrentContentItem setElapsedTime:…]`, which is the
hooked method — re-running the entire resolve path and rescheduling timers, from inside a parse
completion.

*Fix:* factor the "recompute and publish" body into a `%new` method and call *that* instead of
round-tripping through the hooked setter.

### 3.8 (P2) `AMCrashPatcher` no-ops a real system call
`%hook VSSubscriptionRegistrationCenter -registerSubscription:` returns unconditionally on iOS < 17.
That silently breaks subscription registration for anything else in the Music process. It reads like
a leftover from a different tweak.

*Fix:* delete it, or scope it to the specific crashing call site with a comment explaining the crash
it works around.

---

## 4. SpringBoard rendering

### 4.1 (P0) Ancestor walk on every `_UIAnimatingLabel` text set
`%hook _UIAnimatingLabel -setText:` / `-setAttributedText:` call
`DateLyricsFindAncestorDateView(self)` — an unbounded superview walk — on **every** text assignment
to **every** `_UIAnimatingLabel` in SpringBoard. That class is used well beyond the lock screen
(clock, status bar, transient UI). System-wide tax on a very hot setter.

*Fix:* tag the one label you care about once, when the date view finds it:
`objc_setAssociatedObject(label, kIsDateLyricsLabel, @YES, RETAIN)`, then the hook is a single
associated-object lookup and an early return.

### 4.2 (P1) `setText:` swallows `%orig`
When the label is the date label and not showing a lyric, `setText:` converts to an attributed
string, assigns `self.attributedText` (re-entering the *other* hook), and **returns without calling
`%orig`**. `_UIAnimatingLabel`'s animation machinery may depend on internal state set by `setText:`;
skipping it is likely why stock date transitions look off.

*Fix:* call `%orig` first, then apply the stroke-clearing attribute, or better — stop intercepting
these setters entirely and clear the stroke in `_amlApplyCurrentLyric` / the restore path only.

### 4.3 (P1) Recursive subview search per layout pass
`DateLyricsFindAnimatingLabel` recurses the whole date-view subtree on every `layoutSubviews`,
`didMoveToWindow`, `_updateLabel`, `setDate:`, and every payload change ×N views.

*Fix:* cache the found label on the date view as a weak associated object; invalidate in
`didMoveToWindow`.

### 4.4 (P1) Layout feedback loop
`-layoutSubviews` sets `label.frame` and then calls `_amlApplyCurrentLyric`, which sets
`attributedText`, which dirties layout, which schedules another `layoutSubviews`. Only the
`contentChanged` guard prevents a hard loop.

*Fix:* do content updates from the payload notification only; in `layoutSubviews` do geometry only.

### 4.5 (P1) Twelve associated objects as a state machine
`kDateLyricsOriginal{Font,TextColor,NumberOfLines,AdjustsFontSize,MinScale,LineBreakMode,ClipsToBounds,AttributedText,Text,Hidden}`
plus `ShowingLyric`, `AnimatingTransition`, `TransitionGeneration`, `ForcedWidgetDateVisible`,
`RestoringStockDate`. Saved and restored individually, with no atomicity. If any path exits early
(view recycled, respring mid-transition, `dateView == nil` at line 1900), you get a partially
restored label — the "date disappears / wrong font sticks" family of bugs. Also
`kDateLyricsOriginalHiddenKey` is overloaded for both the date view and unrelated widget slots.

*Fix:* one `DateLyricsLabelState` object holding all originals + a `restored` flag, attached as a
single associated object, with `-capture:` / `-restoreInto:` methods. Restore becomes all-or-nothing.

### 4.6 (P1) Restored date text is stale
`DateLyricsRestoreSystemDateLabel` writes back `kDateLyricsOriginalAttributedTextKey`, captured when
lyrics *started* — potentially hours earlier, so it can restore yesterday's date. It calls
`_updateLabel` afterwards but only `if respondsToSelector:`.

*Fix:* don't snapshot the text at all. Restore the styling, then unconditionally ask the date view
to regenerate (`_updateLabel`, `setDate:` with the current date, or `setNeedsLayout` after clearing).

### 4.7 (P1) Widget-slot matching by frame intersection
`DateLyricsWidgetSlotMatchesDateSlot` decides which `CSProminentEmptyElementView` to hide using a
±4 pt vertical overlap test. On iPad, StandBy, landscape, or a different widget arrangement this
will hide the wrong widget or none.

*Fix:* walk the actual view-hierarchy relationship (shared superview + index adjacency, or the
lock-screen layout's own slot identifier) rather than geometry. At minimum, bail out entirely when
more than one candidate matches.

### 4.8 (P1) Uppercase highlight can change string length
Highlight style 1 does `replaceCharactersInRange:withString:[s uppercaseString]`. `ß` → `SS`,
Turkish `i` → `İ` under some locales: the replacement is longer than the range, shifting every
subsequent index. The descending sort mitigates the two-range case but the payload's own `loc/len`
are now wrong for anything downstream (split-line math, the next tick's comparison).

*Fix:* use `uppercaseStringWithLocale:` and verify `result.length == range.length`; if not, skip the
transform for that range (or switch the Caps style to a font-variant small-caps attribute, which
doesn't touch the string at all).

### 4.9 (P1) Parenthesis stripping happens after ranges are computed
The line-level fallback path builds ranges against the **unstripped** text, then
`_amlApplyCurrentLyric` calls `DateLyricsStripParentheses` and only *drops* ranges that no longer
fit. Ranges that still fit numerically now point at the **wrong words** — silent misalignment.

*Fix:* strip once at parse time and compute all ranges against the stripped text (the word-timed
path already does this correctly in `DateLyricsGetFilteredLine`; make the line path match).

### 4.10 (P2) `ShowAdlibs` is force-disabled by `SplitLongLines`
`DateLyricsReloadPrefs` line 2371: if `SplitLongLines` is on, `gDateLyricsShowAdlibs = NO`
regardless of the user's setting. The prefs pane greys the toggle to match, but the coupling is
unexplained and surprising.

*Fix:* either make the dependency explicit in the UI footer text, or fix the split math to handle
background words and drop the coupling.

### 4.11 (P2) Sticky split segment
`DateLyricsSplitPayloadForLabel` remembers the last shown segment index per label keyed only by the
line text. Two songs with an identical line, or a repeated chorus line, resume at the wrong segment.
No invalidation on `trackId` change.

*Fix:* key the memo on `payload[@"trackId"]` + `payload[@"lineId"]`.

### 4.12 (P2) No iOS 18+ guard
`CSProminentSubtitleDateView` / `CSProminentEmptyElementView` are 16/17-era classes. On a newer OS
the hooks bind to nothing and the tweak is silently inert. `runtime-status.json` records this but
nobody reads it.

*Fix:* if the classes are missing, log once via `os_log` with a clear message so bug reports are
actionable.

---

## 5. Preferences

### 5.1 (P0) Three different ways to read the same preference
- Tweak: `CFPreferencesCopyAppValue`, **then** a hand-read of `/var/jb/var/mobile/Library/Preferences/…plist`, **then** `/var/mobile/…plist`
- Prefs bundle read: `NSUserDefaults initWithSuiteName:`
- Prefs bundle write: `NSUserDefaults` **and** `CFPreferencesSetAppValue` (see `HighlightStyle`/`HighlightTrail` at lines 894–903)

These layers cache independently. cfprefsd can hand back a value the on-disk plist doesn't have yet,
and vice versa. This is the classic "I changed the setting and nothing happened" bug.

*Fix:* one accessor, everywhere:
`CFPreferencesCopyValue(key, suite, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` for reads and
`CFPreferencesSetValue` + `CFPreferencesSynchronize` for writes. Delete both hardcoded plist paths.
Wrap it in a small `DLPrefs` shim shared by both targets.

### 5.2 (P0) UIKit drawing off the main thread
`fetchGithubLogo`'s completion block (a URLSession background thread) calls `[UIScreen mainScreen].scale`,
`UIGraphicsBeginImageContextWithOptions`, `[layer renderInContext:]`, and constructs a `UIImageView`.
All main-thread-only. Undefined behavior; crashes under Main Thread Checker.

*Fix:* hop to main before any UIKit work, or better: drop the network fetch entirely and ship the
GitHub icon as a bundle resource.

### 5.3 (P0) `_cachedGithubIcon` data race
Static `UIImage *`, written from the URLSession thread, read from `-specifiers` and
`-tableView:cellForRowAtIndexPath:` on main, no synchronization or `atomic`.

*Fix:* falls out of 5.2 — assign it on main only.

### 5.4 (P1) `resetSettings` clears the wrong container
`NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, …)` inside the prefs bundle resolves to
**Preferences.app's** container. So "Reset Settings" deletes a `Library/DateLyrics` directory that
never existed, and leaves SpringBoard's and Music's real caches untouched. (It does correctly clear
the Music container via `LSApplicationProxy`, and the two bridge files — which per §2.1 are unused.)

*Fix:* delete the Music container path (already done) and post a Darwin notification that
SpringBoard/Music handle by clearing their own `GetLyricsRootPath()`. A process can only reliably
clear its own container.

### 5.5 (P1) `setPreferenceValue:` recurses into itself
The `SplitLongLines` branch calls `[self setPreferenceValue:@NO specifier:adlibsSpec]`, and both
branches then hit `_specifiers = nil; [self reloadSpecifiers];` — mutating the specifier array while
PreferenceSpecifiers is still holding the specifier that triggered the call.

*Fix:* never recurse; write the dependent default directly to prefs and let the reload pick it up.
Defer the reload: `dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; })`.

### 5.6 (P1) Two competing visibility mechanisms
`Root.plist` uses `requires` for `HighlightStyle`, `StrokeWidth`, `HighlightTrail`,
`TransitionStyle`, `TransitionDuration`, `CustomFontName` — *and* `-specifiers` removes the same
specifiers by index and separately sets an `enabled` property on some. Three overlapping systems
fighting over the same rows produces the gaps and stale rows in the pane.

*Fix:* pick `requires` (declarative, PreferenceLoader handles reloads) and delete the manual
`indexesOfObjectsPassingTest:` removal block entirely.

### 5.7 (P1) `posix_spawn` from a sandboxed prefs bundle, no `waitpid`
`respring` and `amlKillMusic` spawn `sbreload`/`killall`. Preferences.app is sandboxed; unless the
jailbreak unsandboxes prefs bundles these fail. Nothing is reported to the user — the button just
does nothing. No `waitpid` either, so successful spawns leave zombies.

*Fix:* check the `posix_spawn` return, `waitpid` for the exit status, and surface a `UIAlertController`
on failure ("Couldn't respring — do it manually"). Or route through `SBSRelaunchAction` /
`FBSSystemService`, which is the supported path from a sandboxed process.

### 5.8 (P1) Preview animation runs at 20 Hz
Both preview controllers run an `NSTimer` at `0.05` s that rebuilds an `NSAttributedString`, re-reads
**all** preferences via `DateLyricsCurrentPrefs()` (a fresh `NSUserDefaults` instance each call), and
runs `sizeWithAttributes:` measurement passes — the whole time the pane is open.

*Fix:* drop to ~10 Hz, hoist the prefs read out of the tick (cache, invalidate on
`setPreferenceValue:`), and use `CADisplayLink` so it pauses with the display.

### 5.9 (P2) The highlight renderer exists three times
`_amlApplyCurrentLyric` (tweak), `-amlAttributedTextForLine:word:` (root controller), and
`-amlUpdatePreviewLabel` (font controller) each independently implement dim/stroke/caps + trail +
adlib filtering + line splitting. They have already drifted (the tweak clamps out-of-bounds ranges,
the prefs copies don't; the font controller ignores `SplitLongLines` entirely). The split-line
segmentation logic alone is copy-pasted three times (`DateLyricsSplitPayloadForLabel`,
`amlSegmentIndexForLine:word:`, and inline in `amlAttributedTextForLine:`).

*Fix:* extract a shared `DateLyricsRenderer.{h,m}` compiled into both targets:
```objc
@interface DLRenderer : NSObject
+ (NSAttributedString *)attributedTextForLine:(NSString *)text
                                 activeRange:(NSRange)active
                             backgroundRange:(NSRange)bg
                                       style:(DLRenderStyle)style
                                   baseColor:(UIColor *)color;
+ (NSArray<NSValue *> *)segmentRangesForText:(NSString *)text font:(UIFont *)f maxWidth:(CGFloat)w;
@end
```
This is the single highest-value refactor in the project — it collapses ~700 duplicated lines and
guarantees the preview matches the lock screen.

### 5.10 (P2) Timers retain their controllers
`scheduledTimerWithTimeInterval:target:self:` in both controllers. Invalidated in
`viewWillDisappear:`, but `startPreviewAnimation` is also called from `setPreferenceValue:`, and
there's no `dealloc` safety net.
*Fix:* block-based timers with `__weak typeof(self)`, plus `[self stopPreviewAnimation]` in `dealloc`.

---

## 6. Smaller cleanups

| # | Location | Issue |
|---|---|---|
| 6.1 | `DateLyrics.xm:1681` | `[payload copy] ? [[payload copy] mutableCopy] : …` — three copies, the ternary is always true. Use `[payload mutableCopy]`. |
| 6.2 | `DateLyricsMakePayloadWithBackgroundRange` | Relies on `nil.count == 0` to propagate nil. Works by accident; make it explicit. |
| 6.3 | `%ctor` | `CFNotificationCenterAddObserver` with `NULL` observer — can never be removed. Pass a unique sentinel pointer and add a `%dtor`. |
| 6.4 | `gDateLyricsPayloadRevision` | Computed, published, never read. Either use it (see 2.2) or delete it. |
| 6.5 | `DateLyricsFinishLabelTransitionAfterDelay` | Calls `[label _amlApplyCurrentLyric]`, a `%new` method only added when `DateLyricsSpringBoard` is `%init`'d. Currently unreachable from Music, but it's an unrecognized-selector crash waiting for a refactor. Guard with `respondsToSelector:`. |
| 6.6 | `DateLyricsFindSiblingDateView` | Uses `NSClassFromString` result without a nil check before `isKindOfClass:` (harmless — `isKindOfClass:nil` is NO — but inconsistent with the other helpers, which do check). |
| 6.7 | `DateLyricsPruneDiskCache` | Runs a full directory listing + `stat` per entry after **every** successful download. Prune every Nth write or on a timer. |
| 6.8 | `Makefile` | `INSTALL_TARGET_PROCESSES = Music SpringBoard` respawns SpringBoard on every `make do` — fine for dev, but consider a separate `make package` target. |
| 6.9 | `DateLyrics.plist` filter | Only `com.apple.Music` and `com.apple.springboard`, yet `%ctor` has an `else` for "other" hosts and `DateLyricsWriteRuntimeStatus` records `@"other"`. Dead branch. |
| 6.10 | `.gitignore` | `reference/` is ignored but present in the tree; confirm nothing needed is being lost on clone. |

---

## Suggested order of work

**Ship first (unblocks everything else):**
1. §1.5 version bumping — otherwise you can't tell whether a fix landed.
2. §1.1 + §1.2 build-time permissions — makes `postinst` unnecessary.
3. §1.3 `postrm` shebang.

**Then the correctness bugs:**
4. §3.1 timers off the run loop — most likely cause of the freezes you're still seeing.
5. §5.1 single preference accessor — most likely cause of settings not applying.
6. §2.1 delete the two dead IPC channels.
7. §5.2/§5.3 UIKit off-main in `fetchGithubLogo`.

**Then the refactors:**
8. §5.9 shared `DLRenderer` (biggest win, ~700 lines deduped).
9. §4.5 single label-state object.
10. §3.2 + §3.3 precompute filtered lines, extract `DLResolveLineState`.
11. §5.6 delete the manual specifier-removal block.
