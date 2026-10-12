#pragma once

#import "DateLyricsModels.h"
#import "DateLyricsPrivateAPI.h"

#include <pthread.h>

typedef struct {
    BOOL showAdlibs;
    BOOL smoothSweep;
    BOOL showInterlude;
    NSInteger interludeStyle;
} DateLyricsResolverOptions;

FOUNDATION_EXPORT DateLyricsTimedLine *DateLyricsFilteredLine(DateLyricsTimedLine *line, BOOL showAdlibs);
FOUNDATION_EXPORT NSDictionary *DateLyricsResolvePayload(DateLyricsScore *score, NSTimeInterval elapsedTime, NSInteger *cursorInOut, NSTimeInterval *nextTriggerOut, NSTimeInterval *nextLineTriggerOut, DateLyricsResolverOptions options);

// Shared resolver/cache state consumed by DateLyrics.xm hooks.
FOUNDATION_EXPORT dispatch_queue_t gLyricsQueue;
FOUNDATION_EXPORT ICURLSession *gSession;
FOUNDATION_EXPORT ICMusicKitRequestContext *gRequestContext;
FOUNDATION_EXPORT NSMutableArray *gLyricsTaskQueue;
FOUNDATION_EXPORT NSMutableSet<NSNumber *> *gPendingLyricsIDs;
FOUNDATION_EXPORT BOOL gIsProcessingQueue;
FOUNDATION_EXPORT NSString *gLyricsRootPath;
FOUNDATION_EXPORT NSMutableDictionary<NSNumber *, NSArray<MSVLyricsLine *> *> *gLyricsCache;
FOUNDATION_EXPORT NSMutableDictionary<NSNumber *, NSArray<DateLyricsTimedLine *> *> *gWordLyricsCache;
FOUNDATION_EXPORT NSMutableArray<NSNumber *> *gLyricsCacheOrder;
FOUNDATION_EXPORT NSMutableSet<NSNumber *> *gUnsynchronizedLyricsIDs;
FOUNDATION_EXPORT NSMutableSet<NSNumber *> *gMusixmatchPendingStoreIDs;
FOUNDATION_EXPORT NSMutableSet<NSNumber *> *gMusixmatchWordUpgradeAttemptedStoreIDs;
FOUNDATION_EXPORT NSMutableDictionary<NSNumber *, NSNumber *> *gMusixmatchFailureRetryAfter;
FOUNDATION_EXPORT NSMutableArray *gMusixmatchTokenWaiters;
FOUNDATION_EXPORT BOOL gMusixmatchTokenRequestInFlight;
FOUNDATION_EXPORT BOOL gMusixmatchTokenCacheLoaded;
FOUNDATION_EXPORT NSString *gMusixmatchUserToken;
FOUNDATION_EXPORT NSTimeInterval gMusixmatchTokenFetchedAt;
FOUNDATION_EXPORT pthread_mutex_t gLyricsCacheMutex;
FOUNDATION_EXPORT __weak MPNowPlayingContentItem *gCurrentContentItem;
