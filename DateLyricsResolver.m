#import "DateLyricsResolver.h"
#import "DateLyricsPayload.h"
#import "DateLyricsPrivateAPI.h"
#include <pthread.h>

static DateLyricsTimedLine *DateLyricsComputeFilteredLine(DateLyricsTimedLine *origLine, BOOL showAdlibs) {
    if (!origLine) return nil;
    if (showAdlibs) return origLine;

    NSMutableIndexSet *parenthesizedIndices = [NSMutableIndexSet indexSet];
    BOOL insideParens = NO;
    for (NSUInteger i = 0; i < origLine.words.count; i++) {
        DateLyricsTimedWord *word = origLine.words[i];
        NSString *wText = word.text;
        NSString *sepBefore = word.separatorBefore;
        
        if ([wText hasPrefix:@"("] || [wText hasPrefix:@"["] || [sepBefore containsString:@"("] || [sepBefore containsString:@"["]) {
            insideParens = YES;
        }
        
        if (insideParens) {
            [parenthesizedIndices addIndex:i];
        }
        
        if ([wText hasSuffix:@")"] || [wText hasSuffix:@"]"]) {
            insideParens = NO;
        }
    }

    BOOL hasBackground = NO;
    for (NSUInteger i = 0; i < origLine.words.count; i++) {
        DateLyricsTimedWord *word = origLine.words[i];
        if (word.isBackground || [parenthesizedIndices containsIndex:i]) {
            hasBackground = YES;
            break;
        }
    }
    if (!hasBackground) {
        return origLine;
    }

    DateLyricsTimedLine *filteredLine = [DateLyricsTimedLine new];
    filteredLine.begin = origLine.begin;
    filteredLine.end = origLine.end;

    NSMutableArray<DateLyricsTimedWord *> *filteredWords = [NSMutableArray array];
    NSMutableString *newText = [NSMutableString string];

    for (NSUInteger i = 0; i < origLine.words.count; i++) {
        DateLyricsTimedWord *word = origLine.words[i];
        if (word.isBackground || [parenthesizedIndices containsIndex:i]) {
            continue;
        }
        DateLyricsTimedWord *newWord = [DateLyricsTimedWord new];
        newWord.begin = word.begin;
        newWord.end = word.end;
        newWord.background = NO;
        
        // Strip any residual parenthesis characters if they were on the word boundaries
        NSString *wordText = word.text;
        NSString *sepBefore = word.separatorBefore;
        if ([wordText hasPrefix:@"("]) wordText = [wordText substringFromIndex:1];
        if ([wordText hasPrefix:@"["]) wordText = [wordText substringFromIndex:1];
        if ([wordText hasSuffix:@")"]) wordText = [wordText substringToIndex:wordText.length - 1];
        if ([wordText hasSuffix:@"]"]) wordText = [wordText substringToIndex:wordText.length - 1];
        newWord.text = wordText;

        if (filteredWords.count == 0) {
            newWord.separatorBefore = @"";
        } else {
            // Clean up any remaining parenthesis from the separator
            NSString *cleanedSep = sepBefore;
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@"(" withString:@""];
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@"[" withString:@""];
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@")" withString:@""];
            cleanedSep = [cleanedSep stringByReplacingOccurrencesOfString:@"]" withString:@""];
            newWord.separatorBefore = cleanedSep.length > 0 ? cleanedSep : @" ";
        }
        [filteredWords addObject:newWord];

        if (newWord.separatorBefore.length > 0) {
            [newText appendString:newWord.separatorBefore];
        }
        if (newWord.text.length > 0) {
            [newText appendString:newWord.text];
        }
    }

    filteredLine.words = [filteredWords copy];
    filteredLine.text = [newText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (filteredWords.count > 0) {
        filteredLine.begin = filteredWords.firstObject.begin;
        filteredLine.end = filteredWords.lastObject.end;
    } else {
        filteredLine.begin = origLine.begin;
        filteredLine.end = origLine.end;
    }

    if (filteredLine.text.length == 0 || filteredLine.words.count == 0) {
        return nil;
    }
    return filteredLine;
}

