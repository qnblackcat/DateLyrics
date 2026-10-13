#pragma once

#import "DateLyricsModels.h"

FOUNDATION_EXPORT NSString *DateLyricsMusixmatchNormalizedString(NSString *value);
FOUNDATION_EXPORT double DateLyricsMusixmatchDouble(id value, double fallback);
FOUNDATION_EXPORT NSArray<DateLyricsTimedLine *> *DateLyricsMusixmatchLinesFromBody(id body, NSTimeInterval trackDuration);
FOUNDATION_EXPORT NSArray<DateLyricsTimedLine *> *DateLyricsMusixmatchLinesFromLRC(NSString *body, NSTimeInterval trackDuration);
