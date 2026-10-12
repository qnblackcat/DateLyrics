// Preference reloading, cache clearing and cross-process notification handlers.

#import "DateLyricsInternal.h"

void DateLyricsReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    void (^reloadBlock)(void) = ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)@"com.shalamand3r.datelyrics");

        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:jbroot(@"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist")];
        if (!prefs) {
            prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        }

        BOOL (^getPrefBool)(NSString *, BOOL) = ^BOOL(NSString *key, BOOL defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val boolValue];
            if (prefs && prefs[key]) return [prefs[key] boolValue];
            return defaultVal;
        };

        NSInteger (^getPrefInteger)(NSString *, NSInteger) = ^NSInteger(NSString *key, NSInteger defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val integerValue];
            if (prefs && prefs[key]) return [prefs[key] integerValue];
            return defaultVal;
        };

        CGFloat (^getPrefFloat)(NSString *, CGFloat) = ^CGFloat(NSString *key, CGFloat defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return (CGFloat)[val floatValue];
            if (prefs && prefs[key]) return (CGFloat)[prefs[key] floatValue];
            return defaultVal;
        };

        double (^getPrefDouble)(NSString *, double) = ^double(NSString *key, double defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val doubleValue];
            if (prefs && prefs[key]) return [prefs[key] doubleValue];
            return defaultVal;
        };

        NSString *(^getPrefString)(NSString *, NSString *) = ^NSString *(NSString *key, NSString *defaultVal) {
            id val = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.shalamand3r.datelyrics"));
            if (val) return [val copy];
            if (prefs && prefs[key]) return [prefs[key] copy];
            return defaultVal;
        };

        gDateLyricsEnabled = getPrefBool(@"Enabled", YES);
        gDateLyricsOnlyExpandedArtwork = getPrefBool(@"OnlyExpandedArtwork", NO);
        gDateLyricsInterludeIndicator = getPrefBool(@"InterludeIndicator", NO);
        gDateLyricsInterludeStyle = getPrefInteger(@"InterludeStyle", 0);
        if (gDateLyricsInterludeStyle < 0 || gDateLyricsInterludeStyle > 2) gDateLyricsInterludeStyle = 0;
        gDateLyricsForceLowercase = getPrefBool(@"ForceLowercase", NO);
        gDateLyricsWordHighlighting = getPrefBool(@"WordHighlighting", YES);
        gDateLyricsHapticsEnabled = getPrefBool(@"HapticsEnabled", NO);
        gDateLyricsHapticStyleSyllable = getPrefInteger(@"HapticStyleSyllable", 1);
        gDateLyricsHapticStyleLine = getPrefInteger(@"HapticStyleLine", 2);
        gDateLyricsUseCustomFont = getPrefBool(@"UseCustomFont", NO);
        gDateLyricsCustomFontName = getPrefString(@"CustomFontName", nil);
        gDateLyricsItalicLyrics = getPrefBool(@"ItalicLyrics", NO);
        gDateLyricsTransitionsEnabled = getPrefBool(@"TransitionsEnabled", YES);
        
        NSInteger transitionStyle = getPrefInteger(@"TransitionStyle", DateLyricsTransitionStyleSlideUp);
        if (transitionStyle < DateLyricsTransitionStyleFade || transitionStyle > DateLyricsTransitionStylePop) {
            transitionStyle = DateLyricsTransitionStyleSlideUp;
        }
        gDateLyricsTransitionStyle = transitionStyle;
        gDateLyricsTransitionDuration = getPrefDouble(@"TransitionDuration", 0.3);
        if (!gDateLyricsTransitionsEnabled) DateLyricsClearEarlyLinePreview();
        gDateLyricsSplitLongLines = getPrefBool(@"SplitLongLines", YES);
        if (gDateLyricsSplitLongLines) {
            gDateLyricsShowAdlibs = NO;
        } else {
            gDateLyricsShowAdlibs = getPrefBool(@"ShowAdlibs", NO);
        }
        gDateLyricsMinimumScale = getPrefFloat(@"MinimumScale", 0.55);
        gDateLyricsPauseTimeout = getPrefDouble(@"PauseTimeout", 2.0);
        gDateLyricsMarqueeEnabled = getPrefBool(@"MarqueeEnabled", YES);
        gDateLyricsMusixmatchEnabled = getPrefBool(@"MusixmatchEnabled", YES);
        gDateLyricsDebugLogging = getPrefBool(@"DebugLogging", NO);
        BOOL smoothSweep = getPrefBool(@"SmoothWordSweep", NO);
        if (smoothSweep != gDateLyricsSmoothSweep) gDateLyricsSweepClockValid = NO;
        gDateLyricsSmoothSweep = smoothSweep;
        gDateLyricsRenderGeneration++;

        if (!gDateLyricsMusixmatchEnabled && gLyricsQueue) {
            // Pending fallback requests are best-effort.  They cannot be
            // allowed to repopulate a score after the user turns the feature
            // off, and clearing the pending IDs lets a later re-enable retry
            // the current track cleanly.
            dispatch_async(gLyricsQueue, ^{
                for (DateLyricsMusixmatchTask *task in [gMusixmatchTokenWaiters copy]) {
                    DateLyricsRemoveMusixmatchLoadingScore(task.storeID);
                }
                [gMusixmatchTokenWaiters removeAllObjects];
                [gMusixmatchPendingStoreIDs removeAllObjects];
                [gMusixmatchWordUpgradeAttemptedStoreIDs removeAllObjects];
                [gMusixmatchFailureRetryAfter removeAllObjects];
                gMusixmatchTokenRequestInFlight = NO;
            });
        }

        if (DateLyricsIsSpringBoardHost() && !gDateLyricsMusixmatchEnabled &&
            [gDateLyricsCurrentScore.source hasPrefix:@"musixmatch"]) {
            gDateLyricsCurrentScore = nil;
            gDateLyricsCurrentPayload = nil;
            gDateLyricsResolverCursor = -1;
            DateLyricsClearEarlyLinePreview();
            gDateLyricsRenderGeneration++;
            DateLyricsApplyCurrentLineToAllCoverSheets();
        }

        if (DateLyricsIsSpringBoardHost()) {
            DateLyricsCancelPauseHideTimer();
            DateLyricsScheduleTicker();
        }
        if (!gDateLyricsEnabled) {
            if (DateLyricsIsSpringBoardHost()) {
                gDateLyricsCurrentPayload = nil;
                DateLyricsApplyCurrentLineToAllCoverSheets();
            }
        } else {
            if (DateLyricsIsSpringBoardHost()) {
                DateLyricsApplyCurrentLineToAllCoverSheets();
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
void DateLyricsClearCaches(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    pthread_mutex_lock(&gLyricsCacheMutex);
    [gLyricsCache removeAllObjects];
    [gWordLyricsCache removeAllObjects];
    [gLyricsCacheOrder removeAllObjects];
    [gUnsynchronizedLyricsIDs removeAllObjects];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *rootPaths = DateLyricsIsSpringBoardHost()
        ? @[DateLyricsRootPathForBundleIdentifier(@"com.apple.Music"), DateLyricsRootPathForBundleIdentifier(@"com.google.ios.youtubemusic")]
        : @[GetLyricsRootPath()];
    for (NSString *rootPath in rootPaths) {
        for (NSString *entry in [fileManager contentsOfDirectoryAtPath:rootPath error:nil]) {
            BOOL isAppleLyrics = [entry hasPrefix:@"syllable-lyrics_"] && [entry hasSuffix:@".xml"];
            BOOL isScore = [entry hasPrefix:@"score-"] && ([entry hasSuffix:@".json"] || [entry hasSuffix:@".json.tmp"]);
            if (!isAppleLyrics && !isScore) continue;
            [fileManager removeItemAtPath:[rootPath stringByAppendingPathComponent:entry] error:nil];
        }
    }

    if (DateLyricsIsPlaybackHost() && gLyricsQueue) {
        dispatch_async(gLyricsQueue, ^{
            // The pending-set check in the callbacks turns this into a
            // cancellation barrier for in-flight fallback requests; a reset
            // must not repopulate the cache a moment later.
            [gMusixmatchPendingStoreIDs removeAllObjects];
            [gMusixmatchTokenWaiters removeAllObjects];
            [gMusixmatchWordUpgradeAttemptedStoreIDs removeAllObjects];
            [gMusixmatchFailureRetryAfter removeAllObjects];
            gMusixmatchTokenRequestInFlight = NO;
            gMusixmatchUserToken = nil;
            gMusixmatchTokenFetchedAt = 0.0;
            gMusixmatchTokenCacheLoaded = NO;
            [[NSFileManager defaultManager] removeItemAtPath:DateLyricsMusixmatchTokenCachePath() error:nil];
        });
    }

    if (DateLyricsIsSpringBoardHost()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DateLyricsCancelPauseHideTimer();
            gDateLyricsCurrentPayload = @{};
            DateLyricsApplyCurrentLineToAllCoverSheets();
        });
    }
}

void DateLyricsHandleAnchorChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *sourceBundleIdentifier = CFEqual(name, CFSTR("com.shalamand3r.datelyrics/anchor.youtube.changed"))
        ? @"com.google.ios.youtubemusic" : @"com.apple.Music";
    // Darwin callbacks do not promise the main thread.  The renderer, resolver
    // cursor and dispatch source are all main-thread state, so serialise the
    // complete consume-and-render step here instead of racing a ticker callback.
    dispatch_async(dispatch_get_main_queue(), ^{
      // An uncaught exception here aborts SpringBoard and sends the device to
      // safe mode, so contain anything the stored files or the renderer throw.
      @try {
        if (!gDateLyricsEnabled) return;

        NSString *path = [DateLyricsRootPathForBundleIdentifier(sourceBundleIdentifier) stringByAppendingPathComponent:@"anchor.json"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        // JSONObjectWithData: throws (rather than failing) on nil data, e.g. when the
        // playback app has not written its anchor yet or its container moved.
        NSDictionary *anchor = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![anchor isKindOfClass:NSDictionary.class] || ![anchor[@"kind"] isEqualToString:@"anchor"]) {
            DateLyricsDebugLog(@"[SB] %@ failed to read valid anchor at path: %@ dataBytes=%lu",
                [sourceBundleIdentifier isEqualToString:@"com.google.ios.youtubemusic"] ? @"[YTM]" : @"[Music]",
                path, (unsigned long)data.length);
            return;
        }

        if (![anchor[@"bundleIdentifier"] isKindOfClass:NSString.class]) {
            NSMutableDictionary *normalizedAnchor = [anchor mutableCopy];
            normalizedAnchor[@"bundleIdentifier"] = sourceBundleIdentifier;
            anchor = normalizedAnchor;
        }

        NSString *previousBundleIdentifier = gDateLyricsLocalAnchor[@"bundleIdentifier"] ?: @"com.apple.Music";
        BOOL sourceChanged = ![previousBundleIdentifier isEqualToString:sourceBundleIdentifier];
        DateLyricsNotePauseState(gDateLyricsLocalAnchor, anchor);
        gDateLyricsLocalAnchor = anchor;
        NSInteger trackId = [anchor[@"trackId"] integerValue];
        DateLyricsDebugLog(@"[SB] %@ received anchor: trackId=%ld elapsed=%.2f rate=%.2f bundle=%@",
            [sourceBundleIdentifier isEqualToString:@"com.google.ios.youtubemusic"] ? @"[YTM]" : @"[Music]",
            (long)trackId, [anchor[@"elapsed"] doubleValue], [anchor[@"rate"] floatValue], sourceBundleIdentifier);
        if (sourceChanged || !gDateLyricsCurrentScore || gDateLyricsCurrentScore.trackId != trackId) {
            NSString *scorePath = [GetLyricsRootPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"score-%ld.json", (long)trackId]];
            NSData *scoreData = [NSData dataWithContentsOfFile:scorePath];
            gDateLyricsCurrentScore = scoreData ? [[DateLyricsScore alloc] initWithJSONData:scoreData] : nil;
            if (gDateLyricsCurrentScore &&
                [gDateLyricsCurrentScore.source hasPrefix:@"musixmatch"] &&
                !gDateLyricsMusixmatchEnabled) {
                gDateLyricsCurrentScore = nil;
            }
            if (gDateLyricsCurrentScore) {
                DateLyricsDebugLog(@"[SB] Loaded score for trackId=%ld (lines=%lu source=%@ wordTiming=%d firstLineWords=%lu)",
                    (long)trackId, (unsigned long)gDateLyricsCurrentScore.lines.count,
                    gDateLyricsCurrentScore.source ?: @"apple", gDateLyricsCurrentScore.hasWordTiming,
                    (unsigned long)gDateLyricsCurrentScore.lines.firstObject.words.count);
            } else {
                DateLyricsDebugLog(@"[SB] Score file missing or invalid at path: %@", scorePath);
                // Never carry an old song's lyric across the fetch/parse window.
                // The score.changed notification will render the new one as soon
                // as Music has written it.
                gDateLyricsCurrentPayload = nil;
                DateLyricsApplyCurrentLineToAllCoverSheets();
            }
        }
        gDateLyricsResolverCursor = -1;
        DateLyricsClearEarlyLinePreview();
        DateLyricsScheduleTicker();
      } @catch (NSException *exception) {
        NSLog(@"[DateLyrics SB] anchor handler exception %@: %@\n%@", exception.name, exception.reason,
            [exception.callStackSymbols componentsJoinedByString:@"\n"]);
      }
    });
}

void DateLyricsHandleScoreChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
      @try {
        if (!gDateLyricsEnabled || !gDateLyricsLocalAnchor) return;

        NSInteger currentTrackId = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
        NSString *scorePath = [GetLyricsRootPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"score-%ld.json", (long)currentTrackId]];
        NSData *scoreData = [NSData dataWithContentsOfFile:scorePath];
        DateLyricsScore *newScore = scoreData ? [[DateLyricsScore alloc] initWithJSONData:scoreData] : nil;
        if (newScore && [newScore.source hasPrefix:@"musixmatch"] && !gDateLyricsMusixmatchEnabled) {
            newScore = nil;
        }
        if (newScore && newScore.trackId == currentTrackId) {
            gDateLyricsCurrentScore = newScore;
            gDateLyricsResolverCursor = -1;
            DateLyricsClearEarlyLinePreview();
            gDateLyricsLastResolvedTrackId = currentTrackId;
            gDateLyricsLastResolvedElapsed = -1.0;
            gDateLyricsRenderGeneration++;
            DateLyricsDebugLog(@"[SB] Score updated for trackId=%ld (lines=%lu source=%@ wordTiming=%d firstLineWords=%lu)",
                (long)currentTrackId, (unsigned long)newScore.lines.count, newScore.source ?: @"apple",
                newScore.hasWordTiming, (unsigned long)newScore.lines.firstObject.words.count);
            DateLyricsScheduleTicker();
        } else {
            // Music intentionally removed an invalid/unsynchronised score (or
            // the file was malformed).  Do not leave the previous song's
            // payload alive in SpringBoard; otherwise a transcript-only track
            // can appear to have lyrics until the next anchor arrives.
            BOOL hadScore = (gDateLyricsCurrentScore != nil || gDateLyricsCurrentPayload != nil);
            gDateLyricsCurrentScore = nil;
            gDateLyricsCurrentPayload = nil;
            gDateLyricsResolverCursor = -1;
            DateLyricsClearEarlyLinePreview();
            gDateLyricsLastResolvedTrackId = currentTrackId;
            gDateLyricsLastResolvedElapsed = -1.0;
            gDateLyricsRenderGeneration++;
            DateLyricsScheduleTicker();
            if (hadScore) {
                DateLyricsDebugLog(@"[SB] Cleared score for trackId=%ld (missing or invalid)", (long)currentTrackId);
                DateLyricsApplyCurrentLineToAllCoverSheets();
            }
        }
      } @catch (NSException *exception) {
        NSLog(@"[DateLyrics SB] score handler exception %@: %@\n%@", exception.name, exception.reason,
            [exception.callStackSymbols componentsJoinedByString:@"\n"]);
      }
    });
}

void DateLyricsHandleAnchorRequest(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (gCurrentContentItem) {
        NSInteger storeID = gCurrentContentItem.amlLastStoreID;
        if (storeID) {
            double elapsedTime = [gCurrentContentItem calculatedElapsedTime];
            float rate = gCurrentContentItem.amlPlaybackRate ? gCurrentContentItem.amlPlaybackRate.floatValue : 0.0f;
            DateLyricsPublishAnchor(storeID, elapsedTime, rate, NO);
        }
    }
}
