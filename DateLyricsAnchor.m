// Publishes the playback anchor (position and rate) to SpringBoard.

#import "DateLyricsInternal.h"

void DateLyricsPublishAnchor(NSInteger storeID, double elapsedTime, float rate, BOOL isSeek) {
    if (storeID <= 0) return;
    // NSJSONSerialization throws (it does not return an error) on NaN or
    // infinity, which aborts Music.
    if (!isfinite(elapsedTime) || !isfinite(rate)) return;
    NSMutableDictionary *anchor = [NSMutableDictionary dictionary];
    anchor[@"protocol"] = @3;
    anchor[@"kind"] = @"anchor";
    anchor[@"trackId"] = @(storeID);
    anchor[@"elapsed"] = @(elapsedTime);
    anchor[@"rate"] = @(rate);
    anchor[@"seek"] = @(isSeek);
    anchor[@"atHostTime"] = @(DateLyricsMonotonicTime());
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    if (bundleIdentifier.length > 0) anchor[@"bundleIdentifier"] = bundleIdentifier;
    static NSInteger revision = 0;
    anchor[@"revision"] = @(++revision);
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:anchor options:0 error:nil];
    if (jsonData) {
        NSString *path = [GetLyricsRootPath() stringByAppendingPathComponent:@"anchor.json"];
        NSString *tempPath = [path stringByAppendingPathExtension:@"tmp"];
        NSError *writeError = nil;
        if ([jsonData writeToFile:tempPath options:NSDataWritingAtomic error:&writeError]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            NSError *moveError = nil;
            if ([[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:path error:&moveError]) {
                if (DateLyricsIsYouTubeMusicHost()) {
                    DateLyricsDebugLog(@"[YTM] anchor persisted trackId=%ld elapsed=%.2f rate=%.2f seek=%d path=%@",
                        (long)storeID, elapsedTime, rate, isSeek, path);
                }
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                    DateLyricsAnchorChangedNotification(), NULL, NULL, YES);
            } else if (DateLyricsIsYouTubeMusicHost()) {
                DateLyricsDebugLog(@"[YTM] anchor write failed path=%@ error=%@", path, moveError);
            }
        } else if (DateLyricsIsYouTubeMusicHost()) {
            DateLyricsDebugLog(@"[YTM] anchor temp write failed path=%@ error=%@", tempPath, writeError);
        }
    } else if (DateLyricsIsYouTubeMusicHost()) {
        DateLyricsDebugLog(@"[YTM] anchor JSON serialization failed trackId=%ld elapsed=%.2f rate=%.2f",
            (long)storeID, elapsedTime, rate);
    }
}
