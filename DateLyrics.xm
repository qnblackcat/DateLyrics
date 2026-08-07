@import Darwin;
@import Foundation;
@import MediaPlayer;
@import QuartzCore;
@import UIKit;
#import <objc/runtime.h>
#import <stdarg.h>

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
@property (assign, nonatomic) BOOL hasITunesStoreIdentifier;
@property (copy, nonatomic) NSString *title;
@property (copy, nonatomic) NSString *trackArtistName;
@property (nonatomic, copy) NSString *amLyricsTitle;
@property (assign, nonatomic) NSTimeInterval elapsedTime;
@property (assign, nonatomic) BOOL lyricsAvailable;
@property (assign, nonatomic) BOOL hasLyricsAvailable;
@property (assign, nonatomic) NSInteger lyricsAdamID;
@property (assign, nonatomic) BOOL hasLyricsAdamID;
@end

@interface MRContentItem : NSObject
@property (nonatomic, copy) MRContentItemMetadata *metadata;
@end

@interface MPNowPlayingContentItem : MPContentItem
@property (assign, nonatomic) NSInteger storeID;
@property (nonatomic, strong) NSTimer *amlTimer;
@property (nonatomic, strong) NSTimer *amlPauseTimer;
@property (nonatomic, copy) NSString *amlCurrentLyricTitle;
@property (nonatomic, copy) NSString *amlCurrentPayloadSignature;
@property (assign, nonatomic) float playbackRate;
@property (nonatomic, strong) NSNumber *amlPlaybackRate;
@property (nonatomic, strong) NSNumber *amlLastSystemElapsedTime;
@property (nonatomic, strong) NSNumber *amlLastSystemTime;
@property (nonatomic, strong) NSNumber *amlLastPayloadPublishTime;
@property (nonatomic, strong) NSNumber *amlLastResolvedElapsed;
@property (nonatomic, strong) NSNumber *amlLastResolvedLineIndex;
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

@interface MPNowPlayingInfoCenter (Private)
- (MPNowPlayingContentItem *)nowPlayingContentItem;
@property (nonatomic, assign) NSUInteger playbackState;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

@interface CSProminentSubtitleDateView : UIView
@end

@interface CSProminentEmptyElementView : UIView
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface _UIAnimatingLabel (DateLyrics)
- (void)_amlApplyCurrentLyric;
@end

@interface LyricsTask : NSObject
@property (nonatomic, assign) NSInteger iTunesStoreID;
@property (nonatomic, assign) NSInteger lyricsAdamID;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, strong) NSURL *lyricURL;
@property (nonatomic, strong) NSString *lyricsFilePath;
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

@implementation LyricsTask
@end

@implementation DateLyricsTimedWord
@end

@implementation DateLyricsTimedLine
@end

@interface DateLyricsWeakBox : NSObject
@property (nonatomic, weak) id object;
@end

@implementation DateLyricsWeakBox
@end

// Cached word-wrap result for one lyric line, held on the label it was computed for.
// segments == nil means "measured, does not need splitting".
@interface DateLyricsSplitPlan : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) id lineId;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, copy) NSString *fontKey;
@property (nonatomic, strong) NSArray<NSValue *> *segments;
@property (nonatomic, assign) NSUInteger lastIndex;
@end

@implementation DateLyricsSplitPlan
@end

static dispatch_queue_t gLyricsQueue = nil;
static ICURLSession *gSession = nil;
static ICMusicKitRequestContext *gRequestContext = nil;
static NSMutableArray<LyricsTask *> *gLyricsTaskQueue = nil;
static NSMutableSet<NSNumber *> *gPendingLyricsIDs = nil;
static BOOL gIsProcessingQueue = NO;
static NSString *gLyricsRootPath = nil;
static NSMutableDictionary<NSNumber *, NSArray<MSVLyricsLine *> *> *gLyricsCache = nil;
static NSMutableDictionary<NSNumber *, NSArray<DateLyricsTimedLine *> *> *gWordLyricsCache = nil;
static NSMutableArray<NSNumber *> *gLyricsCacheOrder = nil;
static pthread_mutex_t gLyricsCacheMutex = PTHREAD_MUTEX_INITIALIZER;
static MPNowPlayingInfoCenter *gNowPlayingInfoCenter = nil;
static __weak MPNowPlayingContentItem *gCurrentContentItem = nil;

static BOOL gDateLyricsEnabled = YES;
static BOOL gDateLyricsForceLowercase = NO;
static BOOL gDateLyricsWordHighlighting = YES;
static BOOL gDateLyricsHighlightTrail = YES;
static NSInteger gDateLyricsHighlightStyle = 2;
static BOOL gDateLyricsUseCustomFont = NO;
static NSString *gDateLyricsCustomFontName = nil;
static BOOL gDateLyricsTransitionsEnabled = YES;
static NSInteger gDateLyricsTransitionStyle = 1;
static NSTimeInterval gDateLyricsTransitionDuration = 0.3;
static CGFloat gDateLyricsStrokeWidth = 3.0;
static BOOL gDateLyricsSplitLongLines = YES;
static BOOL gDateLyricsShowAdlibs = NO;
static CGFloat gDateLyricsMinimumScale = 0.55;
static NSTimeInterval gDateLyricsPauseTimeout = 2.0;
static NSTimeInterval gDateLyricsLineHoldDuration = 2.0;
static BOOL gDateLyricsPauseWhenScreenOff = YES;
// Whether the SpringBoard consumer is active (screen on, or screen-off with
// PauseWhenScreenOff disabled). Music reads this to decide whether to publish.
static BOOL gDateLyricsConsumerActive = YES;
// SpringBoard-side screen state. Only meaningful in the SpringBoard process.
static BOOL gDateLyricsScreenIsOn = YES;

static BOOL gDateLyricsDebugLogging = NO;
static NSString *GetLyricsRootPath(void);

// Diagnostic ring buffer, written to Library/DateLyrics/transition-debug.log inside
// SpringBoard's container. Temporary — remove once the split-boundary glitch is
// understood. Off unless the DebugLogging preference is set.
static void DateLyricsDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void DateLyricsDebugLog(NSString *format, ...) {
    if (!gDateLyricsDebugLogging) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSMutableArray<NSString *> *buffer = nil;
    static dispatch_queue_t queue = nil;
    static NSUInteger sinceFlush = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        buffer = [NSMutableArray array];
        queue = dispatch_queue_create("com.shalamand3r.datelyrics.debuglog", DISPATCH_QUEUE_SERIAL);
    });

    NSString *stamped = [NSString stringWithFormat:@"%.3f %@", [NSDate timeIntervalSinceReferenceDate], message];
    dispatch_async(queue, ^{
        [buffer addObject:stamped];
        if (buffer.count > 500) {
            [buffer removeObjectsInRange:NSMakeRange(0, buffer.count - 500)];
        }
        if (++sinceFlush < 20) return;
        sinceFlush = 0;
        NSString *path = [GetLyricsRootPath() stringByAppendingPathComponent:@"transition-debug.log"];
        [[buffer componentsJoinedByString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}

static NSHashTable<CSProminentSubtitleDateView *> *gDateLyricsDateViews = nil;
static NSHashTable<UIView *> *gDateLyricsWidgetSlots = nil;
static NSDictionary *gDateLyricsCurrentPayload = nil;
static BOOL gDateLyricsHapticsEnabled = NO;
static NSInteger gDateLyricsHapticStyleSyllable = 1;
static NSInteger gDateLyricsHapticStyleLine = 2;

static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot);
static _UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view);
static void DateLyricsPrepareAndApplyDateLabel(_UIAnimatingLabel *label);
static const void *kDateLyricsForcedWidgetDateVisibleKey = &kDateLyricsForcedWidgetDateVisibleKey;
static const void *kDateLyricsOriginalHiddenKey = &kDateLyricsOriginalHiddenKey;
static const void *kDateLyricsRestoringStockDateKey = &kDateLyricsRestoringStockDateKey;
static const void *kDateLyricsLabelShowingLyricKey = &kDateLyricsLabelShowingLyricKey;
static const void *kDateLyricsAnimatingTransitionKey = &kDateLyricsAnimatingTransitionKey;
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
// Set when a content update arrived mid-transition and must be applied on completion.
static const void *kDateLyricsPendingApplyKey = &kDateLyricsPendingApplyKey;
// Cached DateLyricsSplitPlan for the line currently on the label.
static const void *kDateLyricsSplitPlanKey = &kDateLyricsSplitPlanKey;
// Latched (grow-only) wrap width for the label. See DateLyricsSplitAvailableWidth.
static const void *kDateLyricsSplitWidthKey = &kDateLyricsSplitWidthKey;
// Frame the label is pinned to for the duration of a line transition.
static const void *kDateLyricsFrozenFrameKey = &kDateLyricsFrozenFrameKey;

static NSString *const kDateLyricsPrefsSuite = @"com.shalamand3r.datelyrics";
static NSString *const kDateLyricsCurrentLineKey = @"CurrentLyricLine";
static NSString *const kDateLyricsBridgeFilePath = @"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.current-line.txt";
static CFStringRef const kDateLyricsCurrentLineChangedNotification = CFSTR("com.shalamand3r.datelyrics.current-line.changed");
static CFStringRef const kDateLyricsLegacyCurrentLineChangedNotification = CFSTR("com.82flex.amlyrics.current-line.changed");
static const NSTimeInterval kDateLyricsPayloadFreshnessWindow = 6.0;
static const NSUInteger kDateLyricsMaxMemoryCacheEntries = 40;
static const NSUInteger kDateLyricsMaxDiskCacheEntries = 100;
static uint64_t gDateLyricsPayloadRevision = 0;
static NSString *GetLyricsRootPath(void);

typedef NS_ENUM(NSInteger, DateLyricsTransitionStyle) {
    DateLyricsTransitionStyleFade = 0,
    DateLyricsTransitionStyleSlideUp = 1,
    DateLyricsTransitionStyleSlideDown = 2,
    DateLyricsTransitionStylePush = 3,
    DateLyricsTransitionStylePop = 4,
};

static BOOL DateLyricsIsSpringBoardHost(void) {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    NSString *processName = [NSProcessInfo processInfo].processName;
    return [bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
           [processName isEqualToString:@"SpringBoard"];
}

static BOOL DateLyricsIsMusicHost(void) {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    NSString *processName = [NSProcessInfo processInfo].processName;
    return [bundleIdentifier isEqualToString:@"com.apple.Music"] ||
           [processName isEqualToString:@"Music"];
}

static NSString *DateLyricsStorefront(void) {
    NSString *countryCode = [NSLocale currentLocale].countryCode;
    if (![countryCode isKindOfClass:NSString.class] || countryCode.length != 2) return @"us";
    return countryCode.lowercaseString;
}

static NSString *DateLyricsPreferredLocale(void) {
    NSString *locale = [NSLocale preferredLanguages].firstObject;
    if (![locale isKindOfClass:NSString.class] || locale.length == 0) return @"en-US";
    return [locale stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"en-US";
}

static NSString *DateLyricsLocalCurrentLinePath(void) {
    return [GetLyricsRootPath() stringByAppendingPathComponent:@"current-line.txt"];
}

static NSString *DateLyricsMusicContainerCurrentLinePath(void) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) return nil;
    LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:@"com.apple.Music"];
    NSURL *containerURL = [proxy respondsToSelector:@selector(dataContainerURL)] ? proxy.dataContainerURL : nil;
    if (!containerURL) return nil;
    return [[containerURL.path stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"DateLyrics/current-line.txt"];
}

static NSTimeInterval DateLyricsParseTimeString(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return 0;
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@":"];
    if (parts.count == 1) return value.doubleValue;
    if (parts.count == 2) return (parts[0].doubleValue * 60.0) + parts[1].doubleValue;
    if (parts.count == 3) return (parts[0].doubleValue * 3600.0) + (parts[1].doubleValue * 60.0) + parts[2].doubleValue;
    return 0;
}

static NSDictionary *DateLyricsMakePayload(NSString *text, NSRange activeRange) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;
    NSMutableDictionary *payload = [@{ @"text": text } mutableCopy];
    if (activeRange.location != NSNotFound && NSMaxRange(activeRange) <= text.length) {
        payload[@"loc"] = @(activeRange.location);
        payload[@"len"] = @(activeRange.length);
    }
    
    return payload;
}

static NSDictionary *DateLyricsMakePayloadWithBackgroundRange(NSString *text, NSRange activeRange, NSRange backgroundRange) {
    NSDictionary *basePayload = DateLyricsMakePayload(text, activeRange);
    NSMutableDictionary *payload = nil;
    if (basePayload) {
        payload = [basePayload mutableCopy];
    }
    if (payload.count == 0) return nil;
    if (backgroundRange.location != NSNotFound && NSMaxRange(backgroundRange) <= text.length) {
        payload[@"bgLoc"] = @(backgroundRange.location);
        payload[@"bgLen"] = @(backgroundRange.length);
    }
    
    return payload;
}

static void DateLyricsSetRangeFields(NSMutableDictionary *payload, NSString *prefix, NSRange range) {
    if (![payload isKindOfClass:NSMutableDictionary.class] || prefix.length == 0) return;

    NSString *locKey = [prefix stringByAppendingString:@"Loc"];
    NSString *lenKey = [prefix stringByAppendingString:@"Len"];
    if (range.location != NSNotFound && range.length > 0) {
        payload[locKey] = @(range.location);
        payload[lenKey] = @(range.length);
    } else {
        [payload removeObjectForKey:locKey];
        [payload removeObjectForKey:lenKey];
    }
}

static NSRange DateLyricsRangeFromPayload(NSDictionary *payload, NSString *prefix, NSUInteger textLength) {
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

static NSString *DateLyricsSerializePayload(NSDictionary *payload) {
    if (![payload isKindOfClass:NSDictionary.class]) return @"";
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return @"";
    NSString *string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return string ?: @"";
}

static NSDictionary *DateLyricsDeserializePayloadString(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) return nil;
    NSData *json = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (json) {
        id object = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
        if ([object isKindOfClass:NSDictionary.class] &&
            ([object[@"text"] isKindOfClass:NSString.class] || [object[@"cleared"] boolValue])) {
            return object;
        }
    }
    return DateLyricsMakePayload(string, NSMakeRange(NSNotFound, 0));
}

static NSDictionary *DateLyricsPayloadForPublication(NSDictionary *payload) {
    NSMutableDictionary *published = [NSMutableDictionary dictionary];
    if ([payload isKindOfClass:NSDictionary.class]) {
        [published addEntriesFromDictionary:payload];
    } else {
        published[@"cleared"] = @YES;
    }
    published[@"protocolVersion"] = @2;
    published[@"emittedAt"] = @([[NSDate date] timeIntervalSince1970]);
    published[@"revision"] = @(__sync_add_and_fetch(&gDateLyricsPayloadRevision, 1));
    published[@"source"] = DateLyricsIsMusicHost() ? @"music" : @"springboard";
    return [published copy];
}

