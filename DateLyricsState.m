// Shared runtime state: preference-backed globals, host detection and the debug log.

#import "DateLyricsInternal.h"

#pragma mark - Associated object keys

const void *kDateLyricsForcedWidgetDateVisibleKey = &kDateLyricsForcedWidgetDateVisibleKey;
const void *kDateLyricsOriginalHiddenKey = &kDateLyricsOriginalHiddenKey;
const void *kDateLyricsRestoringStockDateKey = &kDateLyricsRestoringStockDateKey;
const void *kDateLyricsLabelShowingLyricKey = &kDateLyricsLabelShowingLyricKey;
const void *kDateLyricsLastRenderedAttrTextKey = &kDateLyricsLastRenderedAttrTextKey;
const void *kDateLyricsLastRenderedTextKey = &kDateLyricsLastRenderedTextKey;
const void *kDateLyricsRenderCacheKey = &kDateLyricsRenderCacheKey;
const void *kDateLyricsAnimatingTransitionKey = &kDateLyricsAnimatingTransitionKey;
const void *kDateLyricsMarqueeActiveKey = &kDateLyricsMarqueeActiveKey;
const void *kDateLyricsMarqueeLineIdKey = &kDateLyricsMarqueeLineIdKey;
const void *kDateLyricsMarqueeContainerKey = &kDateLyricsMarqueeContainerKey;
const void *kDateLyricsMarqueeContentLabelKey = &kDateLyricsMarqueeContentLabelKey;
const void *kDateLyricsTransitionGenerationKey = &kDateLyricsTransitionGenerationKey;
const void *kDateLyricsOriginalClipsToBoundsKey = &kDateLyricsOriginalClipsToBoundsKey;
const void *kDateLyricsOriginalFontKey = &kDateLyricsOriginalFontKey;
const void *kDateLyricsOriginalTextColorKey = &kDateLyricsOriginalTextColorKey;
const void *kDateLyricsOriginalNumberOfLinesKey = &kDateLyricsOriginalNumberOfLinesKey;
const void *kDateLyricsOriginalAdjustsFontSizeKey = &kDateLyricsOriginalAdjustsFontSizeKey;
const void *kDateLyricsOriginalMinScaleKey = &kDateLyricsOriginalMinScaleKey;
const void *kDateLyricsOriginalLineBreakModeKey = &kDateLyricsOriginalLineBreakModeKey;
const void *kDateLyricsOriginalAttributedTextKey = &kDateLyricsOriginalAttributedTextKey;
const void *kDateLyricsOriginalTextKey = &kDateLyricsOriginalTextKey;
const void *kDateLyricsIsDateLabelKey = &kDateLyricsIsDateLabelKey;
const void *kDateLyricsCachedLabelKey = &kDateLyricsCachedLabelKey;
const void *kDateLyricsCachedWidgetHostKey = &kDateLyricsCachedWidgetHostKey;
const void *kDateLyricsSplitPlanKey = &kDateLyricsSplitPlanKey;
const void *kDateLyricsSplitWidthKey = &kDateLyricsSplitWidthKey;
const void *kDateLyricsFrozenFrameKey = &kDateLyricsFrozenFrameKey;
const void *kDateLyricsOutgoingSnapshotKey = &kDateLyricsOutgoingSnapshotKey;
const void *kDateLyricsApplyingLyricContentKey = &kDateLyricsApplyingLyricContentKey;
const void *kDateLyricsSweepMaskKey = &kDateLyricsSweepMaskKey;

NSInteger gDateLyricsHapticStyleSyllable = 1;
NSInteger gDateLyricsHapticStyleLine = 2;
// Experimental: light each syllable progressively over its duration instead
// of switching it on at its start time.
BOOL gDateLyricsSmoothSweep = NO;

