// Musixmatch fallback: token handling, matching and rich-sync fetching.

#import "DateLyricsInternal.h"

// MARK: - Optional Musixmatch rich-sync fallback

// Token flow adapted from github.com/ybenyedder/musixmatch-freeAPI (MIT).
// This remains an opt-in fallback, isolated from Apple's lyric queue; network
// callbacks return to gLyricsQueue before touching shared state.
static NSString *DateLyricsMusixmatchPercentEncode(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSMutableCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static void DateLyricsMusixmatchRequest(NSString *urlString, NSDictionary<NSString *, NSString *> *headers, void (^completion)(NSData *, NSInteger, NSError *)) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        DateLyricsDebugLog(@"[Musixmatch] request rejected: invalid URL");
        if (completion) completion(nil, 0, [NSError errorWithDomain:@"DateLyricsMusixmatch" code:-1 userInfo:nil]);
        return;
    }

    DateLyricsDebugLog(@"[Musixmatch] GET %@%@", url.host ?: @"?", url.path ?: @"/");

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 15.0;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        DateLyricsDebugLog(@"[Musixmatch] response host=%@ status=%ld bytes=%lu error=%@",
                           url.host ?: @"?", (long)status, (unsigned long)data.length, error.localizedDescription ?: @"none");
        if (completion) completion(data, status, error);
    }];
    [dataTask resume];
}

static id DateLyricsMusixmatchFindJSONValue(id object, NSString *key) {
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        id direct = dictionary[key];
        if (direct) return direct;
        for (id value in dictionary.allValues) {
            id found = DateLyricsMusixmatchFindJSONValue(value, key);
            if (found) return found;
        }
    } else if ([object isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)object) {
            id found = DateLyricsMusixmatchFindJSONValue(value, key);
            if (found) return found;
        }
    }
    return nil;
}

static BOOL DateLyricsSerializeMusixmatchLines(NSInteger storeID, NSArray<DateLyricsTimedLine *> *lines) {
    if (storeID <= 0 || lines.count == 0) return NO;

    NSMutableArray<NSDictionary *> *serializedLines = [NSMutableArray arrayWithCapacity:lines.count];
    BOOL hasWordTiming = NO;
    for (DateLyricsTimedLine *line in lines) {
        if (![line isKindOfClass:DateLyricsTimedLine.class] || line.text.length == 0 || line.end <= line.begin) continue;
        NSMutableDictionary *lineDictionary = [@{
            @"begin": @(line.begin),
            @"end": @(line.end),
            @"text": line.text ?: @""
        } mutableCopy];
        NSMutableArray<NSDictionary *> *words = [NSMutableArray array];
        for (DateLyricsTimedWord *word in line.words) {
            if (word.text.length == 0 || word.end <= word.begin) continue;
            hasWordTiming = YES;
            [words addObject:@{
                @"b": @(word.begin),
                @"e": @(word.end),
                @"t": word.text,
                @"s": word.separatorBefore ?: @"",
                @"bg": @(word.isBackground)
            }];
        }
        if (words.count > 0) lineDictionary[@"words"] = words;
        [serializedLines addObject:lineDictionary];
    }
    return DateLyricsWriteScoreJSON(storeID, serializedLines, hasWordTiming, @"musixmatch");
}

void DateLyricsRemoveMusixmatchLoadingScore(NSInteger storeID) {
    if (storeID <= 0) return;
    NSString *path = [GetLyricsRootPath() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"score-%ld.json", (long)storeID]];
    NSData *data = [NSData dataWithContentsOfFile:path];
    DateLyricsScore *score = data.length > 0 ? [[DateLyricsScore alloc] initWithJSONData:data] : nil;
    if (![score.source isEqualToString:@"musixmatch-loading"]) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        DateLyricsScoreChangedNotification(), NULL, NULL, YES);
}

static void DateLyricsWriteMusixmatchLoadingScore(DateLyricsMusixmatchTask *task) {
    if (!task || task.storeID <= 0 || task.wordSyncOnly) return;
    NSTimeInterval end = task.duration > 1.0 ? task.duration : 3600.0;
    DateLyricsWriteScoreJSON(task.storeID, @[@{
        @"begin": @0.0,
        @"end": @(end),
        @"text": @"Loading…"
    }], NO, @"musixmatch-loading");
}