static BOOL DateLyricsPayloadIsFresh(NSDictionary *payload) {
    if (![payload isKindOfClass:NSDictionary.class]) return NO;
    NSNumber *emittedAt = payload[@"emittedAt"];
    if (![emittedAt isKindOfClass:NSNumber.class]) return NO;
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - emittedAt.doubleValue;
    return age >= -2.0 && age <= kDateLyricsPayloadFreshnessWindow;
}

static void DateLyricsApplyCurrentLineToAllCoverSheets(void) {
    if (gDateLyricsDateViews) {
        for (CSProminentSubtitleDateView *dateView in gDateLyricsDateViews) {
            if (![dateView isKindOfClass:UIView.class]) continue;
            DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(dateView));
            [dateView setNeedsLayout];
        }
    }
    if (gDateLyricsWidgetSlots) {
        for (UIView *widgetSlot in gDateLyricsWidgetSlots) {
            if (![widgetSlot isKindOfClass:UIView.class]) continue;
            DateLyricsUpdateWidgetDateView(widgetSlot);
        }
    }
}

static NSDictionary *DateLyricsReadPayloadFromBridgeFile(void) {
    NSString *line = [NSString stringWithContentsOfFile:kDateLyricsBridgeFilePath encoding:NSUTF8StringEncoding error:nil];
    return DateLyricsDeserializePayloadString(line);
}

static void DateLyricsPlayHaptic(NSInteger style) {
    if (!gDateLyricsHapticsEnabled || style < 0 || style > 4) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyle)style];
        [generator prepare];
        [generator impactOccurred];
    });
}

static NSDictionary *DateLyricsReadPayloadFromMusicContainer(void) {
    NSString *path = DateLyricsMusicContainerCurrentLinePath();
    if (path.length == 0) return nil;
    NSString *line = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return DateLyricsDeserializePayloadString(line);
}

static void DateLyricsPersistCurrentLineSharedState(NSDictionary *payload) {
    NSString *publishedLine = DateLyricsSerializePayload(payload);
    [publishedLine writeToFile:kDateLyricsBridgeFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CFPreferencesSetAppValue((__bridge CFStringRef)kDateLyricsCurrentLineKey, (__bridge CFPropertyListRef)publishedLine, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDateLyricsPrefsSuite);
}

static void DateLyricsPublishPayload(NSDictionary *payload) {
    NSDictionary *publishedPayload = DateLyricsPayloadForPublication(payload);
    NSString *publishedLine = DateLyricsSerializePayload(publishedPayload);
    
    if (DateLyricsIsSpringBoardHost()) {
        DateLyricsPersistCurrentLineSharedState(publishedPayload);
    } else {
        [publishedLine writeToFile:DateLyricsLocalCurrentLinePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kDateLyricsCurrentLineChangedNotification, NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kDateLyricsLegacyCurrentLineChangedNotification, NULL, NULL, YES);
}

static NSDictionary *DateLyricsStoredPayload(void) {
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSDictionary *musicContainerPayload = DateLyricsReadPayloadFromMusicContainer();
    if (DateLyricsPayloadIsFresh(musicContainerPayload)) [candidates addObject:musicContainerPayload];
    NSDictionary *filePayload = DateLyricsReadPayloadFromBridgeFile();
    if (DateLyricsPayloadIsFresh(filePayload)) [candidates addObject:filePayload];

    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kDateLyricsCurrentLineKey, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    NSDictionary *prefsPayload = DateLyricsDeserializePayloadString(CFBridgingRelease(value));
    if (DateLyricsPayloadIsFresh(prefsPayload)) [candidates addObject:prefsPayload];

    NSDictionary *newest = nil;
    for (NSDictionary *candidate in candidates) {
        if (!newest || [candidate[@"emittedAt"] doubleValue] > [newest[@"emittedAt"] doubleValue]) {
            newest = candidate;
        }
    }
    return newest;
}

static NSDictionary *DateLyricsCurrentRenderablePayload(void) {
    if (gDateLyricsCurrentPayload) {
        return DateLyricsPayloadIsFresh(gDateLyricsCurrentPayload) ? gDateLyricsCurrentPayload : nil;
    }
    return DateLyricsStoredPayload();
}

static void DateLyricsApplyLabelContent(_UIAnimatingLabel *label, NSString *displayText, NSAttributedString *attrDisplayText) {
    if (![label isKindOfClass:UILabel.class]) return;
    if (attrDisplayText) {
        label.attributedText = attrDisplayText;
    } else {
        UIColor *textColor = label.textColor ?: [UIColor whiteColor];
        if ([textColor respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
            textColor = [textColor resolvedColorWithTraitCollection:label.traitCollection];
        }
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:displayText ?: @""];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        [cleanStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, cleanStr.length)];
        label.attributedText = cleanStr;
    }
}

static UIFont *DateLyricsConfiguredFontForLabel(_UIAnimatingLabel *label) {
    UIFont *baseFont = label.font ?: [UIFont systemFontOfSize:34.0 weight:UIFontWeightSemibold];
    if (!gDateLyricsUseCustomFont || gDateLyricsCustomFontName.length == 0) {
        return baseFont;
    }

    UIFont *customFont = [UIFont fontWithName:gDateLyricsCustomFontName size:baseFont.pointSize];
    return customFont ?: baseFont;
}

static CGFloat DateLyricsMeasuredLineWidth(NSString *text, UIFont *font) {
    if (![text isKindOfClass:NSString.class] || text.length == 0 || ![font isKindOfClass:UIFont.class]) return 0.0;
    NSString *measureText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (measureText.length == 0) return 0.0;

    CGRect rect = [measureText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                         attributes:@{ NSFontAttributeName: font }
                                            context:nil];
    return ceil(CGRectGetWidth(rect));
}

static DateLyricsTimedLine *DateLyricsComputeFilteredLine(DateLyricsTimedLine *origLine) {
    if (!origLine) return nil;
    if (gDateLyricsShowAdlibs) return origLine;

    NSMutableIndexSet *parenthesizedIndices = [NSMutableIndexSet indexSet];
    BOOL insideParens = NO;
    for (NSUInteger i = 0; i < origLine.words.count; i++) {
        DateLyricsTimedWord *word = origLine.words[i];
        NSString *wText = word.text;
        NSString *sepBefore = word.separatorBefore;
        
        if ([wText hasPrefix:@"("] || [wText hasPrefix:@"["] || [sepBefore containsString:@"("] || [sepBefore containsString:@"["]) {
            insideParens = YES;
        }
        
        if (insideParens) {
            [parenthesizedIndices addIndex:i];
        }
        
        if ([wText hasSuffix:@")"] || [wText hasSuffix:@"]"]) {
            insideParens = NO;
        }
    }

    BOOL hasBackground = NO;
    for (NSUInteger i = 0; i < origLine.words.count; i++) {
        DateLyricsTimedWord *word = origLine.words[i];
        if (word.isBackground || [parenthesizedIndices containsIndex:i]) {
            hasBackground = YES;
            break;
        }
    }
    if (!hasBackground) {
        return origLine;
    }

    DateLyricsTimedLine *filteredLine = [DateLyricsTimedLine new];
    filteredLine.begin = origLine.begin;
    filteredLine.end = origLine.end;

    NSMutableArray<DateLyricsTimedWord *> *filteredWords = [NSMutableArray array];
    NSMutableString *newText = [NSMutableString string];

    for (NSUInteger i = 0; i < origLine.words.count; i++) {
        DateLyricsTimedWord *word = origLine.words[i];
        if (word.isBackground || [parenthesizedIndices containsIndex:i]) {
            continue;
        }
        DateLyricsTimedWord *newWord = [DateLyricsTimedWord new];
        newWord.begin = word.begin;
        newWord.end = word.end;
        newWord.background = NO;
        
        // Strip any residual parenthesis characters if they were on the word boundaries
        NSString *wordText = word.text;
        NSString *sepBefore = word.separatorBefore;
        if ([wordText hasPrefix:@"("]) wordText = [wordText substringFromIndex:1];
        if ([wordText hasPrefix:@"["]) wordText = [wordText substringFromIndex:1];
        if ([wordText hasSuffix:@")"]) wordText = [wordText substringToIndex:wordText.length - 1];
        if ([wordText hasSuffix:@"]"]) wordText = [wordText substringToIndex:wordText.length - 1];
        newWord.text = wordText;

        if (filteredWords.count == 0) {
            newWord.separatorBefore = @"";
        } else {
            // Clean up any remaining parenthesis from the separator
            NSString *cleanedSep = sepBefore;
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@"(" withString:@""];
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@"[" withString:@""];
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@")" withString:@""];
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@"]" withString:@""];
            newWord.separatorBefore = cleanedSep.length > 0 ? cleanedSep : @" ";
        }
        [filteredWords addObject:newWord];

        if (newWord.separatorBefore.length > 0) {
            [newText appendString:newWord.separatorBefore];
        }
        if (newWord.text.length > 0) {
            [newText appendString:newWord.text];
        }
    }

    filteredLine.words = [filteredWords copy];
    filteredLine.text = [newText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (filteredWords.count > 0) {
        filteredLine.begin = filteredWords.firstObject.begin;
        filteredLine.end = filteredWords.lastObject.end;
    } else {
        filteredLine.begin = origLine.begin;
        filteredLine.end = origLine.end;
    }

    if (filteredLine.text.length == 0 || filteredLine.words.count == 0) {
        return nil;
    }
    return filteredLine;
}

// Filtering a line is pure — same input, same ShowAdlibs setting, same result — but it
// was being recomputed for every line in the song on every playback tick, allocating a
// replacement line, N replacement words and a rebuilt string each time, purely to work
// out which line is currently playing. At ~4 ticks/sec across a full lyric sheet that
// was the single largest CPU cost in the Music process. Memoised per line; the flag
// invalidates if ShowAdlibs is toggled at runtime.
static DateLyricsTimedLine *DateLyricsGetFilteredLine(DateLyricsTimedLine *origLine) {
    if (!origLine) return nil;
    if (origLine.amlCachedFilteredValid && origLine.amlCachedFilteredAdlibs == gDateLyricsShowAdlibs) {
        return origLine.amlCachedFiltered;
    }

    DateLyricsTimedLine *filtered = DateLyricsComputeFilteredLine(origLine);
    origLine.amlCachedFiltered = filtered;
    origLine.amlCachedFilteredAdlibs = gDateLyricsShowAdlibs;
    origLine.amlCachedFilteredValid = YES;
    return filtered;
}

static NSString *DateLyricsStripParentheses(NSString *text) {
    if (!text) return nil;
    if (gDateLyricsShowAdlibs) return text;

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\([^)]*\\)|\\[[^]]*\\]" options:0 error:nil];
    });

    NSString *stripped = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    
    static NSRegularExpression *spacesRegex = nil;
    static dispatch_once_t spacesOnceToken;
    dispatch_once(&spacesOnceToken, ^{
        spacesRegex = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    });
    stripped = [spacesRegex stringByReplacingMatchesInString:stripped options:0 range:NSMakeRange(0, stripped.length) withTemplate:@" "];
    stripped = [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return stripped.length > 0 ? stripped : nil;
}

// Width to wrap against.
//
// Every candidate width on screen is content-dependent: the label hugs its text,
// and so does CSProminentSubtitleDateView. Measuring either one means the wrap
// width moves whenever our own output changes length, and each move re-wraps the
// line, changes the visible segment, and fires another transition.
//
// Two specific failures this caused:
//   - short segment -> label shrinks -> narrower wrap -> more segments -> repeat
//   - short line followed by a long line: the long line is first wrapped against
//     the width left over from the short one, then the date view grows to its real
//     slot width and the line is re-wrapped, producing a second transition
//     immediately after the first. (The reported non-split -> split glitch.)
//
// So the value is latched and only ever allowed to grow. A shrink is always our
// own content getting shorter; a genuine growth (rotation, a wider slot) is rare
// and legitimate. Once latched, the wrap width is effectively constant, which is
// the property that actually matters — being slightly conservative just means a
// line splits one segment earlier than strictly necessary.
static CGFloat DateLyricsSplitAvailableWidth(UILabel *label) {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;

    // Only the date view is latched. A bogus reading from some other ancestor could
    // poison the latch permanently, and since the latch never shrinks, too wide
    // would mean lines silently stop splitting at all.
    CGFloat measured = 0.0;
    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    if (dateClass) {
        UIView *view = label.superview;
        while ([view isKindOfClass:UIView.class]) {
            if ([view isKindOfClass:dateClass]) {
                measured = CGRectGetWidth(view.bounds);
                break;
            }
            view = view.superview;
        }
    }

    if (measured > 1.0) {
        if (measured > screenWidth) measured = screenWidth;
        NSNumber *latched = objc_getAssociatedObject(label, kDateLyricsSplitWidthKey);
        CGFloat width = latched ? (CGFloat)latched.doubleValue : 0.0;
        if (measured > width + 0.5) {
            width = measured;
            objc_setAssociatedObject(label, kDateLyricsSplitWidthKey, @(width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (width > 1.0) return width;
    }

    // Date view not found yet (label not installed, or class renamed on a newer OS).
    // Fall back without latching so a transient bad value is not made permanent.
    NSNumber *latched = objc_getAssociatedObject(label, kDateLyricsSplitWidthKey);
    if (latched.doubleValue > 1.0) return (CGFloat)latched.doubleValue;
    return screenWidth - 60.0;
}

// Greedy word wrap. Returns nil when the text fits on one line or cannot be split
// (a single word wider than the available width).
static NSArray<NSValue *> *DateLyricsComputeSegments(NSString *text, UIFont *font, CGFloat maxWidth) {
    if (DateLyricsMeasuredLineWidth(text, font) <= maxWidth) return nil;

    NSMutableArray<NSValue *> *wordRanges = [NSMutableArray array];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByWords
                          usingBlock:^(__unused NSString *substring, NSRange substringRange, __unused NSRange enclosingRange, __unused BOOL *stop) {
        [wordRanges addObject:[NSValue valueWithRange:substringRange]];
    }];
    if (wordRanges.count < 2) return nil;

    NSMutableArray<NSValue *> *segmentRanges = [NSMutableArray array];
    NSUInteger segmentStart = 0;
    NSUInteger wordsInCurrentLine = 0;

    for (NSValue *value in wordRanges) {
        NSRange wordRange = value.rangeValue;
        if (wordsInCurrentLine == 0) {
            wordsInCurrentLine = 1;
            continue;
        }

        NSUInteger candidateEnd = NSMaxRange(wordRange);
        NSString *candidateLine = [text substringWithRange:NSMakeRange(segmentStart, candidateEnd - segmentStart)];
        if (DateLyricsMeasuredLineWidth(candidateLine, font) <= maxWidth) {
            wordsInCurrentLine++;
            continue;
        }

        NSUInteger breakLocation = wordRange.location;
        NSString *committedLine = [text substringWithRange:NSMakeRange(segmentStart, breakLocation - segmentStart)];
        if (DateLyricsMeasuredLineWidth(committedLine, font) > maxWidth) {
            return nil;
        }

        [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, breakLocation - segmentStart)]];
        segmentStart = breakLocation;
        wordsInCurrentLine = 1;
    }

    NSString *finalLine = [text substringFromIndex:segmentStart];
    if (DateLyricsMeasuredLineWidth(finalLine, font) > maxWidth) return nil;
    [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, text.length - segmentStart)]];
    if (segmentRanges.count < 2) return nil;

    // Segments break at the *start* of the next word, so every one but the last
    // carries a trailing space ("break down the door like a "), which throws the
    // centring off by a space width. Only the length shrinks, never the location,
    // so highlight offsets — measured from range.location — are unaffected.
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSValue *> *trimmed = [NSMutableArray arrayWithCapacity:segmentRanges.count];
    for (NSValue *value in segmentRanges) {
        NSRange range = value.rangeValue;
        while (range.length > 0 && [whitespace characterIsMember:[text characterAtIndex:NSMaxRange(range) - 1]]) {
            range.length -= 1;
        }
        if (range.length > 0) [trimmed addObject:[NSValue valueWithRange:range]];
    }
    if (trimmed.count < 2) return nil;

    return trimmed;
}

