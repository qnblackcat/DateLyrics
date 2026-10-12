#import "DateLyricsText.h"

NSString *DateLyricsStripParentheses(NSString *text, BOOL showAdlibs) {
    if (!text) return nil;
    if (showAdlibs) return text;

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\([^)]*\\)|\\[[^]]*\\]" options:0 error:nil];
    });

    NSString *stripped = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    
    static NSRegularExpression *spacesRegex = nil;
    static dispatch_once_t spacesOnceToken;
    dispatch_once(&spacesOnceToken, ^{
        spacesRegex = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    });
    stripped = [spacesRegex stringByReplacingMatchesInString:stripped options:0 range:NSMakeRange(0, stripped.length) withTemplate:@" "];
    stripped = [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return stripped.length > 0 ? stripped : nil;
}

