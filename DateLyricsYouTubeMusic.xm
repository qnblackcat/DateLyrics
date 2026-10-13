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

// ---- Prefetching the lyrics panel --------------------------------------------
// Opening the Lyrics tab sends one request through the app's own panel service:
//   YTIPanelRequest { panel_id: "PAmusic_watch_lyrics_panel", params: <28 chars> }
// The params (base64 of a tiny protobuf holding a per-song "t_…" id) are already
// present in the data the app loads when a song starts, so the same request can
// be sent early, through the same service, without the tab ever being opened.
// Set to NO to fall back to "lyrics appear once the tab has been opened".
static const BOOL kDateLyricsYouTubeMusicPrefetch = YES;
static __weak id gDateLyricsYTMPanelService = nil;
// The service is created lazily by the panel view controllers, so before the tab
// has ever been opened there may be none to borrow. Keep an account id captured
// from the app's own objects and build a private service from it instead.
static id gDateLyricsYTMAccountID = nil;
static id gDateLyricsYTMOwnedPanelService = nil;

static void DateLyricsYTMPrefetchLyricsForParams(NSString *params) {
    static NSMutableSet<NSString *> *requested = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ requested = [NSMutableSet set]; });
    @synchronized (requested) {
        if ([requested containsObject:params]) return;
        if (requested.count > 200) [requested removeAllObjects];
        [requested addObject:params];
    }
    // Do not issue a request from inside another request's parse callback.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id service = gDateLyricsYTMPanelService;
        if (!service) {
            Class implClass = NSClassFromString(@"YTPanelServiceImpl");
            id accountID = gDateLyricsYTMAccountID;
            if (!gDateLyricsYTMOwnedPanelService && implClass && accountID &&
                [implClass instancesRespondToSelector:@selector(initWithAccountID:)]) {
                @try {
                    gDateLyricsYTMOwnedPanelService = ((id (*)(id, SEL, id))objc_msgSend)([implClass alloc], @selector(initWithAccountID:), accountID);
                    DateLyricsDebugLog(@"[YTM] prefetch created a private panel service (account=%@) -> %d", accountID, gDateLyricsYTMOwnedPanelService != nil);
                } @catch (NSException *exception) {
                    NSLog(@"[DateLyrics YTM] creating panel service failed %@: %@", exception.name, exception.reason);
                }
            }
            service = gDateLyricsYTMOwnedPanelService;
        }
        Class requestClass = NSClassFromString(@"YTIPanelRequest");
        SEL setPanelID = NSSelectorFromString(@"setPanelId:");
        SEL setParams = NSSelectorFromString(@"setParams:");
        SEL make = NSSelectorFromString(@"makeRequest:refresh:responseBlock:errorBlock:");
        if (!service || !requestClass || ![service respondsToSelector:make] ||
            ![requestClass instancesRespondToSelector:setPanelID] || ![requestClass instancesRespondToSelector:setParams]) {
            DateLyricsDebugLog(@"[YTM] prefetch skipped params=%@ service=%d requestClass=%d accountID=%d", params, service != nil, requestClass != Nil, gDateLyricsYTMAccountID != nil);
            @synchronized (requested) { [requested removeObject:params]; }   // allow another attempt
            return;
        }
        @try {
            id request = [[requestClass alloc] init];
            ((void (*)(id, SEL, id))objc_msgSend)(request, setPanelID, @"PAmusic_watch_lyrics_panel");
            ((void (*)(id, SEL, id))objc_msgSend)(request, setParams, params);
            void (^onResponse)(id) = ^(id response) {
                DateLyricsDebugLog(@"[YTM] prefetch response params=%@ class=%@", params, NSStringFromClass([response class]));
            };
            void (^onError)(id) = ^(id error) {
                DateLyricsDebugLog(@"[YTM] prefetch error params=%@ %@", params, error);
            };
            DateLyricsDebugLog(@"[YTM] prefetch requesting lyrics params=%@", params);
            ((void (*)(id, SEL, id, BOOL, id, id))objc_msgSend)(service, make, request, NO, onResponse, onError);
        } @catch (NSException *exception) {
            NSLog(@"[DateLyrics YTM] prefetch exception %@: %@", exception.name, exception.reason);
        }
    });
}

// The params string is base64 of {177: {1: "t_…"}} (bytes 8a 0b <n+2> 0a <n> <id>),
// where the lyrics id length n varies between songs (15 and 16 seen). It starts
// with "igs", so decode the first 8 characters to validate the shape and read n,
// then take exactly as many characters as that length implies. A partial last
// group is sent by the app with a url-encoded "=" ("%3D").
static BOOL DateLyricsYTMIsBase64Char(uint8_t c) {
    return isalnum(c) || c == '_' || c == '-' || c == '+' || c == '/';
}

