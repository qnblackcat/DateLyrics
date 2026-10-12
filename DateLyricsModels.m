#import "DateLyricsModels.h"
#import <math.h>

@implementation LyricsTask
@end
@implementation DateLyricsMusixmatchTask
@end
@implementation DateLyricsTimedWord
@end
@implementation DateLyricsTimedLine
@end
@implementation DateLyricsWeakBox
@end
@implementation DateLyricsSplitPlan
@end
@implementation DateLyricsSweepVoice
@end
@implementation DateLyricsSweepMask
@end

static BOOL DateLyricsSerializedLinesHaveTiming(NSArray *rawLines) {
    if (![rawLines isKindOfClass:NSArray.class] || rawLines.count == 0) return NO;

    BOOL hasTiming = NO;
    for (id rawLine in rawLines) {
        if (![rawLine isKindOfClass:NSDictionary.class]) return NO;
        NSDictionary *line = (NSDictionary *)rawLine;
        NSNumber *begin = line[@"begin"];
        NSNumber *end = line[@"end"];
        if (![begin isKindOfClass:NSNumber.class] || ![end isKindOfClass:NSNumber.class] ||
            !isfinite(begin.doubleValue) || !isfinite(end.doubleValue)) {
            return NO;
        }
        if (end.doubleValue > begin.doubleValue || begin.doubleValue > 0.001) hasTiming = YES;
        // Line-synced TTML may expose only a start time; a non-zero start still
        // establishes an actual timeline.  The all-zero transcript score does
        // not pass this check.

        NSArray *rawWords = line[@"words"];
        if (rawWords && ![rawWords isKindOfClass:NSArray.class]) return NO;
        for (id rawWord in rawWords) {
            if (![rawWord isKindOfClass:NSDictionary.class]) return NO;
            NSNumber *wordBegin = rawWord[@"b"];
            NSNumber *wordEnd = rawWord[@"e"];
            if (![wordBegin isKindOfClass:NSNumber.class] || ![wordEnd isKindOfClass:NSNumber.class] ||
                !isfinite(wordBegin.doubleValue) || !isfinite(wordEnd.doubleValue)) {
                return NO;
            }
            if (wordEnd.doubleValue > wordBegin.doubleValue) hasTiming = YES;
        }
    }
    return hasTiming;
}

// Seconds by which estimated word starts are pulled earlier (see below), and
// the largest share of a line's sung time that the shift may take, so short
// lines are not switched to their last segment almost immediately.
static const double kDateLyricsYTMSegmentLead = 0.3;
static const double kDateLyricsYTMSegmentLeadMaxFraction = 0.2;

// YouTube Music times whole lines only. Spread each line's sung time over its
// words in proportion to their length so the word-based machinery (Split Long
// Lines follows the active word) works for it. The line's end is usually the
// next line's start, so assume a natural singing pace rather than the full span.
static NSArray<DateLyricsTimedWord *> *DateLyricsEstimatedWordsForLine(DateLyricsTimedLine *line) {
    NSString *text = line.text;
    if (![text isKindOfClass:NSString.class] || text.length == 0) return @[];
    static NSRegularExpression *wordExpression = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wordExpression = [NSRegularExpression regularExpressionWithPattern:@"\\S+" options:0 error:nil];
    });
    NSArray<NSTextCheckingResult *> *matches = [wordExpression matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    double sungDuration = MIN(line.end - line.begin, MAX(1.0, 0.075 * (double)text.length));
    NSUInteger totalWeight = 0;
    for (NSTextCheckingResult *match in matches) totalWeight += match.range.length;
    if (matches.count == 0 || totalWeight == 0 || !(sungDuration > 0.0)) return @[];

    NSMutableArray<DateLyricsTimedWord *> *words = [NSMutableArray arrayWithCapacity:matches.count];
    NSUInteger previousEnd = 0, consumedWeight = 0;
    for (NSTextCheckingResult *match in matches) {
        NSRange range = match.range;
        DateLyricsTimedWord *word = [DateLyricsTimedWord new];
        word.begin = line.begin + sungDuration * ((double)consumedWeight / (double)totalWeight);
        consumedWeight += range.length;
        word.end = line.begin + sungDuration * ((double)consumedWeight / (double)totalWeight);
        word.text = [text substringWithRange:range];
        word.separatorBefore = [text substringWithRange:NSMakeRange(previousEnd, range.location - previousEnd)];
        word.background = NO;
        [words addObject:word];
        previousEnd = NSMaxRange(range);
    }

    // The estimate tends to reach later words after the singer has. Showing the
    // next segment a little early reads better than showing it late, so pull
    // every word but the first earlier by a fixed lead, keeping the words
    // contiguous (each word ends where the next begins).
    if (words.count > 1) {
        double lastEnd = words.lastObject.end;
        double lead = MIN(kDateLyricsYTMSegmentLead, kDateLyricsYTMSegmentLeadMaxFraction * sungDuration);
        for (NSUInteger index = 1; index < words.count; index++) {
            words[index].begin = MAX(line.begin, words[index].begin - lead);
        }
        for (NSUInteger index = 0; index + 1 < words.count; index++) {
            words[index].end = MAX(words[index].begin, words[index + 1].begin);
        }
        words.lastObject.end = MAX(words.lastObject.begin, lastEnd);
    }
    return words;
}

