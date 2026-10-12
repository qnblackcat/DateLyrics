#import "DateLyricsInternal.h"


%group DateLyricsYouTubeMusic

static NSInteger gDateLyricsYouTubeMusicTrackID = 0;
static NSString *gDateLyricsYouTubeMusicVideoID = nil;
static float gDateLyricsYouTubeMusicRate = 0.0f;

static void DateLyricsYouTubeMusicPublishAnchorIfNeeded(NSInteger trackID, double elapsed, float rate) {
    if (trackID <= 0 || !isfinite(elapsed)) return;
    rate = isfinite(rate) ? MAX(0.0f, rate) : 0.0f;

    static NSInteger lastTrackID = 0;
    static double lastElapsed = -1.0;
    static double lastHostTime = -1.0;
    static float lastRate = -1.0f;
    double now = DateLyricsMonotonicTime();
    BOOL trackChanged = trackID != lastTrackID;
    double expected = lastElapsed + ((now - lastHostTime) * MAX(0.0f, lastRate));
    BOOL seeked = !trackChanged && lastHostTime >= 0.0 && fabs(elapsed - expected) > 0.65;
    BOOL pausedPositionChanged = !trackChanged && rate <= 0.0f && lastElapsed >= 0.0 &&
        fabs(elapsed - lastElapsed) > 0.05;
    BOOL rateChanged = trackChanged || lastRate < 0.0f || fabsf(rate - lastRate) > 0.001f;
    BOOL refreshDue = lastHostTime < 0.0 || now - lastHostTime >= 4.0;
    if (!trackChanged && rate <= 0.0f && lastElapsed >= 0.0 && elapsed < lastElapsed - 0.05) {
        seeked = YES;
    }

    if (trackChanged || seeked || pausedPositionChanged || rateChanged || refreshDue) {
        DateLyricsDebugLog(@"[YTM] anchor candidate trackId=%ld elapsed=%.2f rate=%.2f trackChanged=%d seek=%d pausedMove=%d rateChanged=%d refresh=%d",
            (long)trackID, elapsed, rate, trackChanged, seeked, pausedPositionChanged, rateChanged, refreshDue);
        lastTrackID = trackID;
        lastElapsed = elapsed;
        lastHostTime = now;
        lastRate = rate;
        DateLyricsPublishAnchor(trackID, elapsed, rate, seeked);
    }
}

static NSInteger DateLyricsYouTubeMusicTrackID(NSString *contentIdentifier, NSString *title, NSString *artist) {
    NSString *identity = contentIdentifier.length > 0
        ? [@"video:" stringByAppendingString:contentIdentifier]
        : (title.length > 0 || artist.length > 0
            ? [NSString stringWithFormat:@"%@\n%@", title.lowercaseString ?: @"", artist.lowercaseString ?: @""]
            : nil);
    if (identity.length == 0) return 0;
    identity = [identity stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const uint8_t *bytes = (const uint8_t *)identity.UTF8String;
    if (!bytes) return 0;
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger index = 0; bytes[index] != 0; index++) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }
    // Keep the synthetic ID positive and away from zero, which is reserved for
    // an unknown track throughout the score protocol.
    return (NSInteger)((hash & 0x3fffffffffffffffULL) | 1ULL);
}

// The playback controller is the authoritative clock. MPNowPlayingInfoCenter
// dictionaries carry a snapshot that can lag behind it, so metadata updates
// extrapolate from the last controller sample instead of trusting their own
// elapsed value (otherwise anchors jump backwards and every one looks like a seek).
static double gDateLyricsYouTubeMusicSampleElapsed = -1.0;
static double gDateLyricsYouTubeMusicSampleHostTime = -1.0;

static void DateLyricsYouTubeMusicRecordControllerSample(double elapsed) {
    if (!isfinite(elapsed)) return;
    gDateLyricsYouTubeMusicSampleElapsed = elapsed;
    gDateLyricsYouTubeMusicSampleHostTime = DateLyricsMonotonicTime();
}

