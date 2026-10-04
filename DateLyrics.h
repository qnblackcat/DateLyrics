// Declarations for DateLyrics.xm. This header belongs to that single
// translation unit: it carries static prototypes and associated-object keys,
// so it must not be included anywhere else.

#pragma once

@import Darwin;
@import Foundation;
@import MediaPlayer;
@import QuartzCore;
@import UIKit;
#import <objc/runtime.h>
#import <stdarg.h>
#import <math.h>
#import <float.h>
#import <ctype.h>
#import <roothide.h>

#pragma mark - Private API

@interface ICURLResponse : NSObject
@property (nonatomic, readonly) NSData *bodyData;
@end

typedef void (^ICURLSessionCompletionHandler)(ICURLResponse *, NSError *);

@interface MSVLyricsLine : NSObject
@property (assign, nonatomic) NSTimeInterval startTime;
@property (assign, nonatomic) NSTimeInterval endTime;
@property (copy, nonatomic) NSAttributedString *lyricsText;
@end

@interface ICMusicKitRequestContext : NSObject
@end

@interface ICMusicKitURLRequest : NSObject
@property (nonatomic, copy, readonly) ICMusicKitRequestContext *requestContext;
- (instancetype)initWithURL:(NSURL *)arg1 requestContext:(ICMusicKitRequestContext *)arg2;
@end

@interface MRContentItemMetadata : NSObject
@property (assign, nonatomic) NSInteger iTunesStoreIdentifier;
@property (assign, nonatomic) NSTimeInterval elapsedTime;
@property (assign, nonatomic) BOOL lyricsAvailable;
@property (assign, nonatomic) NSInteger lyricsAdamID;
@end

@interface MRContentItem : NSObject
@property (nonatomic, copy) MRContentItemMetadata *metadata;
@end

@interface MPNowPlayingContentItem : MPContentItem
@property (assign, nonatomic) NSInteger storeID;
@property (assign, nonatomic) float playbackRate;
@property (nonatomic, strong) NSNumber *amlPlaybackRate;
@property (nonatomic, strong) NSNumber *amlLastSystemElapsedTime;
@property (nonatomic, strong) NSNumber *amlLastSystemTime;
@property (assign, nonatomic) NSInteger amlLastStoreID;
- (NSTimeInterval)calculatedElapsedTime;
- (void)setElapsedTime:(double)elapsedTime playbackRate:(float)arg2;
@end

@interface MSVLyricsTTMLParser : NSObject
- (instancetype)initWithTTMLData:(NSData *)data;
- (NSArray<MSVLyricsLine *> *)lyricLines;
- (id)parseWithError:(id*)arg1;
@end

@interface ICURLSession : NSObject
- (void)enqueueDataRequest:(id)arg1 withCompletionHandler:(ICURLSessionCompletionHandler)arg2;
@end

@interface MRNowPlayingPlayerClient : NSObject
@property (nonatomic, readonly) MRContentItem *nowPlayingContentItem;
- (void)sendContentItemChanges:(NSArray<MRContentItem *> *)contentItems;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

@interface CSProminentSubtitleDateView : UIView
@end

@interface CSProminentEmptyElementView : UIView
@end

@interface CSCoverSheetViewController : UIViewController
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface _UIAnimatingLabel (DateLyrics)
- (void)_amlApplyCurrentLyric;
@end

#pragma mark - Models

@interface LyricsTask : NSObject
@property (nonatomic, assign) NSInteger iTunesStoreID;
@property (nonatomic, assign) NSInteger lyricsAdamID;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, strong) NSURL *lyricURL;
@property (nonatomic, strong) NSString *lyricsFilePath;
@property (nonatomic, copy) NSString *fallbackTitle;
@property (nonatomic, copy) NSString *fallbackArtist;
@property (nonatomic, copy) NSString *fallbackAlbum;
@property (nonatomic, assign) NSTimeInterval fallbackDuration;
@end

@interface DateLyricsMusixmatchTask : NSObject
@property (nonatomic, assign) NSInteger storeID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *subtitleBody;
@property (nonatomic, assign) BOOL refreshedToken;
@property (nonatomic, assign) BOOL wordSyncOnly;
@property (nonatomic, assign) NSInteger commontrackID;
@end

@interface DateLyricsTimedWord : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *separatorBefore;
@property (nonatomic, assign, getter=isBackground) BOOL background;
@end

@interface DateLyricsTimedLine : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSArray<DateLyricsTimedWord *> *words;
// Memoised adlib-filtered form of this line. See DateLyricsGetFilteredLine.
@property (nonatomic, strong) DateLyricsTimedLine *amlCachedFiltered;
@property (nonatomic, assign) BOOL amlCachedFilteredValid;
@property (nonatomic, assign) BOOL amlCachedFilteredAdlibs;
@end

