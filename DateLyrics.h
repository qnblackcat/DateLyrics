// Shared declarations used by the Logos hooks in DateLyrics.xm. Keep
// translation-unit-local associated-object keys and hook helpers here.

#pragma once

@import Darwin;
@import Foundation;
@import MediaPlayer;
@import QuartzCore;
@import UIKit;
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdarg.h>
#import <math.h>
#import <float.h>
#import <ctype.h>
#import <roothide.h>
#import "DateLyricsModels.h"
#import "DateLyricsLyricsParser.h"
#import "DateLyricsPayload.h"
#import "DateLyricsResolver.h"
#import "DateLyricsText.h"
#import "DateLyricsMusixmatchParser.h"
#import "DateLyricsYouTubeMusic.h"
#import "DateLyricsPrivateAPI.h"

#pragma mark - Private API

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

#pragma mark - Types

typedef NS_ENUM(NSInteger, DateLyricsTransitionStyle) {
    DateLyricsTransitionStyleFade = 0,
    DateLyricsTransitionStyleSlideUp = 1,
    DateLyricsTransitionStyleSlideDown = 2,
    DateLyricsTransitionStylePush = 3,
    DateLyricsTransitionStylePop = 4,
};

#pragma mark - Associated object keys

extern const void *kDateLyricsForcedWidgetDateVisibleKey;
extern const void *kDateLyricsOriginalHiddenKey;
extern const void *kDateLyricsRestoringStockDateKey;
extern const void *kDateLyricsLabelShowingLyricKey;
extern const void *kDateLyricsLastRenderedAttrTextKey;
extern const void *kDateLyricsLastRenderedTextKey;
extern const void *kDateLyricsRenderCacheKey;
extern const void *kDateLyricsAnimatingTransitionKey;
extern const void *kDateLyricsMarqueeActiveKey;
extern const void *kDateLyricsMarqueeLineIdKey;
extern const void *kDateLyricsMarqueeContainerKey;
extern const void *kDateLyricsMarqueeContentLabelKey;
extern const void *kDateLyricsTransitionGenerationKey;
extern const void *kDateLyricsOriginalClipsToBoundsKey;
extern const void *kDateLyricsOriginalFontKey;
extern const void *kDateLyricsOriginalTextColorKey;
extern const void *kDateLyricsOriginalNumberOfLinesKey;
extern const void *kDateLyricsOriginalAdjustsFontSizeKey;
extern const void *kDateLyricsOriginalMinScaleKey;
extern const void *kDateLyricsOriginalLineBreakModeKey;
extern const void *kDateLyricsOriginalAttributedTextKey;
extern const void *kDateLyricsOriginalTextKey;
extern const void *kDateLyricsIsDateLabelKey;
extern const void *kDateLyricsCachedLabelKey;
extern const void *kDateLyricsCachedWidgetHostKey;
extern const void *kDateLyricsSplitPlanKey;
extern const void *kDateLyricsSplitWidthKey;
extern const void *kDateLyricsFrozenFrameKey;
extern const void *kDateLyricsOutgoingSnapshotKey;
extern const void *kDateLyricsApplyingLyricContentKey;
extern const void *kDateLyricsSweepMaskKey;

// Set once on the specific label we drive, so the _UIAnimatingLabel setter hooks
// can early-out with a single lookup instead of walking the superview chain on
// every text assignment in SpringBoard.
// Weak-boxed cache of the label a date view owns, so we stop re-running a
// recursive subview search on every layout pass.
// Cached widget host view. Widget containers can lay out many times per second;
// retain the positive recursive lookup while the host remains in the subtree.
// Cached DateLyricsSplitPlan for the line currently on the label.
// Latched (grow-only) wrap width for the label. See DateLyricsSplitAvailableWidth.
// Frame the label is pinned to for the duration of a line transition.
// Static copy of the outgoing line. Keeping the real label live allows
// syllable colours to update while the line transition is still running.
// Distinguishes our own lyric content writes from SpringBoard's stock date
// updates. The latter must not replace an active lyric during wake/layout.
// DateLyricsSweepMask behind the label's smooth-sweep layer mask.