// Called on gLyricsQueue.
static double DateLyricsYouTubeMusicBestElapsed(double snapshotElapsed) {
    if (gDateLyricsYouTubeMusicSampleHostTime < 0.0) return snapshotElapsed;
    double age = DateLyricsMonotonicTime() - gDateLyricsYouTubeMusicSampleHostTime;
    if (age < 0.0 || age > 1.5) return snapshotElapsed;
    return gDateLyricsYouTubeMusicSampleElapsed + age * MAX(0.0f, gDateLyricsYouTubeMusicRate);
}

// Called on gLyricsQueue. A new video ID means a new track, even when the
// now-playing metadata has not arrived yet.
static void DateLyricsYouTubeMusicAdoptVideoID(NSString *videoID) {
    if (videoID.length == 0 || [videoID isEqualToString:gDateLyricsYouTubeMusicVideoID]) return;
    gDateLyricsYouTubeMusicVideoID = [videoID copy];
    gDateLyricsYouTubeMusicTrackID = DateLyricsYouTubeMusicTrackID(videoID, nil, nil);
    DateLyricsDebugLog(@"[YTM] video changed video=%@ trackId=%ld", videoID, (long)gDateLyricsYouTubeMusicTrackID);
}

// Metadata arrives through MPNowPlayingInfoCenter.
// contentIdentifier may be nil; then the video ID seen by the playback
// callbacks keeps the track identity consistent with them.
static void DateLyricsYouTubeMusicHandleMetadata(NSString *title, NSString *artist,
    NSString *contentIdentifier, double elapsed, double duration, float rate, NSString *source) {
    if (!DateLyricsIsYouTubeMusicHost()) return;
    if (!gDateLyricsEnabled) {
        DateLyricsDebugLog(@"[YTM] metadata ignored: tweak disabled");
        return;
    }
    if (!isfinite(elapsed)) {
        DateLyricsDebugLog(@"[YTM] metadata ignored (%@): invalid elapsed=%f", source, elapsed);
        return;
    }
    float normalizedRate = isfinite(rate) ? MAX(0.0f, rate) : 0.0f;
    dispatch_async(gLyricsQueue, ^{
        NSString *identity = contentIdentifier.length > 0 ? contentIdentifier : gDateLyricsYouTubeMusicVideoID;
        NSInteger trackID = DateLyricsYouTubeMusicTrackID(identity, title, artist);
        if (trackID <= 0) {
            DateLyricsDebugLog(@"[YTM] metadata ignored (%@): no identity title=%@ artist=%@",
                source, title ?: @"<nil>", artist ?: @"<nil>");
            return;
        }
        DateLyricsDebugLog(@"[YTM] metadata (%@) title=%@ artist=%@ id=%@ trackId=%ld elapsed=%.2f duration=%.2f rate=%.2f",
            source, title ?: @"<nil>", artist ?: @"<nil>", identity ?: @"<nil>",
            (long)trackID, elapsed, duration, normalizedRate);
        // Extrapolate with the previous rate: a rate change is stamped at the
        // moment of the change, not after the new rate has been applied.
        double bestElapsed = DateLyricsYouTubeMusicBestElapsed(elapsed);
        gDateLyricsYouTubeMusicTrackID = trackID;
        gDateLyricsYouTubeMusicRate = normalizedRate;
        DateLyricsYouTubeMusicPublishAnchorIfNeeded(trackID, bestElapsed, normalizedRate);
    });
}

static NSString *DateLyricsYTMString(id value) {
    return [value isKindOfClass:NSString.class] ? [(NSString *)value copy] : nil;
}

// ---- Native YouTube Music lyrics -------------------------------------------
// Opening the lyrics tab makes the app decode a panel response that contains a
// "timed_lyrics.eml" component. Its data is a repeated message per line:
//   { 1: "text", 2: { 1: startMs, 2: endMs, 3: { 1: "index" } } }
// Walk the protobuf wire format (no generated classes needed) to find the
// message holding those lines and turn them into a score.
static BOOL DLReadVarint(const uint8_t *b, size_t n, size_t *i, uint64_t *out) {
    uint64_t value = 0;
    for (int shift = 0; shift < 64 && *i < n; shift += 7) {
        uint8_t byte = b[(*i)++];
        value |= (uint64_t)(byte & 0x7f) << shift;
        if (!(byte & 0x80)) { *out = value; return YES; }
    }
    return NO;
}

