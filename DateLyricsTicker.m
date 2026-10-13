// SpringBoard clock: sweep clock, pause timers and the line ticker.

#import "DateLyricsInternal.h"

// Playback clock the smooth sweep animations are timed against. It follows the
// ticker's resolved position but ignores the few-millisecond corrections every
// periodic anchor brings, so a running sweep is only restarted for a pause,
// resume, seek, or real drift.
BOOL gDateLyricsSweepClockValid = NO;
static NSTimeInterval gDateLyricsSweepClockElapsed = 0.0;
static NSTimeInterval gDateLyricsSweepClockHost = 0.0;
static float gDateLyricsSweepClockRate = 0.0f;

static BOOL DateLyricsSyncSweepClock(NSTimeInterval elapsed, NSTimeInterval host, float rate) {
    if (gDateLyricsSweepClockValid && fabsf(rate - gDateLyricsSweepClockRate) < 0.001f) {
        NSTimeInterval predicted = gDateLyricsSweepClockElapsed + (host - gDateLyricsSweepClockHost) * gDateLyricsSweepClockRate;
        NSTimeInterval drift = elapsed - predicted;
        // Pulling a running sweep backwards is more visible than letting it
        // lead slightly, so tolerate more drift in that direction.
        if (drift > -0.15 && drift < 0.05) return NO;
    }
    gDateLyricsSweepClockValid = YES;
    gDateLyricsSweepClockElapsed = elapsed;
    gDateLyricsSweepClockHost = host;
    gDateLyricsSweepClockRate = rate;
    return YES;
}

BOOL DateLyricsSweepSongTime(NSTimeInterval *songTimeOut, float *rateOut) {
    if (!gDateLyricsSweepClockValid) return NO;
    if (songTimeOut) *songTimeOut = gDateLyricsSweepClockElapsed + (DateLyricsMonotonicTime() - gDateLyricsSweepClockHost) * gDateLyricsSweepClockRate;
    if (rateOut) *rateOut = gDateLyricsSweepClockRate;
    return YES;
}

// When the current pause began, on the monotonic clock. A paused anchor is
// re-resolved every time the lock screen reappears, and Music keeps republishing
// the same paused position; measuring the hide delay from here stops either one
// from bringing back a lyric whose pause already timed out (for example after
// another app has taken over playback).
static NSTimeInterval gDateLyricsPausedSince = -1.0;

void DateLyricsNotePauseState(NSDictionary *previousAnchor, NSDictionary *anchor) {
    if ([anchor[@"rate"] floatValue] > 0.0f) {
        gDateLyricsPausedSince = -1.0;
        return;
    }
    // A paused scrub or a different track starts a fresh pause so the new
    // position is shown for the full timeout.
    BOOL samePause = gDateLyricsPausedSince >= 0.0 && previousAnchor &&
        [previousAnchor[@"rate"] floatValue] <= 0.0f &&
        [previousAnchor[@"trackId"] isEqual:anchor[@"trackId"]] &&
        fabs([previousAnchor[@"elapsed"] doubleValue] - [anchor[@"elapsed"] doubleValue]) <= 0.05;
    if (!samePause) gDateLyricsPausedSince = DateLyricsMonotonicTime();
}

static NSTimeInterval DateLyricsPauseHideRemaining(void) {
    NSTimeInterval timeout = MAX(0.0, gDateLyricsPauseTimeout);
    if (gDateLyricsPausedSince < 0.0) return timeout;
    return timeout - (DateLyricsMonotonicTime() - gDateLyricsPausedSince);
}

void DateLyricsCancelPauseHideTimer(void) {
    if (gDateLyricsPauseHideTimer) {
        dispatch_source_cancel(gDateLyricsPauseHideTimer);
        gDateLyricsPauseHideTimer = nil;
    }
}

void DateLyricsSchedulePauseHideTimer(void) {
    NSDictionary *payload = gDateLyricsCurrentPayload;
    if (![payload[@"text"] isKindOfClass:NSString.class] || [payload[@"text"] length] == 0) {
        DateLyricsCancelPauseHideTimer();
        return;
    }

    // Repeated paused anchors are expected; do not reset the delay every time
    // MediaRemote refreshes the same zero-rate position.
    if (gDateLyricsPauseHideTimer) return;

    NSTimeInterval delay = DateLyricsPauseHideRemaining();
    if (delay <= 0.0) {
        gDateLyricsCurrentPayload = nil;
        gDateLyricsRenderGeneration++;
        DateLyricsApplyCurrentLineToAllCoverSheets();
        return;
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    gDateLyricsPauseHideTimer = timer;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        if (gDateLyricsPauseHideTimer != timer) return;
        gDateLyricsPauseHideTimer = nil;
        dispatch_source_cancel(timer);

        if ([gDateLyricsLocalAnchor[@"rate"] floatValue] <= 0.0f &&
            [gDateLyricsCurrentPayload[@"text"] isKindOfClass:NSString.class]) {
            gDateLyricsCurrentPayload = nil;
            gDateLyricsRenderGeneration++;
            DateLyricsApplyCurrentLineToAllCoverSheets();
        }
    });
    dispatch_resume(timer);
}

