#import "DateLyricsInternal.h"


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
_UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view) {
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

static UIView *DateLyricsFindWidgetHostView(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return nil;

    DateLyricsWeakBox *box = objc_getAssociatedObject(view, kDateLyricsCachedWidgetHostKey);
    UIView *cached = box.object;
    if ([cached isKindOfClass:UIView.class] && (cached == view || [cached isDescendantOfView:view])) {
        return cached;
    }

    UIView *host = nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"CHUISWidgetHostViewControllerView"]) {
        host = view;
    } else {
        for (UIView *subview in view.subviews) {
            host = DateLyricsFindWidgetHostView(subview);
            if (host) break;
        }
    }

    if (host) {
        if (!box) {
            box = [DateLyricsWeakBox new];
            objc_setAssociatedObject(view, kDateLyricsCachedWidgetHostKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        box.object = host;
    } else {
        objc_setAssociatedObject(view, kDateLyricsCachedWidgetHostKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    return host;
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
        if (!DateLyricsFindWidgetHostView(subview)) continue;
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
        if (!DateLyricsFindWidgetHostView(subview)) continue;
        BOOL matchesDateSlot = DateLyricsWidgetSlotMatchesDateSlot(subview, dateView);
        if (hidden && !matchesDateSlot) continue;
        if (!hidden && !matchesDateSlot && !objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey)) continue;

        if (hidden) {
            if (!objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey)) {
                objc_setAssociatedObject(subview, kDateLyricsOriginalHiddenKey, @(subview.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (!subview.hidden) subview.hidden = YES;
        } else {
            NSNumber *originalHidden = objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey);
            if (originalHidden) {
                BOOL shouldHide = originalHidden.boolValue;
                if (subview.hidden != shouldHide) subview.hidden = shouldHide;
                objc_setAssociatedObject(subview, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            }
        }
    }
}

static BOOL DateLyricsShouldSuppressStockDate(void) {
    if (!DateLyricsDisplayAllowed() || !gDateLyricsCurrentScore || !gDateLyricsLocalAnchor) return NO;
    if ([gDateLyricsLocalAnchor[@"rate"] floatValue] <= 0.0f) return NO;
    return DateLyricsHasRenderableLyricPayload();
}

BOOL DateLyricsHasRenderableLyricPayload(void) {
    if (!DateLyricsDisplayAllowed()) return NO;
    NSString *text = gDateLyricsCurrentPayload[@"text"];
    return [text isKindOfClass:NSString.class] && text.length > 0;
}

void DateLyricsInvalidateLabelRenderCache(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    objc_setAssociatedObject(label, kDateLyricsRenderCacheKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

void DateLyricsPrepareAndApplyDateLabel(_UIAnimatingLabel *label) {
    if (!label) return;
    DateLyricsInvalidateLabelRenderCache(label);
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

void DateLyricsRestoreSystemDateLabel(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    // Never leave the stock date drawn through a lyric mask.
    DateLyricsRemoveSweepMask(label);
    UIView *outgoingSnapshot = objc_getAssociatedObject(label, kDateLyricsOutgoingSnapshotKey);
    [outgoingSnapshot removeFromSuperview];
    objc_setAssociatedObject(label, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
    if (!DateLyricsLabelHasResidualLyricState(label)) return;

    DateLyricsStopMarquee(label);
    CSProminentSubtitleDateView *dateView = DateLyricsFindAncestorDateView(label);
    objc_setAssociatedObject(label, kDateLyricsLabelShowingLyricKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsLastRenderedAttrTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsLastRenderedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DateLyricsInvalidateLabelRenderCache(label);
    objc_setAssociatedObject(label, @selector(_amlApplyCurrentLyric), nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, @selector(previousLineId), nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
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

void DateLyricsUpdateWidgetDateView(UIView *widgetSlot) {
    if (![widgetSlot isKindOfClass:UIView.class]) return;
    if (!DateLyricsFindWidgetHostView(widgetSlot)) return;

    CSProminentSubtitleDateView *dateView = DateLyricsFindSiblingDateView(widgetSlot);
    if (!dateView) return;

    NSDictionary *payload = DateLyricsCurrentRenderablePayload();
    BOOL hasLyric = [payload[@"text"] isKindOfClass:NSString.class];

    if (!DateLyricsDisplayAllowed()) hasLyric = NO;

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

    BOOL wasForced = [objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue];
    if (wasForced && widgetSlot.hidden && !dateView.hidden) return;

    if (!wasForced && !objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey)) {
        objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, @(dateView.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (dateView.hidden) dateView.hidden = NO;
    if (!wasForced || !widgetSlot.hidden) {
        DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, YES);
    }
    objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!wasForced) {
        DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(dateView));
        [dateView setNeedsLayout];
    }
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
    if (lyric.length > 0 && DateLyricsDisplayAllowed()) {
        label.hidden = NO;
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
        if (!DateLyricsShouldSuppressStockDate()) {
            label.hidden = NO;
        }
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

// Tapping the Lock Screen artwork makes MediaRemoteUI take a lock screen
// background-content assertion and draw the full-screen artwork itself.
// SpringBoard hosts that scene in CSCoverSheetViewController's
// _backgroundContentViewController and drops it again when the player collapses
// (the same add/remove that reports the wallpaper as obscured). Present on
// iOS 16 and 17.
static NSString *const kDateLyricsMediaRemoteUIBundleID = @"com.apple.MediaRemoteUI";

static NSString *DateLyricsBundleIdentifierOf(id object) {
    if (![object respondsToSelector:@selector(bundleIdentifier)]) return nil;
    id bundleID = [object performSelector:@selector(bundleIdentifier)];
    return [bundleID isKindOfClass:NSString.class] && [bundleID length] > 0 ? bundleID : nil;
}

static NSString *DateLyricsSceneClientBundleIdentifier(id scene) {
    if (!scene) return nil;
    if ([scene respondsToSelector:@selector(clientProcess)]) {
        NSString *bundleID = DateLyricsBundleIdentifierOf([scene performSelector:@selector(clientProcess)]);
        if (bundleID) return bundleID;
    }
    if ([scene respondsToSelector:@selector(clientHandle)]) {
        NSString *bundleID = DateLyricsBundleIdentifierOf([scene performSelector:@selector(clientHandle)]);
        if (bundleID) return bundleID;
    }
    if ([scene respondsToSelector:@selector(definition)]) {
        id definition = [scene performSelector:@selector(definition)];
        if ([definition respondsToSelector:@selector(clientIdentity)]) {
            return DateLyricsBundleIdentifierOf([definition performSelector:@selector(clientIdentity)]);
        }
    }
    return nil;
}

static UIViewController *DateLyricsBackgroundContentViewController(CSCoverSheetViewController *coverSheet) {
    Ivar ivar = class_getInstanceVariable(object_getClass(coverSheet), "_backgroundContentViewController");
    if (!ivar) return nil;
    id controller = object_getIvar(coverSheet, ivar);
    return [controller isKindOfClass:UIViewController.class] ? controller : nil;
}

static void DateLyricsSetArtworkExpanded(BOOL expanded) {
    if (gDateLyricsArtworkExpanded == expanded) return;
    gDateLyricsArtworkExpanded = expanded;
    if (!gDateLyricsOnlyExpandedArtwork) return;
    gDateLyricsRenderGeneration++;
    DateLyricsApplyCurrentLineToAllCoverSheets();
}

static void DateLyricsSyncArtworkExpandedState(CSCoverSheetViewController *coverSheet, NSString *reason) {
    UIViewController *background = DateLyricsBackgroundContentViewController(coverSheet);
    NSString *clientBundleID = nil;
    if (background && [background respondsToSelector:@selector(scene)]) {
        clientBundleID = DateLyricsSceneClientBundleIdentifier([background performSelector:@selector(scene)]);
    }
    // If the client cannot be identified, assume Now Playing: wrongly showing
    // lyrics is a better failure than hiding them in the mode the user wants.
    BOOL expanded = background && (!clientBundleID || [clientBundleID isEqualToString:kDateLyricsMediaRemoteUIBundleID]);
    DateLyricsDebugLog(@"[Artwork] %@ (client=%@) -> %@", reason, clientBundleID ?: @"?", expanded ? @"expanded" : @"compact");
    DateLyricsSetArtworkExpanded(expanded);
}

static void DateLyricsSetLockScreenState(BOOL coverSheetVisible, BOOL screenOff, NSString *reason) {
    BOOL wasLive = DateLyricsLockScreenLive();
    BOOL screenOffChanged = gDateLyricsScreenOff != screenOff;
    gDateLyricsCoverSheetVisible = coverSheetVisible;
    gDateLyricsScreenOff = screenOff;
    // Always-On: freeze sweeps fully lit while the screen is off, resume after.
    if (screenOffChanged && gDateLyricsSmoothSweep) DateLyricsSweepResyncAllLabels();
    BOOL live = DateLyricsLockScreenLive();
    if (live == wasLive) return;

    DateLyricsDebugLog(@"[Ticker] lock screen %@ (%@)", live ? @"live" : @"hidden", reason);
    if (live) {
        gDateLyricsCatchingUp = YES;
        DateLyricsScheduleTicker();
        gDateLyricsCatchingUp = NO;
    } else if (gDateLyricsTicker) {
        dispatch_source_cancel(gDateLyricsTicker);
        gDateLyricsTicker = nil;
    }
}

%hook CSCoverSheetViewController

// Presented when the device locks or Notification Center is pulled down;
// dismissed on unlock. Only a completed dismissal counts, so a cancelled
// unlock swipe never stops the ticker.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DateLyricsSetLockScreenState(YES, gDateLyricsScreenOff, @"cover sheet appearing");
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    DateLyricsSetLockScreenState(NO, gDateLyricsScreenOff, @"cover sheet dismissed");
}

// The flag the cover sheet itself uses to pause its widgets with the backlight.
- (void)setInScreenOffMode:(BOOL)screenOff forAutoUnlock:(BOOL)autoUnlock fromUnlockSource:(int)source {
    %orig;
    DateLyricsSetLockScreenState(gDateLyricsCoverSheetVisible, screenOff, screenOff ? @"screen off" : @"screen on");
}

- (void)_addBackgroundContentViewControllerForAction:(id)action {
    %orig;
    DateLyricsSyncArtworkExpandedState(self, @"background content added");
}

- (void)_removeBackgroundContentViewController {
    %orig;
    DateLyricsSyncArtworkExpandedState(self, @"background content removed");
}

%end

%hook _UIAnimatingLabel

// These setters fire for every _UIAnimatingLabel in SpringBoard, not just ours, so
// the very first thing they must do is cheaply establish that this is our label.
// The tag is applied by DateLyricsFindAnimatingLabel when the date view adopts it.
- (void)didMoveToWindow {
    %orig;
    if (self.window) return;
    DateLyricsStopMarquee(self);
    UIView *outgoingSnapshot = objc_getAssociatedObject(self, kDateLyricsOutgoingSnapshotKey);
    [outgoingSnapshot removeFromSuperview];
    objc_setAssociatedObject(self, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void)layoutSubviews {
    %orig;
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) return;
    DateLyricsSweepRelayoutIfResized(self);
}

- (void)setText:(NSString *)text {
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) {
        %orig;
        return;
    }
    if (![objc_getAssociatedObject(self, kDateLyricsApplyingLyricContentKey) boolValue] &&
        [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue] &&
        DateLyricsHasRenderableLyricPayload()) {
        return;
    }
    DateLyricsInvalidateLabelRenderCache(self);
    if (text.length > 0 && ![objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue]) {
        // Routed through attributedText purely to clear any inherited stroke width.
        // %orig is intentionally skipped: setting attributedText supersedes it, and
        // calling both makes the stock date flicker.
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:text];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        self.attributedText = cleanStr;
        return;
    }
    [UIView performWithoutAnimation:^{
        %orig;
    }];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) {
        %orig;
        return;
    }
    if (![objc_getAssociatedObject(self, kDateLyricsApplyingLyricContentKey) boolValue] &&
        [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue] &&
        DateLyricsHasRenderableLyricPayload()) {
        return;
    }
    DateLyricsInvalidateLabelRenderCache(self);
    if (attributedText.length > 0 && ![objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue]) {
        NSMutableAttributedString *cleanStr = [attributedText mutableCopy];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        %orig(cleanStr);
        return;
    }
    [UIView performWithoutAnimation:^{
        %orig;
    }];
}

%new
- (void)_amlApplyCurrentLyric {
    if (!DateLyricsDisplayAllowed()) {
        DateLyricsRestoreSystemDateLabel(self);
        return;
    }
    NSDictionary *sourcePayload = DateLyricsCurrentRenderablePayload();
    NSDictionary *payload = sourcePayload;
    NSString *sourceLyric = payload[@"text"];
    if (sourceLyric.length == 0) {
        DateLyricsRestoreSystemDateLabel(self);
        return;
    }

    UIFont *configuredFont = DateLyricsConfiguredFontForLabel(self);
    BOOL isShowingLyric = [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue];
    NSDictionary *renderCache = objc_getAssociatedObject(self, kDateLyricsRenderCacheKey);
    UIFont *cachedFont = renderCache[@"font"];
    UITraitCollection *cachedTraits = renderCache[@"traits"];
    NSString *cachedDisplayText = renderCache[@"displayText"];
    NSString *currentLabelText = self.attributedText.string ?: self.text ?: @"";
    BOOL labelMatchesCache = [cachedDisplayText isKindOfClass:NSString.class] && [currentLabelText isEqualToString:cachedDisplayText];
    BOOL sizingChanged = renderCache &&
        (fabs([renderCache[@"minimumScale"] doubleValue] - gDateLyricsMinimumScale) > 0.001 ||
         [renderCache[@"splitLongLines"] boolValue] != gDateLyricsSplitLongLines ||
         [renderCache[@"marqueeEnabled"] boolValue] != gDateLyricsMarqueeEnabled);
    BOOL cachedMarqueeNeeded = [renderCache[@"marqueeNeeded"] boolValue];
    BOOL marqueeReady = !cachedMarqueeNeeded ||
        [objc_getAssociatedObject(self, kDateLyricsMarqueeActiveKey) boolValue];
    BOOL cacheMatches = isShowingLyric && renderCache[@"payload"] == sourcePayload &&
        [renderCache[@"generation"] unsignedIntegerValue] == gDateLyricsRenderGeneration &&
        fabs([renderCache[@"width"] doubleValue] - CGRectGetWidth(self.bounds)) < 0.5 &&
        !sizingChanged && [cachedFont isEqual:configuredFont] &&
        [cachedTraits isEqual:self.traitCollection] && labelMatchesCache && marqueeReady;
    if (cacheMatches) return;

    if (payload && !gDateLyricsShowAdlibs) {
        NSString *rawText = payload[@"text"];
        NSString *strippedText = DateLyricsStripParentheses(rawText, gDateLyricsShowAdlibs) ?: @"";
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
    BOOL hasWordTiming = [renderPayload[@"wordTimed"] boolValue];
    // Estimated word timings only drive line splitting; they must not light
    // the line up word by word.
    BOOL canHighlightWords = hasWordTiming && ![renderPayload[@"estimated"] boolValue];
    BOOL splitApplied = [renderPayload[@"splitApplied"] boolValue];

    // Marquee is only needed when the line remains wider than the available
    // container even at the user's selected minimum scale.
    CGFloat _marqueeTextWidth = 0.0;
    CGFloat _marqueeContainerWidth = 0.0;
    BOOL _textOverflows = NO;
    if (gDateLyricsMarqueeEnabled && !splitApplied) {
        BOOL canReuseMarqueeGeometry =
            [renderCache[@"marqueeEnabled"] boolValue] &&
            [cachedDisplayText isEqualToString:lyric] &&
            [cachedFont isEqual:configuredFont] &&
            fabs([renderCache[@"width"] doubleValue] - CGRectGetWidth(self.bounds)) < 0.5 &&
            [renderCache[@"marqueeTextWidth"] isKindOfClass:NSNumber.class] &&
            [renderCache[@"marqueeContainerWidth"] isKindOfClass:NSNumber.class];
        if (canReuseMarqueeGeometry) {
            _marqueeTextWidth = [renderCache[@"marqueeTextWidth"] doubleValue];
            _marqueeContainerWidth = [renderCache[@"marqueeContainerWidth"] doubleValue];
        } else {
            _marqueeContainerWidth = DateLyricsSplitAvailableWidth(self);
            if (_marqueeContainerWidth > 0) {
                _marqueeTextWidth = DateLyricsMeasuredLineWidth(lyric, configuredFont);
            }
        }
        CGFloat allowedScale = MIN(MAX(gDateLyricsMinimumScale, 0.01), 1.0);
        _textOverflows = _marqueeContainerWidth > 0 &&
            (_marqueeTextWidth * allowedScale) > _marqueeContainerWidth + 0.5f;
    }
    // The marquee scrolls a copy of the attributed text, which the mask on
    // this label would not cover; such lines keep the classic highlight.
    BOOL sweepEnabled = gDateLyricsSmoothSweep && gDateLyricsWordHighlighting && canHighlightWords && !_textOverflows;
    if (gDateLyricsWordHighlighting && canHighlightWords) {
        NSMutableAttributedString *mAttrStr = [[NSMutableAttributedString alloc] initWithString:lyric];
        
        UIColor *textColor = DateLyricsBaseTextColorForLabel(self);
        [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, lyric.length)];

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

        // Opacity is the sole highlight style: dim upcoming syllables and retain
        // the normal colour for the spoken portion of the line.
        UIColor *dimmedColor = [textColor colorWithAlphaComponent:kDateLyricsDimmedAlpha];
        BOOL finished = [renderPayload[@"finished"] boolValue];
        BOOL started = renderPayload[@"started"] ? [renderPayload[@"started"] boolValue] : YES;
        if (finished || sweepEnabled) {
            // A sweep line is dimmed by its mask, not by glyph colour.
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
    }

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

    if (isTransitioning && sizingChanged) {
        return;
    }

    // Reassigning these mid-flight dirties layout and fights the running animation,
    // so only touch them when the label is settled.
    if (!isTransitioning) {
        self.font = configuredFont;
        self.numberOfLines = 1;
        // Marquee handles overflow when: enabled, split was NOT applied, and text is wider than container.
        // In that case skip adjustsFontSizeToFitWidth so the label stays full-size for scrolling.
        BOOL marqueeWillHandle = _textOverflows && gDateLyricsMarqueeEnabled && !splitApplied;
        if (isTimed && gDateLyricsSplitLongLines && hasWordTiming) {
            // Split is handling long syllable-timed lines — no scaling, no marquee.
            self.adjustsFontSizeToFitWidth = NO;
            self.minimumScaleFactor = 1.0;
        } else if (marqueeWillHandle) {
            // Marquee will scroll the full-width text — disable auto-shrink.
            self.adjustsFontSizeToFitWidth = NO;
            self.minimumScaleFactor = 1.0;
        } else {
            self.adjustsFontSizeToFitWidth = YES;
            self.minimumScaleFactor = gDateLyricsMinimumScale;
        }
        // The scrolling overlay is created after an incoming transition. Keep
        // the stock label clipped in the meantime so marquee mode never exposes
        // UIKit's temporary trailing ellipsis.
        self.lineBreakMode = gDateLyricsMarqueeEnabled
            ? NSLineBreakByClipping
            : NSLineBreakByTruncatingTail;
        self.clipsToBounds = YES;
    }

    BOOL contentChanged = NO;
    BOOL lineChanged = ![previousDisplayText isEqualToString:displayText];

    id currentLineId = renderPayload[@"lineId"];
    id previousLineId = objc_getAssociatedObject(self, @selector(previousLineId));
    BOOL reverseDirection = NO;
    if (currentLineId && previousLineId) {
        if (![currentLineId isEqual:previousLineId]) {
            lineChanged = YES;
            reverseDirection = DateLyricsCompareLineIdentity(currentLineId, previousLineId) == NSOrderedAscending;
        }
    }

    if (attrDisplayText) {
        NSAttributedString *lastAttrText = objc_getAssociatedObject(self, kDateLyricsLastRenderedAttrTextKey);
        contentChanged = ![lastAttrText isEqualToAttributedString:attrDisplayText];
    } else {
        NSString *lastText = objc_getAssociatedObject(self, kDateLyricsLastRenderedTextKey);
        contentChanged = lastText == nil || ![lastText isEqualToString:displayText];
    }
    // A sweep line's attributed text is constant, so a repeated line ("na na
    // na") would otherwise compare equal and skip its transition.
    contentChanged = contentChanged || sizingChanged || (sweepEnabled && lineChanged);

    // A different line must not replace an active transition. A real-world
    // example is Minibar's caviar ->
    // "Break down the door…" boundary: a stale caviar update arrives ~90 ms after
    // the split line, followed by the correct payload again a few milliseconds
    // later.  Letting either one interrupt the active transition creates three
    // overlapping pushes.  Coalescing all updates means completion renders the
    // newest global payload exactly once.  This also makes a rapid seek settle to
    // its final position instead of displaying transient intermediate lines.
    // Bookkeeping is deliberately not committed here, so previousDisplayText still
    // describes what is actually on screen.
    DateLyricsDebugLog(@"APPLY split=%d wordTimed=%d started=%d finished=%d w=%.1f frame=%.1f contentChg=%d lineChg=%d reverse=%d trans=%d loc=%@ len=%@ id=%@ prevId=%@ text='%@' prev='%@'",
                       [renderPayload[@"splitApplied"] boolValue],
                       [renderPayload[@"wordTimed"] boolValue],
                       renderPayload[@"started"] ? [renderPayload[@"started"] boolValue] : YES,
                       [renderPayload[@"finished"] boolValue],
                       CGRectGetWidth(self.bounds),
                       CGRectGetWidth(self.frame),
                       contentChanged, lineChanged, reverseDirection, isTransitioning,
                       renderPayload[@"loc"] ?: @"-", renderPayload[@"len"] ?: @"-",
                       currentLineId ?: @"-", previousLineId ?: @"-",
                       displayText, previousDisplayText ?: @"-");

    // Same-line syllable changes are safe: the outgoing line is now a static
    // sibling snapshot, while this label is the live incoming line. Applying
    // its new attributed string here keeps the first syllable on timestamp.
    if (contentChanged && isTransitioning && lineChanged) {
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
        if (attrDisplayText) {
            objc_setAssociatedObject(self, kDateLyricsLastRenderedAttrTextKey, attrDisplayText, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(self, kDateLyricsLastRenderedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
        } else {
            objc_setAssociatedObject(self, kDateLyricsLastRenderedAttrTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(self, kDateLyricsLastRenderedTextKey, displayText, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }

        if (lineChanged) {
            DateLyricsAnimateLabelTransition(self, previousDisplayText ?: @"", displayText, attrDisplayText, reverseDirection);
        } else {
            DateLyricsApplyLabelContent(self, displayText, attrDisplayText);
        }
    }
    // After any transition has snapshotted the outgoing line and pinned the
    // frame, so the mask is laid out for the bounds the new line is shown in.
    if (sweepEnabled) {
        DateLyricsLayoutSweepMask(self, renderPayload, displayText);
    } else {
        DateLyricsRemoveSweepMask(self);
    }
    DateLyricsRefreshMarqueeContent(self);

    // Marquee scrolling: start when text overflows and split isn't handling it;
    // restart only on a new line so syllable highlights mid-line don't stutter-restart the scroll.
    UIView *marqueeContainer = objc_getAssociatedObject(self, kDateLyricsMarqueeContainerKey);
    BOOL marqueeViewportChanged = marqueeContainer &&
        fabs(CGRectGetWidth(marqueeContainer.bounds) - CGRectGetWidth(self.bounds)) >= 0.5;
    if (marqueeViewportChanged) {
        DateLyricsStopMarquee(self);
    }

    BOOL marqueeViewportReady = _marqueeContainerWidth > 0.0 &&
        fabs(CGRectGetWidth(self.bounds) - _marqueeContainerWidth) < 0.5;
    BOOL transitionRunning = [objc_getAssociatedObject(self, kDateLyricsAnimatingTransitionKey) boolValue];
    if (!transitionRunning && marqueeViewportReady &&
        gDateLyricsMarqueeEnabled && !splitApplied && _textOverflows) {
        id marqueeLineId = objc_getAssociatedObject(self, kDateLyricsMarqueeLineIdKey);
        BOOL alreadyMarqueeingThisLine = marqueeLineId && currentLineId && [marqueeLineId isEqual:currentLineId];
        if (!alreadyMarqueeingThisLine) {
            NSTimeInterval lineDuration = [renderPayload[@"lineDuration"] doubleValue];
            if (lineDuration < 0.3) lineDuration = 5.0;
            NSTimeInterval remainingLineTime = lineDuration;
            if (currentLineId && gDateLyricsLastResolvedElapsed >= 0.0) {
                NSString *lineIdentity = [currentLineId description] ?: @"";
                NSTimeInterval lineBegin = [lineIdentity componentsSeparatedByString:@"#"].firstObject.doubleValue;
                if (gDateLyricsLastResolvedElapsed >= lineBegin) {
                    remainingLineTime = MAX(0.0,
                        lineBegin + lineDuration - gDateLyricsLastResolvedElapsed);
                }
            }
            CGFloat overflow = _marqueeTextWidth - _marqueeContainerWidth;
            if (DateLyricsStartMarquee(self, overflow, remainingLineTime)) {
                objc_setAssociatedObject(self, kDateLyricsMarqueeLineIdKey, currentLineId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                DateLyricsDebugLog(@"MARQUEE start viewport=%.1f text=%.1f remaining=%.2f line=%@",
                                   _marqueeContainerWidth, _marqueeTextWidth,
                                   remainingLineTime, currentLineId ?: @"-");
            }
        }
    } else if (!_textOverflows) {
        DateLyricsStopMarquee(self);
    }

    objc_setAssociatedObject(self, kDateLyricsRenderCacheKey, @{
        @"generation": @(gDateLyricsRenderGeneration),
        @"payload": sourcePayload,
        @"displayText": displayText,
        @"width": @(CGRectGetWidth(self.bounds)),
        @"minimumScale": @(gDateLyricsMinimumScale),
        @"splitLongLines": @(gDateLyricsSplitLongLines),
        @"marqueeEnabled": @(gDateLyricsMarqueeEnabled),
        @"marqueeNeeded": @(_textOverflows),
        @"marqueeTextWidth": @(_marqueeTextWidth),
        @"marqueeContainerWidth": @(_marqueeContainerWidth),
        @"font": configuredFont,
        @"traits": self.traitCollection ?: [NSNull null]
    }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%end

void DateLyricsInitSpringBoardHooks(void) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        gDateLyricsDateViews = [NSHashTable weakObjectsHashTable];
        gDateLyricsWidgetSlots = [NSHashTable weakObjectsHashTable];
        gDateLyricsCurrentPayload = nil;
        Class coverSheetClass = NSClassFromString(@"CSCoverSheetViewController");
        gDateLyricsArtworkDetectionAvailable = coverSheetClass &&
            class_getInstanceVariable(coverSheetClass, "_backgroundContentViewController") &&
            [coverSheetClass instancesRespondToSelector:@selector(_addBackgroundContentViewControllerForAction:)] &&
            [coverSheetClass instancesRespondToSelector:@selector(_removeBackgroundContentViewController)];
        if (!gDateLyricsArtworkDetectionAvailable) {
            DateLyricsDebugLog(@"[Artwork] background content hooks unavailable; full-screen-only option disabled");
        }
        DateLyricsWriteRuntimeStatus();
        
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsHandleAnchorChanged, CFSTR("com.shalamand3r.datelyrics/anchor.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsHandleScoreChanged, CFSTR("com.shalamand3r.datelyrics/score.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsHandleAnchorChanged, CFSTR("com.shalamand3r.datelyrics/anchor.youtube.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsHandleScoreChanged, CFSTR("com.shalamand3r.datelyrics/score.youtube.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        // Ask either playback host for its latest anchor on SpringBoard launch.
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.shalamand3r.datelyrics/anchor.request"), NULL, NULL, YES);
        %init(DateLyricsSpringBoard);
}
