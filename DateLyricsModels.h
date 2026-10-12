#pragma once

@import Foundation;
@import QuartzCore;

@interface LyricsTask : NSObject
@property (nonatomic, assign) NSInteger iTunesStoreID;
@property (nonatomic, assign) NSInteger lyricsAdamID;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, strong) NSURL *lyricURL;
@property (nonatomic, strong) NSString *lyricsFilePath;
@property (nonatomic, copy) NSString *fallbackTitle;
@property (nonatomic, copy) NSString *fallbackArtist;
@property (nonatomic, copy) NSString *fallbackAlbum;
@property (nonatomic, assign) NSTimeInterval fallbackDuration;
@end

@interface DateLyricsMusixmatchTask : NSObject
@property (nonatomic, assign) NSInteger storeID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *subtitleBody;
@property (nonatomic, assign) BOOL refreshedToken;
@property (nonatomic, assign) BOOL wordSyncOnly;
@property (nonatomic, assign) NSInteger commontrackID;
@end

@interface DateLyricsTimedWord : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *separatorBefore;
@property (nonatomic, assign, getter=isBackground) BOOL background;
@end

@interface DateLyricsTimedLine : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSArray<DateLyricsTimedWord *> *words;
@property (nonatomic, strong) DateLyricsTimedLine *amlCachedFiltered;
@property (nonatomic, assign) BOOL amlCachedFilteredValid;
@property (nonatomic, assign) BOOL amlCachedFilteredAdlibs;
@end

@interface DateLyricsScore : NSObject
@property (nonatomic, assign) NSInteger trackId;
@property (nonatomic, assign) BOOL hasWordTiming;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSArray<DateLyricsTimedLine *> *lines;
- (instancetype)initWithJSONData:(NSData *)data;
@end

@interface DateLyricsWeakBox : NSObject
@property (nonatomic, weak) id object;
@end

@interface DateLyricsSplitPlan : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) id lineId;
@property (nonatomic, assign) NSInteger trackId;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, copy) NSString *fontKey;
@property (nonatomic, strong) NSArray<NSValue *> *segments;
@property (nonatomic, assign) NSUInteger lastIndex;
@end

@interface DateLyricsSweepVoice : NSObject
@property (nonatomic, strong) CALayer *clip;
@property (nonatomic, strong) CAGradientLayer *bar;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) CGFloat fromX;
@property (nonatomic, assign) CGFloat toX;
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@end

@interface DateLyricsSweepMask : NSObject
@property (nonatomic, strong) CALayer *root;
@property (nonatomic, strong) CALayer *dim;
@property (nonatomic, strong) DateLyricsSweepVoice *foreground;
@property (nonatomic, strong) DateLyricsSweepVoice *background;
@property (nonatomic, copy) NSDictionary *payload;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) CGSize boundsSize;
@end