static NSDictionary *DateLyricsSplitPayloadForLabel(NSDictionary *payload, UILabel *label, UIFont *baseFont) {
    if (!gDateLyricsSplitLongLines) return nil;
    if (![payload[@"timed"] boolValue]) return nil;

    NSString *text = payload[@"text"];
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;

    UIFont *measureFont = [baseFont isKindOfClass:UIFont.class] ? baseFont : nil;
    if (!measureFont) return nil;

    CGFloat maxWidth = DateLyricsSplitAvailableWidth(label);
    if (maxWidth <= 1.0) return nil;

    id lineId = payload[@"lineId"];
    NSString *fontKey = [NSString stringWithFormat:@"%@|%.2f", measureFont.fontName, measureFont.pointSize];

    // The segmentation is computed once per line and then reused verbatim for the
    // rest of that line. Recomputing it every syllable tick meant any jitter in the
    // measured width silently produced a different set of segments mid-line, which
    // read as a spurious line change and fired another transition.
    DateLyricsSplitPlan *plan = objc_getAssociatedObject(label, kDateLyricsSplitPlanKey);
    BOOL planMatches = plan
        && [plan.text isEqualToString:text]
        && [plan.fontKey isEqualToString:fontKey]
        && fabs(plan.width - maxWidth) < 0.5
        && (plan.lineId == lineId || [plan.lineId isEqual:lineId]);

    if (!planMatches) {
        plan = [DateLyricsSplitPlan new];
        plan.text = text;
        plan.lineId = lineId;
        plan.width = maxWidth;
        plan.fontKey = fontKey;
        plan.segments = DateLyricsComputeSegments(text, measureFont, maxWidth);
        plan.lastIndex = 0;
        objc_setAssociatedObject(label, kDateLyricsSplitPlanKey, plan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DateLyricsDebugLog(@"PLAN w=%.1f segs=%lu font=%@ text='%@'",
                           maxWidth, (unsigned long)plan.segments.count, fontKey, text);
    }

    // segments == nil is a cached "this line does not need splitting", so we do not
    // re-measure it on every tick either.
    NSArray<NSValue *> *segmentRanges = plan.segments;
    if (segmentRanges.count < 2) return nil;

    NSRange highlightRange = DateLyricsRangeFromPayload(payload, @"", text.length);
    NSRange backgroundRange = DateLyricsRangeFromPayload(payload, @"bg", text.length);
    NSRange focusRange = DateLyricsRangeFromPayload(payload, @"focus", text.length);
    NSRange focusBackgroundRange = DateLyricsRangeFromPayload(payload, @"focusBg", text.length);

    NSUInteger targetIndex = plan.lastIndex;
    for (NSUInteger idx = 0; idx < segmentRanges.count; idx++) {
        NSRange segmentRange = [segmentRanges[idx] rangeValue];
        BOOL containsHighlight = focusRange.location != NSNotFound && NSIntersectionRange(segmentRange, focusRange).length > 0;
        BOOL containsBackground = focusBackgroundRange.location != NSNotFound && NSIntersectionRange(segmentRange, focusBackgroundRange).length > 0;
        if (containsHighlight || containsBackground) {
            targetIndex = idx;
            break;
        }
    }

    // Monotonic within a line. Word timing has gaps — at the start of a line, in
    // instrumental pauses, and after the last word there is no active range at all.
    // The old code fell back to segment 0 in those moments, so a long line would
    // animate forward to segment 2, snap back to segment 0, then animate forward
    // again. Advancing only is the correct reading of a line being sung once
    // through; the plan resets when lineId changes.
    if (targetIndex < plan.lastIndex) targetIndex = plan.lastIndex;
    if (targetIndex >= segmentRanges.count) targetIndex = segmentRanges.count - 1;
    plan.lastIndex = targetIndex;

    NSRange targetRange = [segmentRanges[targetIndex] rangeValue];
    NSString *segmentText = [text substringWithRange:targetRange];
    if (segmentText.length == 0) return nil;

    NSMutableDictionary *splitPayload = [payload mutableCopy];
    splitPayload[@"text"] = segmentText;
    splitPayload[@"splitApplied"] = @YES;
    // Each segment is presented as its own line, so give it its own identity.
    // Line-change detection otherwise falls back to comparing the rendered text,
    // which treats two consecutive segments with identical wording (a repeated
    // "na na na") as unchanged and skips the transition between them.
    splitPayload[@"lineId"] = [NSString stringWithFormat:@"%@#%lu", lineId ?: @"", (unsigned long)targetIndex];

    if (highlightRange.location != NSNotFound) {
        NSRange intersection = NSIntersectionRange(targetRange, highlightRange);
        if (intersection.length > 0) {
            splitPayload[@"loc"] = @(intersection.location - targetRange.location);
            splitPayload[@"len"] = @(intersection.length);
        } else {
            [splitPayload removeObjectForKey:@"loc"];
            [splitPayload removeObjectForKey:@"len"];
        }
    }

    if (backgroundRange.location != NSNotFound) {
        NSRange intersection = NSIntersectionRange(targetRange, backgroundRange);
        if (intersection.length > 0) {
            splitPayload[@"bgLoc"] = @(intersection.location - targetRange.location);
            splitPayload[@"bgLen"] = @(intersection.length);
        } else {
            [splitPayload removeObjectForKey:@"bgLoc"];
            [splitPayload removeObjectForKey:@"bgLen"];
        }
    }

    return splitPayload;
}

static NSUInteger DateLyricsBeginLabelTransition(_UIAnimatingLabel *label) {
    NSUInteger generation = [objc_getAssociatedObject(label, kDateLyricsTransitionGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(label, kDateLyricsTransitionGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsPendingApplyKey, nil, OBJC_ASSOCIATION_ASSIGN);

    // Pin the geometry for the duration of the animation.
    //
    // A UILabel is sized to its text. CATransition works by cross-fading the
    // layer's old backing store against the new one — if the layer's bounds change
    // while that is in flight, the two renderings are laid out at different sizes
    // and both stay visible. That is the tearing seen when a full line is followed
    // by a much shorter split segment, and vice versa.
    //
    // The frozen frame is widened to the stable (latched) width so neither the
    // outgoing nor the incoming line is clipped, and re-centred so centred text
    // does not appear to jump sideways. layoutSubviews re-asserts this every pass
    // until the transition completes, so nothing UIKit does in between can resize
    // the layer mid-animation.
    CGRect frozen = label.frame;
    CGFloat stableWidth = DateLyricsSplitAvailableWidth(label);
    if (stableWidth > frozen.size.width) {
        frozen.origin.x -= (stableWidth - frozen.size.width) / 2.0;
        frozen.size.width = stableWidth;
    }
    if (!CGRectIsEmpty(frozen)) {
        objc_setAssociatedObject(label, kDateLyricsFrozenFrameKey, [NSValue valueWithCGRect:frozen], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        label.frame = frozen;
    }

    [label.layer removeAllAnimations];
    label.alpha = 1.0;
    label.transform = CGAffineTransformIdentity;
    label.clipsToBounds = YES;
    return generation;
}

static void DateLyricsFinishLabelTransitionAfterDelay(_UIAnimatingLabel *label, NSUInteger generation, NSTimeInterval duration) {
    __weak _UIAnimatingLabel *weakLabel = label;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _UIAnimatingLabel *strongLabel = weakLabel;
        if (!strongLabel) return;
        NSUInteger currentGeneration = [objc_getAssociatedObject(strongLabel, kDateLyricsTransitionGenerationKey) unsignedIntegerValue];
        if (currentGeneration != generation) return;
        [strongLabel.layer removeAnimationForKey:@"DateLyricsLineTransition"];
        strongLabel.alpha = 1.0;
        strongLabel.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(strongLabel, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(strongLabel, kDateLyricsPendingApplyKey, nil, OBJC_ASSOCIATION_ASSIGN);
        // Release the pinned geometry; normal layout resumes on the next pass.
        objc_setAssociatedObject(strongLabel, kDateLyricsFrozenFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [strongLabel setNeedsLayout];
        [strongLabel _amlApplyCurrentLyric];
    });
}

static void DateLyricsAnimateLabelTransition(_UIAnimatingLabel *label, NSString *previousDisplayText, NSString *displayText, NSAttributedString *attrDisplayText) {
    if (![label isKindOfClass:UILabel.class]) {
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
        return;
    }

    NSTimeInterval duration = MAX(0.0, gDateLyricsTransitionDuration);
    if (!gDateLyricsTransitionsEnabled || duration <= 0.0 || previousDisplayText.length == 0) {
        [label.layer removeAllAnimations];
        label.alpha = 1.0;
        label.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(label, kDateLyricsPendingApplyKey, nil, OBJC_ASSOCIATION_ASSIGN);
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
        return;
    }

    NSUInteger generation = DateLyricsBeginLabelTransition(label);

    switch (gDateLyricsTransitionStyle) {
        case DateLyricsTransitionStyleFade: {
            [UIView transitionWithView:label duration:duration options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent | UIViewAnimationOptionBeginFromCurrentState animations:^{
                DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
            } completion:nil];
            break;
        }
        case DateLyricsTransitionStyleSlideUp:
        case DateLyricsTransitionStyleSlideDown:
        case DateLyricsTransitionStylePush: {
            CATransition *transition = [CATransition animation];
            transition.duration = duration;
            transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            transition.type = kCATransitionPush;
            if (gDateLyricsTransitionStyle == DateLyricsTransitionStyleSlideUp) {
                transition.subtype = kCATransitionFromTop;
            } else if (gDateLyricsTransitionStyle == DateLyricsTransitionStylePush) {
                transition.subtype = kCATransitionFromRight;
            } else {
                transition.subtype = kCATransitionFromBottom;
            }
            [label.layer addAnimation:transition forKey:@"DateLyricsLineTransition"];
            // _UIAnimatingLabel animates its own content changes — that is what the
            // class is for, and it is why Apple uses it for the lock screen date.
            // Left alone, its built-in animation runs at the same time as the
            // CATransition we just installed, so the layer carries two overlapping
            // animations and briefly renders both the old and new line. Suppressing
            // implicit animations here leaves only our explicit transition, which
            // addAnimation: installs and is therefore unaffected.
            [UIView performWithoutAnimation:^{
                DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
                [label layoutIfNeeded];
            }];
            break;
        }
        case DateLyricsTransitionStylePop: {
            // Same reasoning as the slide styles: the content swap itself must not
            // animate, only the scale/alpha below.
            [UIView performWithoutAnimation:^{
                DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
                [label layoutIfNeeded];
            }];
            label.transform = CGAffineTransformMakeScale(0.9, 0.9);
            label.alpha = 0.0;
            [UIView animateWithDuration:duration delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
                label.transform = CGAffineTransformIdentity;
                label.alpha = 1.0;
            } completion:nil];
            break;
        }
        default: {
            DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
            break;
        }
    }
    DateLyricsFinishLabelTransitionAfterDelay(label, generation, duration);
}

static NSString *DateLyricsHighlightSignature(NSDictionary *payload) {
    if (![payload isKindOfClass:NSDictionary.class]) return nil;
    NSNumber *loc = payload[@"loc"];
    NSNumber *len = payload[@"len"];
    NSNumber *bgLoc = payload[@"bgLoc"];
    NSNumber *bgLen = payload[@"bgLen"];
    if (!loc && !bgLoc) return nil;
    return [NSString stringWithFormat:@"%@:%@:%@:%@", loc ?: @"-", len ?: @"-", bgLoc ?: @"-", bgLen ?: @"-"];
}

static void DateLyricsSchedulePayloadExpiry(NSDictionary *payload) {
    NSNumber *emittedAt = payload[@"emittedAt"];
    if (!emittedAt) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kDateLyricsPayloadFreshnessWindow + 0.2) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([gDateLyricsCurrentPayload[@"emittedAt"] isEqual:emittedAt] && !DateLyricsPayloadIsFresh(gDateLyricsCurrentPayload)) {
            gDateLyricsCurrentPayload = @{};
            DateLyricsApplyCurrentLineToAllCoverSheets();
        }
    });
}

static void DateLyricsCurrentLineChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *previousPayload = gDateLyricsCurrentPayload;
        NSDictionary *nextPayload = DateLyricsStoredPayload() ?: @{};
        NSString *previousText = previousPayload[@"text"];
        NSString *nextText = nextPayload[@"text"];
        if (previousText.length > 0 && nextText.length > 0) {
            id previousLineID = previousPayload[@"lineId"];
            id nextLineID = nextPayload[@"lineId"];
            BOOL lineChanged = previousLineID && nextLineID && ![previousLineID isEqual:nextLineID];
            if (lineChanged) {
                DateLyricsPlayHaptic(gDateLyricsHapticStyleLine);
            } else {
                NSString *previousHighlight = DateLyricsHighlightSignature(previousPayload);
                NSString *nextHighlight = DateLyricsHighlightSignature(nextPayload);
                if (nextHighlight && ![nextHighlight isEqualToString:previousHighlight]) {
                    DateLyricsPlayHaptic(gDateLyricsHapticStyleSyllable);
                }
            }
        }
        gDateLyricsCurrentPayload = [nextPayload copy];
        DateLyricsApplyCurrentLineToAllCoverSheets();
        DateLyricsSchedulePayloadExpiry(nextPayload);
    });
}