static DateLyricsResolverOptions DateLyricsCurrentResolverOptions(void) {
    return (DateLyricsResolverOptions){
        .showAdlibs = gDateLyricsShowAdlibs,
        .smoothSweep = gDateLyricsSmoothSweep,
        .showInterlude = gDateLyricsInterludeIndicator,
        .interludeStyle = gDateLyricsInterludeStyle,
    };
}

void DateLyricsScheduleTicker(void) {
    if (gDateLyricsTicker) {
        dispatch_source_cancel(gDateLyricsTicker);
        gDateLyricsTicker = nil;
    }
    
    if (!gDateLyricsEnabled || !gDateLyricsCurrentScore || !gDateLyricsLocalAnchor) {
        DateLyricsCancelPauseHideTimer();
        return;
    }
    
    float rate = MAX(0.0f, [gDateLyricsLocalAnchor[@"rate"] floatValue]);

    // Nobody can see the label: the cover sheet is dismissed or the screen is
    // off. Stop waking SpringBoard for every syllable; the cover sheet hooks
    // call back in here on return and resolve straight from the anchor. A
    // pause still resolves once so the pause-hide timer can clear the lyric.
    if (rate > 0.0f && !DateLyricsLockScreenLive()) {
        DateLyricsCancelPauseHideTimer();
        return;
    }
    
    NSTimeInterval anchorElapsed = [gDateLyricsLocalAnchor[@"elapsed"] doubleValue];
    NSTimeInterval atHostTime = [gDateLyricsLocalAnchor[@"atHostTime"] doubleValue];
    NSTimeInterval nowHost = DateLyricsMonotonicTime();
    
    // A zero-rate anchor is a pause. Resolve it once so the lock screen cannot
    // keep displaying a payload selected by the old, running anchor, then stop.
    NSTimeInterval currentElapsed = anchorElapsed + ((nowHost - atHostTime) * rate);
    NSTimeInterval anchorAge = MAX(0.0, nowHost - atHostTime);
    if (rate > 0.0f && anchorAge >= kDateLyricsAnchorStaleTimeout) {
        DateLyricsDebugLog(@"[Ticker] expiring stale playback anchor after %.1fs", anchorAge);
        gDateLyricsLocalAnchor = nil;
        gDateLyricsCurrentPayload = nil;
        gDateLyricsResolverCursor = -1;
        DateLyricsClearEarlyLinePreview();
        gDateLyricsRenderGeneration++;
        DateLyricsCancelPauseHideTimer();
        DateLyricsApplyCurrentLineToAllCoverSheets();
        return;
    }

    // The direct-anchor replacement for the old Music-side monotonic clamp.
    // Around a line boundary, extrapolation can land just past the next line and
    // an authoritative MediaRemote update can then land just before it. Resolving
    // both produces next line -> previous line -> next line in ~100 ms. Ignore
    // only that small backwards correction; a larger backwards move is a real
    // seek and must be reflected immediately.
    NSInteger trackId = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    BOOL isExplicitSeek = [gDateLyricsLocalAnchor[@"seek"] boolValue];
    BOOL movedBackwardBySeek = NO;
    BOOL trackChanged = trackId != gDateLyricsLastResolvedTrackId;
    if (trackChanged) {
        gDateLyricsLastResolvedTrackId = trackId;
        gDateLyricsLastResolvedElapsed = -1.0;
        gDateLyricsRenderGeneration++;
    }
    BOOL jitterClamped = NO;
    if (gDateLyricsLastResolvedElapsed >= 0.0) {
        NSTimeInterval backwards = gDateLyricsLastResolvedElapsed - currentElapsed;
        movedBackwardBySeek = isExplicitSeek && backwards > 0.001;
        if (backwards > 0.0 && backwards < kDateLyricsJitterBackstepLimit && !isExplicitSeek) {
            DateLyricsDebugLog(@"[Ticker] clamped %.3fs backwards jitter (%.3f -> %.3f)",
                               backwards, gDateLyricsLastResolvedElapsed, currentElapsed);
            currentElapsed = gDateLyricsLastResolvedElapsed;
            jitterClamped = YES;
        }
    }
    gDateLyricsLastResolvedElapsed = currentElapsed;
    gDateLyricsLastResolutionWasBackwardSeek = movedBackwardBySeek;
    // A clamped position is a held value, not a clock reading.
    BOOL sweepClockChanged = gDateLyricsSmoothSweep && !jitterClamped &&
        DateLyricsSyncSweepClock(currentElapsed, nowHost, rate);

    // A seek, pause, track swap, or score replacement invalidates a pending
    // early line.  In particular, never carry an early forward payload across
    // a backward scrub: the normal resolver must be allowed to produce the
    // reverse transition immediately.
    if (trackChanged || isExplicitSeek || movedBackwardBySeek || rate <= 0.0f) {
        DateLyricsClearEarlyLinePreview();
    }

    NSTimeInterval nextTrigger = -1.0;
    NSTimeInterval nextLineTrigger = -1.0;
    NSDictionary *payload = nil;
    BOOL usingEarlyLine = NO;

    // Hold the previewed line until its real timestamp.  Without this small
    // state machine, the next scheduled word tick would resolve against the
    // actual clock and briefly snap back to the previous line during the
    // 50 ms lead window.
    if (gDateLyricsEarlyLinePayload && gDateLyricsEarlyLineTrackId == trackId &&
        gDateLyricsEarlyLineBegin > currentElapsed && rate > 0.0f && !isExplicitSeek) {
        payload = gDateLyricsEarlyLinePayload;
        nextTrigger = gDateLyricsEarlyLineNextTrigger;
        usingEarlyLine = YES;
    } else {
        if (gDateLyricsEarlyLinePayload && currentElapsed >= gDateLyricsEarlyLineBegin) {
            DateLyricsClearEarlyLinePreview();
        }

        payload = DateLyricsResolvePayload(gDateLyricsCurrentScore, currentElapsed,
                                           &gDateLyricsResolverCursor, &nextTrigger, &nextLineTrigger, DateLyricsCurrentResolverOptions());

        // Only advance a *line* early.  Syllable/word highlights continue to
        // resolve against the real elapsed time, so the 50 ms lead cannot make
        // the karaoke highlight itself run ahead of the source score.
        NSTimeInterval leadWindow = rate * kDateLyricsLineTransitionLead;
        if (gDateLyricsTransitionsEnabled && rate > 0.0f && !isExplicitSeek && !movedBackwardBySeek &&
            nextLineTrigger > currentElapsed &&
            (nextLineTrigger - currentElapsed) <= leadWindow + 0.002) {
            NSInteger previewCursor = gDateLyricsResolverCursor;
            NSTimeInterval ignoredNextLineTrigger = -1.0;
            NSDictionary *previewPayload = DateLyricsResolvePayload(gDateLyricsCurrentScore,
                                                                      nextLineTrigger + 0.001,
                                                                      &previewCursor,
                                                                      NULL,
                                                                      &ignoredNextLineTrigger,
                                                                      DateLyricsCurrentResolverOptions());
            id currentLineID = payload[@"lineId"];
            id previewLineID = previewPayload[@"lineId"];
            if (previewPayload && previewLineID && ![previewLineID isEqual:currentLineID]) {
                NSMutableDictionary *earlyPayload = [previewPayload mutableCopy];
                // Resolve the line identity at its real boundary, but keep
                // word highlighting on the real clock.  The preview therefore
                // enters as an upcoming/dim line and the first syllable is
                // applied by the normal tick at the exact timestamp.
                if ([earlyPayload[@"timed"] boolValue]) {
                    [earlyPayload removeObjectForKey:@"loc"];
                    [earlyPayload removeObjectForKey:@"len"];
                    [earlyPayload removeObjectForKey:@"bgLoc"];
                    [earlyPayload removeObjectForKey:@"bgLen"];
                    [earlyPayload removeObjectForKey:@"focusLoc"];
                    [earlyPayload removeObjectForKey:@"focusLen"];
                    [earlyPayload removeObjectForKey:@"focusBgLoc"];
                    [earlyPayload removeObjectForKey:@"focusBgLen"];
                    for (NSString *key in @[@"sweepLoc", @"sweepLen", @"sweepBegin", @"sweepEnd",
                                            @"bgSweepLoc", @"bgSweepLen", @"bgSweepBegin", @"bgSweepEnd"]) {
                        [earlyPayload removeObjectForKey:key];
                    }
                    earlyPayload[@"started"] = @NO;
                    earlyPayload[@"finished"] = @NO;
                }
                gDateLyricsEarlyLinePayload = [earlyPayload copy];
                gDateLyricsEarlyLineBegin = nextLineTrigger;
                // Always wake at the true boundary. Resolving the preview 1 ms
                // into the line can already consume a first syllable whose
                // begin time equals line.begin; scheduling its reported next
                // trigger would then skip straight to syllable two.
                gDateLyricsEarlyLineNextTrigger = nextLineTrigger;
                gDateLyricsEarlyLineTrackId = trackId;
                gDateLyricsResolverCursor = previewCursor;
                payload = gDateLyricsEarlyLinePayload;
                nextTrigger = gDateLyricsEarlyLineNextTrigger;
                usingEarlyLine = YES;
                DateLyricsDebugLog(@"[Ticker] starting line %.3f %.0fms early (actual=%.3f)",
                                   nextLineTrigger, kDateLyricsLineTransitionLead * 1000.0, currentElapsed);
            }
        }
    }

    // The pause already outlived its timeout: keep the date rather than
    // flashing the paused line for another full timeout.
    if (rate <= 0.0f && DateLyricsPauseHideRemaining() <= 0.0) {
        payload = nil;
    }

    DateLyricsDebugLog(@"[Ticker] elapsed=%.2f text='%@' range=[%@, %@] nextTrigger=%.3f nextLine=%.3f early=%d",
                       currentElapsed, payload[@"text"] ?: @"", payload[@"loc"], payload[@"len"],
                       nextTrigger, nextLineTrigger, usingEarlyLine);
    
    BOOL payloadChanged = ![gDateLyricsCurrentPayload isEqual:payload];
    if (payloadChanged || trackChanged || movedBackwardBySeek) {
        NSDictionary *previousPayload = gDateLyricsCurrentPayload;
        gDateLyricsCurrentPayload = [payload copy];
        gDateLyricsRenderGeneration++;
        
        // Haptics logic
        NSString *previousText = previousPayload[@"text"];
        NSString *nextText = payload[@"text"];
        if (previousText.length > 0 && nextText.length > 0 && ![payload[@"interlude"] boolValue]) {
            id previousLineID = previousPayload[@"lineId"];
            id nextLineID = payload[@"lineId"];
            BOOL lineChanged = previousLineID && nextLineID && ![previousLineID isEqual:nextLineID];
            if (lineChanged) {
                DateLyricsPlayHaptic(gDateLyricsHapticStyleLine);
            } else {
                NSString *previousHighlight = DateLyricsHighlightSignature(previousPayload);
                NSString *nextHighlight = DateLyricsHighlightSignature(payload);
                if (nextHighlight && ![nextHighlight isEqualToString:previousHighlight]) {
                    DateLyricsPlayHaptic(gDateLyricsHapticStyleSyllable);
                }
            }
        }
        
        DateLyricsApplyCurrentLineToAllCoverSheets();
    } else if (sweepClockChanged) {
        // Same syllable, new timing (pause, resume, seek within it).
        DateLyricsSweepResyncAllLabels();
    }

    if (rate <= 0.0f) {
        DateLyricsSchedulePauseHideTimer();
        DateLyricsDebugLog(@"[Ticker] paused at %.2f", currentElapsed);
        return;
    }

    DateLyricsCancelPauseHideTimer();

    NSTimeInterval staleDelay = MAX(0.0, kDateLyricsAnchorStaleTimeout - anchorAge);
    NSTimeInterval delay = staleDelay;
    if (nextTrigger >= 0.0) {
        delay = MIN(MAX(0.0, (nextTrigger - currentElapsed) / rate), staleDelay);
        // When the next trigger is the actual beginning of a new line, fire
        // the ticker 50 ms early so the transition animation has a little time
        // to settle before the source timestamp.  Do not advance word/syllable
        // triggers, and do not subtract the lead twice while a preview is held.
        if (gDateLyricsTransitionsEnabled && !usingEarlyLine && nextLineTrigger >= 0.0 &&
            fabs(nextTrigger - nextLineTrigger) < 0.001) {
            delay -= kDateLyricsLineTransitionLead;
        }
    }
    if (delay >= 0.0) {
        gDateLyricsTicker = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        // 10 ms of leeway lets the kernel coalesce this wake with others;
        // that is well below what a lyric highlight can visibly drift by.
        dispatch_source_set_timer(gDateLyricsTicker, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(gDateLyricsTicker, ^{
            DateLyricsScheduleTicker();
        });
        dispatch_resume(gDateLyricsTicker);
    }
}
