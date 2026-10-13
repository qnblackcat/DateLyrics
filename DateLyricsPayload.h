#pragma once

@import Foundation;

FOUNDATION_EXPORT NSDictionary *DateLyricsMakePayload(NSString *text, NSRange activeRange);
FOUNDATION_EXPORT NSDictionary *DateLyricsMakePayloadWithBackgroundRange(NSString *text, NSRange activeRange, NSRange backgroundRange);
FOUNDATION_EXPORT void DateLyricsSetRangeFields(NSMutableDictionary *payload, NSString *prefix, NSRange range);
