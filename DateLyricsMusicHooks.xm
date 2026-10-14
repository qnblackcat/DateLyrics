#import "DateLyricsInternal.h"




%group DateLyricsPrimary


%hook ICURLSession

- (void)enqueueDataRequest:(id)arg1 withCompletionHandler:(ICURLSessionCompletionHandler)arg2 {
    // Music can replace its URL session or refresh the request context after a
    // token/identity change.  Keeping the first objects forever makes all later
    // lyric requests fail after that rotation.
    ICURLSession *session = nil;
    ICMusicKitRequestContext *requestContext = nil;
    if ([arg1 isKindOfClass:%c(ICMusicKitURLRequest)]) {
        ICMusicKitURLRequest *req = arg1;
        session = self;
        requestContext = [req requestContext];
    }
    dispatch_async(gLyricsQueue, ^{
        if (session) {
            gSession = session;
            gRequestContext = requestContext;
        }
        if (!gIsProcessingQueue) ProcessNextTask();
    });
    %orig;
}

%end

%hook MRNowPlayingPlayerClient

- (void)sendContentItemChanges:(NSArray<MRContentItem *> *)contentItems {
    %orig;
    if (!gDateLyricsEnabled) return;
    dispatch_async(gLyricsQueue, ^{
        
        MRContentItem *item = self.nowPlayingContentItem;
        if (!item || ![item respondsToSelector:@selector(metadata)] || !item.metadata) {
            return;
        }
        NSInteger iTunesStoreID = item.metadata.iTunesStoreIdentifier;
        NSString *fallbackTitle = DateLyricsMetadataString(item.metadata, @[@"title", @"amLyricsTitle", @"name"]);
        NSString *fallbackArtist = DateLyricsMetadataString(item.metadata, @[@"trackArtistName", @"artist", @"artistName"]);
        NSString *fallbackAlbum = DateLyricsMetadataString(item.metadata, @[@"albumName", @"album", @"collectionName"]);
        NSTimeInterval fallbackDuration = DateLyricsMetadataDuration(item.metadata);

        if (!item.metadata.lyricsAvailable) {
            // A track can lose its lyrics flag while switching items.  Remove
            // any score left from an earlier fetch so SpringBoard cannot load
            // it when the new anchor arrives.
            if (iTunesStoreID > 0) {
                NSString *scorePath = [GetLyricsRootPath() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"score-%ld.json", (long)iTunesStoreID]];
                NSData *existingScoreData = [NSData dataWithContentsOfFile:scorePath];
                DateLyricsScore *existingScore = existingScoreData.length > 0
                    ? [[DateLyricsScore alloc] initWithJSONData:existingScoreData]
                    : nil;
                if (![existingScore.source isEqualToString:@"musixmatch"] || existingScore.lines.count == 0) {
                    DateLyricsInvalidateSerializedScore(iTunesStoreID);
                }
                DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                    fallbackAlbum, fallbackDuration, NO);
            }
            return;
        }

        if (iTunesStoreID <= 0) {
            return;
        }
        
        NSInteger lyricsAdamID;
        NSString *lyricURLString;
        NSString *legacyURLString = nil;
        NSString *storefront = DateLyricsStorefront();
        NSString *locale = DateLyricsPreferredLocale();
        NSOperatingSystemVersion osVersion = [NSProcessInfo processInfo].operatingSystemVersion;
        BOOL hasLyricsAdamID = [item.metadata respondsToSelector:@selector(lyricsAdamID)];
        id metadataLyricsURL = [item.metadata respondsToSelector:NSSelectorFromString(@"lyricsURL")]
            ? [(NSObject *)item.metadata valueForKey:@"lyricsURL"] : nil;
        DateLyricsDebugLog(@"[Lyrics] track storeID=%ld title=%@ artist=%@ ios=%ld.%ld.%ld metadata=%@ respondsLyricsAdamID=%d lyricsAdamID=%ld metadataLyricsURL=%@ storefront=%@ locale=%@",
                           (long)iTunesStoreID, fallbackTitle ?: @"", fallbackArtist ?: @"",
                           (long)osVersion.majorVersion, (long)osVersion.minorVersion, (long)osVersion.patchVersion,
                           NSStringFromClass([item.metadata class]), hasLyricsAdamID,
                           (long)(hasLyricsAdamID ? item.metadata.lyricsAdamID : 0),
                           metadataLyricsURL ?: @"-", storefront, locale);
        if (hasLyricsAdamID) {
            lyricsAdamID = item.metadata.lyricsAdamID;
            lyricURLString = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/songs/%lld/syllable-lyrics?l=%@", storefront, (long long)lyricsAdamID, locale];
        } else {
            // Older MediaRemote (iOS 16.2 and earlier) doesn't publish
            // lyricsAdamID.  Try the syllable endpoint with the store ID first
            // and keep the line-timed endpoint as a fallback.
            lyricsAdamID = iTunesStoreID;
            lyricURLString = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/songs/%lld/syllable-lyrics?l=%@", storefront, (long long)lyricsAdamID, locale];
            legacyURLString = [NSString stringWithFormat:@"https://se2.itunes.apple.com/WebObjects/MZStoreElements2.woa/wa/ttmlLyrics?id=%lld&l=%@", (long long)iTunesStoreID, locale];
        }
        DateLyricsDebugLog(@"[Lyrics] storeID=%ld lyricsID=%ld primary=%@ legacy=%@",
                           (long)iTunesStoreID, (long)lyricsAdamID, lyricURLString, legacyURLString ?: @"-");
        if (lyricsAdamID <= 0) {
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, NO);
            return;
        }

        
        NSString *lyricsRoot = GetLyricsRootPath();
        NSString *lyricsFilePath = [lyricsRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"syllable-lyrics_%lld.xml", (long long)lyricsAdamID]];
        if (DateLyricsIsUnsynchronizedLyricsID(lyricsAdamID)) {
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, NO);
            return;
        }
        if (legacyURLString && DateLyricsIsLineTimedOnlyThisSession(iTunesStoreID)) {
            DateLyricsDebugLog(@"[Lyrics] storeID=%ld already fetched as line-timed this session; not refetching", (long)iTunesStoreID);
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, YES);
            return;
        }
        BOOL lyricsCacheExists = [[NSFileManager defaultManager] fileExistsAtPath:lyricsFilePath];
        DateLyricsDebugLog(@"[Lyrics] storeID=%ld cacheFile=%@ exists=%d", (long)iTunesStoreID, lyricsFilePath, lyricsCacheExists);
        if (lyricsCacheExists) {
            NSData *cachedData = [NSData dataWithContentsOfFile:lyricsFilePath];
            BOOL unsynchronized = NO;
            BOOL hasWordTiming = NO;
            BOOL cacheParsed = ParseLyricsData(cachedData, iTunesStoreID, lyricsAdamID,
                                               &unsynchronized, &hasWordTiming);
            DateLyricsDebugLog(@"[Lyrics] storeID=%ld cache parsed=%d wordTiming=%d unsynchronized=%d",
                               (long)iTunesStoreID, cacheParsed, hasWordTiming, unsynchronized);
            if (cacheParsed && (hasWordTiming || !legacyURLString)) {
                if (!hasWordTiming) {
                    DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                        fallbackAlbum, fallbackDuration, YES);
                }
                return;
            }
            if (cacheParsed) {
                // A line-timed file cached by an earlier version.  Without
                // lyricsAdamID the syllable endpoint was never tried, so
                // drop it and fetch again.
                DateLyricsDebugLog(@"[Lyrics] storeID=%ld dropping line-timed cache; refetching", (long)iTunesStoreID);
            }
            [[NSFileManager defaultManager] removeItemAtPath:lyricsFilePath error:nil];
            if (unsynchronized) {
                DateLyricsSetUnsynchronizedLyricsID(lyricsAdamID, YES);
                DateLyricsDebugLog(@"[Parser] Marked cached lyricsAdamID=%ld as transcript-only; skipping fetch", (long)lyricsAdamID);
                DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                    fallbackAlbum, fallbackDuration, NO);
                return;
            }
        }

        if (legacyURLString) {
            // Don't let a line-timed entry in memory shadow the syllable data
            // we are about to fetch.
            DateLyricsEvictMemoryLyrics(iTunesStoreID);
        }
        NSURL *lyricURL = [NSURL URLWithString:lyricURLString];
        NSURL *legacyURL = legacyURLString ? [NSURL URLWithString:legacyURLString] : nil;
        if (lyricURL) {
            AddTaskToQueue(iTunesStoreID, lyricsAdamID, lyricURL, legacyURL, lyricsFilePath,
                fallbackTitle, fallbackArtist, fallbackAlbum, fallbackDuration);
        } else {
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, NO);
        }
    });
}