static void DateLyricsMusixmatchFinishTask(DateLyricsMusixmatchTask *task, NSString *reason) {
    if (!task) return;
    [gMusixmatchPendingStoreIDs removeObject:@(task.storeID)];
    if (reason.length > 0) {
        gMusixmatchFailureRetryAfter[@(task.storeID)] = @([[NSDate date] timeIntervalSince1970] + 15.0 * 60.0);
        DateLyricsRemoveMusixmatchLoadingScore(task.storeID);
        DateLyricsDebugLog(@"[Musixmatch] storeID=%ld failed: %@", (long)task.storeID, reason);
    } else {
        [gMusixmatchFailureRetryAfter removeObjectForKey:@(task.storeID)];
        DateLyricsDebugLog(@"[Musixmatch] storeID=%ld completed", (long)task.storeID);
    }
}

static NSString *DateLyricsMusixmatchURL(NSString *endpoint, NSDictionary<NSString *, id> *parameters) {
    if (endpoint.length == 0) return nil;
    NSMutableDictionary<NSString *, id> *query = [@{
        @"app_id": @"web-desktop-app-v1.0",
        @"format": @"json"
    } mutableCopy];
    [query addEntriesFromDictionary:parameters ?: @{}];
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:query.count];
    NSArray<NSString *> *keys = [[query allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        id value = query[key];
        NSString *stringValue = [value isKindOfClass:NSString.class] ? value : [value description];
        [parts addObject:[NSString stringWithFormat:@"%@=%@",
                          DateLyricsMusixmatchPercentEncode(key),
                          DateLyricsMusixmatchPercentEncode(stringValue ?: @"")]];
    }
    return [NSString stringWithFormat:@"https://apic-desktop.musixmatch.com/ws/1.1/%@?%@",
            endpoint, [parts componentsJoinedByString:@"&"]];
}

static NSDictionary<NSString *, NSString *> *DateLyricsMusixmatchHeaders(void) {
    return @{
        @"User-Agent": @"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        @"Accept": @"application/json",
        @"Cookie": @"x-mxm-token-guid="
    };
}

