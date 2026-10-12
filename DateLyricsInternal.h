// Declarations shared between the DateLyrics translation units. Everything the
// tweak's modules use across files is declared here; anything not listed is
// private to the file that defines it.

#pragma once

#import "DateLyrics.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - Constants

// DateLyricsRender.m
// Opacity of unsung text, shared by the attributed-string and sweep highlighters.
static const CGFloat kDateLyricsDimmedAlpha = 0.35;

// DateLyricsState.m
static const NSTimeInterval kDateLyricsJitterBackstepLimit = 1.0;
// Music publishes a fresh anchor during playback. If its process is killed,
// SpringBoard receives no final pause event, so expire the last running anchor.
static const NSTimeInterval kDateLyricsAnchorStaleTimeout = 15.0;
// Start a forward line transition slightly before its score timestamp.  This
// is deliberately fixed rather than exposed as another preference: 50 ms is
// small enough to preserve the score's timing while hiding timer/notification
// latency on the lock screen.  Syllable updates themselves remain on time.
static const NSTimeInterval kDateLyricsLineTransitionLead = 0.05;
static const NSUInteger kDateLyricsMaxMemoryCacheEntries = 40;
static const NSUInteger kDateLyricsMaxDiskCacheEntries = 100;

#pragma mark - Shared state

// DateLyricsState.m
extern NSInteger gDateLyricsHapticStyleSyllable;
extern NSInteger gDateLyricsHapticStyleLine;
extern BOOL gDateLyricsSmoothSweep;
extern BOOL gDateLyricsEnabled;
extern BOOL gDateLyricsOnlyExpandedArtwork;
extern BOOL gDateLyricsInterludeIndicator;
extern NSInteger gDateLyricsInterludeStyle;
extern BOOL gDateLyricsArtworkExpanded;
extern BOOL gDateLyricsArtworkDetectionAvailable;
extern BOOL gDateLyricsCoverSheetVisible;
extern BOOL gDateLyricsScreenOff;
extern BOOL gDateLyricsCatchingUp;
extern BOOL gDateLyricsForceLowercase;
extern BOOL gDateLyricsWordHighlighting;
extern BOOL gDateLyricsUseCustomFont;
extern NSString *gDateLyricsCustomFontName;
extern BOOL gDateLyricsItalicLyrics;
extern BOOL gDateLyricsTransitionsEnabled;
extern NSInteger gDateLyricsTransitionStyle;
extern NSTimeInterval gDateLyricsTransitionDuration;
extern BOOL gDateLyricsSplitLongLines;
extern BOOL gDateLyricsMarqueeEnabled;
extern BOOL gDateLyricsShowAdlibs;
extern CGFloat gDateLyricsMinimumScale;
extern NSTimeInterval gDateLyricsPauseTimeout;
extern BOOL gDateLyricsMusixmatchEnabled;
extern BOOL gDateLyricsDebugLogging;
extern NSTimeInterval gDateLyricsMarqueeHoldDuration;
extern NSHashTable<UIView *> *gDateLyricsWidgetSlots;
extern NSDictionary *gDateLyricsCurrentPayload;
extern DateLyricsScore *gDateLyricsCurrentScore;
extern NSDictionary *gDateLyricsLocalAnchor;
extern dispatch_source_t gDateLyricsTicker;
extern dispatch_source_t gDateLyricsPauseHideTimer;
extern NSInteger gDateLyricsResolverCursor;
extern NSUInteger gDateLyricsRenderGeneration;
extern NSInteger gDateLyricsLastResolvedTrackId;
extern NSTimeInterval gDateLyricsLastResolvedElapsed;
extern BOOL gDateLyricsLastResolutionWasBackwardSeek;
extern NSDictionary *gDateLyricsEarlyLinePayload;
extern NSTimeInterval gDateLyricsEarlyLineBegin;
extern NSTimeInterval gDateLyricsEarlyLineNextTrigger;
extern NSInteger gDateLyricsEarlyLineTrackId;
extern BOOL gDateLyricsHapticsEnabled;

// DateLyricsTicker.m
extern BOOL gDateLyricsSweepClockValid;

#pragma mark - Functions

// DateLyricsAnchor.m
void DateLyricsPublishAnchor(NSInteger storeID, double elapsedTime, float rate, BOOL isSeek);

// DateLyricsAppleLyrics.m
BOOL DateLyricsIsUnsynchronizedLyricsID(NSInteger lyricsAdamID);
void DateLyricsSetUnsynchronizedLyricsID(NSInteger lyricsAdamID, BOOL unsynchronized);
BOOL ParseLyricsData(NSData *data, NSInteger iTunesStoreID, __unused NSInteger lyricsAdamID,
                            BOOL *unsynchronizedOut, BOOL *wordTimingOut);
void ProcessNextTask(void);
void AddTaskToQueue(NSInteger iTunesStoreID, NSInteger lyricsAdamID, NSURL *lyricURL,
                           NSString *lyricsFilePath, NSString *fallbackTitle, NSString *fallbackArtist,
                           NSString *fallbackAlbum, NSTimeInterval fallbackDuration);

// DateLyricsMusixmatch.m
void DateLyricsRemoveMusixmatchLoadingScore(NSInteger storeID);
NSString *DateLyricsMusixmatchTokenCachePath(void);
void DateLyricsMusixmatchBeginTokenLoad(NSUInteger attempt);
void DateLyricsMusixmatchFetchMacro(DateLyricsMusixmatchTask *task);
NSString *DateLyricsMetadataString(id metadata, NSArray<NSString *> *keys);
NSTimeInterval DateLyricsMetadataDuration(id metadata);
void DateLyricsStartMusixmatchFallback(NSInteger storeID, NSString *title, NSString *artist,
                                              NSString *album, NSTimeInterval duration, BOOL wordSyncOnly);