// Filtering a line is pure — same input, same ShowAdlibs setting, same result — but it
// was being recomputed for every line in the song on every playback tick, allocating a
// replacement line, N replacement words and a rebuilt string each time, purely to work
// out which line is currently playing. At ~4 ticks/sec across a full lyric sheet that
// was the single largest CPU cost in the Music process. Memoised per line; the flag
// invalidates if ShowAdlibs is toggled at runtime.
DateLyricsTimedLine *DateLyricsFilteredLine(DateLyricsTimedLine *origLine, BOOL showAdlibs) {
    if (!origLine) return nil;
    if (origLine.amlCachedFilteredValid && origLine.amlCachedFilteredAdlibs == showAdlibs) {
        return origLine.amlCachedFiltered;
    }

    DateLyricsTimedLine *filtered = DateLyricsComputeFilteredLine(origLine, showAdlibs);
    origLine.amlCachedFiltered = filtered;
    origLine.amlCachedFilteredAdlibs = showAdlibs;
    origLine.amlCachedFilteredValid = YES;
    return filtered;
}


// Shorter gaps than these keep the old behaviour (date before the first line,
// previous line through a break), so a breath between lines never flashes dots.
static const NSTimeInterval kDateLyricsIntroMinimumGap = 3.0;
static const NSTimeInterval kDateLyricsInterludeMinimumGap = 5.0;

// Each glyph must be a single UTF-16 unit with text presentation: ♪ (U+266A)
// takes the label colour and dims like a lyric, unlike the 🎵 emoji.
static NSArray<NSString *> *DateLyricsInterludeGlyphs(NSInteger style) {
    switch (style) {
        case 1: return @[ @"•", @"•", @"•", @"•", @"•" ];
        case 2: return @[ @"•", @"♪", @"•", @"♪", @"•" ];
        default: return @[ @"•", @"•", @"•" ];
    }
}

static NSTimeInterval DateLyricsLineSungEnd(DateLyricsTimedLine *line) {
    NSTimeInterval end = line.end;
    for (DateLyricsTimedWord *word in line.words) {
        end = MAX(end, word.end);
    }
    return end > line.begin ? end : -1.0;
}