static NSDictionary *DateLyricsMusixmatchJSON(NSData *data) {
    if (data.length == 0) return nil;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger index = 0;
    while (index < data.length && isspace(bytes[index])) index++;
    if (index < data.length && bytes[index] == '<') return nil;
    if (data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

NSString *DateLyricsMusixmatchTokenCachePath(void) {
    return [GetLyricsRootPath() stringByAppendingPathComponent:@"musixmatch-token.json"];
}

static void DateLyricsMusixmatchLoadTokenCache(void) {
    if (gMusixmatchTokenCacheLoaded) return;
    gMusixmatchTokenCacheLoaded = YES;
    NSData *cacheData = [NSData dataWithContentsOfFile:DateLyricsMusixmatchTokenCachePath()];
    NSDictionary *cache = cacheData.length > 0
        ? [NSJSONSerialization JSONObjectWithData:cacheData options:0 error:nil]
        : nil;
    NSString *token = [cache[@"v"] isKindOfClass:NSString.class] ? cache[@"v"] : nil;
    if (token.length > 0 && ![token hasPrefix:@"UpgradeOnly"]) {
        gMusixmatchUserToken = token;
        gMusixmatchTokenFetchedAt = [cache[@"t"] doubleValue];
    }
}

static void DateLyricsMusixmatchSaveToken(void) {
    if (gMusixmatchUserToken.length == 0) return;
    NSDictionary *cache = @{@"v": gMusixmatchUserToken, @"t": @(gMusixmatchTokenFetchedAt)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:cache options:0 error:nil];
    [data writeToFile:DateLyricsMusixmatchTokenCachePath() atomically:YES];
}

static BOOL DateLyricsMusixmatchTrackIsTrusted(NSDictionary *track, DateLyricsMusixmatchTask *task) {
    if (![track isKindOfClass:NSDictionary.class] || task.title.length == 0 || task.artist.length == 0) return NO;
    NSString *wantedTitle = DateLyricsMusixmatchNormalizedString(task.title);
    NSString *wantedArtist = DateLyricsMusixmatchNormalizedString(task.artist);
    NSString *gotTitle = DateLyricsMusixmatchNormalizedString(track[@"track_name"]);
    NSString *gotArtist = DateLyricsMusixmatchNormalizedString(track[@"artist_name"]);
    BOOL titleMatches = gotTitle.length > 0 &&
        ([gotTitle isEqualToString:wantedTitle] || [gotTitle containsString:wantedTitle] || [wantedTitle containsString:gotTitle]);
    BOOL artistMatches = gotArtist.length > 0 &&
        ([gotArtist isEqualToString:wantedArtist] || [gotArtist containsString:wantedArtist] || [wantedArtist containsString:gotArtist]);
    double returnedDuration = DateLyricsMusixmatchDouble(track[@"track_length"], 0.0);
    double difference = returnedDuration > 0.0 && task.duration > 0.0
        ? fabs(returnedDuration - task.duration) : DBL_MAX;
    if (difference != DBL_MAX && difference > 15.0) return NO;
    return (titleMatches && artistMatches) || (difference <= 4.0 && (titleMatches || artistMatches));
}

static void DateLyricsMusixmatchFinishTokenLoad(NSString *token, NSString *reason) {
    gMusixmatchTokenRequestInFlight = NO;
    if (token.length > 0 && ![token hasPrefix:@"UpgradeOnly"] && gDateLyricsMusixmatchEnabled) {
        gMusixmatchUserToken = [token copy];
        gMusixmatchTokenFetchedAt = [[NSDate date] timeIntervalSince1970];
        DateLyricsMusixmatchSaveToken();
        DateLyricsDebugLog(@"[Musixmatch] anonymous token loaded and cached");
    } else {
        DateLyricsDebugLog(@"[Musixmatch] anonymous token unavailable: %@", reason ?: @"unknown response");
    }

    NSArray<DateLyricsMusixmatchTask *> *tasks = [gMusixmatchTokenWaiters copy];
    [gMusixmatchTokenWaiters removeAllObjects];
    for (DateLyricsMusixmatchTask *task in tasks) {
        if (gDateLyricsMusixmatchEnabled && gMusixmatchUserToken.length > 0) {
            DateLyricsMusixmatchFetchMacro(task);
        } else {
            DateLyricsMusixmatchFinishTask(task, reason ?: @"Unable to obtain anonymous token");
        }
    }
}

void DateLyricsMusixmatchBeginTokenLoad(NSUInteger attempt) {
    static const NSTimeInterval delays[] = {0.0, 20.0, 45.0, 90.0};
    static const NSUInteger delayCount = sizeof(delays) / sizeof(delays[0]);
    if (attempt >= delayCount) {
        DateLyricsMusixmatchFinishTokenLoad(nil, @"Token request exhausted retries");
        return;
    }
    if (attempt == 0) {
        if (gMusixmatchTokenRequestInFlight) return;
        gMusixmatchTokenRequestInFlight = YES;
    }
    NSTimeInterval delay = delays[attempt];
    DateLyricsDebugLog(@"[Musixmatch] requesting anonymous token attempt=%lu delay=%.0f",
                       (unsigned long)(attempt + 1), delay);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), gLyricsQueue, ^{
        if (!gDateLyricsMusixmatchEnabled || gMusixmatchTokenWaiters.count == 0) {
            DateLyricsMusixmatchFinishTokenLoad(nil, @"Fallback disabled");
            return;
        }
        NSTimeInterval milliseconds = [[NSDate date] timeIntervalSince1970] * 1000.0;
        NSString *url = DateLyricsMusixmatchURL(@"token.get", @{@"t": [NSString stringWithFormat:@"%.0f", milliseconds]});
        DateLyricsMusixmatchRequest(url, DateLyricsMusixmatchHeaders(), ^(NSData *data, NSInteger status, NSError *error) {
            dispatch_async(gLyricsQueue, ^{
                NSDictionary *json = DateLyricsMusixmatchJSON(data);
                NSString *token = DateLyricsMusixmatchFindJSONValue(json, @"user_token");
                if (!error && status >= 200 && status < 300 && [token isKindOfClass:NSString.class] &&
                    token.length > 0 && ![token hasPrefix:@"UpgradeOnly"]) {
                    DateLyricsMusixmatchFinishTokenLoad(token, nil);
                } else if (attempt + 1 < delayCount) {
                    DateLyricsMusixmatchBeginTokenLoad(attempt + 1);
                } else {
                    DateLyricsMusixmatchFinishTokenLoad(nil,
                        error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)status]);
                }
            });
        });
    });
}