// Calls block for every field of the message in [b, b+n). Returns NO when the
// bytes are not a well-formed message.
static BOOL DLEachField(const uint8_t *b, size_t n,
    void (^block)(uint32_t field, uint64_t varint, const uint8_t *p, size_t length, BOOL isLengthDelimited)) {
    size_t i = 0;
    while (i < n) {
        uint64_t key;
        if (!DLReadVarint(b, n, &i, &key)) return NO;
        uint32_t field = (uint32_t)(key >> 3);
        if (field == 0) return NO;
        switch (key & 7) {
            case 0: { uint64_t v; if (!DLReadVarint(b, n, &i, &v)) return NO; block(field, v, NULL, 0, NO); break; }
            case 1: if (n - i < 8) return NO; i += 8; break;
            case 5: if (n - i < 4) return NO; i += 4; break;
            case 2: {
                uint64_t length;
                if (!DLReadVarint(b, n, &i, &length) || length > n - i) return NO;
                block(field, 0, b + i, (size_t)length, YES);
                i += (size_t)length;
                break;
            }
            default: return NO;
        }
    }
    return YES;
}

static BOOL DLParseLyricLine(const uint8_t *b, size_t n, NSString **text, double *begin, double *end) {
    __block NSString *lineText = nil;
    __block uint64_t startMs = 0, endMs = 0;
    __block BOOL hasStart = NO, hasEnd = NO;
    BOOL ok = DLEachField(b, n, ^(uint32_t field, uint64_t varint, const uint8_t *p, size_t length, BOOL isLengthDelimited) {
        if (field == 1 && isLengthDelimited && length > 0 && !lineText) {
            NSString *candidate = [[NSString alloc] initWithBytes:p length:length encoding:NSUTF8StringEncoding];
            if (candidate.length > 0 && [candidate rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound) {
                lineText = candidate;
            }
        } else if (field == 2 && isLengthDelimited && !hasStart) {
            DLEachField(p, length, ^(uint32_t f, uint64_t v, const uint8_t *q, size_t l, BOOL d) {
                if (!d && f == 1) { startMs = v; hasStart = YES; }
                else if (!d && f == 2) { endMs = v; hasEnd = YES; }
            });
        }
    });
    if (!ok || !lineText || !hasStart || !hasEnd) return NO;
    *text = lineText;
    *begin = startMs / 1000.0;
    *end = endMs / 1000.0;
    return YES;
}

// Returns the message level that has the most line-shaped children.
static void DLCollectLyricLines(const uint8_t *b, size_t n, int depth, NSMutableArray<NSDictionary *> *__strong *best) {
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    DLEachField(b, n, ^(uint32_t field, uint64_t varint, const uint8_t *p, size_t length, BOOL isLengthDelimited) {
        if (!isLengthDelimited || length < 4) return;
        NSString *text = nil;
        double begin = 0, end = 0;
        if (DLParseLyricLine(p, length, &text, &begin, &end)) {
            [candidates addObject:@{@"text": text, @"begin": @(begin), @"end": @(end)}];
        } else if (depth < 12) {
            DLCollectLyricLines(p, length, depth + 1, best);
        }
    });
    if (candidates.count > (*best).count) *best = candidates;
}

static void DateLyricsYTMTryExtractTimedLyrics(NSData *data) {
    if (![data isKindOfClass:NSData.class] || data.length < 2000 || !DateLyricsIsYouTubeMusicHost() || !gDateLyricsEnabled) return;
    static const char marker[] = "timed_lyrics.eml";
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    const uint8_t *found = (const uint8_t *)memmem(bytes, data.length, marker, sizeof(marker) - 1);
    if (!found) return;
    NSData *copy = [data copy];
    size_t offset = (size_t)(found - bytes) + sizeof(marker) - 1;
    dispatch_async(gLyricsQueue, ^{
        static NSUInteger lastHash = 0;
        static NSInteger lastTrack = 0;
        NSInteger trackID = gDateLyricsYouTubeMusicTrackID;
        if (trackID <= 0) return;
        if (copy.hash == lastHash && trackID == lastTrack) return;

        const uint8_t *b = (const uint8_t *)copy.bytes;
        NSMutableArray<NSDictionary *> *best = [NSMutableArray array];
        // The component name is a string field of a message; the line data
        // follows it inside the same message, so scan from just after the name,
        // skipping the rest of the hash suffix up to the next field tag.
        size_t start = offset;
        while (start < copy.length && (isalnum(b[start]) || b[start] == '-' || b[start] == '|' || b[start] == '_')) start++;
        DLCollectLyricLines(b + start, copy.length - start, 0, &best);
        if (best.count < 2) {
            DateLyricsDebugLog(@"[YTM] timed lyrics component found but no lines parsed (%lu candidates)", (unsigned long)best.count);
            return;
        }

        NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
        double previousEnd = 0;
        for (NSDictionary *line in best) {
            NSString *text = [line[@"text"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            double begin = [line[@"begin"] doubleValue], end = [line[@"end"] doubleValue];
            // Interlude markers and malformed ranges are not lyrics.
            if (text.length == 0 || [text isEqualToString:@"♪"] || end <= begin || begin < previousEnd - 0.5) continue;
            [lines addObject:@{@"begin": @(begin), @"end": @(end), @"text": text}];
            previousEnd = end;
        }
        if (lines.count < 2) return;
        lastHash = copy.hash;
        lastTrack = trackID;
        // Whole-line timing only; word timings are estimated when the score is
        // loaded (see DateLyricsModels.m), so older files benefit as well.
        BOOL wrote = DateLyricsWriteScoreJSON(trackID, lines, NO, @"youtubemusic");
        DateLyricsDebugLog(@"[YTM] native lyrics parsed lines=%lu first=%@ wrote=%d trackId=%ld",
            (unsigned long)lines.count, lines.firstObject[@"text"], wrote, (long)trackID);
    });
}

%hook GPBMessage

- (id)initWithData:(NSData *)data extensionRegistry:(id)registry error:(id *)error {
    id result = %orig;
    if (result) DateLyricsYTMTryExtractTimedLyrics(data);
    return result;
}

- (id)initWithData:(NSData *)data error:(id *)error {
    id result = %orig;
    if (result) DateLyricsYTMTryExtractTimedLyrics(data);
    return result;
}

- (BOOL)mergeFromData:(NSData *)data extensionRegistry:(id)registry error:(id *)error {
    BOOL result = %orig;
    if (result) DateLyricsYTMTryExtractTimedLyrics(data);
    return result;
}

%end

// The app's own update paths all end up here, so this works even when the
// YTNowPlayingInfoCenter* internals differ between app versions.
%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    if (!DateLyricsIsYouTubeMusicHost() || ![info isKindOfClass:NSDictionary.class]) return;
    NSNumber *elapsed = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] isKindOfClass:NSNumber.class]
        ? info[MPNowPlayingInfoPropertyElapsedPlaybackTime] : nil;
    NSNumber *duration = [info[MPMediaItemPropertyPlaybackDuration] isKindOfClass:NSNumber.class]
        ? info[MPMediaItemPropertyPlaybackDuration] : nil;
    NSNumber *rate = [info[MPNowPlayingInfoPropertyPlaybackRate] isKindOfClass:NSNumber.class]
        ? info[MPNowPlayingInfoPropertyPlaybackRate] : nil;
    DateLyricsYouTubeMusicHandleMetadata(
        DateLyricsYTMString(info[MPMediaItemPropertyTitle]),
        DateLyricsYTMString(info[MPMediaItemPropertyArtist]),
        DateLyricsYTMString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]),
        elapsed ? elapsed.doubleValue : NAN, duration.doubleValue, rate.floatValue, @"MPNowPlayingInfoCenter");
}

