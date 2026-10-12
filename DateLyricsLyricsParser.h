#pragma once

@import Foundation;
#import "DateLyricsModels.h"

@interface DateLyricsWordTTMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedLine *> *lines;
@property (nonatomic, strong) DateLyricsTimedLine *currentLine;
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedWord *> *currentWords;
@property (nonatomic, strong) NSMutableString *pendingSeparator;
@property (nonatomic, strong) NSMutableString *currentSpanText;
@property (nonatomic, assign) BOOL insideParagraph;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spanBackgroundStack;
@end

FOUNDATION_EXPORT NSTimeInterval DateLyricsParseTimeString(NSString *value);
FOUNDATION_EXPORT NSArray<DateLyricsTimedLine *> *DateLyricsParseWordTimedLines(NSData *data);