static void DateLyricsMusixmatchEnsureToken(DateLyricsMusixmatchTask *task, BOOL forceRefresh) {
    if (!task) return;
    DateLyricsMusixmatchLoadTokenCache();
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - gMusixmatchTokenFetchedAt;
    if (!forceRefresh && gMusixmatchUserToken.length > 0 && age >= 0.0 && age < 6.0 * 60.0 * 60.0) {
        DateLyricsDebugLog(@"[Musixmatch] using cached anonymous token age=%.0fs", age);
        DateLyricsMusixmatchFetchMacro(task);
        return;
    }
    if (![gMusixmatchTokenWaiters containsObject:task]) [gMusixmatchTokenWaiters addObject:task];
    if (forceRefresh) {
        gMusixmatchUserToken = nil;
        gMusixmatchTokenFetchedAt = 0.0;
    }
    DateLyricsMusixmatchBeginTokenLoad(0);
}

static BOOL DateLyricsMusixmatchCompleteWithSubtitle(DateLyricsMusixmatchTask *task, NSString *failureReason) {
    if (task.wordSyncOnly) {
        DateLyricsMusixmatchFinishTask(task, failureReason ?: @"No word-synced upgrade available");
        return NO;
    }
    NSArray<DateLyricsTimedLine *> *lines = DateLyricsMusixmatchLinesFromLRC(task.subtitleBody, task.duration);
    if (lines.count > 0 && DateLyricsSerializeMusixmatchLines(task.storeID, lines)) {
        DateLyricsDebugLog(@"[Musixmatch] loaded %lu line-synced lines for storeID=%ld",
                           (unsigned long)lines.count, (long)task.storeID);
        DateLyricsMusixmatchFinishTask(task, nil);
        return YES;
    }
    DateLyricsMusixmatchFinishTask(task, failureReason ?: @"No synchronized lyrics");
    return NO;
}

static void DateLyricsMusixmatchFetchRichsync(DateLyricsMusixmatchTask *task) {
    NSString *url = DateLyricsMusixmatchURL(@"track.richsync.get", @{
        @"commontrack_id": @(task.commontrackID),
        @"usertoken": gMusixmatchUserToken ?: @""
    });
    DateLyricsDebugLog(@"[Musixmatch] requesting rich-sync storeID=%ld commontrack=%ld",
                       (long)task.storeID, (long)task.commontrackID);
    DateLyricsMusixmatchRequest(url, DateLyricsMusixmatchHeaders(), ^(NSData *data, NSInteger status, NSError *error) {
        dispatch_async(gLyricsQueue, ^{
            if (!gDateLyricsMusixmatchEnabled || ![gMusixmatchPendingStoreIDs containsObject:@(task.storeID)]) {
                DateLyricsMusixmatchFinishTask(task, @"Fallback disabled");
                return;
            }
            NSDictionary *json = DateLyricsMusixmatchJSON(data);
            id body = DateLyricsMusixmatchFindJSONValue(json, @"richsync_body");
            NSArray<DateLyricsTimedLine *> *lines = DateLyricsMusixmatchLinesFromBody(body, task.duration);
            BOOL hasWordTiming = NO;
            for (DateLyricsTimedLine *line in lines) {
                if (line.words.count > 0) {
                    hasWordTiming = YES;
                    break;
                }
            }
            DateLyricsDebugLog(@"[Musixmatch] rich-sync response status=%ld parsedLines=%lu",
                               (long)status, (unsigned long)lines.count);
            if (!error && status >= 200 && status < 300 && lines.count > 0 && hasWordTiming &&
                DateLyricsSerializeMusixmatchLines(task.storeID, lines)) {
                DateLyricsDebugLog(@"[Musixmatch] loaded %lu word-synced lines for storeID=%ld",
                                   (unsigned long)lines.count, (long)task.storeID);
                DateLyricsMusixmatchFinishTask(task, nil);
                return;
            }
            DateLyricsMusixmatchCompleteWithSubtitle(task, @"No usable rich-sync or subtitle");
        });
    });
}

