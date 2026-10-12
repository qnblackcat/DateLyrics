// On-disk lyric storage: container paths, score files and cache pruning.

#import "DateLyricsInternal.h"

NSString *DateLyricsRootPathForBundleIdentifier(NSString *bundleIdentifier) {
    static NSMutableDictionary<NSString *, NSString *> *cachedSpringBoardPaths = nil;
    if (DateLyricsIsSpringBoardHost()) {
        if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0) {
            bundleIdentifier = @"com.apple.Music";
        }
        if (!cachedSpringBoardPaths) cachedSpringBoardPaths = [NSMutableDictionary dictionary];
        NSString *cachedPath = cachedSpringBoardPaths[bundleIdentifier];
        if (cachedPath) return cachedPath;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if ([proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
            id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleIdentifier];
            NSURL *containerURL = [proxy respondsToSelector:@selector(dataContainerURL)] ? [proxy performSelector:@selector(dataContainerURL)] : nil;
            if (containerURL) {
                cachedPath = [[containerURL.path stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"DateLyrics"];
                cachedSpringBoardPaths[bundleIdentifier] = cachedPath;
                return cachedPath;
            }
        }
        return [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"DateLyrics"];
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsRootPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
        gLyricsRootPath = [gLyricsRootPath stringByAppendingPathComponent:@"DateLyrics"];
        [[NSFileManager defaultManager] createDirectoryAtPath:gLyricsRootPath withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return gLyricsRootPath;
}

NSString *GetLyricsRootPath(void) {
    if (DateLyricsIsSpringBoardHost()) {
        NSString *bundleIdentifier = gDateLyricsLocalAnchor[@"bundleIdentifier"];
        if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0) {
            bundleIdentifier = @"com.apple.Music";
        }
        return DateLyricsRootPathForBundleIdentifier(bundleIdentifier);
    }
    return DateLyricsRootPathForBundleIdentifier(nil);
}

void DateLyricsWriteRuntimeStatus(void) {
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    NSDictionary *status = @{
        @"host": DateLyricsIsSpringBoardHost() ? @"springboard" : (DateLyricsIsYouTubeMusicHost() ? @"youtube-music" : (DateLyricsIsMusicHost() ? @"music" : @"other")),
        @"osVersion": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion],
        @"CSProminentSubtitleDateView": @(NSClassFromString(@"CSProminentSubtitleDateView") != nil),
        @"CSProminentEmptyElementView": @(NSClassFromString(@"CSProminentEmptyElementView") != nil),
        @"ExpandedArtworkDetection": @(gDateLyricsArtworkDetectionAvailable),
        @"UIAnimatingLabel": @(NSClassFromString(@"_UIAnimatingLabel") != nil),
        @"MSVLyricsTTMLParser": @(NSClassFromString(@"MSVLyricsTTMLParser") != nil),
        @"ICMusicKitURLRequest": @(NSClassFromString(@"ICMusicKitURLRequest") != nil),
        @"YTLocalPlaybackController": @(NSClassFromString(@"YTLocalPlaybackController") != nil),
        @"YTPlaybackTimeHookAvailable": @([NSClassFromString(@"YTLocalPlaybackController") instancesRespondToSelector:@selector(singleVideo:currentVideoTimeDidChange:)]),
        @"YTPlaybackRateHookAvailable": @([NSClassFromString(@"YTLocalPlaybackController") instancesRespondToSelector:@selector(singleVideo:playbackRateDidChange:)]),
        @"updatedAt": @([[NSDate date] timeIntervalSince1970])
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToFile:[GetLyricsRootPath() stringByAppendingPathComponent:@"runtime-status.json"] atomically:YES];
    }
}


BOOL DateLyricsWordLinesHaveTiming(NSArray<DateLyricsTimedLine *> *lines) {
    if (lines.count == 0) return NO;
    BOOL hasTiming = NO;
    for (DateLyricsTimedLine *line in lines) {
        if (!isfinite(line.begin) || !isfinite(line.end)) return NO;
        for (DateLyricsTimedWord *word in line.words) {
            if (!isfinite(word.begin) || !isfinite(word.end)) return NO;
            if (word.end > word.begin) hasTiming = YES;
        }
    }
    return hasTiming;
}

BOOL DateLyricsLineItemsHaveTiming(NSArray<MSVLyricsLine *> *lines) {
    if (lines.count == 0) return NO;
    BOOL hasTiming = NO;
    for (MSVLyricsLine *line in lines) {
        if (!isfinite(line.startTime) || !isfinite(line.endTime)) return NO;
        if (line.endTime > line.startTime) hasTiming = YES;
        // Some line-synced responses provide only increasing start times.
        if (line.startTime > 0.001) hasTiming = YES;
    }
    return hasTiming;
}