@implementation DateLyricsScore
- (instancetype)initWithJSONData:(NSData *)data {
    if ((self = [super init])) {
        NSDictionary *json = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![json isKindOfClass:[NSDictionary class]] || ![json[@"kind"] isEqualToString:@"score"]) return nil;
        self.trackId = [json[@"trackId"] integerValue];
        self.hasWordTiming = [json[@"hasWordTiming"] boolValue];
        self.source = [json[@"source"] isKindOfClass:NSString.class] ? json[@"source"] : nil;
        NSArray *rawLines = json[@"lines"];
        if (self.trackId <= 0 || !DateLyricsSerializedLinesHaveTiming(rawLines)) return nil;
        NSMutableArray *parsedLines = [NSMutableArray array];
        for (id rawLine in rawLines) {
            if (![rawLine isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *lineDict = (NSDictionary *)rawLine;
            DateLyricsTimedLine *line = [DateLyricsTimedLine new];
            line.begin = [lineDict[@"begin"] doubleValue];
            line.end = [lineDict[@"end"] doubleValue];
            line.text = lineDict[@"text"];
            NSMutableArray *parsedWords = [NSMutableArray array];
            id wordsValue = lineDict[@"words"];
            NSArray *rawWords = [wordsValue isKindOfClass:NSArray.class] ? wordsValue : @[];
            for (id rawWord in rawWords) {
                if (![rawWord isKindOfClass:NSDictionary.class]) continue;
                NSDictionary *wordDict = (NSDictionary *)rawWord;
                DateLyricsTimedWord *word = [DateLyricsTimedWord new];
                word.begin = [wordDict[@"b"] doubleValue];
                word.end = [wordDict[@"e"] doubleValue];
                word.text = wordDict[@"t"];
                word.separatorBefore = wordDict[@"s"];
                word.background = [wordDict[@"bg"] boolValue];
                [parsedWords addObject:word];
            }
            line.words = parsedWords;
            [parsedLines addObject:line];
        }
        // Older score files predate the explicit hasWordTiming flag. Infer it
        // from the serialized words so switching from a line-synced track can
        // never leave a cached syllable score rendered as permanently dim.
        if (!self.hasWordTiming) {
            for (DateLyricsTimedLine *line in parsedLines) {
                for (DateLyricsTimedWord *word in line.words) {
                    if (word.end > word.begin) {
                        self.hasWordTiming = YES;
                        break;
                    }
                }
                if (self.hasWordTiming) break;
            }
        }
        if ([self.source isEqualToString:@"youtubemusic"]) {
            BOOL estimatedAny = NO;
            for (DateLyricsTimedLine *line in parsedLines) {
                if (line.words.count > 0) continue;
                NSArray<DateLyricsTimedWord *> *estimated = DateLyricsEstimatedWordsForLine(line);
                if (estimated.count > 0) {
                    line.words = estimated;
                    estimatedAny = YES;
                }
            }
            if (estimatedAny) self.hasWordTiming = YES;
        }
        self.lines = parsedLines;
    }
    return self;
}
@end