static NSString *DateLyricsYTMExtractParams(const uint8_t *bytes, size_t length) {
    static const char prefix[] = "igs";
    const uint8_t *cursor = bytes, *limit = bytes + length;
    while (cursor + 8 <= limit) {
        const uint8_t *hit = (const uint8_t *)memmem(cursor, (size_t)(limit - cursor), prefix, sizeof(prefix) - 1);
        if (!hit || hit + 8 > limit) return nil;
        cursor = hit + 1;
        NSString *headText = [[NSString alloc] initWithBytes:hit length:8 encoding:NSASCIIStringEncoding];
        NSData *head = headText ? [[NSData alloc] initWithBase64EncodedString:headText options:0] : nil;
        if (head.length != 6) continue;
        const uint8_t *h = (const uint8_t *)head.bytes;
        if (h[0] != 0x8a || h[1] != 0x0b || h[3] != 0x0a || h[5] != 't') continue;
        if (h[4] < 10 || h[4] > 24 || h[2] != h[4] + 2) continue;
        size_t byteCount = 3 + h[2];
        size_t charCount = (byteCount * 4 + 2) / 3, padCount = (3 - byteCount % 3) % 3;
        if (hit + charCount > limit) continue;
        BOOL valid = YES;
        for (size_t i = 8; i < charCount && valid; i++) valid = DateLyricsYTMIsBase64Char(hit[i]);
        if (!valid) continue;
        NSMutableString *params = [[NSMutableString alloc] initWithBytes:hit length:charCount encoding:NSASCIIStringEncoding];
        for (size_t i = 0; i < padCount; i++) [params appendString:@"%3D"];
        return params;
    }
    return nil;
}

static void DateLyricsYTMPrefetchLyrics(NSData *data) {
    // A cached lyrics entity is tiny, so do not apply the size floor used elsewhere.
    if (!kDateLyricsYouTubeMusicPrefetch || data.length < 40) return;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSString *params = DateLyricsYTMExtractParams(bytes, data.length);
    if (!params) {
        if (gDateLyricsDebugLogging && memmem(bytes, data.length, "PAmusic_watch_lyrics_panel", 26)) {
            static NSUInteger logged = 0;
            if (logged++ < 4) {
                const uint8_t *marker = (const uint8_t *)memmem(bytes, data.length, "PAmusic_watch_lyrics_panel", 26);
                size_t at = (size_t)(marker - bytes), from = at > 120 ? at - 120 : 0, to = MIN(data.length, at + 200);
                NSMutableString *context = [NSMutableString string];
                for (size_t i = from; i < to; i++) {
                    [context appendString:(bytes[i] >= 0x20 && bytes[i] < 0x7f) ? [NSString stringWithFormat:@"%c", bytes[i]] : @"·"];
                }
                DateLyricsDebugLog(@"[YTM] lyrics panel id found but no params (payload bytes=%lu): %@", (unsigned long)data.length, context);
            }
        }
        return;
    }
    DateLyricsDebugLog(@"[YTM] found lyrics params=%@ (payload bytes=%lu, current video=%@)", params,
        (unsigned long)data.length, gDateLyricsYouTubeMusicVideoID ?: @"<nil>");
    DateLyricsYTMPrefetchLyricsForParams(params);
}

