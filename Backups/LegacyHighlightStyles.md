# Retired Caps and Stroke Highlight Styles

DateLyrics now uses the opacity highlight style exclusively, with the sung
portion of a line retained at full opacity. The Caps and Stroke alternatives,
their outline-width control, and the optional past-syllable toggle were removed
from the active tweak and preferences on 2026-08-08.

The complete pre-removal implementation is preserved in Git at commit
`e365080` (`DateLyrics.xm` and
`DateLyricsPrefs/DateLyricsRootListController.m`). To restore the code without
affecting the current branch, inspect it with:

```sh
git show e365080:DateLyrics.xm
git show e365080:DateLyricsPrefs/DateLyricsRootListController.m
git show e365080:DateLyricsPrefs/Resources/Root.plist
```

The retired preferences were `HighlightStyle`, `StrokeWidth`, and
`HighlightTrail`. Existing values are intentionally ignored by the current
code; they can remain in a user's preferences plist without changing behavior.
