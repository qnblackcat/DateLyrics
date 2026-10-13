# Code structure

All implementation files (`.xm` and `.m`) live in the repository root and are
compiled by the wildcard in the top-level Makefile.

## Headers

- `DateLyrics.h` — imports, private-API declarations, the transition enum and
  the associated-object keys (declared `extern`, defined in `DateLyricsState.m`).
- `DateLyricsInternal.h` — everything shared between the files below: constants,
  `extern` global state, function prototypes, the `DateLyricsInit…Hooks()`
  entry points and the `DateLyricsDebugLog` macro. A function or global that is
  not listed here is private (`static`) to the file that defines it.

## Modules (plain Objective-C)

| File | Responsibility |
| --- | --- |
| `DateLyricsState.m` | Preference-backed globals, host detection (SpringBoard / Music / YouTube Music), notification names, debug log |
| `DateLyricsTicker.m` | SpringBoard clock: sweep clock, pause timers, the line ticker |
| `DateLyricsRender.m` | Label rendering: fonts, long-line splitting, transitions, marquee, smooth sweep |
| `DateLyricsStorage.m` | Container paths, score files, cache pruning, runtime status |
| `DateLyricsMusixmatch.m` | Musixmatch fallback (token, matching, rich-sync) |
| `DateLyricsAppleLyrics.m` | Apple Music TTML ingestion and the download queue |
| `DateLyricsAnchor.m` | Publishes the playback anchor (position and rate) to SpringBoard |
| `DateLyricsRuntime.m` | Preference reloading, cache clearing, cross-process notification handlers |

Lower-level pieces, unchanged by the split:

- `DateLyricsModels` — lyric tasks, timed lines and words, score JSON loading
  (including the estimated word timings used for YouTube Music).
- `DateLyricsLyricsParser` — Apple TTML parsing and time-string conversion.
- `DateLyricsMusixmatchParser` — rich-sync/LRC parsing and normalization helpers.
- `DateLyricsResolver` — line/word timing resolution, adlib filtering, interludes.
- `DateLyricsPayload` / `DateLyricsText` — payload range helpers and text cleanup.

## Logos files (`.xm`)

Each `%group` must be initialised from the file that defines it, so every file
exposes one `DateLyricsInit…Hooks()` function.

| File | Group(s) | Entry point |
| --- | --- | --- |
| `DateLyricsMusicHooks.xm` | `DateLyricsPrimary` (Music), `AMCrashPatcher` | `DateLyricsInitMusicHooks()` |
| `DateLyricsYouTubeMusic.xm` | `DateLyricsYouTubeMusic` (now-playing, native lyrics parser, diagnostics) | `DateLyricsInitYouTubeMusicHooks()` |
| `DateLyricsSpringBoard.xm` | `DateLyricsSpringBoard` (lock screen date view and label) | `DateLyricsInitSpringBoardHooks()` |
| `DateLyrics.xm` | — | `%ctor`: allocates shared state, loads preferences, picks the host |

## Adding code

- New cross-file helper: define it in the closest module, drop `static`, and add
  the prototype to `DateLyricsInternal.h`.
- New hook: add it to the `.xm` file of the process it targets. Logos syntax
  (`%c`, `%orig`, `%init`) only works in `.x`/`.xm` files, and C++ features such
  as `auto` only in `.xm`; module `.m` files are plain Objective-C.