@interface DateLyricsScore : NSObject
@property (nonatomic, assign) NSInteger trackId;
@property (nonatomic, assign) BOOL hasWordTiming;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSArray<DateLyricsTimedLine *> *lines;
- (instancetype)initWithJSONData:(NSData *)data;
@end

@interface DateLyricsWeakBox : NSObject
@property (nonatomic, weak) id object;
@end

// Cached word-wrap result for one lyric line, held on the label it was computed for.
// segments == nil means "measured, does not need splitting".
@interface DateLyricsSplitPlan : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) id lineId;
@property (nonatomic, assign) NSInteger trackId;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, copy) NSString *fontKey;
@property (nonatomic, strong) NSArray<NSValue *> *segments;
@property (nonatomic, assign) NSUInteger lastIndex;
@end

// One voice (lead or background) of the smooth-sweep mask: a clip spanning the
// lit text and a bright bar with a soft leading edge sliding through it.
// Positions are the bar's right edge in clip coordinates.
@interface DateLyricsSweepVoice : NSObject
@property (nonatomic, strong) CALayer *clip;
@property (nonatomic, strong) CAGradientLayer *bar;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) CGFloat fromX;
@property (nonatomic, assign) CGFloat toX;
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@end

// The label draws the whole line at full colour; this mask supplies the dimming.
@interface DateLyricsSweepMask : NSObject
@property (nonatomic, strong) CALayer *root;
@property (nonatomic, strong) CALayer *dim;
@property (nonatomic, strong) DateLyricsSweepVoice *foreground;
@property (nonatomic, strong) DateLyricsSweepVoice *background;
// Inputs of the last layout, replayed when the label is resized.
@property (nonatomic, copy) NSDictionary *payload;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) CGSize boundsSize;
@end

@interface DateLyricsWordTTMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedLine *> *lines;
@property (nonatomic, strong) DateLyricsTimedLine *currentLine;
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedWord *> *currentWords;
@property (nonatomic, strong) NSMutableString *pendingSeparator;
@property (nonatomic, strong) NSMutableString *currentSpanText;
@property (nonatomic, assign) BOOL insideParagraph;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spanBackgroundStack;
@end

#pragma mark - Types

typedef NS_ENUM(NSInteger, DateLyricsTransitionStyle) {
    DateLyricsTransitionStyleFade = 0,
    DateLyricsTransitionStyleSlideUp = 1,
    DateLyricsTransitionStyleSlideDown = 2,
    DateLyricsTransitionStylePush = 3,
    DateLyricsTransitionStylePop = 4,
};

#pragma mark - Associated object keys