// The indicator is a synthetic word-timed line, so the normal karaoke renderer
// dims it and lights the dots, and the normal line transition moves into the
// next lyric. Its lineId is the gap's start time, which sorts between the two
// real lines and keeps seek directions correct. With N glyphs, glyph k lights
// at k/(N+1) of the gap, so the last slice shows them all before the lyric.
static NSDictionary *DateLyricsInterludePayload(NSArray<DateLyricsTimedLine *> *lines, NSInteger resolvedLineIndex, NSTimeInterval elapsedTime, BOOL showAdlibs, BOOL showInterlude, NSInteger style, NSTimeInterval *nextDotOut) {
    if (nextDotOut) *nextDotOut = -1.0;
    if (!showInterlude) return nil;

    NSTimeInterval gapStart = 0.0;
    NSTimeInterval minimumGap = kDateLyricsIntroMinimumGap;
    if (resolvedLineIndex >= 0) {
        DateLyricsTimedLine *line = DateLyricsFilteredLine(lines[resolvedLineIndex], showAdlibs);
        gapStart = line ? DateLyricsLineSungEnd(line) : -1.0;
        minimumGap = kDateLyricsInterludeMinimumGap;
    }
    if (gapStart < 0.0) return nil;

    // No following line means the outro: keep the last lyric, as before.
    NSTimeInterval gapEnd = -1.0;
    for (NSInteger i = resolvedLineIndex + 1; i < (NSInteger)lines.count; i++) {
        DateLyricsTimedLine *next = DateLyricsFilteredLine(lines[i], showAdlibs);
        if (!next) continue;
        gapEnd = next.begin;
        break;
    }
    if (gapEnd <= elapsedTime || gapEnd - gapStart < minimumGap) return nil;

    // Still singing the line before a long break. Nothing else wakes the
    // ticker when a line ends, so ask for a wake at the start of the break.
    if (elapsedTime < gapStart) {
        if (nextDotOut) *nextDotOut = gapStart;
        return nil;
    }

    NSArray<NSString *> *glyphs = DateLyricsInterludeGlyphs(style);
    NSTimeInterval step = (gapEnd - gapStart) / (NSTimeInterval)(glyphs.count + 1);
    NSUInteger litLength = 0;
    NSUInteger glyphEnd = 0;
    for (NSUInteger index = 0; index < glyphs.count; index++) {
        NSTimeInterval lightsAt = gapStart + step * (NSTimeInterval)(index + 1);
        if (elapsedTime < lightsAt) {
            if (nextDotOut) *nextDotOut = lightsAt;
            break;
        }
        if (index > 0) glyphEnd += 1; // the separating space
        glyphEnd += glyphs[index].length;
        litLength = glyphEnd;
    }

    NSString *text = [glyphs componentsJoinedByString:@" "];
    NSRange litRange = litLength > 0 ? NSMakeRange(0, litLength) : NSMakeRange(NSNotFound, 0);
    NSMutableDictionary *payload = [DateLyricsMakePayload(text, litRange) mutableCopy];
    payload[@"timed"] = @YES;
    payload[@"wordTimed"] = @YES;
    payload[@"started"] = @YES;
    payload[@"finished"] = @NO;
    payload[@"interlude"] = @YES;
    payload[@"lineId"] = @(gapStart);
    payload[@"lineDuration"] = @(gapEnd - gapStart);
    return [payload copy];
}

