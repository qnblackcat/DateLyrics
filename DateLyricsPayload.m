#import "DateLyricsPayload.h"

NSDictionary *DateLyricsMakePayload(NSString *text, NSRange activeRange) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;
    NSMutableDictionary *payload = [@{ @"text": text } mutableCopy];
    if (activeRange.location != NSNotFound && NSMaxRange(activeRange) <= text.length) {
        payload[@"loc"] = @(activeRange.location);
        payload[@"len"] = @(activeRange.length);
    }
    
    return payload;
}

NSDictionary *DateLyricsMakePayloadWithBackgroundRange(NSString *text, NSRange activeRange, NSRange backgroundRange) {
    NSDictionary *basePayload = DateLyricsMakePayload(text, activeRange);
    NSMutableDictionary *payload = nil;
    if (basePayload) {
        payload = [basePayload mutableCopy];
    }
    if (payload.count == 0) return nil;
    if (backgroundRange.location != NSNotFound && NSMaxRange(backgroundRange) <= text.length) {
        payload[@"bgLoc"] = @(backgroundRange.location);
        payload[@"bgLen"] = @(backgroundRange.length);
    }
    
    return payload;
}

void DateLyricsSetRangeFields(NSMutableDictionary *payload, NSString *prefix, NSRange range) {
    if (![payload isKindOfClass:NSMutableDictionary.class] || prefix.length == 0) return;

    NSString *locKey = [prefix stringByAppendingString:@"Loc"];
    NSString *lenKey = [prefix stringByAppendingString:@"Len"];
    if (range.location != NSNotFound && range.length > 0) {
        payload[locKey] = @(range.location);
        payload[lenKey] = @(range.length);
    } else {
        [payload removeObjectForKey:locKey];
        [payload removeObjectForKey:lenKey];
    }
}