%end

%hook YTLocalPlaybackController

- (void)setPlaybackRateModel:(id)model {
    %orig;
    float rate = 0.0f;
    if ([model respondsToSelector:@selector(activeRate)]) {
        rate = ((float (*)(id, SEL))objc_msgSend)(model, @selector(activeRate));
    } else if ([model respondsToSelector:@selector(effectivePlaybackRate)]) {
        rate = ((float (*)(id, SEL))objc_msgSend)(model, @selector(effectivePlaybackRate));
    } else if ([model respondsToSelector:@selector(rate)]) {
        rate = ((float (*)(id, SEL))objc_msgSend)(model, @selector(rate));
    }
    NSString *videoID = [self.currentVideoID copy];
    double elapsed = self.currentVideoTime.time;
    float normalizedRate = isfinite(rate) ? MAX(0.0f, rate) : 0.0f;
    if (DateLyricsIsYouTubeMusicHost()) {
        DateLyricsDebugLog(@"[YTM] playback rate callback video=%@ elapsed=%.2f rate=%.2f modelClass=%@",
            videoID ?: @"<nil>", elapsed, normalizedRate, NSStringFromClass([model class]));
    }
    dispatch_async(gLyricsQueue, ^{
        gDateLyricsYouTubeMusicRate = normalizedRate;
        if (videoID.length > 0 && isfinite(elapsed)) {
            DateLyricsYouTubeMusicAdoptVideoID(videoID);
            DateLyricsYouTubeMusicRecordControllerSample(elapsed);
            NSInteger trackID = gDateLyricsYouTubeMusicTrackID;
            DateLyricsYouTubeMusicPublishAnchorIfNeeded(trackID, elapsed, normalizedRate);
        }
    });
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)change {
    %orig;
    if (!DateLyricsIsYouTubeMusicHost()) return;
    if (!gDateLyricsEnabled) {
        DateLyricsDebugLog(@"[YTM] playback-time callback ignored: tweak disabled");
        return;
    }
    if (self.isPlayingAd) {
        DateLyricsDebugLog(@"[YTM] playback-time callback ignored: ad is playing");
        return;
    }
    NSString *videoID = [self.currentVideoID copy];
    double elapsed = self.currentVideoTime.time;
    if (videoID.length == 0 || !isfinite(elapsed)) {
        DateLyricsDebugLog(@"[YTM] playback-time callback missing data video=%@ elapsed=%.2f",
            videoID ?: @"<nil>", elapsed);
        return;
    }
    dispatch_async(gLyricsQueue, ^{
        DateLyricsYouTubeMusicAdoptVideoID(videoID);
        DateLyricsYouTubeMusicRecordControllerSample(elapsed);
        NSInteger trackID = gDateLyricsYouTubeMusicTrackID;
        if (trackID <= 0) return;
        DateLyricsYouTubeMusicPublishAnchorIfNeeded(trackID, elapsed, gDateLyricsYouTubeMusicRate);
    });
}