NSDictionary *DateLyricsResolvePayload(DateLyricsScore *score, NSTimeInterval elapsedTime, NSInteger *cursorInOut, NSTimeInterval *nextTriggerOut, NSTimeInterval *nextLineTriggerOut, DateLyricsResolverOptions options) {
    if (!score || score.lines.count == 0) {
        if (nextTriggerOut) *nextTriggerOut = -1.0;
        if (nextLineTriggerOut) *nextLineTriggerOut = -1.0;
        return nil;
    }
    
    id selectedLineID = nil;
    NSTimeInterval nextWordStart = -1.0;
    NSDictionary *wordPayload = nil;
    
    NSInteger cursorIndex = cursorInOut ? *cursorInOut : -1;
    NSInteger resolvedLineIndex = -1;
    NSArray<DateLyricsTimedLine *> *lines = score.lines;

    // The date owns the slot only before the first lyric. Once a line has
    // started, keep the most recent line selected through any later
    // instrumental gap; allowing the resolver to expire it is what made the
    // stock date slip back into the lyric slot mid-song.
    
    if (cursorIndex >= 0 && cursorIndex < (NSInteger)lines.count) {
        for (NSInteger i = cursorIndex; i < (NSInteger)lines.count; i++) {
            DateLyricsTimedLine *line = DateLyricsFilteredLine(lines[i], options.showAdlibs);
            if (!line) continue;
            if (line.begin > elapsedTime) break;
            resolvedLineIndex = i;
        }
        if (resolvedLineIndex >= 0) {
            for (NSInteger i = resolvedLineIndex + 1; i < (NSInteger)lines.count; i++) {
                DateLyricsTimedLine *next = DateLyricsFilteredLine(lines[i], options.showAdlibs);
                if (!next) continue;
                if (next.begin > elapsedTime) break;
                resolvedLineIndex = i;
            }
        }
    }
    
    if (resolvedLineIndex < 0) {
        for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
            DateLyricsTimedLine *line = DateLyricsFilteredLine(lines[i], options.showAdlibs);
            if (!line) continue;
            if (elapsedTime >= line.begin) {
                resolvedLineIndex = i;
                break;
            }
        }
    }
    
    if (cursorInOut) *cursorInOut = resolvedLineIndex;
    
    if (resolvedLineIndex >= 0) {
        DateLyricsTimedLine *line = DateLyricsFilteredLine(lines[resolvedLineIndex], options.showAdlibs);
        if (line && elapsedTime >= line.begin) {
            
            selectedLineID = @(line.begin);
            
            if (score.hasWordTiming) {
                NSRange activeRange = NSMakeRange(NSNotFound, 0);
                NSRange backgroundActiveRange = NSMakeRange(NSNotFound, 0);
                NSRange previousForegroundWordRange = NSMakeRange(NSNotFound, 0);
                NSRange previousBackgroundWordRange = NSMakeRange(NSNotFound, 0);
                NSTimeInterval previousForegroundWordEnd = -1.0;
                NSTimeInterval previousBackgroundWordEnd = -1.0;
                NSUInteger previousForegroundSegmentStart = NSNotFound;
                NSUInteger previousBackgroundSegmentStart = NSNotFound;
                NSTimeInterval nextForegroundWordStart = -1.0;
                NSTimeInterval nextBackgroundWordStart = -1.0;
                BOOL previousWordWasBackground = NO;
                BOOL hasPreviousWord = NO;
                NSTimeInterval activeForegroundWordBegin = -1.0;
                NSTimeInterval activeBackgroundWordBegin = -1.0;
                // Smooth sweep: the most recently started syllable of each
                // voice, kept after it ends so the renderer can hold it lit.
                NSRange sweepForegroundRange = NSMakeRange(NSNotFound, 0);
                NSRange sweepBackgroundRange = NSMakeRange(NSNotFound, 0);
                NSTimeInterval sweepForegroundBegin = -1.0;
                NSTimeInterval sweepForegroundEnd = -1.0;
                NSTimeInterval sweepBackgroundBegin = -1.0;
                NSTimeInterval sweepBackgroundEnd = -1.0;
                NSUInteger foregroundProgressStart = NSNotFound;
                NSUInteger foregroundProgressEnd = 0;
                NSUInteger backgroundProgressStart = NSNotFound;
                NSUInteger backgroundProgressEnd = 0;
                NSUInteger wordCursor = 0;
                
                for (DateLyricsTimedWord *word in line.words) {
                    wordCursor += word.separatorBefore.length;
                    NSRange wordRange = NSMakeRange(wordCursor, word.text.length);
                    NSUInteger segmentStart = wordRange.location;
                    if (hasPreviousWord && previousWordWasBackground == word.isBackground) {
                        segmentStart = word.isBackground ? previousBackgroundSegmentStart : previousForegroundSegmentStart;
                    }
                    BOOL isActive = elapsedTime >= word.begin && elapsedTime < word.end;
                    if (word.isBackground) {
                        if (elapsedTime >= word.begin && backgroundProgressStart == NSNotFound) backgroundProgressStart = wordRange.location;
                        if (elapsedTime >= word.begin) backgroundProgressEnd = MAX(backgroundProgressEnd, NSMaxRange(wordRange));
                        if (elapsedTime >= word.begin && word.begin >= sweepBackgroundBegin) {
                            sweepBackgroundRange = wordRange;
                            sweepBackgroundBegin = word.begin;
                            sweepBackgroundEnd = word.end;
                        }
                        if (isActive && (backgroundActiveRange.location == NSNotFound || word.begin >= activeBackgroundWordBegin)) {
                            backgroundActiveRange = wordRange;
                            activeBackgroundWordBegin = word.begin;
                        }
                        if (word.begin > elapsedTime && (nextBackgroundWordStart < 0 || word.begin < nextBackgroundWordStart)) nextBackgroundWordStart = word.begin;
                        if (word.end <= elapsedTime && word.end >= previousBackgroundWordEnd) {
                            previousBackgroundWordRange = wordRange;
                            previousBackgroundWordEnd = word.end;
                            previousBackgroundSegmentStart = segmentStart;
                        }
                    } else {
                        if (elapsedTime >= word.begin && foregroundProgressStart == NSNotFound) foregroundProgressStart = wordRange.location;
                        if (elapsedTime >= word.begin) foregroundProgressEnd = MAX(foregroundProgressEnd, NSMaxRange(wordRange));
                        if (elapsedTime >= word.begin && word.begin >= sweepForegroundBegin) {
                            sweepForegroundRange = wordRange;
                            sweepForegroundBegin = word.begin;
                            sweepForegroundEnd = word.end;
                        }
                        if (isActive && (activeRange.location == NSNotFound || word.begin >= activeForegroundWordBegin)) {
                            activeRange = wordRange;
                            activeForegroundWordBegin = word.begin;
                        }
                        if (word.begin > elapsedTime && (nextForegroundWordStart < 0 || word.begin < nextForegroundWordStart)) nextForegroundWordStart = word.begin;
                        if (word.end <= elapsedTime && word.end >= previousForegroundWordEnd) {
                            previousForegroundWordRange = wordRange;
                            previousForegroundWordEnd = word.end;
                            previousForegroundSegmentStart = segmentStart;
                        }
                    }
                    hasPreviousWord = YES;
                    previousWordWasBackground = word.isBackground;
                    wordCursor += word.text.length;
                }
                
                if (activeRange.location == NSNotFound && previousForegroundWordRange.location != NSNotFound &&
                    elapsedTime >= previousForegroundWordEnd &&
                    (nextForegroundWordStart < 0 || elapsedTime < nextForegroundWordStart) && elapsedTime <= line.end) {
                    activeRange = previousForegroundWordRange;
                }
                if (backgroundActiveRange.location == NSNotFound && previousBackgroundWordRange.location != NSNotFound &&
                    elapsedTime >= previousBackgroundWordEnd &&
                    (nextBackgroundWordStart < 0 || elapsedTime < nextBackgroundWordStart) && elapsedTime <= line.end) {
                    backgroundActiveRange = previousBackgroundWordRange;
                }

                NSRange focusForegroundRange = activeRange;
                NSRange focusBackgroundRange = backgroundActiveRange;

                // Keep the sung portion bright instead of reverting the whole
                // line to translucent between word boundaries. The focus ranges
                // above remain the current word for split-segment selection;
                // this cumulative range is the actual rendered highlight.
                if (foregroundProgressStart != NSNotFound && foregroundProgressEnd > foregroundProgressStart) {
                    activeRange = NSMakeRange(foregroundProgressStart, foregroundProgressEnd - foregroundProgressStart);
                }
                if (backgroundProgressStart != NSNotFound && backgroundProgressEnd > backgroundProgressStart) {
                    backgroundActiveRange = NSMakeRange(backgroundProgressStart, backgroundProgressEnd - backgroundProgressStart);
                }
                
                if (nextForegroundWordStart > elapsedTime) nextWordStart = nextForegroundWordStart;
                if (nextBackgroundWordStart > elapsedTime) {
                    if (nextWordStart < 0 || nextBackgroundWordStart < nextWordStart) nextWordStart = nextBackgroundWordStart;
                }
                
                BOOL isLineFinished = YES;
                NSTimeInterval minWordBegin = -1.0;
                for (DateLyricsTimedWord *word in line.words) {
                    if (word.end > elapsedTime) isLineFinished = NO;
                    if (minWordBegin < 0 || word.begin < minWordBegin) minWordBegin = word.begin;
                }
                BOOL isLineStarted = (minWordBegin < 0) || (elapsedTime >= minWordBegin);
                
                NSDictionary *baseWordPayload = DateLyricsMakePayloadWithBackgroundRange(line.text, activeRange, backgroundActiveRange);
                NSMutableDictionary *mutableWordPayload = [(baseWordPayload ?: @{}) mutableCopy];
                if (mutableWordPayload.count > 0) {
                    DateLyricsSetRangeFields(mutableWordPayload, @"focus", focusForegroundRange);
                    DateLyricsSetRangeFields(mutableWordPayload, @"focusBg", focusBackgroundRange);
                    mutableWordPayload[@"timed"] = @YES;
                    // This flag describes the lyric format, independently of
                    // whether a syllable happens to be active on this tick.
                    // A missing loc/len therefore means "not sung yet", not
                    // "this is an ordinary line-synced lyric".
                    mutableWordPayload[@"wordTimed"] = @YES;
                    mutableWordPayload[@"started"] = @(isLineStarted);
                    mutableWordPayload[@"finished"] = @(isLineFinished);
                    mutableWordPayload[@"lineId"] = selectedLineID;
                    if (line.end > line.begin) mutableWordPayload[@"lineDuration"] = @(line.end - line.begin);
                    if (options.smoothSweep) {
                        DateLyricsSetRangeFields(mutableWordPayload, @"sweep", sweepForegroundRange);
                        if (sweepForegroundRange.location != NSNotFound) {
                            mutableWordPayload[@"sweepBegin"] = @(sweepForegroundBegin);
                            mutableWordPayload[@"sweepEnd"] = @(sweepForegroundEnd);
                        }
                        DateLyricsSetRangeFields(mutableWordPayload, @"bgSweep", sweepBackgroundRange);
                        if (sweepBackgroundRange.location != NSNotFound) {
                            mutableWordPayload[@"bgSweepBegin"] = @(sweepBackgroundBegin);
                            mutableWordPayload[@"bgSweepEnd"] = @(sweepBackgroundEnd);
                        }
                    }
                    if ([score.source isEqualToString:@"youtubemusic"]) {
                        // YouTube Music times whole lines; the word timings are
                        // estimates that exist only so long lines can be split.
                        // Keep the focus ranges (they choose the visible
                        // segment) but expose no highlight, as the app has none.
                        for (NSString *key in @[@"loc", @"len", @"bgLoc", @"bgLen",
                                                @"sweepLoc", @"sweepLen", @"sweepBegin", @"sweepEnd",
                                                @"bgSweepLoc", @"bgSweepLen", @"bgSweepBegin", @"bgSweepEnd"]) {
                            [mutableWordPayload removeObjectForKey:key];
                        }
                        mutableWordPayload[@"estimated"] = @YES;
                    }
                    wordPayload = [mutableWordPayload copy];
                } else {
                    wordPayload = nil;
                }
            } else {
                // No word timing. Just basic line payload.
                wordPayload = DateLyricsMakePayload(line.text, NSMakeRange(NSNotFound, 0));
                if (wordPayload) {
                    NSMutableDictionary *m = [wordPayload mutableCopy];
                    m[@"timed"] = @YES;
                    m[@"lineId"] = selectedLineID;
                    if (line.end > line.begin) m[@"lineDuration"] = @(line.end - line.begin);
                    wordPayload = [m copy];
                }
            }
        }
        
        for (NSInteger i = resolvedLineIndex + 1; i < (NSInteger)lines.count; i++) {
            DateLyricsTimedLine *nextLine = DateLyricsFilteredLine(lines[i], options.showAdlibs);
            if (!nextLine) continue;
            if (nextLine.begin > elapsedTime) {
                if (nextWordStart < 0 || nextLine.begin < nextWordStart) nextWordStart = nextLine.begin;
                break;
            }
        }
    } else {
        for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
            DateLyricsTimedLine *upcomingLine = DateLyricsFilteredLine(lines[i], options.showAdlibs);
            if (upcomingLine && upcomingLine.begin > elapsedTime) {
                nextWordStart = upcomingLine.begin;
                break;
            }
        }
    }

    NSTimeInterval nextDot = -1.0;
    NSDictionary *interludePayload = DateLyricsInterludePayload(lines, resolvedLineIndex, elapsedTime, options.showAdlibs, options.showInterlude, options.interludeStyle, &nextDot);
    if (interludePayload) wordPayload = interludePayload;
    if (nextDot > elapsedTime && (nextWordStart < 0 || nextDot < nextWordStart)) nextWordStart = nextDot;
    
    NSTimeInterval nextTrigger = -1.0;
    if (nextWordStart > elapsedTime) nextTrigger = nextWordStart;

    if (nextTriggerOut) *nextTriggerOut = nextTrigger;
    if (nextLineTriggerOut) {
        NSTimeInterval nextLineTrigger = -1.0;
        if (resolvedLineIndex >= 0) {
            for (NSInteger i = resolvedLineIndex + 1; i < (NSInteger)lines.count; i++) {
                DateLyricsTimedLine *nextLine = DateLyricsFilteredLine(lines[i], options.showAdlibs);
                if (!nextLine) continue;
                if (nextLine.begin > elapsedTime) {
                    nextLineTrigger = nextLine.begin;
                    break;
                }
            }
        } else if (resolvedLineIndex < 0) {
            for (DateLyricsTimedLine *upcomingLine in lines) {
                DateLyricsTimedLine *filteredLine = DateLyricsFilteredLine(upcomingLine, options.showAdlibs);
                if (filteredLine && filteredLine.begin > elapsedTime) {
                    nextLineTrigger = filteredLine.begin;
                    break;
                }
            }
        }
        *nextLineTriggerOut = nextLineTrigger;
    }

    return wordPayload;
}

