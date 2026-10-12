#import "DateLyricsInternal.h"

%ctor {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsCache = [[NSMutableDictionary alloc] init];
        gWordLyricsCache = [[NSMutableDictionary alloc] init];
        gLyricsCacheOrder = [NSMutableArray array];
        gUnsynchronizedLyricsIDs = [NSMutableSet set];
        gMusixmatchPendingStoreIDs = [NSMutableSet set];
        gMusixmatchWordUpgradeAttemptedStoreIDs = [NSMutableSet set];
        gMusixmatchFailureRetryAfter = [NSMutableDictionary dictionary];
        gMusixmatchTokenWaiters = [NSMutableArray array];
        gLyricsQueue = dispatch_queue_create("com.shalamand3r.datelyrics.queue", DISPATCH_QUEUE_SERIAL);
        gLyricsTaskQueue = [NSMutableArray array];
        gPendingLyricsIDs = [NSMutableSet set];
    });

    DateLyricsReloadPrefs(NULL, NULL, NULL, NULL, NULL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsReloadPrefs, CFSTR("com.shalamand3r.datelyrics/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsClearCaches, CFSTR("com.shalamand3r.datelyrics/ClearCaches"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    BOOL isSpringBoardHost = DateLyricsIsSpringBoardHost();

    if (isSpringBoardHost) {
        DateLyricsInitSpringBoardHooks();
    } else if (DateLyricsIsMusicHost()) {
        DateLyricsInitMusicHooks();
    } else if (DateLyricsIsYouTubeMusicHost()) {
        DateLyricsInitYouTubeMusicHooks();
    }
}