%end

%hook MPNowPlayingContentItem

%property (nonatomic, strong) NSNumber *amlPlaybackRate;
%property (nonatomic, strong) NSNumber *amlLastSystemElapsedTime;
%property (nonatomic, strong) NSNumber *amlLastSystemTime;
%property (assign, nonatomic) NSInteger amlLastStoreID;

- (void)dealloc {
    if (gCurrentContentItem == self) {
        gCurrentContentItem = nil;
    }
    %orig;
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


- (void)setElapsedTime:(double)elapsedTime playbackRate:(float)playbackRate {
    // Capture this before updating our associated state.  Comparing after this
    // assignment made rateChanged permanently false, so a 1.0 -> 0.0 pause was
    // never sent to SpringBoard and its local clock kept advancing.
    NSNumber *previousRate = self.amlPlaybackRate;
    // MAX() passes NaN straight through, so check finiteness explicitly.
    float sanitizedRate = isfinite(playbackRate) ? MAX(0.0f, playbackRate) : 0.0f;
    self.amlPlaybackRate = @(sanitizedRate);
    self.amlLastSystemElapsedTime = @(elapsedTime);
    self.amlLastSystemTime = @([NSDate timeIntervalSinceReferenceDate]);
    %orig;
    gCurrentContentItem = self;

    NSInteger storeID = 0;
    if ([self respondsToSelector:@selector(storeID)]) {
        storeID = self.storeID;
    } else if ([self respondsToSelector:@selector(metadata)]) {
        id metadata = [self performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            storeID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    if (!gDateLyricsEnabled) {
        self.amlLastStoreID = 0;
        return;
    }

    // Phase 4: Anchor Publishing
    if (storeID <= 0) {
        self.amlLastStoreID = 0;
        return;
    }
    // MediaPlayer reports a NaN position while it reloads the queue. It is no
    // position at all, and must not become the seek-detection baseline.
    if (!isfinite(elapsedTime)) return;

    BOOL rateChanged = !previousRate || fabsf(previousRate.floatValue - sanitizedRate) > 0.001f;
    BOOL trackChanged = (storeID != self.amlLastStoreID);
    
    static double lastAnchorElapsed = -1;
    static double lastAnchorHostTime = -1;
    static float lastAnchorRate = -1;
    
    double nowHost = DateLyricsMonotonicTime();
    double expectedElapsed = lastAnchorElapsed + ((nowHost - lastAnchorHostTime) * lastAnchorRate);
    BOOL pausedPositionChanged = sanitizedRate <= 0.0f && lastAnchorElapsed >= 0.0 &&
        ABS(elapsedTime - lastAnchorElapsed) > 0.05;
    BOOL seeked = lastAnchorHostTime >= 0.0 && ABS(elapsedTime - expectedElapsed) > 0.35;
    // A paused scrub is not clock jitter.  Mark a meaningful backward move as
    // an explicit seek so SpringBoard is allowed to resolve in reverse even
    // when the distance is smaller than the normal playing seek threshold.
    if (sanitizedRate <= 0.0f && lastAnchorElapsed >= 0.0 && elapsedTime < lastAnchorElapsed - 0.05) {
        seeked = YES;
    }
    // Darwin notifications are lossy. A light periodic anchor makes the direct
    // bridge self-healing without restoring the old per-lyric heartbeat.
    BOOL refreshDue = lastAnchorHostTime < 0.0 || nowHost - lastAnchorHostTime >= 4.0;
    
    if (rateChanged || trackChanged || seeked || pausedPositionChanged || refreshDue) {
        lastAnchorElapsed = elapsedTime;
        lastAnchorHostTime = nowHost;
        lastAnchorRate = sanitizedRate;
        self.amlLastStoreID = storeID;
        DateLyricsPublishAnchor(storeID, elapsedTime, sanitizedRate, seeked);
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

void DateLyricsInitMusicHooks(void) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17) {
            dlopen("/System/Library/Frameworks/VideoSubscriberAccount.framework/VideoSubscriberAccount", RTLD_NOW);
            %init(AMCrashPatcher);
        }
        %init(DateLyricsPrimary);
        DateLyricsWriteRuntimeStatus();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            DateLyricsHandleAnchorRequest,
            CFSTR("com.shalamand3r.datelyrics/anchor.request"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
}