static const void *kDateLyricsForcedWidgetDateVisibleKey = &kDateLyricsForcedWidgetDateVisibleKey;
static const void *kDateLyricsOriginalHiddenKey = &kDateLyricsOriginalHiddenKey;
static const void *kDateLyricsRestoringStockDateKey = &kDateLyricsRestoringStockDateKey;
static const void *kDateLyricsLabelShowingLyricKey = &kDateLyricsLabelShowingLyricKey;
static const void *kDateLyricsLastRenderedAttrTextKey = &kDateLyricsLastRenderedAttrTextKey;
static const void *kDateLyricsLastRenderedTextKey = &kDateLyricsLastRenderedTextKey;
static const void *kDateLyricsRenderCacheKey = &kDateLyricsRenderCacheKey;
static const void *kDateLyricsAnimatingTransitionKey = &kDateLyricsAnimatingTransitionKey;
static const void *kDateLyricsMarqueeActiveKey = &kDateLyricsMarqueeActiveKey;
static const void *kDateLyricsMarqueeLineIdKey = &kDateLyricsMarqueeLineIdKey;
static const void *kDateLyricsMarqueeContainerKey = &kDateLyricsMarqueeContainerKey;
static const void *kDateLyricsMarqueeContentLabelKey = &kDateLyricsMarqueeContentLabelKey;
static const void *kDateLyricsTransitionGenerationKey = &kDateLyricsTransitionGenerationKey;
static const void *kDateLyricsOriginalClipsToBoundsKey = &kDateLyricsOriginalClipsToBoundsKey;
static const void *kDateLyricsOriginalFontKey = &kDateLyricsOriginalFontKey;
static const void *kDateLyricsOriginalTextColorKey = &kDateLyricsOriginalTextColorKey;
static const void *kDateLyricsOriginalNumberOfLinesKey = &kDateLyricsOriginalNumberOfLinesKey;
static const void *kDateLyricsOriginalAdjustsFontSizeKey = &kDateLyricsOriginalAdjustsFontSizeKey;
static const void *kDateLyricsOriginalMinScaleKey = &kDateLyricsOriginalMinScaleKey;
static const void *kDateLyricsOriginalLineBreakModeKey = &kDateLyricsOriginalLineBreakModeKey;
static const void *kDateLyricsOriginalAttributedTextKey = &kDateLyricsOriginalAttributedTextKey;
static const void *kDateLyricsOriginalTextKey = &kDateLyricsOriginalTextKey;
// Set once on the specific label we drive, so the _UIAnimatingLabel setter hooks
// can early-out with a single lookup instead of walking the superview chain on
// every text assignment in SpringBoard.
static const void *kDateLyricsIsDateLabelKey = &kDateLyricsIsDateLabelKey;
// Weak-boxed cache of the label a date view owns, so we stop re-running a
// recursive subview search on every layout pass.
static const void *kDateLyricsCachedLabelKey = &kDateLyricsCachedLabelKey;
// Cached widget host view. Widget containers can lay out many times per second;
// retain the positive recursive lookup while the host remains in the subtree.
static const void *kDateLyricsCachedWidgetHostKey = &kDateLyricsCachedWidgetHostKey;
// Cached DateLyricsSplitPlan for the line currently on the label.
static const void *kDateLyricsSplitPlanKey = &kDateLyricsSplitPlanKey;
// Latched (grow-only) wrap width for the label. See DateLyricsSplitAvailableWidth.
static const void *kDateLyricsSplitWidthKey = &kDateLyricsSplitWidthKey;
// Frame the label is pinned to for the duration of a line transition.
static const void *kDateLyricsFrozenFrameKey = &kDateLyricsFrozenFrameKey;
// Static copy of the outgoing line. Keeping the real label live allows
// syllable colours to update while the line transition is still running.
static const void *kDateLyricsOutgoingSnapshotKey = &kDateLyricsOutgoingSnapshotKey;
// Distinguishes our own lyric content writes from SpringBoard's stock date
// updates. The latter must not replace an active lyric during wake/layout.
static const void *kDateLyricsApplyingLyricContentKey = &kDateLyricsApplyingLyricContentKey;
// DateLyricsSweepMask behind the label's smooth-sweep layer mask.
static const void *kDateLyricsSweepMaskKey = &kDateLyricsSweepMaskKey;

#pragma mark - Functions

static DateLyricsTimedLine *DateLyricsGetFilteredLine(DateLyricsTimedLine *line);
static NSDictionary *DateLyricsMakePayload(NSString *text, NSRange activeRange);
static NSDictionary *DateLyricsMakePayloadWithBackgroundRange(NSString *text, NSRange activeRange, NSRange backgroundRange);
static void DateLyricsSetRangeFields(NSMutableDictionary *payload, NSString *prefix, NSRange range);
static void DateLyricsApplyCurrentLineToAllCoverSheets(void);
static void DateLyricsStopMarquee(_UIAnimatingLabel *label);
static UIView *DateLyricsDetachMarquee(_UIAnimatingLabel *label);
static BOOL DateLyricsStartMarquee(_UIAnimatingLabel *label, CGFloat overflow, NSTimeInterval remainingLineTime);
static void DateLyricsRefreshMarqueeContent(_UIAnimatingLabel *label);
static NSDictionary *DateLyricsInterludePayload(NSArray<DateLyricsTimedLine *> *lines, NSInteger resolvedLineIndex, NSTimeInterval elapsedTime, NSTimeInterval *nextDotOut);
static NSString *GetLyricsRootPath(void);
static BOOL DateLyricsIsSpringBoardHost(void);
static BOOL DateLyricsIsMusicHost(void);
static void DateLyricsWriteDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void DateLyricsScheduleTicker(void);
static void DateLyricsCancelPauseHideTimer(void);
static void DateLyricsSchedulePauseHideTimer(void);
static void DateLyricsSweepResyncAllLabels(void);
static void DateLyricsPlayHaptic(NSInteger style);
static NSString *DateLyricsHighlightSignature(NSDictionary *payload);
static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot);
static _UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view);
static void DateLyricsPrepareAndApplyDateLabel(_UIAnimatingLabel *label);
static void DateLyricsRestoreSystemDateLabel(_UIAnimatingLabel *label);
static void DateLyricsInvalidateLabelRenderCache(_UIAnimatingLabel *label);
static BOOL DateLyricsHasRenderableLyricPayload(void);
static void DateLyricsMusixmatchFetchMacro(DateLyricsMusixmatchTask *task);
static void DateLyricsMusixmatchBeginTokenLoad(NSUInteger attempt);
