#import "DateLyricsLyricsParser.h"
#import <math.h>

NSTimeInterval DateLyricsParseTimeString(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return 0;
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@":"];
    if (parts.count == 1) return value.doubleValue;
    if (parts.count == 2) return (parts[0].doubleValue * 60.0) + parts[1].doubleValue;
    if (parts.count == 3) return (parts[0].doubleValue * 3600.0) + (parts[1].doubleValue * 60.0) + parts[2].doubleValue;
    return 0;
}

@implementation DateLyricsWordTTMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _pendingSeparator = [NSMutableString string];
        _spanBackgroundStack = [NSMutableArray array];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"p"]) {
        self.insideParagraph = YES;
        self.currentLine = [DateLyricsTimedLine new];
        self.currentLine.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
        self.currentLine.end = DateLyricsParseTimeString(attributeDict[@"end"]);
        self.currentWords = [NSMutableArray array];
        [self.spanBackgroundStack removeAllObjects];
        [self.pendingSeparator setString:@""];
    } else if (self.insideParagraph && [elementName isEqualToString:@"span"]) {
        NSString *role = attributeDict[@"ttm:role"] ?: attributeDict[@"role"];
        BOOL isBackground = [role isEqualToString:@"x-bg"] || [[self.spanBackgroundStack lastObject] boolValue];
        [self.spanBackgroundStack addObject:@(isBackground)];
        BOOL hasTiming = attributeDict[@"begin"] != nil || attributeDict[@"end"] != nil;
        if (hasTiming) {
            DateLyricsTimedWord *word = [DateLyricsTimedWord new];
            word.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
            word.end = DateLyricsParseTimeString(attributeDict[@"end"]);
            word.separatorBefore = [self.pendingSeparator copy] ?: @"";
            word.background = isBackground;
            [self.currentWords addObject:word];
            self.currentSpanText = [NSMutableString string];
            [self.pendingSeparator setString:@""];
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (!self.insideParagraph || string.length == 0) return;
    if (self.currentSpanText) {
        [self.currentSpanText appendString:string];
    } else {
        [self.pendingSeparator appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"span"]) {
        if (self.currentSpanText) {
            DateLyricsTimedWord *word = self.currentWords.lastObject;
            if (word && !word.text.length) {
                word.text = [self.currentSpanText copy];
            }
            self.currentSpanText = nil;
        }
        if (self.spanBackgroundStack.count > 0) {
            [self.spanBackgroundStack removeLastObject];
        }
    } else if ([elementName isEqualToString:@"p"] && self.currentLine) {
        NSMutableString *fullText = [NSMutableString string];
        for (DateLyricsTimedWord *word in self.currentWords) {
            if (word.separatorBefore.length > 0) {
                [fullText appendString:word.separatorBefore];
            }
            if (word.text.length > 0) {
                [fullText appendString:word.text];
            }
        }
        self.currentLine.text = [fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.currentLine.words = [self.currentWords copy];
        if (self.currentLine.text.length > 0 && self.currentLine.words.count > 0) {
            [self.lines addObject:self.currentLine];
        }
        self.currentLine = nil;
        self.currentWords = nil;
        self.insideParagraph = NO;
        [self.spanBackgroundStack removeAllObjects];
        [self.pendingSeparator setString:@""];
    }
}

@end

NSArray<DateLyricsTimedLine *> *DateLyricsParseWordTimedLines(NSData *data) {
    if (!data.length) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    DateLyricsWordTTMLParserDelegate *delegate = [DateLyricsWordTTMLParserDelegate new];
    parser.delegate = delegate;
    BOOL ok = [parser parse];
    
    if (!ok || delegate.lines.count == 0) return nil;
    return [delegate.lines copy];
}