static NSString *GetLyricsRootPath(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsRootPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
        gLyricsRootPath = [gLyricsRootPath stringByAppendingPathComponent:@"DateLyrics"];
        [[NSFileManager defaultManager] createDirectoryAtPath:gLyricsRootPath withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return gLyricsRootPath;
}

static void DateLyricsWriteRuntimeStatus(void) {
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    NSDictionary *status = @{
        @"host": DateLyricsIsSpringBoardHost() ? @"springboard" : (DateLyricsIsMusicHost() ? @"music" : @"other"),
        @"osVersion": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion],
        @"CSProminentSubtitleDateView": @(NSClassFromString(@"CSProminentSubtitleDateView") != nil),
        @"CSProminentEmptyElementView": @(NSClassFromString(@"CSProminentEmptyElementView") != nil),
        @"UIAnimatingLabel": @(NSClassFromString(@"_UIAnimatingLabel") != nil),
        @"MSVLyricsTTMLParser": @(NSClassFromString(@"MSVLyricsTTMLParser") != nil),
        @"ICMusicKitURLRequest": @(NSClassFromString(@"ICMusicKitURLRequest") != nil),
        @"updatedAt": @([[NSDate date] timeIntervalSince1970])
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToFile:[GetLyricsRootPath() stringByAppendingPathComponent:@"runtime-status.json"] atomically:YES];
    }
}

@interface DateLyricsWordTTMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedLine *> *lines;
@property (nonatomic, strong) DateLyricsTimedLine *currentLine;
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedWord *> *currentWords;
@property (nonatomic, strong) NSMutableString *pendingSeparator;
@property (nonatomic, strong) NSMutableString *currentSpanText;
@property (nonatomic, assign) BOOL insideParagraph;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spanBackgroundStack;
@end

@implementation DateLyricsWordTTMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _pendingSeparator = [NSMutableString string];
        _spanBackgroundStack = [NSMutableArray array];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"p"]) {
        self.insideParagraph = YES;
        self.currentLine = [DateLyricsTimedLine new];
        self.currentLine.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
        self.currentLine.end = DateLyricsParseTimeString(attributeDict[@"end"]);
        self.currentWords = [NSMutableArray array];
        [self.spanBackgroundStack removeAllObjects];
        [self.pendingSeparator setString:@""];
    } else if (self.insideParagraph && [elementName isEqualToString:@"span"]) {
        NSString *role = attributeDict[@"ttm:role"] ?: attributeDict[@"role"];
        BOOL isBackground = [role isEqualToString:@"x-bg"] || [[self.spanBackgroundStack lastObject] boolValue];
        [self.spanBackgroundStack addObject:@(isBackground)];
        BOOL hasTiming = attributeDict[@"begin"] != nil || attributeDict[@"end"] != nil;
        if (hasTiming) {
            DateLyricsTimedWord *word = [DateLyricsTimedWord new];
            word.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
            word.end = DateLyricsParseTimeString(attributeDict[@"end"]);
            word.separatorBefore = [self.pendingSeparator copy] ?: @"";
            word.background = isBackground;
            [self.currentWords addObject:word];
            self.currentSpanText = [NSMutableString string];
            [self.pendingSeparator setString:@""];
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (!self.insideParagraph || string.length == 0) return;
    if (self.currentSpanText) {
        [self.currentSpanText appendString:string];
    } else {
        [self.pendingSeparator appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"span"]) {
        if (self.currentSpanText) {
            DateLyricsTimedWord *word = self.currentWords.lastObject;
            if (word && !word.text.length) {
                word.text = [self.currentSpanText copy];
            }
            self.currentSpanText = nil;
        }
        if (self.spanBackgroundStack.count > 0) {
            [self.spanBackgroundStack removeLastObject];
        }
    } else if ([elementName isEqualToString:@"p"] && self.currentLine) {
        NSMutableString *fullText = [NSMutableString string];
        for (DateLyricsTimedWord *word in self.currentWords) {
            if (word.separatorBefore.length > 0) {
                [fullText appendString:word.separatorBefore];
            }
            if (word.text.length > 0) {
                [fullText appendString:word.text];
            }
        }
        self.currentLine.text = [fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.currentLine.words = [self.currentWords copy];
        if (self.currentLine.text.length > 0 && self.currentLine.words.count > 0) {
            [self.lines addObject:self.currentLine];
        }
        self.currentLine = nil;
        self.currentWords = nil;
        self.insideParagraph = NO;
        [self.spanBackgroundStack removeAllObjects];
        [self.pendingSeparator setString:@""];
    }
}

@end

static NSArray<DateLyricsTimedLine *> *DateLyricsParseWordTimedLines(NSData *data) {
    if (!data.length) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    DateLyricsWordTTMLParserDelegate *delegate = [DateLyricsWordTTMLParserDelegate new];
    parser.delegate = delegate;
    BOOL ok = [parser parse];
    
    if (!ok || delegate.lines.count == 0) return nil;
    return [delegate.lines copy];
}

static void DateLyricsTouchMemoryCacheLocked(NSNumber *storeID) {
    if (!storeID) return;
    [gLyricsCacheOrder removeObject:storeID];
    [gLyricsCacheOrder addObject:storeID];
    while (gLyricsCacheOrder.count > kDateLyricsMaxMemoryCacheEntries) {
        NSNumber *oldestStoreID = gLyricsCacheOrder.firstObject;
        [gLyricsCacheOrder removeObjectAtIndex:0];
        [gLyricsCache removeObjectForKey:oldestStoreID];
        [gWordLyricsCache removeObjectForKey:oldestStoreID];
    }
}

static void DateLyricsPruneDiskCache(void) {
    NSString *rootPath = GetLyricsRootPath();
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:nil];
    NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:@"syllable-lyrics_"] || ![entry hasSuffix:@".xml"]) continue;
        NSString *path = [rootPath stringByAppendingPathComponent:entry];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        [files addObject:@{ @"path": path, @"date": attributes[NSFileModificationDate] ?: [NSDate distantPast] }];
    }
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"date"] compare:right[@"date"]];
    }];
    while (files.count > kDateLyricsMaxDiskCacheEntries) {
        NSDictionary *oldest = files.firstObject;
        [[NSFileManager defaultManager] removeItemAtPath:oldest[@"path"] error:nil];
        [files removeObjectAtIndex:0];
    }
}

static BOOL ParseLyricsData(NSData *data, NSInteger iTunesStoreID, __unused NSInteger lyricsAdamID) {
    if (!data.length || iTunesStoreID <= 0) return NO;

    pthread_mutex_lock(&gLyricsCacheMutex);
    NSNumber *storeIDKey = @(iTunesStoreID);
    if ([gLyricsCache[storeIDKey] count] > 0 || [gWordLyricsCache[storeIDKey] count] > 0) {
        DateLyricsTouchMemoryCacheLocked(storeIDKey);
        pthread_mutex_unlock(&gLyricsCacheMutex);
        return YES;
    }
    pthread_mutex_unlock(&gLyricsCacheMutex);

    NSArray<DateLyricsTimedLine *> *wordLines = DateLyricsParseWordTimedLines(data);
    NSError *parseError = nil;
    NSMutableArray<MSVLyricsLine *> *lyricLines = nil;
    Class parserClass = %c(MSVLyricsTTMLParser);
    if (parserClass) {
        MSVLyricsTTMLParser *parser = [[parserClass alloc] initWithTTMLData:data];
        [parser parseWithError:&parseError];
        if (!parseError) {
            lyricLines = [[parser lyricLines] mutableCopy];
        }
    }
    [lyricLines sortUsingComparator:^NSComparisonResult(MSVLyricsLine *line1, MSVLyricsLine *line2) {
        if (line1.startTime < line2.startTime) {
            return NSOrderedAscending;
        } else if (line1.startTime > line2.startTime) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];
    if (lyricLines.count == 0 && wordLines.count == 0) return NO;

    pthread_mutex_lock(&gLyricsCacheMutex);
    if (lyricLines.count > 0) {
        gLyricsCache[storeIDKey] = [lyricLines copy];
    }
    if (wordLines.count > 0) {
        gWordLyricsCache[storeIDKey] = wordLines;
    }
    DateLyricsTouchMemoryCacheLocked(storeIDKey);
    pthread_mutex_unlock(&gLyricsCacheMutex);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gCurrentContentItem) {
            NSInteger currentStoreID = 0;
            if ([gCurrentContentItem respondsToSelector:@selector(storeID)]) {
                currentStoreID = gCurrentContentItem.storeID;
            } else if ([gCurrentContentItem respondsToSelector:@selector(metadata)]) {
                id metadata = [gCurrentContentItem performSelector:@selector(metadata)];
                if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
                    currentStoreID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
                }
            }
            if (currentStoreID == iTunesStoreID) {
                double et = [gCurrentContentItem calculatedElapsedTime];
                float rate = 1.0f;
                if (gCurrentContentItem.amlPlaybackRate != nil) {
                    rate = [gCurrentContentItem.amlPlaybackRate floatValue];
                } else if ([gCurrentContentItem respondsToSelector:@selector(playbackRate)]) {
                    rate = gCurrentContentItem.playbackRate;
                }
                [gCurrentContentItem setElapsedTime:et playbackRate:rate];
            }
        }
    });
    return YES;
}

static void ProcessNextTask(void) {
    if (!gSession || !gRequestContext || [gLyricsTaskQueue count] == 0) {
        gIsProcessingQueue = NO;
        return;
    }
    
    gIsProcessingQueue = YES;
    LyricsTask *task = [gLyricsTaskQueue firstObject];
    [gLyricsTaskQueue removeObjectAtIndex:0];
    
    ICMusicKitURLRequest *request = [[%c(ICMusicKitURLRequest) alloc] initWithURL:task.lyricURL requestContext:gRequestContext];
    [gSession enqueueDataRequest:request withCompletionHandler:^(ICURLResponse *response, NSError *error) {
        dispatch_async(gLyricsQueue, ^{
            BOOL taskFailed = NO;
            
            if (error) {
                taskFailed = YES;
            } else if (![response.bodyData isKindOfClass:[NSData class]]) {
                taskFailed = YES;
            } else {
                id object = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:nil];
                if ([object isKindOfClass:[NSDictionary class]]) {
                    if (((NSDictionary *)object)[@"data"]) {
                        object = ((NSDictionary *)object)[@"data"];
                        if ([object isKindOfClass:[NSArray class]]) {
                            object = ((NSArray *)object).firstObject;
                            if ([object isKindOfClass:[NSDictionary class]]) {
                                object = ((NSDictionary *)object)[@"attributes"];
                                if ([object isKindOfClass:[NSDictionary class]]) {
                                    object = ((NSDictionary *)object)[@"ttml"];
                                }
                            }
                        }
                    } else if (((NSDictionary *)object)[@"ttml"]) {
                        object = ((NSDictionary *)object)[@"ttml"];
                    }
                }
                
                if (![object isKindOfClass:[NSString class]]) {
                    taskFailed = YES;
                } else {
                    NSData *data = [(NSString *)object dataUsingEncoding:NSUTF8StringEncoding];
                    if (data.length && ParseLyricsData(data, task.iTunesStoreID, task.lyricsAdamID)) {
                        if (![data writeToFile:task.lyricsFilePath atomically:YES]) {
                            taskFailed = YES;
                        } else {
                            DateLyricsPruneDiskCache();
                        }
                    } else {
                        taskFailed = YES;
                        [[NSFileManager defaultManager] removeItemAtPath:task.lyricsFilePath error:nil];
                    }
                }
            }
            
            if (taskFailed) {
                task.retryCount++;
                if (task.retryCount < 3) {
                    NSTimeInterval retryDelay = 0.5 * (1 << (task.retryCount - 1));
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryDelay * NSEC_PER_SEC)), gLyricsQueue, ^{
                        [gLyricsTaskQueue addObject:task];
                        if (!gIsProcessingQueue) ProcessNextTask();
                    });
                } else {
                    [gPendingLyricsIDs removeObject:@(task.lyricsAdamID)];
                }
            } else {
                [gPendingLyricsIDs removeObject:@(task.lyricsAdamID)];
            }
            
            ProcessNextTask();
        });
    }];
}

static void AddTaskToQueue(NSInteger iTunesStoreID, NSInteger lyricsAdamID, NSURL *lyricURL, NSString *lyricsFilePath) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsTaskQueue = [NSMutableArray array];
        gPendingLyricsIDs = [NSMutableSet set];
    });
    
    if ([gPendingLyricsIDs containsObject:@(lyricsAdamID)]) {
        return;
    }
    
    LyricsTask *task = [[LyricsTask alloc] init];
    task.iTunesStoreID = iTunesStoreID;
    task.lyricsAdamID = lyricsAdamID;
    task.retryCount = 0;
    task.lyricURL = lyricURL;
    task.lyricsFilePath = lyricsFilePath;
    
    [gLyricsTaskQueue addObject:task];
    [gPendingLyricsIDs addObject:@(lyricsAdamID)];
    
    if (!gIsProcessingQueue) {
        ProcessNextTask();
    }
}

%group DateLyricsPrimary

%hook ICURLSession

- (void)enqueueDataRequest:(id)arg1 withCompletionHandler:(ICURLSessionCompletionHandler)arg2 {
    if (!gSession) {
        gSession = self;
    }
    if (!gRequestContext) {
        if ([arg1 isKindOfClass:%c(ICMusicKitURLRequest)]) {
            ICMusicKitURLRequest *req = arg1;
            gRequestContext = [req requestContext];
        }
    }
    if (gSession && gRequestContext) {
        dispatch_async(gLyricsQueue, ^{
            if (!gIsProcessingQueue) ProcessNextTask();
        });
    }
    %orig;
}

%end

%hook MRNowPlayingPlayerClient

