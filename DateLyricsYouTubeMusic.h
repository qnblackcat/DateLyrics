// Minimal interfaces reconstructed from the YouTube Music class dump (9.37.2 /
// 9.39.2). Keep this self-contained so the tweak does not need the target app's
// headers at build time.

#pragma once

#import <Foundation/Foundation.h>

@interface YTSingleVideoTime : NSObject
@property (readonly, nonatomic) double time;
@end

@interface YTLocalPlaybackController : NSObject
@property (readonly, nonatomic) NSString *currentVideoID;
@property (readonly, nonatomic) YTSingleVideoTime *currentVideoTime;
@property (readonly, nonatomic) _Bool isPlayingAd;
- (void)setPlaybackRateModel:(id)model;
- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)change;
- (void)singleVideo:(id)video playbackRateDidChange:(float)rate;
@end