static void DateLyricsYTMTryExtractTimedLyrics(NSData *data, id message) {
    if (![data isKindOfClass:NSData.class] || data.length < 40 || !DateLyricsIsYouTubeMusicHost() || !gDateLyricsEnabled) return;
    DateLyricsYTMPrefetchLyrics(data);
    if (data.length < 2000) return;
    // Resource bundles (file groups) mention "timed_lyrics.eml" by name only.
    if ([NSStringFromClass([message class]) rangeOfString:@"FileGroup"].location != NSNotFound) return;
    static const char marker[] = "timed_lyrics.eml";
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    const uint8_t *found = (const uint8_t *)memmem(bytes, data.length, marker, sizeof(marker) - 1);
    if (!found) {
        // A renamed component is the likely failure after an app update: report
        // any component name that mentions lyrics so the new one can be found.
        if (gDateLyricsDebugLogging && memmem(bytes, data.length, "lyric", 5)) {
            static NSMutableSet<NSString *> *reported = nil;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ reported = [NSMutableSet set]; });
            NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
            for (size_t i = 0; i + 4 < data.length && names.count < 12; i++) {
                if (bytes[i] != '.' || memcmp(bytes + i, ".eml", 4) != 0) continue;
                size_t begin = i;
                while (begin > 0 && (isalnum(bytes[begin - 1]) || bytes[begin - 1] == '_') && i - begin < 60) begin--;
                NSString *name = [[NSString alloc] initWithBytes:bytes + begin length:i + 4 - begin encoding:NSUTF8StringEncoding];
                if ([name rangeOfString:@"lyric" options:NSCaseInsensitiveSearch].location != NSNotFound) [names addObject:name];
            }
            NSString *summary = [names.array componentsJoinedByString:@", "];
            @synchronized (reported) {
                if (names.count > 0 && ![reported containsObject:summary]) {
                    [reported addObject:summary];
                    DateLyricsDebugLog(@"[YTM] payload mentions lyrics but has no timed_lyrics component; lyric components: %@ (bytes=%lu)",
                        summary, (unsigned long)data.length);
                }
            }
        }
        return;
    }
    DateLyricsDebugLog(@"[YTM] timed_lyrics component found (payload bytes=%lu)", (unsigned long)data.length);
    NSData *copy = [data copy];
    size_t offset = (size_t)(found - bytes) + sizeof(marker) - 1;
    dispatch_async(gLyricsQueue, ^{
        static NSUInteger lastHash = 0;
        static NSInteger lastTrack = 0;
        const uint8_t *b = (const uint8_t *)copy.bytes;
        // The response names the video it belongs to ("lyrics_sharing_panel_<id>").
        // Using it, rather than the track currently playing, matters for lyrics that
        // are prefetched or arrive late: they must never be filed under another song.
        NSString *videoID = nil;
        static const char videoTag[] = "lyrics_sharing_panel_";
        const uint8_t *tagHit = (const uint8_t *)memmem(b, copy.length, videoTag, sizeof(videoTag) - 1);
        if (tagHit && (size_t)(tagHit - b) + sizeof(videoTag) - 1 + 11 <= copy.length) {
            const uint8_t *id = tagHit + sizeof(videoTag) - 1;
            BOOL valid = YES;
            for (int i = 0; i < 11; i++) valid = valid && (isalnum(id[i]) || id[i] == '_' || id[i] == '-');
            if (valid) videoID = [[NSString alloc] initWithBytes:id length:11 encoding:NSASCIIStringEncoding];
        }
        NSInteger trackID = videoID ? DateLyricsYouTubeMusicTrackID(videoID, nil, nil) : gDateLyricsYouTubeMusicTrackID;
        if (trackID <= 0) return;
        if (copy.hash == lastHash && trackID == lastTrack) return;

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
        DateLyricsDebugLog(@"[YTM] native lyrics parsed lines=%lu first=%@ wrote=%d trackId=%ld video=%@",
            (unsigned long)lines.count, lines.firstObject[@"text"], wrote, (long)trackID, videoID ?: @"<current>");
    });
}

%hook GPBMessage

- (id)initWithData:(NSData *)data extensionRegistry:(id)registry error:(id *)error {
    id result = %orig;
    if (result) DateLyricsYTMTryExtractTimedLyrics(data, result);
    return result;
}

- (id)initWithData:(NSData *)data error:(id *)error {
    id result = %orig;
    if (result) DateLyricsYTMTryExtractTimedLyrics(data, result);
    return result;
}

