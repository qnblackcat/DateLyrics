// Label rendering: fonts, long-line splitting, transitions, marquee and smooth sweep.

#import "DateLyricsInternal.h"

void DateLyricsApplyCurrentLineToAllCoverSheets(void) {
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

void DateLyricsPlayHaptic(NSInteger style) {
    if (!gDateLyricsHapticsEnabled || gDateLyricsCatchingUp || !DateLyricsDisplayAllowed() || style < 0 || style > 4) return;
    void (^playBlock)(void) = ^{
        static NSMutableDictionary<NSNumber *, UIImpactFeedbackGenerator *> *generators = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            generators = [NSMutableDictionary dictionary];
        });
        NSNumber *key = @(style);
        UIImpactFeedbackGenerator *generator = generators[key];
        if (!generator) {
            generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyle)style];
            generators[key] = generator;
        }
        [generator prepare];
        [generator impactOccurred];
    };
    if ([NSThread isMainThread]) {
        playBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), playBlock);
    }
}

NSDictionary *DateLyricsCurrentRenderablePayload(void) {
    return gDateLyricsCurrentPayload;
}

UIColor *DateLyricsBaseTextColorForLabel(_UIAnimatingLabel *label) {
    // _UIAnimatingLabel can adopt the first foreground colour from an
    // attributed string as its textColor. A fully-dim incoming lyric would
    // therefore poison the base colour for every later syllable on that line.
    // Always derive filled/dimmed colours from the stock colour captured before
    // DateLyrics first took ownership of the label.
    UIColor *textColor = objc_getAssociatedObject(label, kDateLyricsOriginalTextColorKey);
    if (![textColor isKindOfClass:UIColor.class]) textColor = label.textColor;
    if (![textColor isKindOfClass:UIColor.class]) textColor = UIColor.whiteColor;
    if ([textColor respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        textColor = [textColor resolvedColorWithTraitCollection:label.traitCollection];
    }
    return textColor;
}

void DateLyricsApplyLabelContent(_UIAnimatingLabel *label, NSString *displayText, NSAttributedString *attrDisplayText) {
    if (![label isKindOfClass:UILabel.class]) return;
    BOOL wasApplying = [objc_getAssociatedObject(label, kDateLyricsApplyingLyricContentKey) boolValue];
    objc_setAssociatedObject(label, kDateLyricsApplyingLyricContentKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (attrDisplayText) {
        label.attributedText = attrDisplayText;
    } else {
        UIColor *textColor = DateLyricsBaseTextColorForLabel(label);
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:displayText ?: @""];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        [cleanStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, cleanStr.length)];
        label.attributedText = cleanStr;
    }
    objc_setAssociatedObject(label, kDateLyricsApplyingLyricContentKey, @(wasApplying), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [label setNeedsDisplay];
    [label setNeedsLayout];
}

// Prefer the font's real italic face; fonts without one get a synthetic ~12° slant.
static UIFont *DateLyricsItalicFont(UIFont *font) {
    if (![font isKindOfClass:UIFont.class]) return font;
    static UIFont *lastSourceFont = nil;
    static UIFont *lastItalicFont = nil;
    if (lastSourceFont && [lastSourceFont isEqual:font]) return lastItalicFont;

    UIFontDescriptor *descriptor = font.fontDescriptor;
    UIFontDescriptorSymbolicTraits traits = descriptor.symbolicTraits;
    UIFont *italicFont = nil;
    if (traits & UIFontDescriptorTraitItalic) {
        italicFont = font;
    } else {
        UIFontDescriptor *italicDescriptor = [descriptor fontDescriptorWithSymbolicTraits:traits | UIFontDescriptorTraitItalic];
        if (italicDescriptor) {
            UIFont *candidate = [UIFont fontWithDescriptor:italicDescriptor size:font.pointSize];
            if (candidate.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) italicFont = candidate;
        }
        if (!italicFont) {
            CGAffineTransform slant = CGAffineTransformMake(1.0, 0.0, tan(12.0 * M_PI / 180.0), 1.0, 0.0, 0.0);
            italicFont = [UIFont fontWithDescriptor:[descriptor fontDescriptorWithMatrix:slant] size:font.pointSize] ?: font;
        }
    }

    lastSourceFont = font;
    lastItalicFont = italicFont;
    return italicFont;
}

UIFont *DateLyricsConfiguredFontForLabel(_UIAnimatingLabel *label) {
    UIFont *originalFont = objc_getAssociatedObject(label, kDateLyricsOriginalFontKey);
    UIFont *baseFont = originalFont ?: label.font ?: [UIFont systemFontOfSize:34.0 weight:UIFontWeightSemibold];
    UIFont *font = baseFont;
    if (gDateLyricsUseCustomFont && gDateLyricsCustomFontName.length > 0) {
        font = [UIFont fontWithName:gDateLyricsCustomFontName size:baseFont.pointSize] ?: baseFont;
    }
    return gDateLyricsItalicLyrics ? DateLyricsItalicFont(font) : font;
}

CGFloat DateLyricsMeasuredLineWidth(NSString *text, UIFont *font) {
    if (![text isKindOfClass:NSString.class] || text.length == 0 || ![font isKindOfClass:UIFont.class]) return 0.0;
    NSString *measureText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (measureText.length == 0) return 0.0;

    CGRect rect = [measureText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                         attributes:@{ NSFontAttributeName: font }
                                            context:nil];
    return ceil(CGRectGetWidth(rect));
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
CGFloat DateLyricsSplitAvailableWidth(UILabel *label) {
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

NSDictionary *DateLyricsSplitPayloadForLabel(NSDictionary *payload, UILabel *label, UIFont *baseFont) {
    if (!gDateLyricsSplitLongLines) return nil;
    // Artificial segments follow syllable focus. A line-synced-only score has
    // no word focus to choose the active segment, so keep it as one line and
    // let UILabel scale down to the configured minimum, then truncate its tail.
    if (![payload[@"wordTimed"] boolValue]) return nil;

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
    NSInteger trackId = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    BOOL planMatches = plan
        && [plan.text isEqualToString:text]
        && [plan.fontKey isEqualToString:fontKey]
        && plan.trackId == trackId
        && fabs(plan.width - maxWidth) < 0.5
        && (plan.lineId == lineId || [plan.lineId isEqual:lineId]);

    if (!planMatches) {
        plan = [DateLyricsSplitPlan new];
        plan.text = text;
        plan.lineId = lineId;
        plan.trackId = trackId;
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

    // Monotonic while playback advances. Word timing has gaps — at the start of
    // a line, in instrumental pauses, and after the last word there is no active
    // range at all. The old code fell back to segment 0 in those moments, so a
    // long line could advance to segment 2, snap back to segment 0, then advance
    // again. A real backward seek is different: allow its focus range to move
    // the segment back so the reverse transition is visible. If the seek lands
    // before the first word, segment 0 is the only unambiguous choice.
    if (gDateLyricsLastResolutionWasBackwardSeek &&
        focusRange.location == NSNotFound && focusBackgroundRange.location == NSNotFound) {
        targetIndex = 0;
    } else if (!gDateLyricsLastResolutionWasBackwardSeek && targetIndex < plan.lastIndex) {
        targetIndex = plan.lastIndex;
    }
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

    // A sweep syllable outside the visible segment leaves the segment static.
    for (NSString *prefix in @[@"sweep", @"bgSweep"]) {
        NSRange sweepRange = DateLyricsRangeFromPayload(payload, prefix, text.length);
        NSRange intersection = sweepRange.location != NSNotFound
            ? NSIntersectionRange(targetRange, sweepRange) : NSMakeRange(NSNotFound, 0);
        DateLyricsSetRangeFields(splitPayload, prefix,
            intersection.length > 0 ? NSMakeRange(intersection.location - targetRange.location, intersection.length)
                                    : NSMakeRange(NSNotFound, 0));
    }

    return splitPayload;
}

static NSUInteger DateLyricsBeginLabelTransition(_UIAnimatingLabel *label) {
    NSUInteger generation = [objc_getAssociatedObject(label, kDateLyricsTransitionGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(label, kDateLyricsTransitionGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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
        UIView *outgoingSnapshot = objc_getAssociatedObject(strongLabel, kDateLyricsOutgoingSnapshotKey);
        [outgoingSnapshot removeFromSuperview];
        objc_setAssociatedObject(strongLabel, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [strongLabel.layer removeAnimationForKey:@"DateLyricsLineTransition"];
        strongLabel.alpha = 1.0;
        strongLabel.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(strongLabel, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        // Release the pinned geometry; normal layout resumes on the next pass.
        objc_setAssociatedObject(strongLabel, kDateLyricsFrozenFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [strongLabel setNeedsLayout];
        if ([strongLabel respondsToSelector:@selector(_amlApplyCurrentLyric)]) {
            [strongLabel _amlApplyCurrentLyric];
        }
    });
}

// lineId is either a numeric line-start time or "line-start#split-segment".
// Compare both pieces so scrubbing backwards within a split line also reverses
// the visual direction.
NSComparisonResult DateLyricsCompareLineIdentity(id leftIdentity, id rightIdentity) {
    NSString *left = [leftIdentity description] ?: @"";
    NSString *right = [rightIdentity description] ?: @"";
    NSArray<NSString *> *leftParts = [left componentsSeparatedByString:@"#"];
    NSArray<NSString *> *rightParts = [right componentsSeparatedByString:@"#"];
    double leftTime = leftParts.firstObject.doubleValue;
    double rightTime = rightParts.firstObject.doubleValue;
    if (fabs(leftTime - rightTime) > 0.0001) {
        return leftTime < rightTime ? NSOrderedAscending : NSOrderedDescending;
    }
    NSInteger leftSegment = leftParts.count > 1 ? leftParts[1].integerValue : 0;
    NSInteger rightSegment = rightParts.count > 1 ? rightParts[1].integerValue : 0;
    if (leftSegment == rightSegment) return NSOrderedSame;
    return leftSegment < rightSegment ? NSOrderedAscending : NSOrderedDescending;
}

void DateLyricsAnimateLabelTransition(_UIAnimatingLabel *label, NSString *previousDisplayText, NSString *displayText, NSAttributedString *attrDisplayText, BOOL reverseDirection) {
    if (![label isKindOfClass:UILabel.class]) {
        DateLyricsStopMarquee(label);
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
        return;
    }

    NSTimeInterval duration = MAX(0.0, gDateLyricsTransitionDuration);
    if (!gDateLyricsTransitionsEnabled || duration <= 0.0 || previousDisplayText.length == 0) {
        DateLyricsStopMarquee(label);
        [label.layer removeAllAnimations];
        label.alpha = 1.0;
        label.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
        return;
    }

    UIView *oldSnapshot = objc_getAssociatedObject(label, kDateLyricsOutgoingSnapshotKey);
    [oldSnapshot removeFromSuperview];
    UIView *outgoingSnapshot = DateLyricsDetachMarquee(label);
    NSUInteger generation = DateLyricsBeginLabelTransition(label);

    if (!outgoingSnapshot) {
        outgoingSnapshot = [label snapshotViewAfterScreenUpdates:NO];
    }
    if (outgoingSnapshot && label.superview) {
        outgoingSnapshot.frame = label.frame;
        outgoingSnapshot.userInteractionEnabled = NO;
        [label.superview insertSubview:outgoingSnapshot belowSubview:label];
        objc_setAssociatedObject(label, kDateLyricsOutgoingSnapshotKey, outgoingSnapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // The outgoing visual is frozen above; the actual label is now free to
    // receive syllable attributed-text updates throughout the animation.
    [UIView performWithoutAnimation:^{
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText);
        [label layoutIfNeeded];
    }];

    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState |
                                     UIViewAnimationOptionAllowUserInteraction |
                                     UIViewAnimationOptionCurveEaseInOut;

    switch (gDateLyricsTransitionStyle) {
        case DateLyricsTransitionStyleFade: {
            label.alpha = 0.0;
            [UIView animateKeyframesWithDuration:duration delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
                [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.45 animations:^{
                    outgoingSnapshot.alpha = 0.0;
                }];
                [UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{
                    label.alpha = 1.0;
                }];
            } completion:nil];
            break;
        }
        case DateLyricsTransitionStyleSlideUp:
        case DateLyricsTransitionStyleSlideDown:
        case DateLyricsTransitionStylePush: {
            CGFloat dx = 0.0;
            CGFloat dy = 0.0;
            if (gDateLyricsTransitionStyle == DateLyricsTransitionStyleSlideUp) {
                dy = reverseDirection ? -CGRectGetHeight(label.bounds) : CGRectGetHeight(label.bounds);
            } else if (gDateLyricsTransitionStyle == DateLyricsTransitionStylePush) {
                dx = reverseDirection ? -CGRectGetWidth(label.bounds) : CGRectGetWidth(label.bounds);
            } else {
                dy = reverseDirection ? CGRectGetHeight(label.bounds) : -CGRectGetHeight(label.bounds);
            }
            label.transform = CGAffineTransformMakeTranslation(dx, dy);
            label.alpha = 0.0;
            [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
                label.transform = CGAffineTransformIdentity;
                label.alpha = 1.0;
                outgoingSnapshot.transform = CGAffineTransformMakeTranslation(-dx, -dy);
                outgoingSnapshot.alpha = 0.0;
            } completion:nil];
            break;
        }
        case DateLyricsTransitionStylePop: {
            CGFloat incomingScale = reverseDirection ? 1.1 : 0.9;
            CGFloat outgoingScale = reverseDirection ? 0.9 : 1.1;
            label.transform = CGAffineTransformMakeScale(incomingScale, incomingScale);
            label.alpha = 0.0;
            [UIView animateKeyframesWithDuration:duration delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
                [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.42 animations:^{
                    outgoingSnapshot.transform = CGAffineTransformMakeScale(outgoingScale, outgoingScale);
                    outgoingSnapshot.alpha = 0.0;
                }];
                [UIView addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5 animations:^{
                    label.transform = CGAffineTransformIdentity;
                    label.alpha = 1.0;
                }];
            } completion:nil];
            break;
        }
        default: {
            break;
        }
    }
    DateLyricsFinishLabelTransitionAfterDelay(label, generation, duration);
}

NSString *DateLyricsHighlightSignature(NSDictionary *payload) {
    if (![payload isKindOfClass:NSDictionary.class]) return nil;
    NSNumber *loc = payload[@"loc"];
    NSNumber *len = payload[@"len"];
    NSNumber *bgLoc = payload[@"bgLoc"];
    NSNumber *bgLen = payload[@"bgLen"];
    if (!loc && !bgLoc) return nil;
    return [NSString stringWithFormat:@"%@:%@:%@:%@", loc ?: @"-", len ?: @"-", bgLoc ?: @"-", bgLen ?: @"-"];
}

UIView *DateLyricsDetachMarquee(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return nil;

    UIView *container = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    UILabel *contentLabel = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    if (contentLabel) {
        CALayer *presentation = contentLabel.layer.presentationLayer;
        if (presentation) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            contentLabel.layer.transform = presentation.transform;
            [CATransaction commit];
        }
        [contentLabel.layer removeAllAnimations];
    }

    objc_setAssociatedObject(label, kDateLyricsMarqueeContainerKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsMarqueeContentLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsMarqueeLineIdKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsMarqueeActiveKey, nil, OBJC_ASSOCIATION_ASSIGN);
    label.alpha = 1.0;
    return container;
}

void DateLyricsStopMarquee(_UIAnimatingLabel *label) {
    UIView *container = DateLyricsDetachMarquee(label);
    [container removeFromSuperview];
}

void DateLyricsRefreshMarqueeContent(_UIAnimatingLabel *label) {
    UILabel *contentLabel = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    if (![contentLabel isKindOfClass:UILabel.class]) return;

    contentLabel.font = label.font;
    contentLabel.textColor = label.textColor;
    if (label.attributedText) {
        contentLabel.attributedText = label.attributedText;
    } else {
        contentLabel.text = label.text;
    }
}

// Render the full line in an isolated clipped overlay. The stock label remains
// available for vertical/scale transitions, so marquee and line animations never
// compete for the same transform.
BOOL DateLyricsStartMarquee(_UIAnimatingLabel *label, CGFloat overflow, NSTimeInterval remainingLineTime) {
    if (![label isKindOfClass:UILabel.class] || !label.superview) return NO;
    if (overflow <= 0.5 || remainingLineTime <= 0.0) return NO;

    // _amlApplyCurrentLyric only calls this after the incoming line transition
    // has completed. End before the next line's 50 ms early transition trigger;
    // if too little time remains, leave the line clipped instead of overlapping.
    NSTimeInterval animationDuration = remainingLineTime -
        (gDateLyricsTransitionsEnabled ? kDateLyricsLineTransitionLead : 0.0);
    if (animationDuration < 0.2) return NO;

    DateLyricsStopMarquee(label);

    CGRect viewportFrame = label.frame;
    CGFloat viewportWidth = CGRectGetWidth(viewportFrame);
    if (viewportWidth <= 1.0) return NO;

    UIView *container = [[UIView alloc] initWithFrame:viewportFrame];
    container.userInteractionEnabled = NO;
    container.clipsToBounds = YES;
    container.backgroundColor = UIColor.clearColor;

    UILabel *contentLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0,
                                                                       viewportWidth + overflow,
                                                                       CGRectGetHeight(container.bounds))];
    contentLabel.numberOfLines = 1;
    contentLabel.adjustsFontSizeToFitWidth = NO;
    contentLabel.lineBreakMode = NSLineBreakByClipping;
    contentLabel.textAlignment = NSTextAlignmentLeft;
    contentLabel.font = label.font;
    contentLabel.textColor = label.textColor;
    contentLabel.backgroundColor = UIColor.clearColor;
    contentLabel.attributedText = label.attributedText;
    if (!contentLabel.attributedText) contentLabel.text = label.text;
    [container addSubview:contentLabel];

    [label.superview insertSubview:container aboveSubview:label];
    label.alpha = 0.0;

    NSTimeInterval holdAtStart = MIN(gDateLyricsMarqueeHoldDuration, animationDuration * 0.25);
    CGFloat holdFraction = MIN(MAX((CGFloat)(holdAtStart / animationDuration), 0.0f), 0.8f);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    contentLabel.layer.transform = CATransform3DMakeTranslation(-overflow, 0.0, 0.0);
    [CATransaction commit];

    CAKeyframeAnimation *scroll = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    scroll.values = @[@0.0, @0.0, @(-overflow)];
    scroll.keyTimes = @[@0.0, @(holdFraction), @1.0];
    scroll.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
    ];
    scroll.duration = animationDuration;
    [contentLabel.layer addAnimation:scroll forKey:@"DateLyricsMarquee"];

    objc_setAssociatedObject(label, kDateLyricsMarqueeContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeContentLabelKey, contentLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}


static DateLyricsSweepVoice *DateLyricsMakeSweepVoice(CALayer *root) {
    DateLyricsSweepVoice *voice = [DateLyricsSweepVoice new];
    voice.clip = [CALayer layer];
    voice.clip.masksToBounds = YES;
    voice.bar = [CAGradientLayer layer];
    voice.bar.startPoint = CGPointMake(0.0, 0.5);
    voice.bar.endPoint = CGPointMake(1.0, 0.5);
    voice.bar.colors = @[(id)UIColor.whiteColor.CGColor,
                         (id)UIColor.whiteColor.CGColor,
                         (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    voice.bar.anchorPoint = CGPointMake(1.0, 0.5);
    voice.bar.contentsScale = UIScreen.mainScreen.scale;
    [voice.clip addSublayer:voice.bar];
    [root addSublayer:voice.clip];
    return voice;
}

void DateLyricsRemoveSweepMask(UILabel *label) {
    DateLyricsSweepMask *mask = objc_getAssociatedObject(label, kDateLyricsSweepMaskKey);
    if (!mask) return;
    if (label.layer.mask == mask.root) label.layer.mask = nil;
    objc_setAssociatedObject(label, kDateLyricsSweepMaskKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

// Call inside a CATransaction with actions disabled.
static void DateLyricsApplySweepVoiceTiming(DateLyricsSweepVoice *voice) {
    CAGradientLayer *bar = voice.bar;
    [bar removeAnimationForKey:@"DateLyricsSweep"];
    voice.clip.hidden = !voice.active;
    if (!voice.active) return;

    // With the screen off (Always-On) nothing animates: the syllable is held
    // fully lit, which is exactly the classic word-by-word look.
    NSTimeInterval duration = voice.end - voice.begin;
    NSTimeInterval songTime = 0.0;
    float rate = 0.0f;
    BOOL timed = duration > 0.0 && !gDateLyricsScreenOff && DateLyricsSweepSongTime(&songTime, &rate);
    CGFloat progress = timed ? (CGFloat)MIN(MAX((songTime - voice.begin) / duration, 0.0), 1.0) : 1.0;
    CGFloat y = bar.position.y;
    CGFloat currentX = voice.fromX + (voice.toX - voice.fromX) * progress;
    if (!timed || rate <= 0.0f || progress >= 1.0) {
        bar.position = CGPointMake(currentX, y);
        return;
    }

    // The model holds the end state; the animation covers what is left of it.
    bar.position = CGPointMake(voice.toX, y);
    CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
    sweep.fromValue = @(currentX);
    sweep.toValue = @(voice.toX);
    sweep.duration = (voice.end - MAX(songTime, voice.begin)) / rate;
    NSTimeInterval delay = MAX(0.0, voice.begin - songTime) / rate;
    if (delay > 0.0) {
        sweep.beginTime = CACurrentMediaTime() + delay;
        sweep.fillMode = kCAFillModeBackwards;
    }
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    // The sweep runs for as long as lyrics are sung; at 30 fps it still reads
    // as continuous, and ProMotion displays are not held at 120 Hz for it.
    sweep.preferredFrameRateRange = CAFrameRateRangeMake(30.0, 30.0, 30.0);
    [bar addAnimation:sweep forKey:@"DateLyricsSweep"];
}

void DateLyricsLayoutSweepMask(UILabel *label, NSDictionary *payload, NSString *text) {
    CGRect bounds = label.bounds;
    UIFont *font = label.font;
    NSUInteger length = text.length;
    if (length == 0 || ![font isKindOfClass:UIFont.class]) return;

    DateLyricsSweepMask *mask = objc_getAssociatedObject(label, kDateLyricsSweepMaskKey);
    if (!mask) {
        mask = [DateLyricsSweepMask new];
        mask.root = [CALayer layer];
        mask.dim = [CALayer layer];
        [mask.root addSublayer:mask.dim];
        mask.foreground = DateLyricsMakeSweepVoice(mask.root);
        mask.background = DateLyricsMakeSweepVoice(mask.root);
        objc_setAssociatedObject(label, kDateLyricsSweepMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    mask.payload = payload;
    mask.text = text;
    mask.boundsSize = bounds.size;
    // Not laid out yet: the resize that follows lays the mask out.
    if (CGRectGetWidth(bounds) <= 1.0 || CGRectGetHeight(bounds) <= 1.0) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // Reproduce UILabel's single-line placement: advance widths, shrunk when
    // the label scales text to fit, then aligned within the bounds.
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    CGFloat (^advance)(NSUInteger) = ^CGFloat(NSUInteger index) {
        if (index == 0) return 0.0;
        return [[text substringToIndex:MIN(index, length)] sizeWithAttributes:attributes].width;
    };
    CGFloat boundsWidth = CGRectGetWidth(bounds);
    CGFloat textWidth = advance(length);
    CGFloat scale = 1.0;
    if (label.adjustsFontSizeToFitWidth && textWidth > boundsWidth) {
        scale = MAX(label.minimumScaleFactor, boundsWidth / textWidth);
    }
    CGFloat drawnWidth = textWidth * scale;
    CGFloat originX = CGRectGetMinX(bounds);
    if (drawnWidth < boundsWidth) {
        if (label.textAlignment == NSTextAlignmentCenter) originX += (boundsWidth - drawnWidth) / 2.0;
        else if (label.textAlignment == NSTextAlignmentRight) originX += boundsWidth - drawnWidth;
    }
    CGFloat feather = MAX(6.0, round(font.pointSize * scale * 0.6));

    CGRect rootFrame = CGRectInset(bounds, -2.0 * feather, -CGRectGetHeight(bounds));
    mask.root.frame = rootFrame;
    mask.dim.frame = mask.root.bounds;
    CGFloat rootWidth = CGRectGetWidth(rootFrame);
    CGFloat rootHeight = CGRectGetHeight(rootFrame);

    CGFloat (^xAt)(NSUInteger) = ^CGFloat(NSUInteger index) {
        return originX + advance(index) * scale - CGRectGetMinX(rootFrame);
    };
    // How far a lit run's clip may extend past its text: across adjacent
    // whitespace (so glyph overhang is kept) but never into a neighbouring
    // word or syllable, which must stay dim until it is sung.
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceCharacterSet;
    CGFloat (^slackAfter)(NSUInteger) = ^CGFloat(NSUInteger index) {
        NSUInteger next = index;
        while (next < length && [whitespace characterIsMember:[text characterAtIndex:next]]) next++;
        if (next >= length) return feather;
        return MIN(feather, (advance(next) - advance(index)) * scale);
    };
    CGFloat (^slackBefore)(NSUInteger) = ^CGFloat(NSUInteger index) {
        NSUInteger previous = index;
        while (previous > 0 && [whitespace characterIsMember:[text characterAtIndex:previous - 1]]) previous--;
        if (previous == 0) return feather;
        return MIN(feather, (advance(index) - advance(previous)) * scale);
    };

    BOOL finished = [payload[@"finished"] boolValue];
    BOOL started = payload[@"started"] ? [payload[@"started"] boolValue] : YES;
    mask.dim.backgroundColor = [UIColor colorWithWhite:1.0 alpha:finished ? 1.0 : kDateLyricsDimmedAlpha].CGColor;

    void (^layoutVoice)(DateLyricsSweepVoice *, NSString *, NSString *) =
        ^(DateLyricsSweepVoice *voice, NSString *litPrefix, NSString *sweepPrefix) {
        NSRange lit = DateLyricsRangeFromPayload(payload, litPrefix, length);
        voice.active = started && !finished && lit.location != NSNotFound;
        if (!voice.active) return;

        NSRange sweep = DateLyricsRangeFromPayload(payload, sweepPrefix, length);
        NSNumber *begin = payload[[sweepPrefix stringByAppendingString:@"Begin"]];
        NSNumber *end = payload[[sweepPrefix stringByAppendingString:@"End"]];
        // Only a syllable at the leading edge of the lit run is animated;
        // anything else is drawn as the lit run alone.
        BOOL animated = sweep.location != NSNotFound && sweep.location >= lit.location &&
            NSMaxRange(sweep) == NSMaxRange(lit) &&
            [begin isKindOfClass:NSNumber.class] && [end isKindOfClass:NSNumber.class];

        NSUInteger litEnd = NSMaxRange(lit);
        CGFloat clipLeft = xAt(lit.location) - slackBefore(lit.location);
        CGFloat clipRight = xAt(litEnd) + slackAfter(litEnd);
        voice.clip.frame = CGRectMake(clipLeft, 0.0, MAX(0.0, clipRight - clipLeft), rootHeight);
        CGFloat barLength = rootWidth + 2.0 * feather;
        voice.bar.bounds = CGRectMake(0.0, 0.0, barLength, rootHeight);
        voice.bar.locations = @[@0.0, @((barLength - feather) / barLength), @1.0];
        voice.bar.position = CGPointMake(voice.bar.position.x, rootHeight / 2.0);

        // The soft edge enters at the syllable's first glyph and finishes a
        // feather past its last, where the clip has already cut it off.
        voice.toX = xAt(litEnd) + feather - clipLeft;
        if (animated) {
            voice.fromX = xAt(sweep.location) - clipLeft;
            voice.begin = begin.doubleValue;
            voice.end = end.doubleValue;
        } else {
            voice.fromX = voice.toX;
            voice.begin = 0.0;
            voice.end = 0.0;
        }
    };
    layoutVoice(mask.foreground, @"", @"sweep");
    layoutVoice(mask.background, @"bg", @"bgSweep");
    DateLyricsApplySweepVoiceTiming(mask.foreground);
    DateLyricsApplySweepVoiceTiming(mask.background);

    if (label.layer.mask != mask.root) label.layer.mask = mask.root;
    [CATransaction commit];
}

static void DateLyricsSweepResyncLabel(UILabel *label) {
    DateLyricsSweepMask *mask = objc_getAssociatedObject(label, kDateLyricsSweepMaskKey);
    if (!mask) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DateLyricsApplySweepVoiceTiming(mask.foreground);
    DateLyricsApplySweepVoiceTiming(mask.background);
    [CATransaction commit];
}

void DateLyricsSweepResyncAllLabels(void) {
    for (CSProminentSubtitleDateView *dateView in gDateLyricsDateViews) {
        if (![dateView isKindOfClass:UIView.class]) continue;
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(dateView);
        if (label) DateLyricsSweepResyncLabel(label);
    }
}

// The mask is laid out in the label's own coordinates, so any later resize
// (a transition releasing its pinned frame, a date view relayout) re-runs it.
void DateLyricsSweepRelayoutIfResized(UILabel *label) {
    DateLyricsSweepMask *mask = objc_getAssociatedObject(label, kDateLyricsSweepMaskKey);
    if (!mask || CGSizeEqualToSize(mask.boundsSize, label.bounds.size)) return;
    DateLyricsLayoutSweepMask(label, mask.payload, mask.text);
}
