# DateLyrics — Lyric Backend Refactor Plan

Moving lyric timing out of Apple Music and into SpringBoard.

**Status:** proposal. Nothing here is implemented.
**Prerequisite:** the monotonic-clock fix (`amlLastResolvedElapsed`) is shipped and confirmed.

---

## 1. Summary

Today Apple Music resolves *which words are lit* on every playback tick and ships the
finished string to SpringBoard through a file, several times a second, forever.

The proposal is to invert it. Music hands over the **whole parsed song once**, plus a
small **playback anchor** whenever playback state changes. SpringBoard caches the song
and runs its own clock, resolving the active line and word locally.

| | Today | After |
|---|---|---|
| Cross-process messages | ~4/sec, continuously | ~1 per track + ~1 per play/pause/seek |
| File writes during playback | ~4/sec (atomic: temp + rename) | 0 |
| JSON parses in SpringBoard | ~4/sec | 1 per track |
| Work while screen is off | full pipeline keeps running | none |
| Line resolution cost | O(lines × words) + allocations, per tick | O(1) amortised via cursor |
| Clocks that can disagree | 2 (Music extrapolation + MediaRemote) | 1 |

That last row matters beyond performance: the glitch we just spent a session on was
caused by two clocks disagreeing by ~90ms. Under this design there is only one clock,
so that class of bug becomes structurally impossible rather than defended against.

---

## 2. Measured baseline

From `transition-debug.log`, 30.6s of playback (Minibar, syllable-timed):

```
SpringBoard label applies:      386  (12.6/sec)
  produced no visible change:    84  (22% — pure waste)
  arrived <5ms after previous:  264  (69% — duplicate bursts)
  median gap between applies:   1.0ms
actual line changes:             18  (0.6/sec)
```

Two separate problems are visible here.

**Amplification.** 69% of applies land within 5ms of the previous one, median gap 1ms.
Each payload triggers roughly 3–4 render passes, because `DateLyricsApplyCurrentLine`
`ToAllCoverSheets` walks the date views *and* calls `setNeedsLayout`, which re-enters
through `layoutSubviews`, and the `_updateLabel` / `setDate:` hooks fire too. So ~4
real payloads/sec become ~12.6 render passes/sec.

**Waste.** 22% of applies compute a full attributed string, run the split plan, and
compare — then change nothing. And the useful signal is only 18 line changes in 30
seconds.

### Where the heat comes from

Per payload, today:

| Cost | Where |
|---|---|
| O(lines × words) scan, holding `gLyricsCacheMutex` | `setElapsedTime:playbackRate:` |
| One `DateLyricsTimedLine` + N `DateLyricsTimedWord` + an `NSMutableString`, **per line, per tick** | `DateLyricsGetFilteredLine` |
| JSON serialise | `DateLyricsSerializePayload` |
| Atomic file write (temp file + rename = 2 syscalls + fsync) | `DateLyricsPublishPayload` |
| 2 × `CFNotificationCenterPostNotification` | same |
| SpringBoard wakes, reads file, JSON parses | `DateLyricsStoredPayload` |
| ×3–4: attributed string build, split plan, range maths, compare | `_amlApplyCurrentLyric` |

The `DateLyricsGetFilteredLine` allocation is the worst single item — it rebuilds a
filtered copy of *every line in the song* on *every tick*, just to decide which one is
current. That alone is most of the CPU.

**And all of this runs with the screen off.** Music keeps resolving and writing while
the phone is in your pocket. Nothing consumes it. This is likely the largest share of
the heat you're feeling, and it's free to fix.

---

## 3. Target architecture

### Producer — Apple Music

Two messages, both rare.

**A. Score** — published once per track, as soon as lyrics are parsed.
The complete timing data, already filtered and normalised so the consumer never has to
re-derive anything.

**B. Anchor** — published only when the playback timeline changes:
- play / pause
- rate change
- seek (detected as `|actual − predicted| > 0.35s`)
- track change

An anchor is a description of the timeline, not a position:
`elapsed` at `atHostTime`, advancing at `rate`. From it the consumer can compute the
position at any future instant without being told again.