dispatch_queue_t gLyricsQueue = nil;
ICURLSession *gSession = nil;
ICMusicKitRequestContext *gRequestContext = nil;
NSMutableArray<LyricsTask *> *gLyricsTaskQueue = nil;
NSMutableSet<NSNumber *> *gPendingLyricsIDs = nil;
BOOL gIsProcessingQueue = NO;
NSString *gLyricsRootPath = nil;
NSMutableDictionary<NSNumber *, NSArray<MSVLyricsLine *> *> *gLyricsCache = nil;
NSMutableDictionary<NSNumber *, NSArray<DateLyricsTimedLine *> *> *gWordLyricsCache = nil;
NSMutableArray<NSNumber *> *gLyricsCacheOrder = nil;
// Transcript-only files are a valid Apple response, but they are not useful to
// DateLyrics.  Remember rejected Adam IDs for this Music process so every
// now-playing update does not refetch the same unsynchronised document.
NSMutableSet<NSNumber *> *gUnsynchronizedLyricsIDs = nil;
// Musixmatch is an opt-in fallback only.  These state objects are touched on
// gLyricsQueue; the NSURLSession callbacks hop back to that queue before
// mutating them.
NSMutableSet<NSNumber *> *gMusixmatchPendingStoreIDs = nil;
NSMutableSet<NSNumber *> *gMusixmatchWordUpgradeAttemptedStoreIDs = nil;
NSMutableDictionary<NSNumber *, NSNumber *> *gMusixmatchFailureRetryAfter = nil;
NSMutableArray<DateLyricsMusixmatchTask *> *gMusixmatchTokenWaiters = nil;
BOOL gMusixmatchTokenRequestInFlight = NO;
BOOL gMusixmatchTokenCacheLoaded = NO;
NSString *gMusixmatchUserToken = nil;
NSTimeInterval gMusixmatchTokenFetchedAt = 0.0;
pthread_mutex_t gLyricsCacheMutex = PTHREAD_MUTEX_INITIALIZER;
__weak MPNowPlayingContentItem *gCurrentContentItem = nil;

