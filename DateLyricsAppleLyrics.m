// Apple Music lyric ingestion: TTML parsing and the download task queue.

#import "DateLyricsInternal.h"

BOOL DateLyricsIsUnsynchronizedLyricsID(NSInteger lyricsAdamID) {
    if (lyricsAdamID <= 0) return NO;
    NSNumber *key = @(lyricsAdamID);
    pthread_mutex_lock(&gLyricsCacheMutex);
    BOOL known = [gUnsynchronizedLyricsIDs containsObject:key];
    pthread_mutex_unlock(&gLyricsCacheMutex);
    return known;
}

void DateLyricsSetUnsynchronizedLyricsID(NSInteger lyricsAdamID, BOOL unsynchronized) {
    if (lyricsAdamID <= 0) return;
    NSNumber *key = @(lyricsAdamID);
    pthread_mutex_lock(&gLyricsCacheMutex);
    if (unsynchronized) {
        [gUnsynchronizedLyricsIDs addObject:key];
    } else {
        [gUnsynchronizedLyricsIDs removeObject:key];
    }
    pthread_mutex_unlock(&gLyricsCacheMutex);
}

static BOOL DateLyricsXMLDeclaresNoTiming(NSData *data) {
    if (!data.length) return NO;

    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xml.length == 0) return NO;

    // Apple marks transcript-only TTML explicitly.  Check the document before
    // invoking either parser because the private parser still returns one line
    // per <p>, all at time zero, for this format.
    NSRange doubleQuoted = [xml rangeOfString:@"itunes:timing=\"None\"" options:NSCaseInsensitiveSearch];
    if (doubleQuoted.location != NSNotFound) return YES;
    NSRange singleQuoted = [xml rangeOfString:@"itunes:timing='None'" options:NSCaseInsensitiveSearch];
    return singleQuoted.location != NSNotFound;
}