BOOL gDateLyricsEnabled = YES;
// "Only in Full-Screen Artwork". The expanded Lock Screen player is drawn by
// MediaRemoteUI as background content behind the cover sheet; SpringBoard's
// view of that state is tracked by the CSCoverSheetViewController hooks.
BOOL gDateLyricsOnlyExpandedArtwork = NO;
// "• • •" before the first lyric and through long instrumental breaks.
BOOL gDateLyricsInterludeIndicator = NO;
NSInteger gDateLyricsInterludeStyle = 0;
BOOL gDateLyricsArtworkExpanded = NO;
BOOL gDateLyricsArtworkDetectionAvailable = NO;
// Whether anyone can see the date label: the cover sheet is presented and the
// screen is on. Both default to "visible" so a missed hook degrades to the old
// always-ticking behaviour instead of freezing lyrics.
BOOL gDateLyricsCoverSheetVisible = YES;
BOOL gDateLyricsScreenOff = NO;
// Set while catching up after the lock screen returns, so the jump to the
// current line does not buzz like a real line change.
BOOL gDateLyricsCatchingUp = NO;
BOOL gDateLyricsForceLowercase = NO;
BOOL gDateLyricsWordHighlighting = YES;
BOOL gDateLyricsUseCustomFont = NO;
NSString *gDateLyricsCustomFontName = nil;
BOOL gDateLyricsItalicLyrics = NO;
BOOL gDateLyricsTransitionsEnabled = YES;
NSInteger gDateLyricsTransitionStyle = 1;
NSTimeInterval gDateLyricsTransitionDuration = 0.3;
BOOL gDateLyricsSplitLongLines = YES;
BOOL gDateLyricsMarqueeEnabled = YES;
BOOL gDateLyricsShowAdlibs = NO;
CGFloat gDateLyricsMinimumScale = 0.55;
NSTimeInterval gDateLyricsPauseTimeout = 2.0;
BOOL gDateLyricsMusixmatchEnabled = YES;
// Keep disk logging opt-in.  The diagnostic path writes asynchronously on every
// ticker/render event and should never be enabled in a normal install.
BOOL gDateLyricsDebugLogging = NO;
NSTimeInterval gDateLyricsMarqueeHoldDuration = 0.5;

// Whether lyrics may be drawn on the Lock Screen right now. Playback tracking
// and line resolution keep running regardless, so a lyric can appear the moment
// the player expands. If this iOS version lacks the background-content hooks,
// the full-screen option is ignored rather than hiding lyrics forever.
BOOL DateLyricsLockScreenLive(void) {
    return gDateLyricsCoverSheetVisible && !gDateLyricsScreenOff;
}

BOOL DateLyricsDisplayAllowed(void) {
    if (!gDateLyricsEnabled) return NO;
    if (!gDateLyricsOnlyExpandedArtwork || !gDateLyricsArtworkDetectionAvailable) return YES;
    return gDateLyricsArtworkExpanded;
}

// Opt-in diagnostics for SpringBoard rendering and Music lyric ingestion.
void DateLyricsWriteDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.shalamand3r.datelyrics.debuglog", DISPATCH_QUEUE_SERIAL);
    });

    NSString *host = DateLyricsIsSpringBoardHost() ? @"SB" : (DateLyricsIsYouTubeMusicHost() ? @"YTM" : (DateLyricsIsMusicHost() ? @"Music" : @"Other"));
    NSString *stamped = [NSString stringWithFormat:@"[DateLyrics %@] %.3f %@", host, [NSDate timeIntervalSinceReferenceDate], message];
    NSLog(@"%@", stamped);

    dispatch_async(queue, ^{
        // SpringBoard can use the shared mobile path. Music is sandboxed, so
        // keep its diagnostics in the same container as its lyric cache; the
        // preferences viewer reads both locations.
        NSString *dir = DateLyricsIsPlaybackHost() ? GetLyricsRootPath() : @"/var/mobile/Library/DateLyrics";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *path = [dir stringByAppendingPathComponent:@"tweak-debug.log"];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[[stamped stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } else {
            [[stamped stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    });
}
NSHashTable<UIView *> *gDateLyricsWidgetSlots = nil;
NSDictionary *gDateLyricsCurrentPayload = nil;

// SpringBoard Consumer Clock (Phase 3)
DateLyricsScore *gDateLyricsCurrentScore = nil;
NSDictionary *gDateLyricsLocalAnchor = nil; // { elapsed, rate, atHostTime, trackId }
dispatch_source_t gDateLyricsTicker = nil;
dispatch_source_t gDateLyricsPauseHideTimer = nil;
NSInteger gDateLyricsResolverCursor = -1;
// Bumped when a render-affecting payload, track, or preference changes. Labels
// use it to avoid rebuilding the same attributed string on every UIKit layout.
NSUInteger gDateLyricsRenderGeneration = 1;
// MediaRemote's authoritative clock can arrive a few milliseconds behind our
// extrapolated anchor. Keep only the lyric-resolution clock monotonic within one
// track; the anchor itself remains untouched so playback and real seeks stay true.
NSInteger gDateLyricsLastResolvedTrackId = 0;
NSTimeInterval gDateLyricsLastResolvedElapsed = -1.0;
BOOL gDateLyricsLastResolutionWasBackwardSeek = NO;
NSDictionary *gDateLyricsEarlyLinePayload = nil;
NSTimeInterval gDateLyricsEarlyLineBegin = -1.0;
NSTimeInterval gDateLyricsEarlyLineNextTrigger = -1.0;
NSInteger gDateLyricsEarlyLineTrackId = 0;
void DateLyricsClearEarlyLinePreview(void) {
    gDateLyricsEarlyLinePayload = nil;
    gDateLyricsEarlyLineBegin = -1.0;
    gDateLyricsEarlyLineNextTrigger = -1.0;
    gDateLyricsEarlyLineTrackId = 0;
}

NSTimeInterval DateLyricsMonotonicTime(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9;
}
BOOL gDateLyricsHapticsEnabled = NO;


BOOL DateLyricsIsSpringBoardHost(void) {
    static BOOL isSpringBoard = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
        NSString *processName = [NSProcessInfo processInfo].processName;
        isSpringBoard = [bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
                        [processName isEqualToString:@"SpringBoard"];
    });
    return isSpringBoard;
}

BOOL DateLyricsIsMusicHost(void) {
    static BOOL isMusic = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
        NSString *processName = [NSProcessInfo processInfo].processName;
        isMusic = [bundleIdentifier isEqualToString:@"com.apple.Music"] ||
                  [processName isEqualToString:@"Music"];
    });
    return isMusic;
}