Music must **not** publish on ordinary tick updates. Everything else follows from that.

### Consumer — SpringBoard

- Holds the score for the current `trackId`, in memory, with a small disk cache.
- Runs one timer, and only when *all* of: enabled, lyrics available, a date label is
  live, screen on, `rate > 0`.
- Each tick: `position = anchor.elapsed + (now − anchor.atHostTime) × anchor.rate`
- Resolves line and word using a **cursor** — since position advances monotonically,
  the next lookup starts where the last one stopped. No rescanning.
- Schedules the *next* tick for the next word boundary rather than polling at a fixed
  rate. Idle during long instrumental gaps.
- Renders only when the resolved output differs from what's on screen.

---

## 4. Wire format

```jsonc
// score — written once per track
{
  "protocol": 3,
  "kind": "score",
  "trackId": 6766751167,
  "generatedAt": 807833690.075,
  "hasWordTiming": true,
  "lines": [
    {
      "begin": 10.018,
      "end": 12.244,
      "text": "Break down the door like a bombshell",
      "words": [
        { "b": 10.018, "e": 10.290, "t": "Break", "s": "",  "bg": false },
        { "b": 10.290, "e": 10.512, "t": "down",  "s": " ", "bg": false }
        // s = separator that precedes the word, preserved so character
        // offsets reconstruct exactly. bg = background/adlib vocal.
      ]
    }
  ]
}
```

```jsonc
// anchor — written on playback state changes only
{
  "protocol": 3,
  "kind": "anchor",
  "trackId": 6766751167,
  "elapsed": 10.144,        // seconds into the track
  "rate": 1.0,              // 0.0 = paused
  "atHostTime": 41983.221,  // CLOCK_MONOTONIC_RAW seconds, NOT wall clock
  "revision": 412           // strictly increasing, for ordering
}
```

**`atHostTime` must be monotonic, not wall clock.** The current code stamps
`emittedAt` with `[NSDate date]`, which an NTP correction can move. Use
`clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)`. Both processes share the same monotonic
clock base, so the arithmetic is valid across the process boundary.

**Ordering is by `revision`, never by timestamp.** `gDateLyricsPayloadRevision` already
exists and is currently computed and never read.

### Transport

Keep the file bridge — it works and you know its failure modes. It's a poor fit for
30 messages/sec and a perfectly good fit for one per song.

- Score → `<music container>/Library/DateLyrics/score-<trackId>.json`
- Anchor → `<music container>/Library/DateLyrics/anchor.json`
- Darwin notifications: `…/score.changed` and `…/anchor.changed`

Separate files mean an anchor write can't tear a score read, and the score is written
exactly once.

Drop `com.82flex.amlyrics.*` unless you still need compatibility with something.

---

## 5. Implementation phases

Each phase should build, run, and be independently revertable. Do not start the next
until the current one is confirmed on device.

### Phase 0 — Precompute, no architecture change

Pure win, no protocol change, safe to ship alone. **Do this first** — it may reduce the
heat enough that you can decide how much of the rest you want.

1. In `ParseLyricsData`, after building `wordLines`, also build and cache the
   **adlib-filtered variant**. Store both in a per-track object keyed by
   `(storeID, showAdlibs)`.
2. Delete `DateLyricsGetFilteredLine` from the tick path entirely.
3. In `setElapsedTime:playbackRate:`, copy the line array out under the lock, then
   release it before doing any resolution work. Never hold `gLyricsCacheMutex` across
   the scan.
4. Add a cursor: remember the last resolved line index; start the next search there and
   walk forward, falling back to a full scan only when position moves backwards.

Expected: most of the Music-side CPU gone. Verify with Instruments or by feel.

### Phase 1 — Screen-off gating

Also independent, also large.

In SpringBoard, observe backlight state (`SBBacklightController` /
`com.apple.springboard.hasBlankedScreen` Darwin notification). Publish a
`consumerActive` flag that Music reads. When false, Music short-circuits at the top of
`setElapsedTime:playbackRate:` — no resolution, no publish.

This alone removes ~100% of the cost while the phone is in a pocket.