void DateLyricsTouchMemoryCacheLocked(NSNumber *storeID) {
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

void DateLyricsPruneDiskCache(void) {
    NSString *rootPath = GetLyricsRootPath();
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:nil];
    NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *scoreFiles = [NSMutableArray array];
    for (NSString *entry in entries) {
        BOOL isAppleLyrics = [entry hasPrefix:@"syllable-lyrics_"] && [entry hasSuffix:@".xml"];
        BOOL isScore = [entry hasPrefix:@"score-"] && [entry hasSuffix:@".json"];
        if (!isAppleLyrics && !isScore) continue;
        NSString *path = [rootPath stringByAppendingPathComponent:entry];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSMutableArray *destination = isScore ? scoreFiles : files;
        [destination addObject:@{ @"path": path, @"date": attributes[NSFileModificationDate] ?: [NSDate distantPast] }];
    }
    for (NSMutableArray<NSDictionary *> *cacheFiles in @[files, scoreFiles]) {
        [cacheFiles sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"date"] compare:right[@"date"]];
        }];
        while (cacheFiles.count > kDateLyricsMaxDiskCacheEntries) {
            NSDictionary *oldest = cacheFiles.firstObject;
            [[NSFileManager defaultManager] removeItemAtPath:oldest[@"path"] error:nil];
            [cacheFiles removeObjectAtIndex:0];
        }
    }
}

BOOL DateLyricsWriteScoreJSON(NSInteger storeID, NSArray<NSDictionary *> *linesArray, BOOL hasWordTiming, NSString *source) {
    if (storeID <= 0 || linesArray.count == 0) return NO;

    NSMutableDictionary *score = [NSMutableDictionary dictionary];
    score[@"protocol"] = @3;
    score[@"kind"] = @"score";
    score[@"trackId"] = @(storeID);
    score[@"generatedAt"] = @([NSDate timeIntervalSinceReferenceDate]);
    score[@"hasWordTiming"] = @(hasWordTiming);
    if (source.length > 0) score[@"source"] = source;
    score[@"lines"] = linesArray;

    // Timings come from external lyric data; a NaN in them would throw below.
    if (![NSJSONSerialization isValidJSONObject:score]) return NO;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:score options:0 error:nil];
    if (!jsonData) return NO;

    NSString *path = [GetLyricsRootPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"score-%ld.json", (long)storeID]];
    NSString *tempPath = [path stringByAppendingPathExtension:@"tmp"];
    if (![jsonData writeToFile:tempPath atomically:YES]) return NO;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if (![[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:path error:nil]) return NO;

    DateLyricsPruneDiskCache();
    DateLyricsDebugLog(@"[Score] wrote storeID=%ld lines=%lu wordTiming=%d source=%@",
                       (long)storeID, (unsigned long)linesArray.count, hasWordTiming, source ?: @"apple");

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        DateLyricsScoreChangedNotification(), NULL, NULL, YES);
    return YES;
}

void DateLyricsSerializeScore(NSInteger storeID, NSArray<DateLyricsTimedLine *> *wordLines, NSArray<MSVLyricsLine *> *lyricLines) {
    if (wordLines.count == 0 && lyricLines.count == 0) return;

    NSMutableArray *linesArray = [NSMutableArray array];

    if (wordLines.count > 0) {
        for (DateLyricsTimedLine *line in wordLines) {
            NSMutableDictionary *lineDict = [NSMutableDictionary dictionary];
            lineDict[@"begin"] = @(line.begin);
            lineDict[@"end"] = @(line.end);
            lineDict[@"text"] = line.text ?: @"";
            
            NSMutableArray *wordsArray = [NSMutableArray array];
            for (DateLyricsTimedWord *word in line.words) {
                [wordsArray addObject:@{
                    @"b": @(word.begin),
                    @"e": @(word.end),
                    @"t": word.text ?: @"",
                    @"s": word.separatorBefore ?: @"",
                    @"bg": @(word.background)
                }];
            }
            lineDict[@"words"] = wordsArray;
            [linesArray addObject:lineDict];
        }
    } else {
        for (MSVLyricsLine *line in lyricLines) {
            NSMutableDictionary *lineDict = [NSMutableDictionary dictionary];
            lineDict[@"begin"] = @(line.startTime);
            lineDict[@"end"] = @(line.endTime);
            
            id lyricsText = [line respondsToSelector:@selector(lyricsText)] ? [line performSelector:@selector(lyricsText)] : nil;
            NSString *rawTitle = nil;
            if ([lyricsText isKindOfClass:[NSAttributedString class]]) {
                rawTitle = [lyricsText string];
            } else if ([lyricsText isKindOfClass:[NSString class]]) {
                rawTitle = (NSString *)lyricsText;
            }
            lineDict[@"text"] = DateLyricsStripParentheses(rawTitle, gDateLyricsShowAdlibs) ?: @"";
            [linesArray addObject:lineDict];
        }
    }
    
    DateLyricsWriteScoreJSON(storeID, linesArray, wordLines.count > 0, nil);
}

void DateLyricsInvalidateSerializedScore(NSInteger storeID) {
    if (storeID <= 0) return;
    NSNumber *storeIDKey = @(storeID);
    pthread_mutex_lock(&gLyricsCacheMutex);
    [gLyricsCache removeObjectForKey:storeIDKey];
    [gWordLyricsCache removeObjectForKey:storeIDKey];
    [gLyricsCacheOrder removeObject:storeIDKey];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    NSString *path = [GetLyricsRootPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"score-%ld.json", (long)storeID]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        DateLyricsScoreChangedNotification(), NULL, NULL, YES);
}