- (void)sendContentItemChanges:(NSArray<MRContentItem *> *)contentItems {
    %orig;
    if (!gDateLyricsEnabled) return;
    dispatch_async(gLyricsQueue, ^{
        
        MRContentItem *item = self.nowPlayingContentItem;
        NSInteger iTunesStoreID = item.metadata.iTunesStoreIdentifier;

        if (!item.metadata.lyricsAvailable) {
            DateLyricsPublishPayload(nil);
            return;
        }

        if (iTunesStoreID <= 0) {
            DateLyricsPublishPayload(nil);
            return;
        }
        
        NSInteger lyricsAdamID;
        NSString *lyricURLString;
        NSString *storefront = DateLyricsStorefront();
        NSString *locale = DateLyricsPreferredLocale();
        if ([item.metadata respondsToSelector:@selector(lyricsAdamID)]) {
            lyricsAdamID = item.metadata.lyricsAdamID;
            lyricURLString = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/songs/%lld/syllable-lyrics?l=%@", storefront, (long long)lyricsAdamID, locale];
        } else {
            lyricsAdamID = iTunesStoreID;
            lyricURLString = [NSString stringWithFormat:@"https://se2.itunes.apple.com/WebObjects/MZStoreElements2.woa/wa/ttmlLyrics?id=%lld&l=%@", (long long)iTunesStoreID, locale];
        }
        if (lyricsAdamID <= 0) {
            DateLyricsPublishPayload(nil);
            return;
        }
        
        NSString *lyricsRoot = GetLyricsRootPath();
        NSString *lyricsFilePath = [lyricsRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"syllable-lyrics_%lld.xml", (long long)lyricsAdamID]];
        BOOL lyricsCacheExists = [[NSFileManager defaultManager] fileExistsAtPath:lyricsFilePath];
        if (lyricsCacheExists) {
            NSData *cachedData = [NSData dataWithContentsOfFile:lyricsFilePath];
            if (ParseLyricsData(cachedData, iTunesStoreID, lyricsAdamID)) {
                return;
            }
            [[NSFileManager defaultManager] removeItemAtPath:lyricsFilePath error:nil];
        }

        NSURL *lyricURL = [NSURL URLWithString:lyricURLString];
        if (lyricURL) AddTaskToQueue(iTunesStoreID, lyricsAdamID, lyricURL, lyricsFilePath);
    });
}

%end

%hook MPNowPlayingInfoCenter

- (MPNowPlayingContentItem *)nowPlayingContentItem {
    if (!gNowPlayingInfoCenter) {
        gNowPlayingInfoCenter = self;
    }
    return %orig;
}

%end

%hook MPNowPlayingContentItem

%property (nonatomic, strong) NSTimer *amlTimer;
%property (nonatomic, strong) NSTimer *amlPauseTimer;
%property (nonatomic, copy) NSString *amlCurrentLyricTitle;
%property (nonatomic, copy) NSString *amlCurrentPayloadSignature;
%property (nonatomic, strong) NSNumber *amlPlaybackRate;
%property (nonatomic, strong) NSNumber *amlLastSystemElapsedTime;
%property (nonatomic, strong) NSNumber *amlLastSystemTime;
%property (nonatomic, strong) NSNumber *amlLastPayloadPublishTime;
%property (nonatomic, strong) NSNumber *amlLastResolvedElapsed;
%property (nonatomic, strong) NSNumber *amlLastResolvedLineIndex;
%property (assign, nonatomic) NSInteger amlLastStoreID;

- (void)dealloc {
    [self.amlTimer invalidate];
    self.amlTimer = nil;
    [self.amlPauseTimer invalidate];
    self.amlPauseTimer = nil;
    if (gCurrentContentItem == self) {
        gCurrentContentItem = nil;
    }
    %orig;
}

%new
- (void)amlPauseTimerFired:(NSTimer *)timer {
    self.amlCurrentLyricTitle = nil;
    self.amlCurrentPayloadSignature = nil;
    DateLyricsPublishPayload(nil);
}

%new
- (NSTimeInterval)calculatedElapsedTime {
    if (self.amlLastSystemElapsedTime == nil) {
        NSTimeInterval et = 0;
        if ([self respondsToSelector:@selector(elapsedTime)]) {
            et = [(id)self elapsedTime];
        } else if ([self respondsToSelector:@selector(metadata)]) {
            id metadata = [self performSelector:@selector(metadata)];
            if ([metadata respondsToSelector:@selector(elapsedTime)]) {
                et = (NSTimeInterval)[(NSNumber *)[metadata performSelector:@selector(elapsedTime)] doubleValue];
            }
        }
        return et;
    }
    NSTimeInterval et = [self.amlLastSystemElapsedTime doubleValue];
    if (self.amlPlaybackRate != nil && [self.amlPlaybackRate floatValue] > 0.0f) {
        NSTimeInterval timePassed = [NSDate timeIntervalSinceReferenceDate] - [self.amlLastSystemTime doubleValue];
        et += timePassed * [self.amlPlaybackRate floatValue];
    }
    return et;
}

%new
- (void)amlTimerFired:(NSTimer *)timer {
    NSInteger storeID = 0;
    if ([self respondsToSelector:@selector(storeID)]) {
        storeID = self.storeID;
    } else if ([self respondsToSelector:@selector(metadata)]) {
        id metadata = [self performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            storeID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    NSInteger currentStoreID = 0;
    MPNowPlayingContentItem *currentItem = gNowPlayingInfoCenter.nowPlayingContentItem;
    if ([currentItem respondsToSelector:@selector(storeID)]) {
        currentStoreID = currentItem.storeID;
    } else if ([currentItem respondsToSelector:@selector(metadata)]) {
        id metadata = [currentItem performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            currentStoreID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    BOOL isTrulyPlaying = YES;
    if (gNowPlayingInfoCenter && [gNowPlayingInfoCenter respondsToSelector:@selector(playbackState)]) {
        NSUInteger state = gNowPlayingInfoCenter.playbackState;
        if (state == 2 || state == 3) {
            isTrulyPlaying = NO;
        }
    }

    float rate = 1.0f;
    if (self.amlPlaybackRate != nil) {
        rate = [self.amlPlaybackRate floatValue];
    } else if ([self respondsToSelector:@selector(playbackRate)]) {
        rate = self.playbackRate;
    }

    if (!storeID || (gNowPlayingInfoCenter && currentStoreID != storeID) || !isTrulyPlaying || rate <= 0.0f) {
        [timer invalidate];
        self.amlTimer = nil;
        if (!isTrulyPlaying || rate <= 0.0f) {
            double elapsedTime = [self calculatedElapsedTime];
            [self setElapsedTime:MAX(0, elapsedTime) playbackRate:0.0f];
        }
        return;
    }
    double elapsedTime = [self calculatedElapsedTime];
    [self setElapsedTime:MAX(0, elapsedTime) playbackRate:rate];
}

- (void)setElapsedTime:(double)elapsedTime playbackRate:(float)playbackRate {
    self.amlPlaybackRate = @(playbackRate);
    self.amlLastSystemElapsedTime = @(elapsedTime);
    self.amlLastSystemTime = @([NSDate timeIntervalSinceReferenceDate]);
    %orig;
    gCurrentContentItem = self;
    [self.amlTimer invalidate];
    self.amlTimer = nil;
    [self.amlPauseTimer invalidate];
    self.amlPauseTimer = nil;

    if (!gDateLyricsEnabled) {
        self.amlCurrentLyricTitle = nil;
        self.amlCurrentPayloadSignature = nil;
        self.amlLastPayloadPublishTime = nil;
        return;
    }

    NSInteger storeID = 0;
    if ([self respondsToSelector:@selector(storeID)]) {
        storeID = self.storeID;
    } else if ([self respondsToSelector:@selector(metadata)]) {
        id metadata = [self performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            storeID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    if (storeID != self.amlLastStoreID) {
        self.amlLastStoreID = storeID;
        self.amlCurrentLyricTitle = nil;
        self.amlCurrentPayloadSignature = nil;
        self.amlLastPayloadPublishTime = nil;
        self.amlLastResolvedElapsed = nil;
        self.amlLastResolvedLineIndex = nil;
    }

    // Keep the position we resolve lyrics against monotonic.
    //
    // Two clocks feed this method: MediaRemote's authoritative updates, and our own
    // amlTimerFired: which extrapolates (last known position + wall clock * rate).
    // The extrapolation regularly overshoots a line boundary by a few tens of
    // milliseconds, and the next real update then arrives slightly *earlier* — still
    // inside the previous line. The lyric therefore advanced, snapped back to the
    // previous line, and advanced again, all within ~100ms. That is the transition
    // glitch: three line changes instead of one.
    //
    // Small backwards steps are that jitter and are ignored. A large one is a real
    // seek and is honoured. Only the resolution clock is clamped — %orig and
    // amlLastSystemElapsedTime above keep Apple's true value, so extrapolation
    // continues to track the real timeline.
    static const NSTimeInterval kDateLyricsSeekThreshold = 1.0;
    if (self.amlLastResolvedElapsed != nil) {
        NSTimeInterval lastResolved = self.amlLastResolvedElapsed.doubleValue;
        NSTimeInterval backwards = lastResolved - elapsedTime;
        if (backwards > 0.0 && backwards < kDateLyricsSeekThreshold) {
            elapsedTime = lastResolved;
        }
    }
    self.amlLastResolvedElapsed = @(elapsedTime);

    if (!storeID) {
        if (self.amlCurrentLyricTitle || self.amlCurrentPayloadSignature || !self.amlLastPayloadPublishTime) {
            self.amlCurrentLyricTitle = nil;
            self.amlCurrentPayloadSignature = nil;
            self.amlLastPayloadPublishTime = @([[NSDate date] timeIntervalSince1970]);
            DateLyricsPublishPayload(nil);
        }
        return;
    }

    // Phase 1: screen-off gating.
    // When PauseWhenScreenOff is enabled and the screen is off, skip the
    // resolution and publish pipeline entirely.
    if (gDateLyricsPauseWhenScreenOff && !gDateLyricsConsumerActive) {
        return;
    }

    NSString *title = nil;
    id selectedLineID = nil;
    NSTimeInterval nextWordStart = -1.0;
    NSTimeInterval currentLineExpiry = -1.0;
    BOOL suppressLineFallback = NO;
    NSDictionary *wordPayload = nil;

    // Narrow the mutex to just the dictionary lookups. Once we have retained
    // references to the arrays we can release the lock; ParseLyricsData only
    // replaces the entire array under the lock, so the old array stays alive
    // as long as we hold these local references.
    pthread_mutex_lock(&gLyricsCacheMutex);
    NSArray<DateLyricsTimedLine *> *wordLines = gWordLyricsCache[@(storeID)];
    NSArray<MSVLyricsLine *> *lyricLines = gLyricsCache[@(storeID)];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    // Cursor-based resolution: remember the index of the last resolved word-line
    // so we don't rescan from the end on every tick. The typical case — position
    // advancing forward — only needs to look at the cursor line and a few ahead.
    // A backwards move (seek) falls back to a full reverse scan.
    NSInteger cursorIndex = self.amlLastResolvedLineIndex ? [self.amlLastResolvedLineIndex integerValue] : -1;
    NSInteger resolvedWordLineIndex = -1;

    // Fast-path: try from cursor forward first.
    if (cursorIndex >= 0 && cursorIndex < (NSInteger)wordLines.count) {
        for (NSInteger i = cursorIndex; i < (NSInteger)wordLines.count; i++) {
            DateLyricsTimedLine *line = DateLyricsGetFilteredLine(wordLines[i]);
            if (!line) continue;
            if (line.begin > elapsedTime) break; // haven't reached this line yet
            if (line.end > line.begin && elapsedTime > line.end + gDateLyricsLineHoldDuration) continue;
            resolvedWordLineIndex = i;
        }
        // If we found something and it's not the last line, also check
        // whether a subsequent line has now started (fast forward).
        if (resolvedWordLineIndex >= 0) {
            for (NSInteger i = resolvedWordLineIndex + 1; i < (NSInteger)wordLines.count; i++) {
                DateLyricsTimedLine *next = DateLyricsGetFilteredLine(wordLines[i]);
                if (!next) continue;
                if (next.begin > elapsedTime) break;
                if (next.end > next.begin && elapsedTime > next.end + gDateLyricsLineHoldDuration) continue;
                resolvedWordLineIndex = i;
            }
        }
    }

    // If the fast-path didn't find anything (no cursor, or position went backwards),
    // fall back to the original reverse scan.
    if (resolvedWordLineIndex < 0) {
        for (NSInteger i = (NSInteger)wordLines.count - 1; i >= 0; i--) {
            DateLyricsTimedLine *line = DateLyricsGetFilteredLine(wordLines[i]);
            if (!line) continue;
            if (elapsedTime >= line.begin) {
                if (line.end > line.begin && elapsedTime > line.end + gDateLyricsLineHoldDuration) break;
                resolvedWordLineIndex = i;
                break;
            }
        }
    }

    if (resolvedWordLineIndex >= 0) {
        self.amlLastResolvedLineIndex = @(resolvedWordLineIndex);
    }

    // The cursor above found the line index; jump directly to it for word-level
    // detail instead of re-scanning from the end. We also compute nextWordStart
    // from the next line's begin time for timer scheduling.
    if (resolvedWordLineIndex >= 0) {
        DateLyricsTimedLine *line = DateLyricsGetFilteredLine(wordLines[resolvedWordLineIndex]);
        if (line && elapsedTime >= line.begin &&
            !(line.end > line.begin && elapsedTime > line.end + gDateLyricsLineHoldDuration)) {

            title = line.text;
            selectedLineID = @(line.begin);
            if (line.end > line.begin) currentLineExpiry = line.end + gDateLyricsLineHoldDuration;
            NSRange activeRange = NSMakeRange(NSNotFound, 0);
            NSRange backgroundActiveRange = NSMakeRange(NSNotFound, 0);
            NSRange previousForegroundWordRange = NSMakeRange(NSNotFound, 0);
            NSRange previousBackgroundWordRange = NSMakeRange(NSNotFound, 0);
            NSTimeInterval previousForegroundWordEnd = -1.0;
            NSTimeInterval previousBackgroundWordEnd = -1.0;
            NSUInteger activeRangeSegmentStart = NSNotFound;
            NSUInteger backgroundActiveRangeSegmentStart = NSNotFound;
            NSUInteger previousForegroundSegmentStart = NSNotFound;
            NSUInteger previousBackgroundSegmentStart = NSNotFound;
            NSTimeInterval nextForegroundWordStart = -1.0;
            NSTimeInterval nextBackgroundWordStart = -1.0;
            BOOL previousWordWasBackground = NO;
            BOOL hasPreviousWord = NO;
            NSTimeInterval activeForegroundWordBegin = -1.0;
            NSTimeInterval activeBackgroundWordBegin = -1.0;
            NSUInteger wordCursor = 0;

            for (DateLyricsTimedWord *word in line.words) {
                wordCursor += word.separatorBefore.length;
                NSRange wordRange = NSMakeRange(wordCursor, word.text.length);
                NSUInteger segmentStart = wordRange.location;
                if (hasPreviousWord && previousWordWasBackground == word.isBackground) {
                    segmentStart = word.isBackground ? previousBackgroundSegmentStart : previousForegroundSegmentStart;
                }
                BOOL isActive = elapsedTime >= word.begin && elapsedTime < word.end;
                if (word.isBackground) {
                    if (isActive && (backgroundActiveRange.location == NSNotFound || word.begin >= activeBackgroundWordBegin)) {
                        backgroundActiveRange = wordRange;
                        backgroundActiveRangeSegmentStart = segmentStart;
                        activeBackgroundWordBegin = word.begin;
                    }
                    if (word.begin > elapsedTime && (nextBackgroundWordStart < 0 || word.begin < nextBackgroundWordStart)) nextBackgroundWordStart = word.begin;
                    if (word.end <= elapsedTime && word.end >= previousBackgroundWordEnd) {
                        previousBackgroundWordRange = wordRange;
                        previousBackgroundWordEnd = word.end;
                        previousBackgroundSegmentStart = segmentStart;
                    }
                } else {
                    if (isActive && (activeRange.location == NSNotFound || word.begin >= activeForegroundWordBegin)) {
                        activeRange = wordRange;
                        activeRangeSegmentStart = segmentStart;
                        activeForegroundWordBegin = word.begin;
                    }
                    if (word.begin > elapsedTime && (nextForegroundWordStart < 0 || word.begin < nextForegroundWordStart)) nextForegroundWordStart = word.begin;
                    if (word.end <= elapsedTime && word.end >= previousForegroundWordEnd) {
                        previousForegroundWordRange = wordRange;
                        previousForegroundWordEnd = word.end;
                        previousForegroundSegmentStart = segmentStart;
                    }
                }
                hasPreviousWord = YES;
                previousWordWasBackground = word.isBackground;
                wordCursor += word.text.length;
            }

            if (activeRange.location == NSNotFound && previousForegroundWordRange.location != NSNotFound &&
                elapsedTime >= previousForegroundWordEnd &&
                (nextForegroundWordStart < 0 || elapsedTime < nextForegroundWordStart) && elapsedTime <= line.end) {
                activeRange = previousForegroundWordRange;
                activeRangeSegmentStart = previousForegroundSegmentStart;
            }
            if (backgroundActiveRange.location == NSNotFound && previousBackgroundWordRange.location != NSNotFound &&
                elapsedTime >= previousBackgroundWordEnd &&
                (nextBackgroundWordStart < 0 || elapsedTime < nextBackgroundWordStart) && elapsedTime <= line.end) {
                backgroundActiveRange = previousBackgroundWordRange;
                backgroundActiveRangeSegmentStart = previousBackgroundSegmentStart;
            }

            if (nextForegroundWordStart > elapsedTime) nextWordStart = nextForegroundWordStart;
            if (nextBackgroundWordStart > elapsedTime) {
                if (nextWordStart < 0 || nextBackgroundWordStart < nextWordStart) nextWordStart = nextBackgroundWordStart;
            }

            NSRange focusForegroundRange = activeRange;
            NSRange focusBackgroundRange = backgroundActiveRange;
            if (activeRange.location != NSNotFound && gDateLyricsHighlightTrail && activeRangeSegmentStart != NSNotFound)
                activeRange = NSMakeRange(activeRangeSegmentStart, NSMaxRange(activeRange) - activeRangeSegmentStart);
            if (backgroundActiveRange.location != NSNotFound && gDateLyricsHighlightTrail && backgroundActiveRangeSegmentStart != NSNotFound)
                backgroundActiveRange = NSMakeRange(backgroundActiveRangeSegmentStart, NSMaxRange(backgroundActiveRange) - backgroundActiveRangeSegmentStart);

            BOOL isLineFinished = YES;
            NSTimeInterval minWordBegin = -1.0;
            for (DateLyricsTimedWord *word in line.words) {
                if (word.end > elapsedTime) isLineFinished = NO;
                if (minWordBegin < 0 || word.begin < minWordBegin) minWordBegin = word.begin;
            }
            BOOL isLineStarted = (minWordBegin < 0) || (elapsedTime >= minWordBegin);

            NSDictionary *baseWordPayload = DateLyricsMakePayloadWithBackgroundRange(line.text, activeRange, backgroundActiveRange);
            NSMutableDictionary *mutableWordPayload = [(baseWordPayload ?: @{}) mutableCopy];
            if (mutableWordPayload.count > 0) {
                DateLyricsSetRangeFields(mutableWordPayload, @"focus", focusForegroundRange);
                DateLyricsSetRangeFields(mutableWordPayload, @"focusBg", focusBackgroundRange);
                mutableWordPayload[@"started"] = @(isLineStarted);
                mutableWordPayload[@"finished"] = @(isLineFinished);
                mutableWordPayload[@"lineId"] = selectedLineID;
                wordPayload = [mutableWordPayload copy];
            } else {
                wordPayload = nil;
            }
        } else {
            suppressLineFallback = YES;
        }
        // Schedule the next timer boundary from the next word line's begin.
        if (resolvedWordLineIndex + 1 < (NSInteger)wordLines.count) {
            DateLyricsTimedLine *nextLine = DateLyricsGetFilteredLine(wordLines[resolvedWordLineIndex + 1]);
            if (nextLine && nextLine.begin > elapsedTime) {
                if (nextWordStart < 0 || nextLine.begin < nextWordStart) nextWordStart = nextLine.begin;
            }
        }
    } else {
        // No resolved line; find the next upcoming word-line start for the timer.
        for (NSInteger i = 0; i < (NSInteger)wordLines.count; i++) {
            DateLyricsTimedLine *upcomingLine = DateLyricsGetFilteredLine(wordLines[i]);
            if (upcomingLine && upcomingLine.begin > elapsedTime) {
                nextWordStart = upcomingLine.begin;
                break;
            }
        }
    }




    NSTimeInterval nextLineStart = -1.0;

    for (MSVLyricsLine *line in [lyricLines reverseObjectEnumerator]) {
        if (elapsedTime >= line.startTime) {
            if (!title.length && !suppressLineFallback) {
                NSTimeInterval lineEndTime = 0.0;
                if ([line respondsToSelector:@selector(endTime)]) lineEndTime = line.endTime;
                if (lineEndTime > line.startTime && elapsedTime > lineEndTime + gDateLyricsLineHoldDuration) {
                    break;
                }
                id lyricsText = [line respondsToSelector:@selector(lyricsText)] ? [line performSelector:@selector(lyricsText)] : nil;
                NSString *rawTitle = nil;
                if ([lyricsText isKindOfClass:[NSAttributedString class]]) {
                    rawTitle = [lyricsText string];
                } else if ([lyricsText isKindOfClass:[NSString class]]) {
                    rawTitle = (NSString *)lyricsText;
                }
                title = DateLyricsStripParentheses(rawTitle);
                selectedLineID = @(line.startTime);
                if (lineEndTime > line.startTime) currentLineExpiry = lineEndTime + gDateLyricsLineHoldDuration;
            }
            break;
        } else {
            if (nextLineStart < 0 || line.startTime < nextLineStart) {
                nextLineStart = line.startTime;
            }
        }
    }

    if (playbackRate <= 0.0f) {
        self.amlPauseTimer = [NSTimer scheduledTimerWithTimeInterval:gDateLyricsPauseTimeout target:self selector:@selector(amlPauseTimerFired:) userInfo:nil repeats:NO];
    } else {
        float timerRate = playbackRate;
        NSTimeInterval nextTrigger = -1.0;
        if (nextWordStart > elapsedTime) {
            nextTrigger = nextWordStart;
        }
        if (nextLineStart > elapsedTime) {
            if (nextTrigger < 0 || nextLineStart < nextTrigger) {
                nextTrigger = nextLineStart;
            }
        }
        if (currentLineExpiry > elapsedTime && (nextTrigger < 0 || currentLineExpiry < nextTrigger)) {
            nextTrigger = currentLineExpiry;
        }

        if (nextTrigger > elapsedTime) {
            NSTimeInterval delay = MIN((nextTrigger - elapsedTime) / timerRate, 1.0);
            self.amlTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                             target:self selector:@selector(amlTimerFired:)
                                                           userInfo:nil repeats:NO];
        } else {
            self.amlTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(amlTimerFired:)
                                                           userInfo:nil repeats:NO];
        }
    }

    NSDictionary *payload = nil;
    if (wordPayload) {
        NSMutableDictionary *timedPayload = [wordPayload mutableCopy];
        timedPayload[@"timed"] = @YES;
        payload = [timedPayload copy];
    } else {
        payload = DateLyricsMakePayload(title, NSMakeRange(NSNotFound, 0));
        if (payload) {
            NSMutableDictionary *mutablePayload = [payload mutableCopy];
            mutablePayload[@"lineId"] = selectedLineID ?: title ?: @"";
            payload = [mutablePayload copy];
        }
    }
    if (payload) {
        NSMutableDictionary *identifiedPayload = [payload mutableCopy];
        identifiedPayload[@"trackId"] = @(storeID);
        payload = [identifiedPayload copy];
    }
    NSString *payloadSignature = DateLyricsSerializePayload(payload);

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL heartbeatDue = !self.amlLastPayloadPublishTime || now - self.amlLastPayloadPublishTime.doubleValue >= 2.0;
    if (![payloadSignature isEqualToString:self.amlCurrentPayloadSignature] || heartbeatDue) {
        self.amlCurrentLyricTitle = title;
        self.amlCurrentPayloadSignature = payloadSignature;
        self.amlLastPayloadPublishTime = @(now);
        DateLyricsPublishPayload(payload);
    }
}

%end

%end

%group DateLyricsSpringBoard

static _UIAnimatingLabel *DateLyricsSearchAnimatingLabel(UIView *view, Class labelClass) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:labelClass]) {
            return (_UIAnimatingLabel *)subview;
        }
        _UIAnimatingLabel *nestedLabel = DateLyricsSearchAnimatingLabel(subview, labelClass);
        if (nestedLabel) return nestedLabel;
    }
    return nil;
}