> If you only do Phases 0 and 1, you've probably solved the heat. Phases 2–4 are about
> correctness and architecture, and they're the ones that make the timing bug class
> impossible. Judge after measuring.

### Phase 2 — Score publishing (producer)

1. Define the score serialiser. Source data is already in `gWordLyricsCache` /
   `gLyricsCache`; this is mostly a `DateLyricsTimedLine` → JSON mapping.
2. Publish the score at the end of `ParseLyricsData`, once, on `gLyricsQueue`.
3. Write to `score-<trackId>.json`, post `score.changed`.
4. Keep the existing per-tick payload publishing running in parallel for now.
   SpringBoard ignores the score. Ship it. Confirm the file appears and is well-formed.

### Phase 3 — Consumer-side clock (SpringBoard)

The substantial phase.

1. **`DateLyricsScore`** — model object: array of lines, each with words, plus a
   `hasWordTiming` flag. Loaded from JSON, cached in memory by `trackId`, with a small
   LRU on disk (reuse `kDateLyricsMaxDiskCacheEntries`).
2. **`DateLyricsClock`** — holds the current anchor; `-positionAtNow` does the
   arithmetic. Single source of truth for playback position.
3. **`DateLyricsResolver`** — given a score and a position, returns
   `{lineIndex, text, activeRange, backgroundRange, focusRange, started, finished}`.
   This is the logic currently inlined in `setElapsedTime:playbackRate:`
   (~180 lines). Lift it as-is, but as a pure function over a cursor.
   *It should have no dependency on UIKit or on any global.* That makes it testable
   off-device, which nothing in this codebase currently is.
4. **`DateLyricsTicker`** — schedules the next wake for the next word boundary
   (`min(nextWordStart, nextLineStart, currentLineExpiry)`), clamped to ~1s.
   `dispatch_source_timer` on the main queue. Runs only when:
   `enabled ∧ scoreLoaded ∧ rate > 0 ∧ screenOn ∧ dateLabelLive`.
5. Feed the resolver's output into the existing `_amlApplyCurrentLyric` path by
   building the same payload dictionary it already consumes. **Do not touch the
   rendering code in this phase.** Same input shape, different producer.
6. Behind a preference (`UseLocalTiming`, default off) so you can A/B on device without
   reinstalling.

### Phase 4 — Anchor publishing, and deletions

1. Music: replace per-tick publishing with anchor-only. Publish when `rate` changes, on
   track change, or when `|elapsed − predicted| > 0.35s`.
2. Flip `UseLocalTiming` to on by default.
3. Delete, once confirmed:
   - the per-tick payload path in `setElapsedTime:playbackRate:`
   - `DateLyricsPersistCurrentLineSharedState`, `kDateLyricsBridgeFilePath`,
     `kDateLyricsCurrentLineKey` — **already dead today**, nothing writes them
   - the prefs branch of `DateLyricsStoredPayload`
   - `kDateLyricsPayloadFreshnessWindow` and `DateLyricsPayloadIsFresh` — freshness
     stops being a concept when the consumer owns the clock
   - `DateLyricsSchedulePayloadExpiry` and its one-`dispatch_after`-per-payload
   - `amlTimer` / `amlPauseTimer` and `calculatedElapsedTime` — the extrapolation that
     caused the 90ms bounce
   - `amlLastResolvedElapsed` and the monotonic clamp — no longer needed, since the
     two clocks it reconciled no longer both exist

---

## 6. Correctness requirements

These are the cases that will bite. Each needs an explicit decision, and most map to a
bug already hit this session.