- (void)singleVideo:(id)video playbackRateDidChange:(float)rate {
    %orig;
    if (!DateLyricsIsYouTubeMusicHost() || !gDateLyricsEnabled || self.isPlayingAd) return;
    NSString *videoID = [self.currentVideoID copy];
    double elapsed = self.currentVideoTime.time;
    float normalizedRate = isfinite(rate) ? MAX(0.0f, rate) : 0.0f;
    dispatch_async(gLyricsQueue, ^{
        DateLyricsYouTubeMusicAdoptVideoID(videoID);
        DateLyricsYouTubeMusicRecordControllerSample(elapsed);
        gDateLyricsYouTubeMusicRate = normalizedRate;
        DateLyricsDebugLog(@"[YTM] playbackRateDidChange video=%@ elapsed=%.2f rate=%.2f",
            videoID ?: @"<nil>", elapsed, normalizedRate);
        if (gDateLyricsYouTubeMusicTrackID > 0 && isfinite(elapsed)) {
            DateLyricsYouTubeMusicPublishAnchorIfNeeded(
                gDateLyricsYouTubeMusicTrackID, elapsed, normalizedRate);
        }
    });
}

%end

%end

void DateLyricsInitYouTubeMusicHooks(void) {
    %init(DateLyricsYouTubeMusic);
    DateLyricsWriteRuntimeStatus();
    DateLyricsDebugLog(@"[YTM] hooks initialized enabled=%d", gDateLyricsEnabled);
}