void DateLyricsMusixmatchFetchMacro(DateLyricsMusixmatchTask *task) {
    if (!task || gMusixmatchUserToken.length == 0) {
        DateLyricsMusixmatchFinishTask(task, @"Missing anonymous token");
        return;
    }
    NSDictionary *parameters = @{
        @"namespace": @"lyrics_richsynched",
        @"subtitle_format": @"lrc",
        @"q_track": task.title ?: @"",
        @"q_artist": task.artist ?: @"",
        @"q_album": task.album ?: @"",
        @"q_duration": task.duration > 0.0 ? @((NSInteger)llround(task.duration)) : @"",
        @"usertoken": gMusixmatchUserToken
    };
    DateLyricsDebugLog(@"[Musixmatch] matching storeID=%ld title=%@ artist=%@ duration=%.0f",
                       (long)task.storeID, task.title ?: @"", task.artist ?: @"", task.duration);
    DateLyricsMusixmatchRequest(DateLyricsMusixmatchURL(@"macro.subtitles.get", parameters),
                                DateLyricsMusixmatchHeaders(),
                                ^(NSData *data, NSInteger status, NSError *error) {
        dispatch_async(gLyricsQueue, ^{
            if (!gDateLyricsMusixmatchEnabled || ![gMusixmatchPendingStoreIDs containsObject:@(task.storeID)]) {
                DateLyricsMusixmatchFinishTask(task, @"Fallback disabled");
                return;
            }
            NSDictionary *json = DateLyricsMusixmatchJSON(data);
            NSInteger apiStatus = [DateLyricsMusixmatchFindJSONValue(json, @"status_code") integerValue];
            DateLyricsDebugLog(@"[Musixmatch] match response http=%ld api=%ld bytes=%lu",
                               (long)status, (long)apiStatus, (unsigned long)data.length);
            if (apiStatus == 401 && !task.refreshedToken) {
                task.refreshedToken = YES;
                DateLyricsDebugLog(@"[Musixmatch] token exhausted; refreshing once");
                DateLyricsMusixmatchEnsureToken(task, YES);
                return;
            }
            if (error || status < 200 || status >= 300 || !json) {
                DateLyricsMusixmatchFinishTask(task,
                    error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)status]);
                return;
            }

            id matcher = DateLyricsMusixmatchFindJSONValue(json, @"matcher.track.get");
            NSDictionary *track = DateLyricsMusixmatchFindJSONValue(matcher, @"track");
            if (![track isKindOfClass:NSDictionary.class] ||
                !DateLyricsMusixmatchTrackIsTrusted(track, task) ||
                [track[@"instrumental"] boolValue]) {
                DateLyricsDebugLog(@"[Musixmatch] rejected want title=%@ artist=%@ duration=%.0f; got track_name=%@ artist_name=%@ track_length=%@ instrumental=%@ keys=%lu",
                                   task.title ?: @"", task.artist ?: @"", task.duration,
                                   [track isKindOfClass:NSDictionary.class] ? track[@"track_name"] : @"<no track>",
                                   [track isKindOfClass:NSDictionary.class] ? track[@"artist_name"] : @"",
                                   [track isKindOfClass:NSDictionary.class] ? track[@"track_length"] : @"",
                                   [track isKindOfClass:NSDictionary.class] ? track[@"instrumental"] : @"",
                                   (unsigned long)([matcher isKindOfClass:NSDictionary.class] ? [(NSDictionary *)matcher count] : 0));
                DateLyricsMusixmatchFinishTask(task, @"No trustworthy non-instrumental match");
                return;
            }
            task.commontrackID = [track[@"commontrack_id"] integerValue];
            id subtitleBody = DateLyricsMusixmatchFindJSONValue(json, @"subtitle_body");
            task.subtitleBody = [subtitleBody isKindOfClass:NSString.class] ? subtitleBody : nil;
            BOOL hasRichsync = [track[@"has_richsync"] boolValue];
            DateLyricsDebugLog(@"[Musixmatch] matched title=%@ artist=%@ commontrack=%ld richsync=%d subtitle=%d",
                               track[@"track_name"] ?: @"", track[@"artist_name"] ?: @"",
                               (long)task.commontrackID, hasRichsync, task.subtitleBody.length > 0);
            if (hasRichsync && task.commontrackID > 0) {
                DateLyricsMusixmatchFetchRichsync(task);
            } else {
                DateLyricsMusixmatchCompleteWithSubtitle(task, @"Matched track has no synchronized lyrics");
            }
        });
    });
}