| Case | Required behaviour |
|---|---|
| **Lyrics arrive after playback starts** | Score published mid-song. Consumer must jump straight to the correct line for the current position, no animation. |
| **Track changes before score arrives** | Consumer clears immediately on `trackId` mismatch. Never render one song's lyrics against another's clock — check `trackId` on *every* resolve. |
| **Seek** | Anchor with a large delta. Consumer must reset its cursor and allow backwards movement. Contrast with the ≤1s jitter that must be ignored. |
| **Pause** | `rate = 0`. Ticker stops; last line stays visible for `PauseTimeout`, then clears. Position must not advance. |
| **Scrubbing** | Anchors may arrive in bursts. Coalesce — apply only the newest by `revision`. |
| **Screen off mid-song** | Ticker stops. On wake, recompute from the anchor; do not replay. |
| **Respring mid-song** | Consumer has no anchor. Either request one (Darwin ping Music) or wait for the next state change. **Decide this** — otherwise lyrics stay blank until the user pauses. Recommend: Music re-publishes its anchor on receiving `…/anchor.request`. |
| **Music killed** | Anchor goes stale with no notification. Consumer needs a liveness rule — if `rate > 0` and no anchor for >30s, clear. |
| **Clock jitter ≤1s** | Ignore (this session's bug). Under the new design only one clock exists, so this should be impossible — but assert it in debug rather than assuming. |
| **Two date views** | Both resolve from the same clock, so they stay in sync automatically. Today they each independently read the payload. |

---

## 7. Verification

The resolver being a pure function is the point of this refactor beyond performance —
it's the first piece of this codebase that can be tested without a phone.

1. **Off-device unit tests.** Compile `DateLyricsResolver` for macOS. Feed it the
   `syllable-lyrics_6766751167.xml` you already have, step position in 10ms increments
   across the whole song, and assert:
   - the resolved line index never decreases
   - every line is reached
   - `activeRange` is always within `text.length`
   - no gap where a line is active but no line is resolved, except real instrumental gaps
2. **Regression for this session's bug.** Feed positions that jump backwards by 90ms
   across a line boundary. Assert the resolved line does not revert.
3. **On-device A/B.** `UseLocalTiming` off vs on, same song, compare
   `transition-debug.log`. Success = same 18 line changes, no reverts, and the apply
   count down from ~386 to under 100.
4. **Thermals.** Play a full album screen-off, before and after. This is the number you
   actually care about.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Consumer clock drifts from real audio | Anchor on every rate change; add a low-rate sanity anchor (~every 30s) if drift is measurable. Cheap insurance, still 100× less traffic than today. |
| Score JSON is large for long songs | ~20KB for Minibar. Written once. Fine. Compress only if a real problem appears. |
| Regression in an edge case above | Phases 3–4 behind `UseLocalTiming`. Keep the old path until confident. |
| Half-finished refactor left in tree | Phases 0 and 1 are standalone wins. If you stop after them, nothing is left inconsistent. |
| Monotonic clock base differs across processes | `CLOCK_MONOTONIC_RAW` is system-wide on iOS. Verify once in Phase 2 by logging both sides. |

---

## 9. Recommended order

1. **Phase 0** — precompute + cursor + don't hold the lock. Biggest CPU win, smallest diff.
2. **Phase 1** — screen-off gating. Biggest battery/heat win, tiny diff.
3. *Measure.* Decide whether 2–4 are still worth it.
4. **Phase 2** → **3** → **4**, one at a time, each confirmed on device.

Phases 0 and 1 together are perhaps 150 lines changed and should address the heat.
Everything after is architecture: it makes the code testable and makes a whole class of
timing bug impossible. Worth doing, but not urgent, and not something to start while
another bug is open.

---

## 10. Also worth folding in

Not part of this refactor, but they touch the same code and are cheap while you're there:

- **The 3–4× render amplification** (§2). Independent of the backend — it's
  `setNeedsLayout` in `DateLyricsApplyCurrentLineToAllCoverSheets` re-entering through
  `layoutSubviews`. Worth attacking separately; it's a ~3× reduction in SpringBoard-side
  work for a very small change, but it needs care, as removing that `setNeedsLayout`
  once already changed rendering behaviour.
- **§5.9 in `AUDIT.md`** — the highlight renderer exists three times (tweak, prefs root
  controller, font controller) and has already drifted. If the resolver becomes a shared
  pure function, the renderer should follow.
- **Remove the debug logging** (`DateLyricsDebugLog`, `DebugLogging` pref) once you're
  done with it — or keep it behind a default-off pref, since it just paid for itself.