BOOL DateLyricsIsYouTubeMusicHost(void) {
    static BOOL isYouTubeMusic = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isYouTubeMusic = [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.google.ios.youtubemusic"];
    });
    return isYouTubeMusic;
}

BOOL DateLyricsIsPlaybackHost(void) {
    return DateLyricsIsMusicHost() || DateLyricsIsYouTubeMusicHost();
}

CFStringRef DateLyricsScoreChangedNotification(void) {
    return DateLyricsIsYouTubeMusicHost()
        ? CFSTR("com.shalamand3r.datelyrics/score.youtube.changed")
        : CFSTR("com.shalamand3r.datelyrics/score.changed");
}

CFStringRef DateLyricsAnchorChangedNotification(void) {
    return DateLyricsIsYouTubeMusicHost()
        ? CFSTR("com.shalamand3r.datelyrics/anchor.youtube.changed")
        : CFSTR("com.shalamand3r.datelyrics/anchor.changed");
}

NSString *DateLyricsStorefront(void) {
    NSString *countryCode = [NSLocale currentLocale].countryCode;
    if (![countryCode isKindOfClass:NSString.class] || countryCode.length != 2) return @"us";
    return countryCode.lowercaseString;
}

NSString *DateLyricsPreferredLocale(void) {
    NSString *locale = [NSLocale preferredLanguages].firstObject;
    if (![locale isKindOfClass:NSString.class] || locale.length == 0) return @"en-US";
    return [locale stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"en-US";
}


NSRange DateLyricsRangeFromPayload(NSDictionary *payload, NSString *prefix, NSUInteger textLength) {
    if (![payload isKindOfClass:NSDictionary.class] || ![prefix isKindOfClass:NSString.class]) return NSMakeRange(NSNotFound, 0);
    NSString *locKey = nil;
    NSString *lenKey = nil;
    if ([prefix isEqualToString:@""]) {
        locKey = @"loc";
        lenKey = @"len";
    } else {
        locKey = [prefix stringByAppendingString:@"Loc"];
        lenKey = [prefix stringByAppendingString:@"Len"];
    }

    NSNumber *locNum = payload[locKey];
    NSNumber *lenNum = payload[lenKey];
    if (![locNum isKindOfClass:NSNumber.class] || ![lenNum isKindOfClass:NSNumber.class]) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSUInteger loc = locNum.unsignedIntegerValue;
    NSUInteger len = lenNum.unsignedIntegerValue;
    NSRange range = NSMakeRange(loc, len);
    if (loc == NSNotFound || len == 0 || NSMaxRange(range) > textLength) {
        return NSMakeRange(NSNotFound, 0);
    }
    return range;
}