// DateLyricsRender.m
void DateLyricsApplyCurrentLineToAllCoverSheets(void);
void DateLyricsPlayHaptic(NSInteger style);
NSDictionary *DateLyricsCurrentRenderablePayload(void);
UIColor *DateLyricsBaseTextColorForLabel(_UIAnimatingLabel *label);
void DateLyricsApplyLabelContent(_UIAnimatingLabel *label, NSString *displayText, NSAttributedString *attrDisplayText);
UIFont *DateLyricsConfiguredFontForLabel(_UIAnimatingLabel *label);
CGFloat DateLyricsMeasuredLineWidth(NSString *text, UIFont *font);
CGFloat DateLyricsSplitAvailableWidth(UILabel *label);
NSDictionary *DateLyricsSplitPayloadForLabel(NSDictionary *payload, UILabel *label, UIFont *baseFont);
NSComparisonResult DateLyricsCompareLineIdentity(id leftIdentity, id rightIdentity);
void DateLyricsAnimateLabelTransition(_UIAnimatingLabel *label, NSString *previousDisplayText, NSString *displayText, NSAttributedString *attrDisplayText, BOOL reverseDirection);
NSString *DateLyricsHighlightSignature(NSDictionary *payload);
UIView *DateLyricsDetachMarquee(_UIAnimatingLabel *label);
void DateLyricsStopMarquee(_UIAnimatingLabel *label);
void DateLyricsRefreshMarqueeContent(_UIAnimatingLabel *label);
BOOL DateLyricsStartMarquee(_UIAnimatingLabel *label, CGFloat overflow, NSTimeInterval remainingLineTime);
void DateLyricsRemoveSweepMask(UILabel *label);
void DateLyricsLayoutSweepMask(UILabel *label, NSDictionary *payload, NSString *text);
void DateLyricsSweepResyncAllLabels(void);
void DateLyricsSweepRelayoutIfResized(UILabel *label);

// DateLyricsRuntime.m
void DateLyricsReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
void DateLyricsClearCaches(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
void DateLyricsHandleAnchorChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
void DateLyricsHandleScoreChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
void DateLyricsHandleAnchorRequest(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

// DateLyricsSpringBoard.xm
_UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view);
BOOL DateLyricsHasRenderableLyricPayload(void);
void DateLyricsInvalidateLabelRenderCache(_UIAnimatingLabel *label);
void DateLyricsPrepareAndApplyDateLabel(_UIAnimatingLabel *label);
void DateLyricsRestoreSystemDateLabel(_UIAnimatingLabel *label);
void DateLyricsUpdateWidgetDateView(UIView *widgetSlot);

// DateLyricsState.m
BOOL DateLyricsLockScreenLive(void);
BOOL DateLyricsDisplayAllowed(void);
void DateLyricsWriteDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void DateLyricsClearEarlyLinePreview(void);
NSTimeInterval DateLyricsMonotonicTime(void);
BOOL DateLyricsIsSpringBoardHost(void);
BOOL DateLyricsIsMusicHost(void);
BOOL DateLyricsIsYouTubeMusicHost(void);
BOOL DateLyricsIsPlaybackHost(void);
CFStringRef DateLyricsScoreChangedNotification(void);
CFStringRef DateLyricsAnchorChangedNotification(void);
NSString *DateLyricsStorefront(void);
NSString *DateLyricsPreferredLocale(void);
NSRange DateLyricsRangeFromPayload(NSDictionary *payload, NSString *prefix, NSUInteger textLength);

// DateLyricsStorage.m
NSString *DateLyricsRootPathForBundleIdentifier(NSString *bundleIdentifier);
NSString *GetLyricsRootPath(void);
void DateLyricsWriteRuntimeStatus(void);
BOOL DateLyricsWordLinesHaveTiming(NSArray<DateLyricsTimedLine *> *lines);
BOOL DateLyricsLineItemsHaveTiming(NSArray<MSVLyricsLine *> *lines);
void DateLyricsTouchMemoryCacheLocked(NSNumber *storeID);
void DateLyricsPruneDiskCache(void);
BOOL DateLyricsWriteScoreJSON(NSInteger storeID, NSArray<NSDictionary *> *linesArray, BOOL hasWordTiming, NSString *source);
void DateLyricsSerializeScore(NSInteger storeID, NSArray<DateLyricsTimedLine *> *wordLines, NSArray<MSVLyricsLine *> *lyricLines);
void DateLyricsInvalidateSerializedScore(NSInteger storeID);

// DateLyricsTicker.m
BOOL DateLyricsSweepSongTime(NSTimeInterval *songTimeOut, float *rateOut);
void DateLyricsNotePauseState(NSDictionary *previousAnchor, NSDictionary *anchor);
void DateLyricsCancelPauseHideTimer(void);
void DateLyricsSchedulePauseHideTimer(void);
void DateLyricsScheduleTicker(void);

#pragma mark - Hook installation (one per Logos file)

void DateLyricsInitMusicHooks(void);
void DateLyricsInitYouTubeMusicHooks(void);
void DateLyricsInitSpringBoardHooks(void);

#ifdef __cplusplus
}
#endif

#pragma mark - Logging

#define DateLyricsDebugLog(...) do { \
    if (gDateLyricsDebugLogging) DateLyricsWriteDebugLog(__VA_ARGS__); \
} while (0)

static NSHashTable<CSProminentSubtitleDateView *> *gDateLyricsDateViews = nil;