- (BOOL)mergeFromData:(NSData *)data extensionRegistry:(id)registry error:(id *)error {
    BOOL result = %orig;
    if (result) DateLyricsYTMTryExtractTimedLyrics(data, self);
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

%hook YTPanelServiceImpl

- (id)initWithAccountID:(id)accountID {
    id result = %orig;
    if (accountID) gDateLyricsYTMAccountID = accountID;
    if (result) gDateLyricsYTMPanelService = result;
    return result;
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

// Many of the app's objects are built with -initWithAccountID:. Wrap every such
// initialiser (defined directly on a class of the main executable) until the first
// account id has been seen, then put the originals back. Later account changes
// reach gDateLyricsYTMAccountID through the YTPanelServiceImpl hook. Method lists
// are read without touching the classes, so no +initialize runs from here.
typedef struct { Method method; IMP original; } DateLyricsYTMWrappedInit;
static DateLyricsYTMWrappedInit *gDateLyricsYTMWrappedInits = NULL;
static unsigned int gDateLyricsYTMWrappedInitCount = 0;
static BOOL gDateLyricsYTMAccountCaptureDone = NO;

static void DateLyricsYouTubeMusicRemoveAccountCapture(NSString *firstClass) {
    @synchronized ([NSObject class]) {
        if (gDateLyricsYTMAccountCaptureDone) return;
        gDateLyricsYTMAccountCaptureDone = YES;
        for (unsigned int i = 0; i < gDateLyricsYTMWrappedInitCount; i++) {
            method_setImplementation(gDateLyricsYTMWrappedInits[i].method, gDateLyricsYTMWrappedInits[i].original);
        }
    }
    DateLyricsDebugLog(@"[YTM] account captured from %@; restored %u initialisers", firstClass, gDateLyricsYTMWrappedInitCount);
}

static void DateLyricsYouTubeMusicInstallAccountCapture(void) {
    const char *mainImage = [NSBundle mainBundle].executablePath.fileSystemRepresentation;
    SEL target = @selector(initWithAccountID:);
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    gDateLyricsYTMWrappedInits = (DateLyricsYTMWrappedInit *)calloc(classCount, sizeof(DateLyricsYTMWrappedInit));
    for (unsigned int i = 0; i < classCount; i++) {
        const char *image = class_getImageName(classes[i]);
        if (!image || !mainImage || strcmp(image, mainImage) != 0) continue;
        if (strcmp(class_getName(classes[i]), "YTPanelServiceImpl") == 0) continue;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(classes[i], &count);
        for (unsigned int m = 0; m < count; m++) {
            if (method_getName(methods[m]) != target) continue;
            const char *types = method_getTypeEncoding(methods[m]);
            if (!types || types[0] != '@') continue;              // must return an object
            if (gDateLyricsYTMWrappedInitCount >= classCount) break;
            IMP original = method_getImplementation(methods[m]);
            gDateLyricsYTMWrappedInits[gDateLyricsYTMWrappedInitCount++] = (DateLyricsYTMWrappedInit){methods[m], original};
            method_setImplementation(methods[m], imp_implementationWithBlock(^id(id selfObject, id accountID) {
                if (accountID) {
                    gDateLyricsYTMAccountID = accountID;
                    DateLyricsYouTubeMusicRemoveAccountCapture(NSStringFromClass([selfObject class]));
                }
                return ((id (*)(id, SEL, id))original)(selfObject, target, accountID);
            }));
        }
        free(methods);
    }
    free(classes);
    DateLyricsDebugLog(@"[YTM] account capture installed on %u initialisers", gDateLyricsYTMWrappedInitCount);
}

// Records which of the internals the hooks depend on exist in this build of the
// app. Must run before %init: Logos adds a method when the hooked class lacks it,
// which would make every selector look present afterwards.
static void DateLyricsYouTubeMusicSelfCheck(void) {
    if (!gDateLyricsDebugLogging) return;
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    DateLyricsDebugLog(@"[YTM] self-check app=%@ build=%@ ios=%@", info[@"CFBundleShortVersionString"],
        info[@"CFBundleVersion"], [UIDevice currentDevice].systemVersion);
    Class playback = NSClassFromString(@"YTLocalPlaybackController");
    DateLyricsDebugLog(@"[YTM] self-check YTLocalPlaybackController=%d currentVideoID=%d currentVideoTime=%d isPlayingAd=%d "
        @"setPlaybackRateModel=%d timeDidChange=%d rateDidChange=%d",
        playback != Nil,
        [playback instancesRespondToSelector:@selector(currentVideoID)],
        [playback instancesRespondToSelector:@selector(currentVideoTime)],
        [playback instancesRespondToSelector:@selector(isPlayingAd)],
        [playback instancesRespondToSelector:@selector(setPlaybackRateModel:)],
        [playback instancesRespondToSelector:@selector(singleVideo:currentVideoTimeDidChange:)],
        [playback instancesRespondToSelector:@selector(singleVideo:playbackRateDidChange:)]);
    Class nowPlaying = NSClassFromString(@"MPNowPlayingInfoCenter");
    Class message = NSClassFromString(@"GPBMessage");
    DateLyricsDebugLog(@"[YTM] self-check MPNowPlayingInfoCenter.setNowPlayingInfo=%d GPBMessage=%d initWithData:extensionRegistry:error:=%d "
        @"initWithData:error:=%d mergeFromData:extensionRegistry:error:=%d",
        [nowPlaying instancesRespondToSelector:@selector(setNowPlayingInfo:)], message != Nil,
        [message instancesRespondToSelector:@selector(initWithData:extensionRegistry:error:)],
        [message instancesRespondToSelector:@selector(initWithData:error:)],
        [message instancesRespondToSelector:@selector(mergeFromData:extensionRegistry:error:)]);
}

void DateLyricsInitYouTubeMusicHooks(void) {
    DateLyricsYouTubeMusicSelfCheck();
    DateLyricsYouTubeMusicInstallAccountCapture();
    %init(DateLyricsYouTubeMusic);
    DateLyricsWriteRuntimeStatus();
    DateLyricsDebugLog(@"[YTM] hooks initialized enabled=%d", gDateLyricsEnabled);
}