NSString *DateLyricsMetadataString(id metadata, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        SEL selector = NSSelectorFromString(key);
        if (![metadata respondsToSelector:selector]) continue;
        @try {
            id value = [metadata valueForKey:key];
            if ([value isKindOfClass:NSString.class] && [value length] > 0) return [value copy];
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

NSTimeInterval DateLyricsMetadataDuration(id metadata) {
    for (NSString *key in @[@"duration", @"durationInSeconds", @"trackDuration", @"playbackDuration", @"totalTime"]) {
        if (![metadata respondsToSelector:NSSelectorFromString(key)]) continue;
        @try {
            id value = [metadata valueForKey:key];
            double duration = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
            if (!isfinite(duration) || duration <= 0.0) continue;
            if ([key isEqualToString:@"totalTime"] && duration > 10000.0) duration /= 1000.0;
            return duration;
        } @catch (__unused NSException *exception) {
        }
    }
    return 0.0;
}

void DateLyricsStartMusixmatchFallback(NSInteger storeID, NSString *title, NSString *artist,
                                              NSString *album, NSTimeInterval duration, BOOL wordSyncOnly) {
    if (!gDateLyricsMusixmatchEnabled || storeID <= 0) return;
    if (title.length == 0 || artist.length == 0) {
        DateLyricsDebugLog(@"[Musixmatch] storeID=%ld skipped: title or artist missing", (long)storeID);
        return;
    }
    DateLyricsDebugLog(@"[Musixmatch] fallback start storeID=%ld title=%@ artist=%@ album=%@ duration=%.0f wordOnly=%d",
                       (long)storeID, title, artist, album ?: @"", duration, wordSyncOnly);
    if ([gMusixmatchPendingStoreIDs containsObject:@(storeID)]) return;
    if (wordSyncOnly && [gMusixmatchWordUpgradeAttemptedStoreIDs containsObject:@(storeID)]) return;
    NSTimeInterval retryAfter = [gMusixmatchFailureRetryAfter[@(storeID)] doubleValue];
    if (retryAfter > [[NSDate date] timeIntervalSince1970]) {
        DateLyricsDebugLog(@"[Musixmatch] storeID=%ld skipped during failure cooldown", (long)storeID);
        return;
    }

    NSString *scorePath = [GetLyricsRootPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"score-%ld.json", (long)storeID]];
    NSData *cachedScoreData = [NSData dataWithContentsOfFile:scorePath];
    DateLyricsScore *cachedScore = cachedScoreData ? [[DateLyricsScore alloc] initWithJSONData:cachedScoreData] : nil;
    BOOL shouldTryWordUpgrade = wordSyncOnly && cachedScore.trackId == storeID &&
        cachedScore.lines.count > 0 && !cachedScore.hasWordTiming;
    BOOL isLoadingScore = [cachedScore.source isEqualToString:@"musixmatch-loading"];
    if (cachedScore.trackId == storeID && cachedScore.lines.count > 0 &&
        !shouldTryWordUpgrade && !isLoadingScore) {
        DateLyricsDebugLog(@"[Musixmatch] using cached score storeID=%ld source=%@ lines=%lu",
                           (long)storeID, cachedScore.source ?: @"apple", (unsigned long)cachedScore.lines.count);
        return;
    }

    DateLyricsMusixmatchTask *task = [DateLyricsMusixmatchTask new];
    task.storeID = storeID;
    task.title = title;
    task.artist = artist;
    task.album = album;
    task.duration = duration;
    task.wordSyncOnly = wordSyncOnly;
    [gMusixmatchPendingStoreIDs addObject:@(storeID)];
    if (wordSyncOnly) [gMusixmatchWordUpgradeAttemptedStoreIDs addObject:@(storeID)];
    DateLyricsWriteMusixmatchLoadingScore(task);
    DateLyricsMusixmatchEnsureToken(task, NO);
}