// Cached on the owning view. The recursive search used to run on every layout
// pass, every payload, and every date change, across every registered cover sheet.
static _UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return nil;
    Class labelClass = NSClassFromString(@"_UIAnimatingLabel");
    if (!labelClass) return nil;

    DateLyricsWeakBox *box = objc_getAssociatedObject(view, kDateLyricsCachedLabelKey);
    _UIAnimatingLabel *cached = box.object;
    // Only trust the cache while the label is still installed under this view.
    if ([cached isKindOfClass:labelClass] && cached.superview) {
        return cached;
    }

    _UIAnimatingLabel *label = DateLyricsSearchAnimatingLabel(view, labelClass);
    if (label) {
        // Tag the label itself so the setText:/setAttributedText: hooks can decide
        // in O(1) instead of walking the superview chain for every _UIAnimatingLabel
        // in SpringBoard.
        objc_setAssociatedObject(label, kDateLyricsIsDateLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!box) {
            box = [DateLyricsWeakBox new];
            objc_setAssociatedObject(view, kDateLyricsCachedLabelKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        box.object = label;
    }
    return label;
}

static BOOL DateLyricsViewContainsClassNamed(UIView *view, NSString *className) {
    if (![view isKindOfClass:UIView.class] || className.length == 0) return NO;
    if ([NSStringFromClass(view.class) isEqualToString:className]) return YES;

    for (UIView *subview in view.subviews) {
        if (DateLyricsViewContainsClassNamed(subview, className)) {
            return YES;
        }
    }
    return NO;
}

static CSProminentSubtitleDateView *DateLyricsFindSiblingDateView(UIView *view) {
    UIView *containerView = view.superview;
    if (![containerView isKindOfClass:UIView.class]) return nil;

    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    for (UIView *subview in containerView.subviews) {
        if ([subview isKindOfClass:dateClass]) {
            return (CSProminentSubtitleDateView *)subview;
        }
    }
    return nil;
}

static CSProminentSubtitleDateView *DateLyricsFindAncestorDateView(UIView *view) {
    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    UIView *currentView = view;
    while ([currentView isKindOfClass:UIView.class]) {
        if ([currentView isKindOfClass:dateClass]) {
            return (CSProminentSubtitleDateView *)currentView;
        }
        currentView = currentView.superview;
    }
    return nil;
}

static BOOL DateLyricsWidgetSlotMatchesDateSlot(UIView *widgetSlot, UIView *dateView) {
    if (![widgetSlot isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return NO;

    CGRect slotFrame = widgetSlot.frame;
    if (CGRectIsEmpty(slotFrame)) {
        return NO;
    }

    CGRect dateFrame = dateView.frame;
    if (CGRectIntersectsRect(slotFrame, dateFrame)) {
        return YES;
    }

    return CGRectGetMaxY(slotFrame) >= CGRectGetMinY(dateFrame) - 4.0 &&
           CGRectGetMinY(slotFrame) <= CGRectGetMaxY(dateFrame) + 4.0;
}

static UIView *DateLyricsFindMatchingWidgetSlotForDateView(UIView *dateView) {
    UIView *containerView = dateView.superview;
    if (![containerView isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return nil;

    Class emptyElementClass = NSClassFromString(@"CSProminentEmptyElementView");
    for (UIView *subview in containerView.subviews) {
        if (![subview isKindOfClass:emptyElementClass]) continue;
        if (!DateLyricsViewContainsClassNamed(subview, @"CHUISWidgetHostViewControllerView")) continue;
        if (!DateLyricsWidgetSlotMatchesDateSlot(subview, dateView)) continue;
        return subview;
    }
    return nil;
}

static void DateLyricsSetWidgetDateSlotHidden(UIView *containerView, UIView *dateView, BOOL hidden) {
    if (![containerView isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return;

    Class emptyElementClass = NSClassFromString(@"CSProminentEmptyElementView");
    for (UIView *subview in containerView.subviews) {
        if (![subview isKindOfClass:emptyElementClass]) continue;
        if (!DateLyricsViewContainsClassNamed(subview, @"CHUISWidgetHostViewControllerView")) continue;
        BOOL matchesDateSlot = DateLyricsWidgetSlotMatchesDateSlot(subview, dateView);
        if (hidden && !matchesDateSlot) continue;
        if (!hidden && !matchesDateSlot && !objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey)) continue;

        if (hidden) {
            if (!objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey)) {
                objc_setAssociatedObject(subview, kDateLyricsOriginalHiddenKey, @(subview.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            subview.hidden = YES;
        } else {
            NSNumber *originalHidden = objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey);
            if (originalHidden) {
                subview.hidden = originalHidden.boolValue;
                objc_setAssociatedObject(subview, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            }
        }
    }
}

static void DateLyricsPrepareAndApplyDateLabel(_UIAnimatingLabel *label) {
    if (!label) return;
    [label _amlApplyCurrentLyric];
}

static BOOL DateLyricsLabelHasResidualLyricState(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return NO;
    if ([objc_getAssociatedObject(label, kDateLyricsLabelShowingLyricKey) boolValue]) return YES;

    NSString *lastLyric = objc_getAssociatedObject(label, @selector(_amlApplyCurrentLyric));
    if (![lastLyric isKindOfClass:NSString.class] || lastLyric.length == 0) return NO;

    NSString *currentString = label.attributedText.string ?: label.text;
    return [currentString isEqualToString:lastLyric];
}

static void DateLyricsResetHybridVisibilityIfNeeded(CSProminentSubtitleDateView *dateView) {
    if (![dateView isKindOfClass:UIView.class]) return;
    if (![objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) return;
    if (DateLyricsFindMatchingWidgetSlotForDateView(dateView)) return;

    NSNumber *originalHidden = objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey);
    dateView.hidden = originalHidden ? originalHidden.boolValue : NO;
    objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void DateLyricsRestoreSystemDateLabel(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    if (!DateLyricsLabelHasResidualLyricState(label)) return;

    CSProminentSubtitleDateView *dateView = DateLyricsFindAncestorDateView(label);
    objc_setAssociatedObject(label, kDateLyricsLabelShowingLyricKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, @selector(_amlApplyCurrentLyric), nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, @selector(previousLineId), nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsPendingApplyKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsSplitPlanKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsFrozenFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
    // Bumping the generation invalidates any in-flight completion block, so it
    // cannot resurrect a lyric on top of the stock date after we restore.
    NSUInteger generation = [objc_getAssociatedObject(label, kDateLyricsTransitionGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(label, kDateLyricsTransitionGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [label.layer removeAllAnimations];
    label.alpha = 1.0;
    label.transform = CGAffineTransformIdentity;

    NSNumber *origClips = objc_getAssociatedObject(label, kDateLyricsOriginalClipsToBoundsKey);
    if (origClips) {
        label.clipsToBounds = origClips.boolValue;
        objc_setAssociatedObject(label, kDateLyricsOriginalClipsToBoundsKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    UIFont *origFont = objc_getAssociatedObject(label, kDateLyricsOriginalFontKey);
    if (origFont) {
        label.font = origFont;
        objc_setAssociatedObject(label, kDateLyricsOriginalFontKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    
    UIColor *origColor = objc_getAssociatedObject(label, kDateLyricsOriginalTextColorKey);
    if (origColor) {
        label.textColor = origColor;
        objc_setAssociatedObject(label, kDateLyricsOriginalTextColorKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    
    id origNumLines = objc_getAssociatedObject(label, kDateLyricsOriginalNumberOfLinesKey);
    if (origNumLines) {
        label.numberOfLines = [origNumLines integerValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalNumberOfLinesKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    
    id origAdjusts = objc_getAssociatedObject(label, kDateLyricsOriginalAdjustsFontSizeKey);
    if (origAdjusts) {
        label.adjustsFontSizeToFitWidth = [origAdjusts boolValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalAdjustsFontSizeKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    
    id origMinScale = objc_getAssociatedObject(label, kDateLyricsOriginalMinScaleKey);
    if (origMinScale) {
        label.minimumScaleFactor = [origMinScale doubleValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalMinScaleKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    
    id origLineBreak = objc_getAssociatedObject(label, kDateLyricsOriginalLineBreakModeKey);
    if (origLineBreak) {
        label.lineBreakMode = (NSLineBreakMode)[origLineBreak integerValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalLineBreakModeKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    if (!dateView) return;

    label.text = nil;
    label.attributedText = nil;
    label.hidden = NO;
    if (![objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) {
        dateView.hidden = NO;
    }

    objc_setAssociatedObject(dateView, kDateLyricsRestoringStockDateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    NSAttributedString *origAttrText = objc_getAssociatedObject(label, kDateLyricsOriginalAttributedTextKey);
    NSString *origText = objc_getAssociatedObject(label, kDateLyricsOriginalTextKey);
    if (origAttrText) {
        NSMutableAttributedString *cleanStr = [origAttrText mutableCopy];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        label.attributedText = cleanStr;
        objc_setAssociatedObject(label, kDateLyricsOriginalAttributedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    } else if (origText) {
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:origText];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        label.attributedText = cleanStr;
        objc_setAssociatedObject(label, kDateLyricsOriginalTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    if ([dateView respondsToSelector:@selector(_updateLabel)]) {
        [dateView performSelector:@selector(_updateLabel)];
    }
    [label setNeedsLayout];
    [dateView setNeedsLayout];
    [dateView layoutIfNeeded];
    objc_setAssociatedObject(dateView, kDateLyricsRestoringStockDateKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot) {
    if (![widgetSlot isKindOfClass:UIView.class]) return;
    if (!DateLyricsViewContainsClassNamed(widgetSlot, @"CHUISWidgetHostViewControllerView")) return;

    CSProminentSubtitleDateView *dateView = DateLyricsFindSiblingDateView(widgetSlot);
    if (!dateView) return;

    NSDictionary *payload = DateLyricsCurrentRenderablePayload();
    BOOL hasLyric = [payload[@"text"] isKindOfClass:NSString.class];

    if (!gDateLyricsEnabled) hasLyric = NO;

    if (!hasLyric) {
        if ([objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) {
            NSNumber *originalHidden = objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey);
            if (originalHidden) {
                dateView.hidden = originalHidden.boolValue;
                objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            }
            DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, NO);
            objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }

    if (!objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey)) {
        objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, @(dateView.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    dateView.hidden = NO;
    DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, YES);
    objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(dateView));
    [dateView setNeedsLayout];
}

%hook CSProminentSubtitleDateView

- (void)didMoveToWindow {
    %orig;
    if (gDateLyricsDateViews) [gDateLyricsDateViews addObject:self];
    DateLyricsResetHybridVisibilityIfNeeded(self);
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(self));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;

    _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
    if (!label) return;

    DateLyricsResetHybridVisibilityIfNeeded(self);

    NSDictionary *payload = DateLyricsCurrentRenderablePayload();
    NSString *lyric = payload[@"text"];
    if (lyric.length > 0 && gDateLyricsEnabled) {
        // While a transition runs, hold the label at the frame captured when it
        // started. UIKit will otherwise re-size the label to its new (shorter or
        // longer) text mid-animation, which is what tears the outgoing and
        // incoming lines into each other.
        NSValue *frozen = objc_getAssociatedObject(label, kDateLyricsFrozenFrameKey);
        if (frozen) {
            CGRect frozenFrame = frozen.CGRectValue;
            if (!CGRectEqualToRect(label.frame, frozenFrame)) {
                label.frame = frozenFrame;
            }
            objc_setAssociatedObject(label, kDateLyricsPendingApplyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }

        CGRect frame = label.frame;
        frame.origin.x = 0.0;
        frame.size.width = self.bounds.size.width;
        if (!CGRectEqualToRect(frame, label.frame)) {
            label.frame = frame;
        }
        [label _amlApplyCurrentLyric];
    } else {
        DateLyricsRestoreSystemDateLabel(label);
    }
}

- (void)_updateLabel {
    %orig;
    if ([objc_getAssociatedObject(self, kDateLyricsRestoringStockDateKey) boolValue]) return;
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(self));
}

- (void)setDate:(id)date {
    %orig;
    if ([objc_getAssociatedObject(self, kDateLyricsRestoringStockDateKey) boolValue]) return;
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(self));
}

%end

%hook CSProminentEmptyElementView

- (void)didMoveToWindow {
    %orig;
    if (gDateLyricsWidgetSlots) [gDateLyricsWidgetSlots addObject:self];
    DateLyricsUpdateWidgetDateView(self);
}

- (void)layoutSubviews {
    %orig;
    if (gDateLyricsWidgetSlots) [gDateLyricsWidgetSlots addObject:self];
    DateLyricsUpdateWidgetDateView(self);
}

%end

%hook _UIAnimatingLabel

// These setters fire for every _UIAnimatingLabel in SpringBoard, not just ours, so
// the very first thing they must do is cheaply establish that this is our label.
// The tag is applied by DateLyricsFindAnimatingLabel when the date view adopts it.
- (void)setText:(NSString *)text {
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) {
        %orig;
        return;
    }
    if (text.length > 0 && ![objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue]) {
        // Routed through attributedText purely to clear any inherited stroke width.
        // %orig is intentionally skipped: setting attributedText supersedes it, and
        // calling both makes the stock date flicker.
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:text];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        self.attributedText = cleanStr;
        return;
    }
    %orig;
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) {
        %orig;
        return;
    }
    if (attributedText.length > 0 && ![objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue]) {
        NSMutableAttributedString *cleanStr = [attributedText mutableCopy];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        %orig(cleanStr);
        return;
    }
    %orig;
}

%new
- (void)_amlApplyCurrentLyric {
    if (!gDateLyricsEnabled) {
        DateLyricsRestoreSystemDateLabel(self);
        return;
    }
    NSDictionary *payload = DateLyricsCurrentRenderablePayload();
    if (payload && !gDateLyricsShowAdlibs) {
        NSString *rawText = payload[@"text"];
        NSString *strippedText = DateLyricsStripParentheses(rawText) ?: @"";
        if (![strippedText isEqualToString:rawText]) {
            NSMutableDictionary *mutablePayload = [payload mutableCopy];
            mutablePayload[@"text"] = strippedText;
            
            NSUInteger strippedLen = strippedText.length;
            NSNumber *locNum = mutablePayload[@"loc"];
            NSNumber *lenNum = mutablePayload[@"len"];
            if (locNum && lenNum) {
                NSUInteger loc = locNum.unsignedIntegerValue;
                NSUInteger len = lenNum.unsignedIntegerValue;
                if (loc == NSNotFound || loc + len > strippedLen) {
                    [mutablePayload removeObjectForKey:@"loc"];
                    [mutablePayload removeObjectForKey:@"len"];
                }
            }
            
            NSNumber *bgLocNum = mutablePayload[@"bgLoc"];
            NSNumber *bgLenNum = mutablePayload[@"bgLen"];
            if (bgLocNum && bgLenNum) {
                NSUInteger bgLoc = bgLocNum.unsignedIntegerValue;
                NSUInteger bgLen = bgLenNum.unsignedIntegerValue;
                if (bgLoc == NSNotFound || bgLoc + bgLen > strippedLen) {
                    [mutablePayload removeObjectForKey:@"bgLoc"];
                    [mutablePayload removeObjectForKey:@"bgLen"];
                }
            }
            payload = [mutablePayload copy];
        }
    }
    UIFont *configuredFont = DateLyricsConfiguredFontForLabel(self);
    NSDictionary *renderPayload = DateLyricsSplitPayloadForLabel(payload, self, configuredFont) ?: payload;
    NSString *lyric = renderPayload[@"text"];
    
    if (lyric.length == 0) {
        DateLyricsRestoreSystemDateLabel(self);
        return;
    }

    if (gDateLyricsForceLowercase) {
        lyric = [lyric lowercaseString];
    }

    NSString *displayText = lyric;
    NSString *previousDisplayText = objc_getAssociatedObject(self, @selector(_amlApplyCurrentLyric));

    NSAttributedString *attrDisplayText = nil;
    NSNumber *locNum = renderPayload[@"loc"];
    NSNumber *lenNum = renderPayload[@"len"];
    NSNumber *bgLocNum = renderPayload[@"bgLoc"];
    NSNumber *bgLenNum = renderPayload[@"bgLen"];
    BOOL isTimed = [renderPayload[@"timed"] boolValue];

    if (gDateLyricsWordHighlighting && (isTimed || (locNum && lenNum))) {
        NSMutableAttributedString *mAttrStr = [[NSMutableAttributedString alloc] initWithString:lyric];
        
        UIColor *textColor = self.textColor ?: [UIColor whiteColor];
        if ([textColor respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
            textColor = [textColor resolvedColorWithTraitCollection:self.traitCollection];
        }
        [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, lyric.length)];
        [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, lyric.length)];

        NSUInteger loc = locNum ? locNum.unsignedIntegerValue : NSNotFound;
        NSUInteger len = lenNum ? lenNum.unsignedIntegerValue : 0;

        NSRange highlightRange = NSMakeRange(NSNotFound, 0);
        if (loc != NSNotFound && loc + len <= lyric.length) {
            highlightRange = NSMakeRange(loc, len);
        }

        NSRange backgroundHighlightRange = NSMakeRange(NSNotFound, 0);
        if (bgLocNum && bgLenNum) {
            NSUInteger bgLoc = bgLocNum.unsignedIntegerValue;
            NSUInteger bgLen = bgLenNum.unsignedIntegerValue;
            if (bgLoc != NSNotFound && bgLoc + bgLen <= lyric.length && bgLen > 0) {
                backgroundHighlightRange = NSMakeRange(bgLoc, bgLen);
            }
        }

        if (gDateLyricsHighlightStyle == 1) {
            NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
            if (highlightRange.location != NSNotFound && highlightRange.length > 0) {
                [ranges addObject:[NSValue valueWithRange:highlightRange]];
            }
            if (backgroundHighlightRange.location != NSNotFound && backgroundHighlightRange.length > 0) {
                [ranges addObject:[NSValue valueWithRange:backgroundHighlightRange]];
            }
            if (ranges.count > 0) {
                [ranges sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
                    NSRange left = a.rangeValue;
                    NSRange right = b.rangeValue;
                    if (left.location > right.location) return NSOrderedAscending;
                    if (left.location < right.location) return NSOrderedDescending;
                    return NSOrderedSame;
                }];
                for (NSValue *value in ranges) {
                    NSRange range = value.rangeValue;
                    if (NSMaxRange(range) > mAttrStr.length) continue;
                    NSString *syllable = [lyric substringWithRange:range];
                    NSString *upper = [syllable uppercaseStringWithLocale:[NSLocale currentLocale]];
                    // Uppercasing is not always length-preserving (ß -> SS, and some
                    // locale-specific forms). A longer replacement would shift every
                    // range recorded against this string, so skip rather than corrupt.
                    if (upper.length != syllable.length) continue;
                    [mAttrStr replaceCharactersInRange:range withString:upper];
                }
                [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, mAttrStr.length)];
                [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, mAttrStr.length)];
                attrDisplayText = mAttrStr;
            }
        } else if (gDateLyricsHighlightStyle == 2) {
            UIColor *dimmedColor = [textColor colorWithAlphaComponent:0.35];

            BOOL finished = [renderPayload[@"finished"] boolValue];
            BOOL started = renderPayload[@"started"] ? [renderPayload[@"started"] boolValue] : YES;

            [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, lyric.length)];

            if (finished) {
                [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, lyric.length)];
            } else if (!started) {
                [mAttrStr addAttribute:NSForegroundColorAttributeName value:dimmedColor range:NSMakeRange(0, lyric.length)];
            } else {
                [mAttrStr addAttribute:NSForegroundColorAttributeName value:dimmedColor range:NSMakeRange(0, lyric.length)];
                if (highlightRange.location != NSNotFound && highlightRange.length > 0) {
                    [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:highlightRange];
                }
                if (backgroundHighlightRange.location != NSNotFound && backgroundHighlightRange.length > 0) {
                    [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:backgroundHighlightRange];
                }
            }
            attrDisplayText = mAttrStr;
        } else {  
            // Stroke style
            if ((highlightRange.location != NSNotFound && highlightRange.length > 0) ||
                (backgroundHighlightRange.location != NSNotFound && backgroundHighlightRange.length > 0)) {
                
                [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, lyric.length)];
                [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, lyric.length)];
                
                if (highlightRange.location != NSNotFound && highlightRange.length > 0) {
                    [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@(-gDateLyricsStrokeWidth) range:highlightRange];
                    [mAttrStr addAttribute:NSStrokeColorAttributeName value:textColor range:highlightRange];
                }
                if (backgroundHighlightRange.location != NSNotFound && backgroundHighlightRange.length > 0) {
                    [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@(-gDateLyricsStrokeWidth) range:backgroundHighlightRange];
                    [mAttrStr addAttribute:NSStrokeColorAttributeName value:textColor range:backgroundHighlightRange];
                }
                attrDisplayText = mAttrStr;
            } else if (isTimed) {
                [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, lyric.length)];
                [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, lyric.length)];
                attrDisplayText = mAttrStr;
            }
        }
    }

    BOOL isShowingLyric = [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue];
    if (!isShowingLyric) {
        if (self.font) {
            objc_setAssociatedObject(self, kDateLyricsOriginalFontKey, self.font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (self.textColor) {
            objc_setAssociatedObject(self, kDateLyricsOriginalTextColorKey, self.textColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(self, kDateLyricsOriginalNumberOfLinesKey, @(self.numberOfLines), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalAdjustsFontSizeKey, @(self.adjustsFontSizeToFitWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalMinScaleKey, @(self.minimumScaleFactor), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalLineBreakModeKey, @(self.lineBreakMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalClipsToBoundsKey, @(self.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        if (self.attributedText) {
            objc_setAssociatedObject(self, kDateLyricsOriginalAttributedTextKey, self.attributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (self.text) {
            objc_setAssociatedObject(self, kDateLyricsOriginalTextKey, self.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }

    BOOL isTransitioning = [objc_getAssociatedObject(self, kDateLyricsAnimatingTransitionKey) boolValue];

    // Reassigning these mid-flight dirties layout and fights the running animation,
    // so only touch them when the label is settled.
    if (!isTransitioning) {
        self.font = configuredFont;
        self.numberOfLines = 1;
        if (isTimed) {
            if (gDateLyricsSplitLongLines) {
                self.adjustsFontSizeToFitWidth = NO;
                self.minimumScaleFactor = 1.0;
            } else {
                self.adjustsFontSizeToFitWidth = YES;
                self.minimumScaleFactor = gDateLyricsMinimumScale;
            }
        } else {
            self.adjustsFontSizeToFitWidth = YES;
            self.minimumScaleFactor = gDateLyricsMinimumScale;
        }
        self.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    BOOL contentChanged = NO;
    BOOL lineChanged = ![previousDisplayText isEqualToString:displayText];

    id currentLineId = renderPayload[@"lineId"];
    id previousLineId = objc_getAssociatedObject(self, @selector(previousLineId));
    if (currentLineId && previousLineId) {
        if (![currentLineId isEqual:previousLineId]) {
            lineChanged = YES;
        }
    }

    if (attrDisplayText) {
        contentChanged = ![self.attributedText isEqualToAttributedString:attrDisplayText];
    } else {
        contentChanged = self.attributedText != nil || ![self.text isEqualToString:displayText];
    }

    // A syllable update landing mid-transition must not repaint the label — that is
    // what tore the outgoing and incoming lines into each other. Coalesce it into a
    // single pending flag; the transition's completion re-runs us once we settle.
    // Bookkeeping is deliberately *not* committed here, so previousDisplayText keeps
    // describing what is actually on screen.
    DateLyricsDebugLog(@"APPLY split=%d w=%.1f frame=%.1f contentChg=%d lineChg=%d trans=%d loc=%@ len=%@ id=%@ prevId=%@ text='%@' prev='%@'",
                       [renderPayload[@"splitApplied"] boolValue],
                       CGRectGetWidth(self.bounds),
                       CGRectGetWidth(self.frame),
                       contentChanged, lineChanged, isTransitioning,
                       renderPayload[@"loc"] ?: @"-", renderPayload[@"len"] ?: @"-",
                       currentLineId ?: @"-", previousLineId ?: @"-",
                       displayText, previousDisplayText ?: @"-");

    if (contentChanged && isTransitioning && !lineChanged) {
        objc_setAssociatedObject(self, kDateLyricsPendingApplyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    objc_setAssociatedObject(self, @selector(_amlApplyCurrentLyric), displayText, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (currentLineId) {
        objc_setAssociatedObject(self, @selector(previousLineId), currentLineId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(self, @selector(previousLineId), nil, OBJC_ASSOCIATION_ASSIGN);
    }
    objc_setAssociatedObject(self, kDateLyricsLabelShowingLyricKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (contentChanged) {
        if (lineChanged) {
            DateLyricsAnimateLabelTransition(self, previousDisplayText ?: @"", displayText, attrDisplayText);
        } else {
            DateLyricsApplyLabelContent(self, displayText, attrDisplayText);
        }
    }
}

%end

%end

%group AMCrashPatcher

%hook VSSubscriptionRegistrationCenter

- (void)registerSubscription:(id)arg1 {
    return;
}

%end

%end

static void DateLyricsReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    void (^reloadBlock)(void) = ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)@"com.shalamand3r.datelyrics");

        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        if (!prefs) {
            prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        }

        auto getPrefBool = ^BOOL(NSString *key, BOOL defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val boolValue];
            if (prefs && prefs[key]) return [prefs[key] boolValue];
            return defaultVal;
        };

        auto getPrefInteger = ^NSInteger(NSString *key, NSInteger defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val integerValue];
            if (prefs && prefs[key]) return [prefs[key] integerValue];
            return defaultVal;
        };

        auto getPrefFloat = ^CGFloat(NSString *key, CGFloat defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return (CGFloat)[val floatValue];
            if (prefs && prefs[key]) return (CGFloat)[prefs[key] floatValue];
            return defaultVal;
        };

        auto getPrefDouble = ^double(NSString *key, double defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val doubleValue];
            if (prefs && prefs[key]) return [prefs[key] doubleValue];
            return defaultVal;
        };

        auto getPrefString = ^NSString *(NSString *key, NSString *defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val copy];
            if (prefs && prefs[key]) return [prefs[key] copy];
            return defaultVal;
        };

        gDateLyricsDebugLogging = getPrefBool(@"DebugLogging", YES);
        gDateLyricsEnabled = getPrefBool(@"Enabled", YES);
        gDateLyricsForceLowercase = getPrefBool(@"ForceLowercase", NO);
        gDateLyricsWordHighlighting = getPrefBool(@"WordHighlighting", YES);
        gDateLyricsHighlightStyle = getPrefInteger(@"HighlightStyle", 2);
        gDateLyricsHighlightTrail = getPrefBool(@"HighlightTrail", YES);
        gDateLyricsHapticsEnabled = getPrefBool(@"HapticsEnabled", NO);
        gDateLyricsHapticStyleSyllable = getPrefInteger(@"HapticStyleSyllable", 1);
        gDateLyricsHapticStyleLine = getPrefInteger(@"HapticStyleLine", 2);
        gDateLyricsUseCustomFont = getPrefBool(@"UseCustomFont", NO);
        gDateLyricsCustomFontName = getPrefString(@"CustomFontName", nil);
        gDateLyricsTransitionsEnabled = getPrefBool(@"TransitionsEnabled", YES);
        
        NSInteger transitionStyle = getPrefInteger(@"TransitionStyle", DateLyricsTransitionStyleSlideUp);
        if (transitionStyle < DateLyricsTransitionStyleFade || transitionStyle > DateLyricsTransitionStylePop) {
            transitionStyle = DateLyricsTransitionStyleSlideUp;
        }
        gDateLyricsTransitionStyle = transitionStyle;
        gDateLyricsTransitionDuration = getPrefDouble(@"TransitionDuration", 0.3);
        gDateLyricsStrokeWidth = getPrefFloat(@"StrokeWidth", 3.0);
        gDateLyricsSplitLongLines = getPrefBool(@"SplitLongLines", YES);
        if (gDateLyricsSplitLongLines) {
            gDateLyricsShowAdlibs = NO;
        } else {
            gDateLyricsShowAdlibs = getPrefBool(@"ShowAdlibs", NO);
        }
        gDateLyricsMinimumScale = getPrefFloat(@"MinimumScale", 0.55);
        gDateLyricsPauseTimeout = getPrefDouble(@"PauseTimeout", 2.0);
        gDateLyricsLineHoldDuration = getPrefDouble(@"LineHoldDuration", 2.0);
        gDateLyricsLineHoldDuration = MIN(MAX(gDateLyricsLineHoldDuration, 0.0), 10.0);
        gDateLyricsPauseWhenScreenOff = getPrefBool(@"PauseWhenScreenOff", YES);

        if (!gDateLyricsEnabled) {
            if (DateLyricsIsSpringBoardHost()) {
                gDateLyricsCurrentPayload = nil;
                DateLyricsApplyCurrentLineToAllCoverSheets();
            } else if (DateLyricsIsMusicHost()) {
                DateLyricsPublishPayload(nil);
            }
        } else {
            if (DateLyricsIsSpringBoardHost()) {
                gDateLyricsCurrentPayload = [(DateLyricsStoredPayload() ?: @{}) copy];
                DateLyricsApplyCurrentLineToAllCoverSheets();
                DateLyricsSchedulePayloadExpiry(gDateLyricsCurrentPayload);
            }
        }
    };

    if ([NSThread isMainThread]) {
        reloadBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), reloadBlock);
    }
}

// The preferences bundle cannot delete SpringBoard's or Music's lyric cache: each
// process has its own container and Preferences.app is sandboxed away from both.
// It posts this instead, and whichever hosts are alive clear their own storage.
static void DateLyricsClearCaches(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    pthread_mutex_lock(&gLyricsCacheMutex);
    [gLyricsCache removeAllObjects];
    [gWordLyricsCache removeAllObjects];
    [gLyricsCacheOrder removeAllObjects];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    NSString *rootPath = GetLyricsRootPath();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *entry in [fileManager contentsOfDirectoryAtPath:rootPath error:nil]) {
        if (![entry hasPrefix:@"syllable-lyrics_"] || ![entry hasSuffix:@".xml"]) continue;
        [fileManager removeItemAtPath:[rootPath stringByAppendingPathComponent:entry] error:nil];
    }

    if (DateLyricsIsSpringBoardHost()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gDateLyricsCurrentPayload = @{};
            DateLyricsApplyCurrentLineToAllCoverSheets();
        });
    }
}

// Screen-state bridge: SpringBoard observes system backlight notifications and
// forwards them to Music via our own Darwin namespace.
static void DateLyricsHandleScreenOff(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    gDateLyricsScreenIsOn = NO;
    if (gDateLyricsPauseWhenScreenOff) {
        gDateLyricsConsumerActive = NO;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.shalamand3r.datelyrics/screenOff"), NULL, NULL, YES);
    }
}

static void DateLyricsHandleScreenOn(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    gDateLyricsScreenIsOn = YES;
    if (!gDateLyricsConsumerActive) {
        gDateLyricsConsumerActive = YES;
        // Tell Music to resume publishing.
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.shalamand3r.datelyrics/screenOn"), NULL, NULL, YES);
        // Immediately re-apply whatever payload we last stored so there's no
        // blank frame on wake.
        dispatch_async(dispatch_get_main_queue(), ^{
            gDateLyricsCurrentPayload = [(DateLyricsStoredPayload() ?: @{}) copy];
            DateLyricsApplyCurrentLineToAllCoverSheets();
        });
    }
}

// Music-side receivers for the screen-state bridge.
static void DateLyricsHandleConsumerPaused(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    gDateLyricsConsumerActive = NO;
}

static void DateLyricsHandleConsumerResumed(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    gDateLyricsConsumerActive = YES;
}

%ctor {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsCache = [[NSMutableDictionary alloc] init];
        gWordLyricsCache = [[NSMutableDictionary alloc] init];
        gLyricsCacheOrder = [NSMutableArray array];
        gLyricsQueue = dispatch_queue_create("com.shalamand3r.datelyrics.queue", DISPATCH_QUEUE_SERIAL);
        gLyricsTaskQueue = [NSMutableArray array];
        gPendingLyricsIDs = [NSMutableSet set];
    });

    DateLyricsReloadPrefs(NULL, NULL, NULL, NULL, NULL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsReloadPrefs, CFSTR("com.shalamand3r.datelyrics/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsClearCaches, CFSTR("com.shalamand3r.datelyrics/ClearCaches"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    BOOL isSpringBoardHost = DateLyricsIsSpringBoardHost();

    if (isSpringBoardHost) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        gDateLyricsDateViews = [NSHashTable weakObjectsHashTable];
        gDateLyricsWidgetSlots = [NSHashTable weakObjectsHashTable];
        gDateLyricsCurrentPayload = [(DateLyricsStoredPayload() ?: @{}) copy];
        DateLyricsWriteRuntimeStatus();
        
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsCurrentLineChanged, kDateLyricsCurrentLineChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        // Screen-off gating: observe backlight state and bridge it to Music.
        // com.apple.springboard.hasBlankedScreen fires on screen-off;
        // com.apple.springboard.didTurnOnDisplay fires on wake.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            DateLyricsHandleScreenOff,
            CFSTR("com.apple.springboard.hasBlankedScreen"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            DateLyricsHandleScreenOn,
            CFSTR("com.apple.springboard.didTurnOnDisplay"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        %init(DateLyricsSpringBoard);
        DateLyricsSchedulePayloadExpiry(gDateLyricsCurrentPayload);
    } else if (DateLyricsIsMusicHost()) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17) {
            dlopen("/System/Library/Frameworks/VideoSubscriberAccount.framework/VideoSubscriberAccount", RTLD_NOW);
            %init(AMCrashPatcher);
        }
        %init(DateLyricsPrimary);
        DateLyricsWriteRuntimeStatus();

        // Listen for SpringBoard's screen-state bridge notifications so Music
        // knows when the consumer is active.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            DateLyricsHandleConsumerPaused,
            CFSTR("com.shalamand3r.datelyrics/screenOff"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            DateLyricsHandleConsumerResumed,
            CFSTR("com.shalamand3r.datelyrics/screenOn"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
