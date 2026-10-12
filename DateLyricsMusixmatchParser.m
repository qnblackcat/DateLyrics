#import "DateLyricsMusixmatchParser.h"
#import <math.h>

NSString *DateLyricsMusixmatchNormalizedString(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *normalized = [[value lowercaseString] decomposedStringWithCanonicalMapping];
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];
    BOOL needsSpace = NO;
    for (NSUInteger index = 0; index < normalized.length; index++) {
        unichar character = [normalized characterAtIndex:index];
        if ([alphanumeric characterIsMember:character]) {
            if (needsSpace && result.length > 0) [result appendString:@" "];
            [result appendFormat:@"%C", character];
            needsSpace = NO;
        } else {
            needsSpace = YES;
        }
    }
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

double DateLyricsMusixmatchDouble(id value, double fallback) {
    if (![value respondsToSelector:@selector(doubleValue)]) return fallback;
    double number = [value doubleValue];
    return isfinite(number) ? number : fallback;
}

NSArray<DateLyricsTimedLine *> *DateLyricsMusixmatchLinesFromBody(id body, NSTimeInterval trackDuration) {
    id parsedBody = body;
    if ([parsedBody isKindOfClass:NSString.class]) {
        NSData *data = [(NSString *)parsedBody dataUsingEncoding:NSUTF8StringEncoding];
        parsedBody = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    }
    if (![parsedBody isKindOfClass:NSArray.class]) return nil;

    NSMutableArray<DateLyricsTimedLine *> *lines = [NSMutableArray array];
    NSArray *rawLines = (NSArray *)parsedBody;
    for (NSUInteger lineIndex = 0; lineIndex < rawLines.count; lineIndex++) {
        id rawLine = rawLines[lineIndex];
        if (![rawLine isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *lineDictionary = (NSDictionary *)rawLine;
        double begin = DateLyricsMusixmatchDouble(lineDictionary[@"ts"], -1.0);
        double end = DateLyricsMusixmatchDouble(lineDictionary[@"te"], -1.0);
        if (begin < 0.0) continue;
        if (end <= begin) {
            for (NSUInteger nextIndex = lineIndex + 1; nextIndex < rawLines.count; nextIndex++) {
                id nextLine = rawLines[nextIndex];
                if (![nextLine isKindOfClass:NSDictionary.class]) continue;
                double nextBegin = DateLyricsMusixmatchDouble(nextLine[@"ts"], -1.0);
                if (nextBegin > begin) {
                    end = nextBegin;
                    break;
                }
            }
        }
        if (end <= begin && trackDuration > begin) end = trackDuration;
        if (end <= begin) end = begin + 5.0;

        NSArray *rawWords = [lineDictionary[@"l"] isKindOfClass:NSArray.class] ? lineDictionary[@"l"] : @[];
        NSMutableArray<DateLyricsTimedWord *> *words = [NSMutableArray array];
        NSMutableString *assembledText = [NSMutableString string];
        NSMutableString *pendingSeparator = [NSMutableString string];
        for (NSUInteger index = 0; index < rawWords.count; index++) {
            id rawWord = rawWords[index];
            if (![rawWord isKindOfClass:NSDictionary.class]) continue;
            NSString *text = [rawWord[@"c"] isKindOfClass:NSString.class] ? rawWord[@"c"] : @"";
            if (text.length == 0) continue;

            // Rich-sync represents spaces as their own timed fragments.  Keep
            // those characters in the line text, but store them as a separator
            // instead of a highlightable word; otherwise the active range can
            // land on a blank and long-line splitting counts spaces as words.
            BOOL isWhitespace = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0;
            if (isWhitespace) {
                [pendingSeparator appendString:text];
                continue;
            }

            NSString *separator = pendingSeparator.length > 0
                ? [pendingSeparator copy]
                : (words.count > 0 ? @" " : @"");
            [assembledText appendString:separator];
            [assembledText appendString:text];

            double offset = DateLyricsMusixmatchDouble(rawWord[@"o"], 0.0);
            double wordBegin = begin + MAX(0.0, offset);
            double nextOffset = end - begin;
            for (NSUInteger nextIndex = index + 1; nextIndex < rawWords.count; nextIndex++) {
                id nextWord = rawWords[nextIndex];
                if (![nextWord isKindOfClass:NSDictionary.class]) continue;
                nextOffset = DateLyricsMusixmatchDouble(nextWord[@"o"], nextOffset);
                break;
            }
            double wordEnd = MIN(end, begin + MAX(offset + 0.01, nextOffset));
            if (wordEnd <= wordBegin) wordEnd = MIN(end, wordBegin + 0.01);

            DateLyricsTimedWord *word = [DateLyricsTimedWord new];
            word.begin = wordBegin;
            word.end = wordEnd;
            word.text = text;
            word.separatorBefore = separator;
            [pendingSeparator setString:@""];
            word.background = NO;
            [words addObject:word];
        }

        NSString *lineText = [assembledText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (lineText.length == 0 && [lineDictionary[@"x"] isKindOfClass:NSString.class]) {
            lineText = [lineDictionary[@"x"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (lineText.length == 0) continue;

        DateLyricsTimedLine *line = [DateLyricsTimedLine new];
        line.begin = begin;
        line.end = end;
        line.text = lineText;
        line.words = words;
        [lines addObject:line];
    }

    [lines sortUsingComparator:^NSComparisonResult(DateLyricsTimedLine *left, DateLyricsTimedLine *right) {
        return left.begin < right.begin ? NSOrderedAscending : (left.begin > right.begin ? NSOrderedDescending : NSOrderedSame);
    }];
    return lines.count > 0 ? [lines copy] : nil;
}

NSArray<DateLyricsTimedLine *> *DateLyricsMusixmatchLinesFromLRC(NSString *body, NSTimeInterval trackDuration) {
    if (![body isKindOfClass:NSString.class] || body.length == 0) return nil;
    static NSRegularExpression *timestampExpression = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timestampExpression = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d+):(\\d+(?:\\.\\d+)?)\\](.*)$" options:0 error:nil];
    });

    NSMutableArray<DateLyricsTimedLine *> *lines = [NSMutableArray array];
    [body enumerateLinesUsingBlock:^(NSString *rawLine, BOOL *stop) {
        NSTextCheckingResult *match = [timestampExpression firstMatchInString:rawLine options:0 range:NSMakeRange(0, rawLine.length)];
        if (match.numberOfRanges < 4) return;
        double minutes = [[rawLine substringWithRange:[match rangeAtIndex:1]] doubleValue];
        double seconds = [[rawLine substringWithRange:[match rangeAtIndex:2]] doubleValue];
        NSString *text = [[rawLine substringWithRange:[match rangeAtIndex:3]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length == 0) return;

        DateLyricsTimedLine *line = [DateLyricsTimedLine new];
        line.begin = MAX(0.0, minutes * 60.0 + seconds);
        line.text = text;
        line.words = @[];
        [lines addObject:line];
    }];
    [lines sortUsingComparator:^NSComparisonResult(DateLyricsTimedLine *left, DateLyricsTimedLine *right) {
        return left.begin < right.begin ? NSOrderedAscending : (left.begin > right.begin ? NSOrderedDescending : NSOrderedSame);
    }];
    for (NSUInteger index = 0; index < lines.count; index++) {
        DateLyricsTimedLine *line = lines[index];
        NSTimeInterval nextBegin = index + 1 < lines.count ? lines[index + 1].begin : trackDuration;
        line.end = nextBegin > line.begin ? nextBegin : line.begin + 5.0;
    }
    return lines.count > 0 ? [lines copy] : nil;
}