BOOL ParseLyricsData(NSData *data, NSInteger iTunesStoreID, __unused NSInteger lyricsAdamID,
                            BOOL *unsynchronizedOut, BOOL *wordTimingOut) {
    if (unsynchronizedOut) *unsynchronizedOut = NO;
    if (wordTimingOut) *wordTimingOut = NO;
    if (!data.length || iTunesStoreID <= 0) return NO;

    if (DateLyricsXMLDeclaresNoTiming(data)) {
        if (unsynchronizedOut) *unsynchronizedOut = YES;
        DateLyricsInvalidateSerializedScore(iTunesStoreID);
        DateLyricsDebugLog(@"[Parser] Ignoring TTML transcript marked itunes:timing=None for storeID=%ld", (long)iTunesStoreID);
        return NO;
    }

    pthread_mutex_lock(&gLyricsCacheMutex);
    NSNumber *storeIDKey = @(iTunesStoreID);
    NSArray *cachedLineItems = gLyricsCache[storeIDKey];
    NSArray *cachedWordLines = gWordLyricsCache[storeIDKey];
    BOOL cachedLineTiming = DateLyricsLineItemsHaveTiming(cachedLineItems);
    BOOL cachedWordTiming = DateLyricsWordLinesHaveTiming(cachedWordLines);
    if ((cachedLineItems.count > 0 && cachedLineTiming) || (cachedWordLines.count > 0 && cachedWordTiming)) {
        if (wordTimingOut) *wordTimingOut = cachedWordTiming;
        DateLyricsTouchMemoryCacheLocked(storeIDKey);
        pthread_mutex_unlock(&gLyricsCacheMutex);
        return YES;
    }
    [gLyricsCache removeObjectForKey:storeIDKey];
    [gWordLyricsCache removeObjectForKey:storeIDKey];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    NSArray<DateLyricsTimedLine *> *wordLines = DateLyricsParseWordTimedLines(data);
    NSError *parseError = nil;
    NSMutableArray<MSVLyricsLine *> *lyricLines = nil;
    Class parserClass = objc_getClass("MSVLyricsTTMLParser");
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

    // A plain transcript has text but no timeline. Treat it as no lyrics for
    // DateLyrics purposes; displaying it would make one arbitrary line occupy
    // the date view for the entire song. Prefer word timing when available, or
    // otherwise valid line timing from Apple's parser.
    if (!DateLyricsWordLinesHaveTiming(wordLines)) wordLines = nil;
    if (!DateLyricsLineItemsHaveTiming(lyricLines)) lyricLines = nil;
    if (lyricLines.count == 0 && wordLines.count == 0) {
        if (unsynchronizedOut) *unsynchronizedOut = YES;
        DateLyricsInvalidateSerializedScore(iTunesStoreID);
        DateLyricsDebugLog(@"[Parser] Ignoring unsynchronized lyrics for storeID=%ld", (long)iTunesStoreID);
        return NO;
    }

    pthread_mutex_lock(&gLyricsCacheMutex);
    if (lyricLines.count > 0) {
        gLyricsCache[storeIDKey] = [lyricLines copy];
    }
    if (wordLines.count > 0) {
        gWordLyricsCache[storeIDKey] = wordLines;
    }
    DateLyricsTouchMemoryCacheLocked(storeIDKey);
    pthread_mutex_unlock(&gLyricsCacheMutex);

    // Write score JSON to disk for the consumer (Phase 2)
    DateLyricsSerializeScore(iTunesStoreID, wordLines, lyricLines);
    if (wordTimingOut) *wordTimingOut = wordLines.count > 0;
    
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

void ProcessNextTask(void) {
    if (!gSession || !gRequestContext || [gLyricsTaskQueue count] == 0) {
        gIsProcessingQueue = NO;
        return;
    }
    
    gIsProcessingQueue = YES;
    LyricsTask *task = [gLyricsTaskQueue firstObject];
    [gLyricsTaskQueue removeObjectAtIndex:0];
    
    ICMusicKitURLRequest *request = [[objc_getClass("ICMusicKitURLRequest") alloc] initWithURL:task.lyricURL requestContext:gRequestContext];
    [gSession enqueueDataRequest:request withCompletionHandler:^(ICURLResponse *response, NSError *error) {
        dispatch_async(gLyricsQueue, ^{
            BOOL taskFailed = NO;
            
            if (error) {
                taskFailed = YES;
            } else if (![response.bodyData isKindOfClass:[NSData class]]) {
                taskFailed = YES;
            } else {
                id object = response.bodyData.length > 0 ? [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:nil] : nil;
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
                    BOOL unsynchronized = NO;
                    BOOL hasWordTiming = NO;
                    if (data.length && ParseLyricsData(data, task.iTunesStoreID, task.lyricsAdamID,
                                                       &unsynchronized, &hasWordTiming)) {
                        DateLyricsSetUnsynchronizedLyricsID(task.lyricsAdamID, NO);
                        if (![data writeToFile:task.lyricsFilePath atomically:YES]) {
                            taskFailed = YES;
                        } else {
                            DateLyricsPruneDiskCache();
                            if (!hasWordTiming) {
                                DateLyricsStartMusixmatchFallback(task.iTunesStoreID, task.fallbackTitle,
                                    task.fallbackArtist, task.fallbackAlbum, task.fallbackDuration, YES);
                            }
                        }
                    } else {
                        taskFailed = !unsynchronized;
                        if (unsynchronized) {
                            DateLyricsSetUnsynchronizedLyricsID(task.lyricsAdamID, YES);
                            DateLyricsDebugLog(@"[Parser] Marked lyricsAdamID=%ld as transcript-only; skipping retries", (long)task.lyricsAdamID);
                            DateLyricsStartMusixmatchFallback(task.iTunesStoreID, task.fallbackTitle,
                                task.fallbackArtist, task.fallbackAlbum, task.fallbackDuration, NO);
                        }
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

            if (task.retryCount >= 3) {
                DateLyricsStartMusixmatchFallback(task.iTunesStoreID, task.fallbackTitle,
                    task.fallbackArtist, task.fallbackAlbum, task.fallbackDuration, NO);
            }
            
            ProcessNextTask();
        });
    }];
}

void AddTaskToQueue(NSInteger iTunesStoreID, NSInteger lyricsAdamID, NSURL *lyricURL,
                           NSString *lyricsFilePath, NSString *fallbackTitle, NSString *fallbackArtist,
                           NSString *fallbackAlbum, NSTimeInterval fallbackDuration) {
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
    task.fallbackTitle = fallbackTitle;
    task.fallbackArtist = fallbackArtist;
    task.fallbackAlbum = fallbackAlbum;
    task.fallbackDuration = fallbackDuration;
    
    [gLyricsTaskQueue addObject:task];
    [gPendingLyricsIDs addObject:@(lyricsAdamID)];
    
    if (!gIsProcessingQueue) {
        ProcessNextTask();
    }
}
