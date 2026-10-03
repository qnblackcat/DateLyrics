#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <roothide.h>
#import "DateLyricsRootListController.h"

extern char **environ;

@interface DateLyricsPreviewWord : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL isBackground;
@property (nonatomic, assign) double beginTime;
@property (nonatomic, assign) double endTime;
@end
@implementation DateLyricsPreviewWord
@end

@interface DateLyricsPreviewLine : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<NSValue *> *wordRanges;
@property (nonatomic, copy) NSArray<NSNumber *> *wordIsBackground;
@property (nonatomic, assign) double beginTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, copy) NSArray<NSNumber *> *wordBeginTimes;
@property (nonatomic, copy) NSArray<NSNumber *> *wordEndTimes;
@end
@implementation DateLyricsPreviewLine
@end

@interface DateLyricsTTMLParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsPreviewLine *> *lines;
@property (nonatomic, strong) NSMutableArray<DateLyricsPreviewWord *> *currentWords;
@property (nonatomic, assign) NSInteger backgroundDepth;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spanIsBgStack;
@property (nonatomic, assign) BOOL insideP;
@property (nonatomic, assign) double currentPBegin;
@property (nonatomic, assign) double currentPEnd;
@property (nonatomic, assign) double currentSpanBegin;
@property (nonatomic, assign) double currentSpanEnd;
@end

@implementation DateLyricsTTMLParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _currentWords = [NSMutableArray array];
        _backgroundDepth = 0;
        _spanIsBgStack = [NSMutableArray array];
        _insideP = NO;
        _currentPBegin = 0.0;
        _currentPEnd = 0.0;
        _currentSpanBegin = 0.0;
        _currentSpanEnd = 0.0;
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"p"]) {
        _insideP = YES;
        [_currentWords removeAllObjects];
        _backgroundDepth = 0;
        [_spanIsBgStack removeAllObjects];
        _currentPBegin = [attributeDict[@"begin"] doubleValue];
        _currentPEnd = [attributeDict[@"end"] doubleValue];
    } else if ([elementName isEqualToString:@"span"] && _insideP) {
        BOOL isThisSpanBg = NO;
        NSString *role = attributeDict[@"ttm:role"] ?: attributeDict[@"role"];
        if ([role isEqualToString:@"x-bg"]) {
            isThisSpanBg = YES;
            _backgroundDepth++;
        }
        [_spanIsBgStack addObject:@(isThisSpanBg)];

        if (attributeDict[@"begin"]) {
            _currentSpanBegin = [attributeDict[@"begin"] doubleValue];
        } else {
            _currentSpanBegin = 0.0;
        }
        if (attributeDict[@"end"]) {
            _currentSpanEnd = [attributeDict[@"end"] doubleValue];
        } else {
            _currentSpanEnd = 0.0;
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (!_insideP) return;
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    DateLyricsPreviewWord *word = [[DateLyricsPreviewWord alloc] init];
    word.text = trimmed;
    word.isBackground = (_backgroundDepth > 0);
    word.beginTime = _currentSpanBegin;
    word.endTime = _currentSpanEnd;
    [_currentWords addObject:word];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"span"] && _insideP) {
        if (_spanIsBgStack.count > 0) {
            BOOL wasThisSpanBg = [[_spanIsBgStack lastObject] boolValue];
            [_spanIsBgStack removeLastObject];
            if (wasThisSpanBg && _backgroundDepth > 0) {
                _backgroundDepth--;
            }
        }
    } else if ([elementName isEqualToString:@"p"] && _insideP) {
        _insideP = NO;
        if (_currentWords.count == 0) return;

        NSMutableString *text = [NSMutableString string];
        NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
        NSMutableArray<NSNumber *> *bgFlags = [NSMutableArray array];
        NSMutableArray<NSNumber *> *wordBegins = [NSMutableArray array];
        NSMutableArray<NSNumber *> *wordEnds = [NSMutableArray array];
        for (DateLyricsPreviewWord *word in _currentWords) {
            if (text.length > 0) [text appendString:@" "];
            NSRange range = NSMakeRange(text.length, word.text.length);
            [text appendString:word.text];
            [ranges addObject:[NSValue valueWithRange:range]];
            [bgFlags addObject:@(word.isBackground)];
            [wordBegins addObject:@(word.beginTime)];
            [wordEnds addObject:@(word.endTime)];
        }

        DateLyricsPreviewLine *line = [[DateLyricsPreviewLine alloc] init];
        line.text = [text copy];
        line.wordRanges = [ranges copy];
        line.wordIsBackground = [bgFlags copy];
        line.beginTime = _currentPBegin;
        line.endTime = _currentPEnd;
        line.wordBeginTimes = [wordBegins copy];
        line.wordEndTimes = [wordEnds copy];
        [_lines addObject:line];
    }
}

@end

static NSArray<DateLyricsPreviewLine *> *DateLyricsLoadPreviewLines(void) {
    NSString *path = [[NSBundle bundleForClass:NSClassFromString(@"DateLyricsRootListController")] pathForResource:@"preview" ofType:@"xml"];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    DateLyricsTTMLParser *delegate = [[DateLyricsTTMLParser alloc] init];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = delegate;
    [parser parse];
    return delegate.lines.count > 0 ? [delegate.lines copy] : nil;
}

static NSString *const kDateLyricsPrefsSuite = @"com.shalamand3r.datelyrics";
static UIImage *_cachedGithubIcon = nil;

static NSArray<NSString *> *DateLyricsDebugLogPaths(void) {
    NSString *primaryPath = @"/var/mobile/Library/DateLyrics/tweak-debug.log";
    NSString *jbrootPath = jbroot(primaryPath);
    NSMutableArray *paths = [NSMutableArray arrayWithObject:primaryPath];
    if (![paths containsObject:jbrootPath]) [paths addObject:jbrootPath];
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if ([proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:@"com.apple.Music"];
        NSURL *containerURL = [proxy respondsToSelector:@selector(dataContainerURL)] ? [proxy performSelector:@selector(dataContainerURL)] : nil;
        if (containerURL.path.length > 0) [paths addObject:[containerURL.path stringByAppendingPathComponent:@"Library/DateLyrics/tweak-debug.log"]];
    }
    return paths;
}

static NSString *DateLyricsCombinedDebugLogText(void) {
    NSMutableString *combined = [NSMutableString string];
    for (NSString *path in DateLyricsDebugLogPaths()) {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (text.length > 0) [combined appendString:text];
    }
    return combined.length > 0 ? combined : nil;
}

static NSString *DateLyricsRecentLogText(NSString *text) {
    if (text.length == 0) return nil;
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger maximumLines = 500;
    if (lines.count <= maximumLines) return text;
    return [[lines subarrayWithRange:NSMakeRange(lines.count - maximumLines, maximumLines)] componentsJoinedByString:@"\n"];
}

@interface DateLyricsLogViewController : UIViewController
@property (nonatomic, copy) NSString *logText;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation DateLyricsLogViewController

- (void)loadView {
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.textView.alwaysBounceVertical = YES;
    self.textView.backgroundColor = [UIColor systemBackgroundColor];
    self.textView.textColor = [UIColor labelColor];
    self.view = self.textView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Debug Log";
    self.textView.text = self.logText.length > 0 ? self.logText : @"No log entries yet.";
    UIBarButtonItem *copyButton = [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(copyLog)];
    UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(clearLog)];
    self.navigationItem.rightBarButtonItems = @[copyButton, clearButton];
}

- (void)copyLog {
    if (self.logText.length == 0) return;
    UIPasteboard.generalPasteboard.string = self.logText;
    self.navigationItem.rightBarButtonItems.firstObject.title = @"Copied";
}

- (void)clearLog {
    for (NSString *path in DateLyricsDebugLogPaths()) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    self.logText = nil;
    self.textView.text = @"No log entries yet.";
}

@end

static NSArray<NSDictionary<NSString *, NSString *> *> *DateLyricsFontOptions(void) {
	static NSArray<NSDictionary<NSString *, NSString *> *> *cachedOptions = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSArray<NSString *> *preferenceOrder = @[@"DemiBold", @"Semibold", @"SemiBold", @"Bold", @"Medium", @"Regular", @"Roman", @"Book", @"Light"];
		NSMutableArray<NSDictionary<NSString *, NSString *> *> *options = [NSMutableArray array];
		NSArray<NSString *> *families = [[UIFont familyNames] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

		for (NSString *family in families) {
			NSArray<NSString *> *fontNames = [[UIFont fontNamesForFamilyName:family] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
			if (fontNames.count == 0) continue;

			NSString *chosenFontName = fontNames.firstObject;
			NSInteger chosenRank = NSIntegerMax;
			for (NSString *fontName in fontNames) {
				NSString *lowerName = fontName.lowercaseString;
				NSInteger rank = preferenceOrder.count + 10;
				for (NSUInteger i = 0; i < preferenceOrder.count; i++) {
					if ([lowerName containsString:[preferenceOrder[i] lowercaseString]]) {
						rank = (NSInteger)i;
						break;
					}
				}
				if (rank < chosenRank) {
					chosenRank = rank;
					chosenFontName = fontName;
				}
			}

			[options addObject:@{
				@"title": family,
				@"value": chosenFontName
			}];
		}

		cachedOptions = [options copy];
	});
	return cachedOptions;
}

static NSArray<NSString *> *DateLyricsFontTitles(void) {
	NSMutableArray<NSString *> *titles = [NSMutableArray array];
	for (NSDictionary<NSString *, NSString *> *option in DateLyricsFontOptions()) {
		[titles addObject:option[@"title"] ?: option[@"value"]];
	}
	return [titles copy];
}

static NSArray<NSString *> *DateLyricsFontValues(void) {
	NSMutableArray<NSString *> *values = [NSMutableArray array];
	for (NSDictionary<NSString *, NSString *> *option in DateLyricsFontOptions()) {
		[values addObject:option[@"value"] ?: @""];
	}
	return [values copy];
}

static NSDictionary *DateLyricsCurrentPrefs(void) {
        NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        values[@"ForceLowercase"] = @([prefs boolForKey:@"ForceLowercase"]);
        values[@"WordHighlighting"] = @([prefs objectForKey:@"WordHighlighting"] ? [prefs boolForKey:@"WordHighlighting"] : YES);
        values[@"UseCustomFont"] = @([prefs boolForKey:@"UseCustomFont"]);
        values[@"TransitionsEnabled"] = @([prefs objectForKey:@"TransitionsEnabled"] ? [prefs boolForKey:@"TransitionsEnabled"] : YES);
        values[@"TransitionStyle"] = @([prefs objectForKey:@"TransitionStyle"] ? (NSInteger)[prefs integerForKey:@"TransitionStyle"] : 1);
        id transDuration = [prefs objectForKey:@"TransitionDuration"];
        values[@"TransitionDuration"] = transDuration ?: @0.3;
        id minScale = [prefs objectForKey:@"MinimumScale"];
        values[@"MinimumScale"] = minScale ?: @0.55;
        NSString *fontName = [prefs objectForKey:@"CustomFontName"];
        if ([fontName isKindOfClass:NSString.class]) values[@"CustomFontName"] = fontName;
        values[@"SplitLongLines"] = @([prefs objectForKey:@"SplitLongLines"] ? [prefs boolForKey:@"SplitLongLines"] : YES);
        values[@"ShowAdlibs"] = @([prefs objectForKey:@"ShowAdlibs"] ? [prefs boolForKey:@"ShowAdlibs"] : NO);
        return values;
}
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSURL *dataContainerURL;
+ (id)applicationProxyForIdentifier:(id)arg1;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID options:(NSDictionary *)options error:(NSError **)error;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID options:(NSDictionary *)options;
@end

@interface DateLyricsRootListController ()
@property (nonatomic, strong) UIImageView *headerImageView;
@property (nonatomic, strong) UILabel *mainTitleLabel;
@property (nonatomic, strong) UILabel *mainPreviewLabel;
@property (nonatomic, strong) NSTimer *previewAnimationTimer;
@property (nonatomic, assign) NSInteger previewLineIndex;
@property (nonatomic, assign) NSInteger previewWordIndex;
@property (nonatomic, strong) NSArray<DateLyricsPreviewLine *> *previewLines;
@property (nonatomic, assign) NSTimeInterval previewStartTime;
@property (nonatomic, assign) BOOL resetInProgress;
@end

@interface DateLyricsFontListController ()
@end

@implementation DateLyricsRootListController

- (NSUInteger)amlSegmentIndexForLine:(NSInteger)lineIdx word:(NSInteger)wordIdx {
        if (!self.previewLines || self.previewLines.count == 0) return 0;
        NSInteger actualLineIdx = lineIdx % (NSInteger)self.previewLines.count;
        DateLyricsPreviewLine *previewLine = self.previewLines[actualLineIdx];

        NSDictionary *prefs = DateLyricsCurrentPrefs();
        BOOL showAdlibs = [prefs[@"ShowAdlibs"] boolValue];
        BOOL splitLongLines = [prefs[@"SplitLongLines"] boolValue];

        if (!splitLongLines) return 0;

        NSMutableString *filteredText = [NSMutableString string];
        NSMutableArray<NSValue *> *filteredRanges = [NSMutableArray array];
        for (NSUInteger i = 0; i < previewLine.wordRanges.count; i++) {
                BOOL isBg = [previewLine.wordIsBackground[i] boolValue];
                if (isBg && !showAdlibs) continue;
                NSRange srcRange = [previewLine.wordRanges[i] rangeValue];
                NSString *word = [previewLine.text substringWithRange:srcRange];
                if (filteredText.length > 0) [filteredText appendString:@" "];
                NSRange newRange = NSMakeRange(filteredText.length, word.length);
                [filteredText appendString:word];
                [filteredRanges addObject:[NSValue valueWithRange:newRange]];
        }

        NSString *baseText = [filteredText copy];
        NSArray<NSValue *> *wordRanges = [filteredRanges copy];

        if (baseText.length == 0 || wordRanges.count < 2) return 0;

        UIFont *font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
        BOOL useCustomFont = [prefs[@"UseCustomFont"] boolValue];
        NSString *fontName = prefs[@"CustomFontName"];
        if (useCustomFont && [fontName isKindOfClass:NSString.class] && fontName.length > 0) {
                UIFont *customFont = [UIFont fontWithName:fontName size:20.0];
                if (customFont) font = customFont;
        }

        CGFloat maxWidth = CGRectGetWidth(self.mainPreviewLabel.bounds);
        if (maxWidth <= 1.0) {
                maxWidth = CGRectGetWidth(self.mainPreviewLabel.frame);
        }
        if (maxWidth <= 1.0) {
                maxWidth = [UIScreen mainScreen].bounds.size.width - 60.0;
        }
        if (maxWidth <= 1.0) return 0;

        CGSize totalSize = [baseText sizeWithAttributes:@{NSFontAttributeName: font}];
        if (totalSize.width <= maxWidth) return 0;

        NSMutableArray<NSValue *> *segmentRanges = [NSMutableArray array];
        NSMutableArray<NSValue *> *segmentWordIndexRanges = [NSMutableArray array];
        NSUInteger segmentStart = 0;
        NSUInteger segmentStartWordIdx = 0;
        NSUInteger wordsInCurrentSegment = 0;

        for (NSUInteger idx = 0; idx < wordRanges.count; idx++) {
                NSRange wordRange = [wordRanges[idx] rangeValue];
                if (wordsInCurrentSegment == 0) {
                        wordsInCurrentSegment = 1;
                        continue;
                }

                NSUInteger candidateEnd = NSMaxRange(wordRange);
                NSString *candidateLine = [baseText substringWithRange:NSMakeRange(segmentStart, candidateEnd - segmentStart)];
                CGSize candSize = [candidateLine sizeWithAttributes:@{NSFontAttributeName: font}];
                if (candSize.width <= maxWidth) {
                        wordsInCurrentSegment++;
                        continue;
                }

                NSUInteger breakLocation = wordRange.location;
                [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, breakLocation - segmentStart)]];
                [segmentWordIndexRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStartWordIdx, idx - segmentStartWordIdx)]];
                segmentStart = breakLocation;
                segmentStartWordIdx = idx;
                wordsInCurrentSegment = 1;
        }

        [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, baseText.length - segmentStart)]];
        [segmentWordIndexRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStartWordIdx, wordRanges.count - segmentStartWordIdx)]];

        if (wordIdx >= 0) {
                for (NSUInteger idx = 0; idx < segmentWordIndexRanges.count; idx++) {
                        NSRange wordIdxRange = [segmentWordIndexRanges[idx] rangeValue];
                        if (wordIdx >= (NSInteger)wordIdxRange.location && wordIdx < (NSInteger)NSMaxRange(wordIdxRange)) {
                                return idx;
                        }
                }
        }

        return 0;
}

- (void)amlAnimatePreviewFromLine:(NSInteger)fromLine toLine:(NSInteger)toLine withWord:(NSInteger)word {
	NSInteger fromLineIdx = fromLine % (NSInteger)MAX(self.previewLines.count, 1);
	NSInteger fromWordCount = (self.previewLines.count > 0) ? (NSInteger)self.previewLines[fromLineIdx].wordRanges.count : 3;
	[self amlAnimatePreviewFromLine:fromLine toLine:toLine withWord:word fromWord:fromWordCount - 1];
}

- (void)amlAnimatePreviewFromLine:(NSInteger)fromLine toLine:(NSInteger)toLine withWord:(NSInteger)word fromWord:(NSInteger)fromWord {
	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL transitionsEnabled = [prefs[@"TransitionsEnabled"] boolValue];
	
	if (!transitionsEnabled || !self.mainPreviewLabel) {
		self.previewLineIndex = toLine;
		self.previewWordIndex = word;
		[self amlRefreshMainPreview];
		return;
	}

	NSInteger style = [prefs[@"TransitionStyle"] integerValue];
	CGFloat duration = [prefs[@"TransitionDuration"] floatValue];
	
	UILabel *currentLabel = self.mainPreviewLabel;
	UILabel *nextLabel = [[UILabel alloc] initWithFrame:currentLabel.frame];
	
	NSAttributedString *nextAttr = [self amlAttributedTextForLine:toLine word:word];
	NSAttributedString *currentAttr = [self amlAttributedTextForLine:fromLine word:fromWord];
	
	currentLabel.attributedText = currentAttr;
	nextLabel.attributedText = nextAttr;

	self.previewLineIndex = toLine;
	self.previewWordIndex = word;

	nextLabel.textAlignment = currentLabel.textAlignment;
	nextLabel.adjustsFontSizeToFitWidth = currentLabel.adjustsFontSizeToFitWidth;
	nextLabel.minimumScaleFactor = currentLabel.minimumScaleFactor;
	nextLabel.alpha = 0.0;
	[currentLabel.superview addSubview:nextLabel];

	if (style == 1) nextLabel.transform = CGAffineTransformMakeTranslation(0, 20);
	else if (style == 2) nextLabel.transform = CGAffineTransformMakeTranslation(0, -20);
	else if (style == 3) nextLabel.transform = CGAffineTransformMakeTranslation(currentLabel.bounds.size.width, 0);
	else if (style == 4) nextLabel.transform = CGAffineTransformMakeScale(0.5, 0.5);

	[UIView animateKeyframesWithDuration:duration
							  delay:0
							options:UIViewKeyframeAnimationOptionCalculationModeCubic
						 animations:^{
		if (style == 0 || style == 4) {
			[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.45 animations:^{
				currentLabel.alpha = 0.0;
				if (style == 4) currentLabel.transform = CGAffineTransformMakeScale(1.1, 1.1);
			}];
			[UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{
				nextLabel.alpha = 1.0;
				nextLabel.transform = CGAffineTransformIdentity;
			}];
		} else {
			[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:1.0 animations:^{
				nextLabel.alpha = 1.0;
				nextLabel.transform = CGAffineTransformIdentity;
				if (style == 1) currentLabel.transform = CGAffineTransformMakeTranslation(0, -20);
				else if (style == 2) currentLabel.transform = CGAffineTransformMakeTranslation(0, 20);
				else currentLabel.transform = CGAffineTransformMakeTranslation(-currentLabel.bounds.size.width, 0);
				currentLabel.alpha = 0.0;
			}];
		}
	}
						 completion:^(BOOL finished) {
						 [self amlRefreshMainPreview];
						 currentLabel.alpha = 1.0;
						 currentLabel.transform = CGAffineTransformIdentity;
						 [nextLabel removeFromSuperview];
					 }];
}

- (void)amlPreviewTimerTick {
	if (!self.previewLines || self.previewLines.count == 0) return;

	NSTimeInterval timeInSong = fmod([NSDate timeIntervalSinceReferenceDate] - self.previewStartTime, 42.0);

	NSInteger resolvedLineIndex = 0;
	for (NSInteger i = 0; i < self.previewLines.count; i++) {
		if (timeInSong >= self.previewLines[i].beginTime) {
			resolvedLineIndex = i;
		} else {
			break;
		}
	}

	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL showAdlibs = [prefs[@"ShowAdlibs"] boolValue];
	DateLyricsPreviewLine *previewLine = self.previewLines[resolvedLineIndex];
	NSMutableArray<NSNumber *> *visibleWordBegins = [NSMutableArray array];
	NSMutableArray<NSNumber *> *visibleWordEnds = [NSMutableArray array];
	for (NSUInteger i = 0; i < previewLine.wordRanges.count; i++) {
		BOOL isBg = [previewLine.wordIsBackground[i] boolValue];
		if (isBg && !showAdlibs) continue;
		[visibleWordBegins addObject:previewLine.wordBeginTimes[i]];
		[visibleWordEnds addObject:previewLine.wordEndTimes[i]];
	}

	NSInteger resolvedWordIndex = -1;
	if (timeInSong >= previewLine.beginTime) {
		for (NSInteger i = 0; i < visibleWordBegins.count; i++) {
			double wBegin = [visibleWordBegins[i] doubleValue];
			if (timeInSong >= wBegin) {
				resolvedWordIndex = i;
			}
		}
	}

	if (resolvedLineIndex != self.previewLineIndex) {
		NSInteger oldLineIndex = self.previewLineIndex;
		[self amlAnimatePreviewFromLine:oldLineIndex toLine:resolvedLineIndex withWord:resolvedWordIndex];
	} else if (resolvedWordIndex != self.previewWordIndex) {
		NSUInteger oldSeg = [self amlSegmentIndexForLine:self.previewLineIndex word:self.previewWordIndex];
		NSUInteger newSeg = [self amlSegmentIndexForLine:resolvedLineIndex word:resolvedWordIndex];
		if (oldSeg != newSeg) {
			[self amlAnimatePreviewFromLine:self.previewLineIndex toLine:resolvedLineIndex withWord:resolvedWordIndex fromWord:self.previewWordIndex];
		} else {
			self.previewWordIndex = resolvedWordIndex;
			[self amlRefreshMainPreview];
		}
	}
}

- (void)startPreviewAnimation {
	[self stopPreviewAnimation];
	if (!self.previewLines) {
		self.previewLines = DateLyricsLoadPreviewLines();
	}
	self.previewStartTime = [NSDate timeIntervalSinceReferenceDate];
	self.previewLineIndex = 0;
	self.previewWordIndex = -1;
	self.previewAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(amlPreviewTimerTick) userInfo:nil repeats:YES];
}

- (void)stopPreviewAnimation {
	[self.previewAnimationTimer invalidate];
	self.previewAnimationTimer = nil;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
		NSDictionary *prefs = DateLyricsCurrentPrefs();
		BOOL showsFontStyle = [prefs[@"UseCustomFont"] boolValue];
		BOOL transitionsEnabled = prefs[@"TransitionsEnabled"] ? [prefs[@"TransitionsEnabled"] boolValue] : YES;
		BOOL splitLongLinesEnabled = [prefs[@"SplitLongLines"] boolValue];

		NSIndexSet *fontIndexes = [specs indexesOfObjectsPassingTest:^BOOL(PSSpecifier *spec, NSUInteger idx, BOOL *stop) {
			return [[[spec propertyForKey:@"key"] description] isEqualToString:@"CustomFontName"] && !showsFontStyle;
		}];
		if (fontIndexes.count > 0) {
			[specs removeObjectsAtIndexes:fontIndexes];
		}

		NSIndexSet *visibilityIndexes = [specs indexesOfObjectsPassingTest:^BOOL(PSSpecifier *spec, NSUInteger idx, BOOL *stop) {
			NSString *key = [[spec propertyForKey:@"key"] description];
			if ([key isEqualToString:@"TransitionStyle"] || [key isEqualToString:@"TransitionDuration"]) {
				return !transitionsEnabled;
			}
			return NO;
		}];
		if (visibilityIndexes.count > 0) {
			[specs removeObjectsAtIndexes:visibilityIndexes];
		}

		for (PSSpecifier *spec in specs) {
			NSString *specifierID = [spec propertyForKey:@"id"];
			NSString *specifierKey = [spec propertyForKey:@"key"];

			if ([specifierID isEqualToString:@"GitHubCell"]) {
				if (_cachedGithubIcon) {
					[spec setProperty:_cachedGithubIcon forKey:@"iconImage"];
				} else {
					UIGraphicsBeginImageContextWithOptions(CGSizeMake(29, 29), NO, 0);
					UIImage *blank = UIGraphicsGetImageFromCurrentImageContext();
					UIGraphicsEndImageContext();
					[spec setProperty:blank forKey:@"iconImage"];
				}
			}

			if ([specifierKey isEqualToString:@"CustomFontName"]) {
				[spec setProperty:@"titlesDataSource:" forKey:@"titlesDataSource"];
				[spec setProperty:@"valuesDataSource:" forKey:@"valuesDataSource"];
			}

			if ([specifierKey isEqualToString:@"ShowAdlibs"]) {
				[spec setProperty:(splitLongLinesEnabled ? @NO : @YES) forKey:@"enabled"];
			}

		}

		_specifiers = [specs copy];
	}
	return _specifiers;
}

- (NSArray *)titlesDataSource:(PSSpecifier *)specifier {
	return DateLyricsFontTitles();
}

- (NSArray *)valuesDataSource:(PSSpecifier *)specifier {
	return DateLyricsFontValues();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];

	if ([[specifier propertyForKey:@"id"] isEqualToString:@"GitHubCell"]) {
		if (!_cachedGithubIcon) {
			UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)[cell.imageView viewWithTag:1234];
			if (!spinner) {
				spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
				spinner.tag = 1234;
				[cell.imageView addSubview:spinner];

				spinner.translatesAutoresizingMaskIntoConstraints = NO;
				[NSLayoutConstraint activateConstraints:@[
					[spinner.centerXAnchor constraintEqualToAnchor:cell.imageView.centerXAnchor],
					[spinner.centerYAnchor constraintEqualToAnchor:cell.imageView.centerYAnchor]
				]];
			}
			[spinner startAnimating];
		} else {
			UIView *spinner = [cell.imageView viewWithTag:1234];
			if (spinner) {
				[spinner removeFromSuperview];
			}
		}
	}

	if ([[specifier propertyForKey:@"action"] isEqualToString:@"resetSettings"]) {
		cell.textLabel.textColor = [UIColor systemRedColor];
	}

	return cell;
}

- (NSAttributedString *)amlAttributedTextForLine:(NSInteger)lineIdx word:(NSInteger)wordIdx {
        if (!self.previewLines) {
                self.previewLines = DateLyricsLoadPreviewLines();
        }

        NSDictionary *prefs = DateLyricsCurrentPrefs();
        BOOL forceLowercase = [prefs[@"ForceLowercase"] boolValue];
        BOOL wordHighlighting = [prefs[@"WordHighlighting"] boolValue];
        BOOL useCustomFont = [prefs[@"UseCustomFont"] boolValue];
        BOOL showAdlibs = [prefs[@"ShowAdlibs"] boolValue];
        BOOL splitLongLines = [prefs[@"SplitLongLines"] boolValue];

        DateLyricsPreviewLine *previewLine = nil;
        NSArray<NSValue *> *wordRanges = nil;
        NSString *baseText = nil;
        NSMutableArray<NSNumber *> *visibleWordBegins = [NSMutableArray array];

        if (self.previewLines.count > 0) {
                NSInteger actualLineIdx = lineIdx % (NSInteger)self.previewLines.count;
                previewLine = self.previewLines[actualLineIdx];

                NSMutableString *filteredText = [NSMutableString string];
                NSMutableArray<NSValue *> *filteredRanges = [NSMutableArray array];
                for (NSUInteger i = 0; i < previewLine.wordRanges.count; i++) {
                        BOOL isBg = [previewLine.wordIsBackground[i] boolValue];
                        if (isBg && !showAdlibs) continue;
                        NSRange srcRange = [previewLine.wordRanges[i] rangeValue];
                        NSString *word = [previewLine.text substringWithRange:srcRange];
                        if (filteredText.length > 0) [filteredText appendString:@" "];
                        NSRange newRange = NSMakeRange(filteredText.length, word.length);
                        [filteredText appendString:word];
                        [filteredRanges addObject:[NSValue valueWithRange:newRange]];
                        [visibleWordBegins addObject:previewLine.wordBeginTimes[i]];
                }
                baseText = [filteredText copy];
                wordRanges = [filteredRanges copy];
        } else {
                NSArray *fallback = @[@"1 Test Lyric", @"Lyric Test 1"];
                baseText = fallback[lineIdx % fallback.count];
                if (lineIdx % 2 == 0) {
                        wordRanges = @[
                                [NSValue valueWithRange:NSMakeRange(0, 1)],
                                [NSValue valueWithRange:NSMakeRange(2, 4)],
                                [NSValue valueWithRange:NSMakeRange(7, 5)]
                        ];
                } else {
                        wordRanges = @[
                                [NSValue valueWithRange:NSMakeRange(0, 5)],
                                [NSValue valueWithRange:NSMakeRange(6, 4)],
                                [NSValue valueWithRange:NSMakeRange(11, 1)]
                        ];
                }
        }

        UIFont *font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
        NSString *fontName = prefs[@"CustomFontName"];
        if (useCustomFont && [fontName isKindOfClass:NSString.class] && fontName.length > 0) {
                UIFont *customFont = [UIFont fontWithName:fontName size:20.0];
                if (customFont) font = customFont;
        }

        if (splitLongLines && baseText.length > 0 && wordRanges.count >= 2) {
                CGFloat maxWidth = CGRectGetWidth(self.mainPreviewLabel.bounds);
                if (maxWidth <= 1.0) {
                        maxWidth = CGRectGetWidth(self.mainPreviewLabel.frame);
                }
                if (maxWidth <= 1.0) {
                        maxWidth = [UIScreen mainScreen].bounds.size.width - 60.0;
                }
                if (maxWidth > 1.0) {
                        CGSize totalSize = [baseText sizeWithAttributes:@{NSFontAttributeName: font}];
                        if (totalSize.width > maxWidth) {
                                NSMutableArray<NSValue *> *segmentRanges = [NSMutableArray array];
                                NSMutableArray<NSValue *> *segmentWordIndexRanges = [NSMutableArray array];
                                NSUInteger segmentStart = 0;
                                NSUInteger segmentStartWordIdx = 0;
                                NSUInteger wordsInCurrentSegment = 0;

                                for (NSUInteger idx = 0; idx < wordRanges.count; idx++) {
                                        NSRange wordRange = [wordRanges[idx] rangeValue];
                                        if (wordsInCurrentSegment == 0) {
                                                wordsInCurrentSegment = 1;
                                                continue;
                                        }

                                        NSUInteger candidateEnd = NSMaxRange(wordRange);
                                        NSString *candidateLine = [baseText substringWithRange:NSMakeRange(segmentStart, candidateEnd - segmentStart)];
                                        CGSize candSize = [candidateLine sizeWithAttributes:@{NSFontAttributeName: font}];
                                        if (candSize.width <= maxWidth) {
                                                wordsInCurrentSegment++;
                                                continue;
                                        }

                                        NSUInteger breakLocation = wordRange.location;
                                        [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, breakLocation - segmentStart)]];
                                        [segmentWordIndexRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStartWordIdx, idx - segmentStartWordIdx)]];
                                        segmentStart = breakLocation;
                                        segmentStartWordIdx = idx;
                                        wordsInCurrentSegment = 1;
                                }

                                [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, baseText.length - segmentStart)]];
                                [segmentWordIndexRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStartWordIdx, wordRanges.count - segmentStartWordIdx)]];

                                if (segmentRanges.count >= 2) {
                                        NSUInteger targetSegmentIdx = 0;
                                        if (wordIdx >= 0) {
                                                for (NSUInteger idx = 0; idx < segmentWordIndexRanges.count; idx++) {
                                                        NSRange wordIdxRange = [segmentWordIndexRanges[idx] rangeValue];
                                                        if (wordIdx >= (NSInteger)wordIdxRange.location && wordIdx < (NSInteger)NSMaxRange(wordIdxRange)) {
                                                                targetSegmentIdx = idx;
                                                                break;
                                                        }
                                                }
                                        }

                                        NSRange targetRange = [segmentRanges[targetSegmentIdx] rangeValue];
                                        NSRange targetWordRange = [segmentWordIndexRanges[targetSegmentIdx] rangeValue];
                                        NSString *segmentText = [baseText substringWithRange:targetRange];
                                        
                                        if (segmentText.length > 0 && [segmentText hasPrefix:@" "]) {
                                                targetRange.location += 1;
                                                targetRange.length -= 1;
                                                segmentText = [baseText substringWithRange:targetRange];
                                        }

                                        NSMutableArray<NSValue *> *adjustedWordRanges = [NSMutableArray array];
                                        for (NSUInteger idx = targetWordRange.location; idx < NSMaxRange(targetWordRange); idx++) {
                                                NSRange origRange = [wordRanges[idx] rangeValue];
                                                NSRange adjRange = NSMakeRange(origRange.location - targetRange.location, origRange.length);
                                                [adjustedWordRanges addObject:[NSValue valueWithRange:adjRange]];
                                        }

                                        baseText = segmentText;
                                        wordRanges = [adjustedWordRanges copy];
                                        if (wordIdx >= 0) {
                                                wordIdx = wordIdx - (NSInteger)targetWordRange.location;
                                        }
                                }
                        }
                }
        }

        if (forceLowercase) baseText = baseText.lowercaseString;

        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:baseText];
        [attributed addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attributed.length)];
        [attributed addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:NSMakeRange(0, attributed.length)];
        [attributed addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, attributed.length)];

        if (wordHighlighting && wordRanges.count > 0) {
                BOOL hasActiveWord = (wordIdx >= 0 && wordIdx < (NSInteger)wordRanges.count);

                UIColor *textColor = [UIColor labelColor];
                UIColor *dimmedColor = [textColor colorWithAlphaComponent:0.35];
                [attributed addAttribute:NSForegroundColorAttributeName value:dimmedColor range:NSMakeRange(0, attributed.length)];
                if (hasActiveWord) {
                        NSRange activeRange = [wordRanges[wordIdx] rangeValue];
                        NSRange highlightRange = NSMakeRange(0, NSMaxRange(activeRange));
                        if (NSMaxRange(highlightRange) <= attributed.length) {
                                [attributed addAttribute:NSForegroundColorAttributeName value:textColor range:highlightRange];
                        }
                }
        }

        return attributed;
}

- (void)amlRefreshMainPreview {
        self.mainPreviewLabel.alpha = 1.0;
        self.mainPreviewLabel.attributedText = [self amlAttributedTextForLine:self.previewLineIndex word:self.previewWordIndex];
}

- (void)loadView {
	[super loadView];

	UITableView *tableView = [self table];
	tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	self.navigationItem.backButtonTitle = @"Back";

	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
	titleView.backgroundColor = [UIColor clearColor];
	UILabel *previewLabel = [[UILabel alloc] initWithFrame:titleView.bounds];
	previewLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	previewLabel.textAlignment = NSTextAlignmentCenter;
	previewLabel.numberOfLines = 1;
	previewLabel.adjustsFontSizeToFitWidth = YES;
	previewLabel.minimumScaleFactor = 0.55;
	previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[titleView addSubview:previewLabel];

	self.mainPreviewLabel = previewLabel;
	self.navigationItem.titleView = titleView;
	self.previewWordIndex = -1;
	[self amlRefreshMainPreview];

	UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 180)];

	self.headerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 20, 100, 100)];
	self.headerImageView.contentMode = UIViewContentModeScaleAspectFit;
	self.headerImageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	self.headerImageView.center = CGPointMake(headerView.center.x, self.headerImageView.center.y);
	self.headerImageView.layer.cornerRadius = 22;
	self.headerImageView.layer.masksToBounds = YES;
	[headerView addSubview:self.headerImageView];

	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 130, headerView.bounds.size.width, 40)];
	titleLabel.text = @"DateLyrics";
	titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[headerView addSubview:titleLabel];

	tableView.tableHeaderView = headerView;
	[self amlUpdateHeaderArtwork];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	UIColor *tintColor = [UIColor colorWithRed:255/255.0 green:127/255.0 blue:189/255.0 alpha:1.0];
	[UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = tintColor;
	self.view.tintColor = tintColor;
	[self amlUpdateHeaderArtwork];

	if (!_cachedGithubIcon) {
		[self fetchGithubLogo];
	}
	[self amlRefreshMainPreview];
	[self startPreviewAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopPreviewAnimation];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self amlUpdateHeaderArtwork];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"Enabled"]) {
		UIImage *respringImage = [UIImage systemImageNamed:@"arrow.clockwise"];
		UIBarButtonItem *respringButton = [[UIBarButtonItem alloc] initWithImage:respringImage style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
		respringButton.tintColor = [UIColor systemBlueColor];
		self.navigationItem.rightBarButtonItem = respringButton;
	}

	if ([key isEqualToString:@"SplitLongLines"]) {
		if ([value boolValue]) {
			NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
			[prefs setBool:NO forKey:@"ShowAdlibs"];
			[prefs synchronize];
		}
	}

	if ([key isEqualToString:@"WordHighlighting"] ||
	        [key isEqualToString:@"UseCustomFont"] ||
	        [key isEqualToString:@"TransitionsEnabled"] ||
	        [key isEqualToString:@"MinimumScale"] ||
	        [key isEqualToString:@"SplitLongLines"] ||
	        [key isEqualToString:@"ShowAdlibs"]) {

	        _specifiers = nil;
	        [self reloadSpecifiers];

	        if ([key isEqualToString:@"TransitionsEnabled"]) {
	                if ([value boolValue]) [self startPreviewAnimation];
	                else [self stopPreviewAnimation];
	        }
	}
	[self amlRefreshMainPreview];
}
- (void)amlUpdateHeaderArtwork {
	if (!self.headerImageView) return;

	NSString *resourceName = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? @"DateLyricsIconDark" : @"DateLyricsIconLight";
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:resourceName ofType:@"png"];
	self.headerImageView.image = [UIImage imageWithContentsOfFile:path];
}

- (void)amlKillMusic {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];
	NSArray<NSArray<NSString *> *> *commands = @[
		@[ jbroot(@"/usr/bin/killall"), @"-9", @"Music" ],
		@[ @"/usr/bin/killall", @"-9", @"Music" ],
		@[ @"/bin/killall", @"-9", @"Music" ]
	];
	for (NSArray<NSString *> *command in commands) {
		if (![[NSFileManager defaultManager] isExecutableFileAtPath:command.firstObject]) continue;
		pid_t pid;
		size_t argc = command.count;
		char *argv[argc + 1];
		for (size_t i = 0; i < argc; i++) {
			argv[i] = (char *)command[i].UTF8String;
		}
		argv[argc] = NULL;
		if (posix_spawn(&pid, command.firstObject.UTF8String, NULL, NULL, argv, environ) == 0) {
			break;
		}
	}
}

- (void)respring {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
	[haptic impactOccurred];
	NSArray<NSArray<NSString *> *> *commands = @[
		@[ jbroot(@"/usr/bin/sbreload") ],
		@[ @"/usr/bin/sbreload" ],
		@[ @"/usr/bin/killall", @"-9", @"SpringBoard" ],
		@[ @"/bin/killall", @"-9", @"SpringBoard" ]
	];
	for (NSArray<NSString *> *command in commands) {
		if (![[NSFileManager defaultManager] isExecutableFileAtPath:command.firstObject]) continue;
		pid_t pid;
		size_t argc = command.count;
		char *argv[argc + 1];
		for (size_t i = 0; i < argc; i++) {
			argv[i] = (char *)command[i].UTF8String;
		}
		argv[argc] = NULL;
		if (posix_spawn(&pid, command.firstObject.UTF8String, NULL, NULL, argv, environ) == 0) {
			break;
		}
	}
}

- (void)resetSettings {
	if (self.resetInProgress) return;
	self.resetInProgress = YES;

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];

    CFPreferencesSetAppValue((__bridge CFStringRef)@"Enabled", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"ForceLowercase", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"WordHighlighting", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"HapticsEnabled", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"HapticStyleSyllable", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"HapticStyleLine", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"UseCustomFont", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"CustomFontName", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"MinimumScale", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"DebugLogging", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"PauseTimeout", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"MusixmatchEnabled", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"TransitionsEnabled", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"TransitionStyle", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"TransitionDuration", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"SplitLongLines", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"ShowAdlibs", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDateLyricsPrefsSuite);

    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Best-effort direct cleanup. Preferences.app is sandboxed, so these will often
    // fail silently — the ClearCaches notification below is what actually works,
    // because each host clears its own container from inside its own process.
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (proxyClass) {
        LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:@"com.apple.Music"];
        NSURL *containerURL = [proxy respondsToSelector:@selector(dataContainerURL)] ? proxy.dataContainerURL : nil;
        if (containerURL) {
            NSString *musicLyricsPath = [[containerURL.path stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"DateLyrics"];
            if ([fileManager fileExistsAtPath:musicLyricsPath]) {
                [fileManager removeItemAtPath:musicLyricsPath error:nil];
            }
        }
    }

    [self reload];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.shalamand3r.datelyrics/ClearCaches", NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.shalamand3r.datelyrics/ReloadPrefs", NULL, NULL, YES);
	self.resetInProgress = NO;
}

- (void)openGithub {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/shalamand3r/DateLyrics"] options:@{} completionHandler:nil];
}

- (void)fetchGithubLogo {
	if (_cachedGithubIcon) return;
	NSURL *url = [NSURL URLWithString:@"https://github.com/shalamand3r/shalamand3r.github.io/blob/main/CydiaIcon.png?raw=true"];
	__weak typeof(self) weakSelf = self;
	[[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (!data || error) return;

		// Everything below touches UIKit (UIScreen, UIGraphics, CALayer rendering)
		// and mutates the shared _cachedGithubIcon static. All of it must run on the
		// main thread; this block is on a URLSession worker.
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || _cachedGithubIcon) return;

			UIImage *image = [UIImage imageWithData:data];
			if (!image) return;

			CGRect bounds = CGRectMake(0, 0, 29, 29);
			UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:bounds];
			UIImage *squircleImage = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
				UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:7.0];
				[clip addClip];
				[image drawInRect:bounds];
			}];
			if (!squircleImage) return;

			_cachedGithubIcon = squircleImage;

			PSSpecifier *githubSpecifier = [strongSelf specifierForID:@"GitHubCell"];
			if (!githubSpecifier) return;

			[githubSpecifier setProperty:squircleImage forKey:@"iconImage"];
			[strongSelf reloadSpecifier:githubSpecifier];

			NSIndexPath *indexPath = [strongSelf indexPathForSpecifier:githubSpecifier];
			if (indexPath) {
				UITableViewCell *cell = [strongSelf.table cellForRowAtIndexPath:indexPath];
				UIView *spinner = [cell.imageView viewWithTag:1234];
				if (spinner) {
					[spinner removeFromSuperview];
				}
			}
		});
	}] resume];
}

@end

@interface DateLyricsFontListController ()
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) NSTimer *previewAnimationTimer;
@property (nonatomic, assign) NSInteger previewLineIndex;
@property (nonatomic, assign) NSInteger previewWordIndex;
@property (nonatomic, strong) NSArray<DateLyricsPreviewLine *> *previewLines;
@property (nonatomic, assign) NSTimeInterval previewStartTime;
@end

@implementation DateLyricsFontListController

- (NSString *)amlSelectedFontName {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
	NSString *fontName = [prefs objectForKey:@"CustomFontName"];
	return [fontName isKindOfClass:NSString.class] && fontName.length > 0 ? fontName : @"AvenirNext-DemiBold";
}

- (void)amlUpdatePreviewLabel {
	if (!self.previewLines) {
		self.previewLines = DateLyricsLoadPreviewLines();
	}

	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL forceLowercase = [prefs[@"ForceLowercase"] boolValue];
	BOOL wordHighlighting = [prefs[@"WordHighlighting"] boolValue];
	BOOL showAdlibs = [prefs[@"ShowAdlibs"] boolValue];
	CGFloat minimumScale = [prefs[@"MinimumScale"] floatValue];

	NSString *baseText = nil;
	NSArray<NSValue *> *wordRanges = nil;

	if (self.previewLines.count > 0) {
		NSInteger lineIdx = self.previewLineIndex % (NSInteger)self.previewLines.count;
		DateLyricsPreviewLine *line = self.previewLines[lineIdx];
		NSMutableString *filteredText = [NSMutableString string];
		NSMutableArray<NSValue *> *filteredRanges = [NSMutableArray array];
		for (NSUInteger i = 0; i < line.wordRanges.count; i++) {
			BOOL isBg = [line.wordIsBackground[i] boolValue];
			if (isBg && !showAdlibs) continue;
			NSRange srcRange = [line.wordRanges[i] rangeValue];
			NSString *word = [line.text substringWithRange:srcRange];
			if (filteredText.length > 0) [filteredText appendString:@" "];
			NSRange newRange = NSMakeRange(filteredText.length, word.length);
			[filteredText appendString:word];
			[filteredRanges addObject:[NSValue valueWithRange:newRange]];
		}
		baseText = [filteredText copy];
		wordRanges = [filteredRanges copy];
	} else {
		NSArray *fallback = @[@"1 Test Lyric", @"Lyric Test 1"];
		baseText = fallback[self.previewLineIndex % fallback.count];
		if (self.previewLineIndex % 2 == 0) {
			wordRanges = @[
				[NSValue valueWithRange:NSMakeRange(0, 1)],
				[NSValue valueWithRange:NSMakeRange(2, 4)],
				[NSValue valueWithRange:NSMakeRange(7, 5)]
			];
		} else {
			wordRanges = @[
				[NSValue valueWithRange:NSMakeRange(0, 5)],
				[NSValue valueWithRange:NSMakeRange(6, 4)],
				[NSValue valueWithRange:NSMakeRange(11, 1)]
			];
		}
	}

	if (forceLowercase) baseText = baseText.lowercaseString;

	NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:baseText];
	NSString *fontName = [self amlSelectedFontName];
	UIFont *font = [UIFont fontWithName:fontName size:20.0] ?: [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
	[attributed addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attributed.length)];
	[attributed addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:NSMakeRange(0, attributed.length)];
	[attributed addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, attributed.length)];

	if (wordHighlighting && wordRanges.count > 0) {
		NSInteger wordIdx = self.previewWordIndex;
		if (self.previewAnimationTimer && self.previewLines.count > 0) {
			NSTimeInterval timeInSong = fmod([NSDate timeIntervalSinceReferenceDate] - self.previewStartTime, 42.0);
			NSInteger lineIdx = self.previewLineIndex % (NSInteger)self.previewLines.count;
			DateLyricsPreviewLine *currentLine = self.previewLines[lineIdx];

			NSMutableArray<NSNumber *> *visibleWordBegins = [NSMutableArray array];
			for (NSUInteger i = 0; i < currentLine.wordRanges.count; i++) {
				BOOL isBg = [currentLine.wordIsBackground[i] boolValue];
				if (isBg && !showAdlibs) continue;
				[visibleWordBegins addObject:currentLine.wordBeginTimes[i]];
			}

			NSInteger resolvedWordIndex = -1;
			if (timeInSong >= currentLine.beginTime) {
				for (NSInteger i = 0; i < visibleWordBegins.count; i++) {
					double wBegin = [visibleWordBegins[i] doubleValue];
					if (timeInSong >= wBegin) {
						resolvedWordIndex = i;
					}
				}
			}
			wordIdx = resolvedWordIndex;
			self.previewWordIndex = resolvedWordIndex;
		}

		BOOL hasActiveWord = (wordIdx >= 0 && wordIdx < (NSInteger)wordRanges.count);
		UIColor *textColor = [UIColor labelColor];
		UIColor *dimmedColor = [textColor colorWithAlphaComponent:0.35];
		[attributed addAttribute:NSForegroundColorAttributeName value:dimmedColor range:NSMakeRange(0, attributed.length)];
		if (hasActiveWord) {
			NSRange activeRange = [wordRanges[wordIdx] rangeValue];
			NSRange highlightRange = NSMakeRange(0, NSMaxRange(activeRange));
			if (NSMaxRange(highlightRange) <= attributed.length) {
				[attributed addAttribute:NSForegroundColorAttributeName value:textColor range:highlightRange];
			}
		}
	}

	self.previewLabel.minimumScaleFactor = minimumScale;
	self.previewLabel.attributedText = attributed;
}

- (void)amlAnimatePreviewFromLine:(NSInteger)fromLine toLine:(NSInteger)toLine withWord:(NSInteger)word {
	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL transitionsEnabled = [prefs[@"TransitionsEnabled"] boolValue];
	
	if (!transitionsEnabled || !self.previewLabel) {
		self.previewLineIndex = toLine;
		self.previewWordIndex = word;
		[self amlUpdatePreviewLabel];
		return;
	}

	NSInteger style = [prefs[@"TransitionStyle"] integerValue];
	CGFloat duration = [prefs[@"TransitionDuration"] floatValue];
	
	UILabel *currentLabel = self.previewLabel;
	UILabel *nextLabel = [[UILabel alloc] initWithFrame:currentLabel.frame];
	nextLabel.minimumScaleFactor = currentLabel.minimumScaleFactor;
	nextLabel.adjustsFontSizeToFitWidth = currentLabel.adjustsFontSizeToFitWidth;
	
	self.previewLineIndex = toLine;
	self.previewWordIndex = word;
	[self amlUpdatePreviewLabel];
	nextLabel.attributedText = currentLabel.attributedText;
	
	self.previewLineIndex = fromLine;
	NSInteger fromLineIdx = fromLine % (NSInteger)MAX(self.previewLines.count, 1);
	NSInteger fromWordCount = (self.previewLines.count > 0) ? (NSInteger)self.previewLines[fromLineIdx].wordRanges.count : 3;
	self.previewWordIndex = fromWordCount - 1;
	[self amlUpdatePreviewLabel];
	
	self.previewLineIndex = toLine;
	self.previewWordIndex = word;

	nextLabel.textAlignment = currentLabel.textAlignment;
	nextLabel.adjustsFontSizeToFitWidth = currentLabel.adjustsFontSizeToFitWidth;
	nextLabel.minimumScaleFactor = currentLabel.minimumScaleFactor;
	nextLabel.alpha = 0.0;
	[currentLabel.superview addSubview:nextLabel];

	if (style == 1) nextLabel.transform = CGAffineTransformMakeTranslation(0, 20);
	else if (style == 2) nextLabel.transform = CGAffineTransformMakeTranslation(0, -20);
	else if (style == 3) nextLabel.transform = CGAffineTransformMakeTranslation(currentLabel.bounds.size.width, 0);
	else if (style == 4) nextLabel.transform = CGAffineTransformMakeScale(0.5, 0.5);

	[UIView animateKeyframesWithDuration:duration
							  delay:0
							options:UIViewKeyframeAnimationOptionCalculationModeCubic
						 animations:^{
		if (style == 0 || style == 4) {
			[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.45 animations:^{
				currentLabel.alpha = 0.0;
				if (style == 4) currentLabel.transform = CGAffineTransformMakeScale(1.1, 1.1);
			}];
			[UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{
				nextLabel.alpha = 1.0;
				nextLabel.transform = CGAffineTransformIdentity;
			}];
		} else {
			[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:1.0 animations:^{
				nextLabel.alpha = 1.0;
				nextLabel.transform = CGAffineTransformIdentity;
				if (style == 1) currentLabel.transform = CGAffineTransformMakeTranslation(0, -20);
				else if (style == 2) currentLabel.transform = CGAffineTransformMakeTranslation(0, 20);
				else currentLabel.transform = CGAffineTransformMakeTranslation(-currentLabel.bounds.size.width, 0);
				currentLabel.alpha = 0.0;
			}];
		}
	}
						 completion:^(BOOL finished) {
						 [self amlUpdatePreviewLabel];
						 currentLabel.alpha = 1.0;
						 currentLabel.transform = CGAffineTransformIdentity;
						 [nextLabel removeFromSuperview];
					 }];
}

- (void)amlPreviewTimerTick {
	if (!self.previewLines || self.previewLines.count == 0) return;

	NSTimeInterval timeInSong = fmod([NSDate timeIntervalSinceReferenceDate] - self.previewStartTime, 42.0);

	NSInteger resolvedLineIndex = 0;
	for (NSInteger i = 0; i < self.previewLines.count; i++) {
		if (timeInSong >= self.previewLines[i].beginTime) {
			resolvedLineIndex = i;
		} else {
			break;
		}
	}

	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL showAdlibs = [prefs[@"ShowAdlibs"] boolValue];
	DateLyricsPreviewLine *previewLine = self.previewLines[resolvedLineIndex];
	NSMutableArray<NSNumber *> *visibleWordBegins = [NSMutableArray array];
	NSMutableArray<NSNumber *> *visibleWordEnds = [NSMutableArray array];
	for (NSUInteger i = 0; i < previewLine.wordRanges.count; i++) {
		BOOL isBg = [previewLine.wordIsBackground[i] boolValue];
		if (isBg && !showAdlibs) continue;
		[visibleWordBegins addObject:previewLine.wordBeginTimes[i]];
		[visibleWordEnds addObject:previewLine.wordEndTimes[i]];
	}

	NSInteger resolvedWordIndex = -1;
	if (timeInSong >= previewLine.beginTime) {
		for (NSInteger i = 0; i < visibleWordBegins.count; i++) {
			double wBegin = [visibleWordBegins[i] doubleValue];
			if (timeInSong >= wBegin) {
				resolvedWordIndex = i;
			}
		}
	}

	if (resolvedLineIndex != self.previewLineIndex) {
		NSInteger oldLineIndex = self.previewLineIndex;
		[self amlAnimatePreviewFromLine:oldLineIndex toLine:resolvedLineIndex withWord:resolvedWordIndex];
	} else if (resolvedWordIndex != self.previewWordIndex) {
		self.previewWordIndex = resolvedWordIndex;
		[self amlUpdatePreviewLabel];
	}
}

- (void)startPreviewAnimation {
	[self stopPreviewAnimation];
	if (!self.previewLines) {
		self.previewLines = DateLyricsLoadPreviewLines();
	}
	self.previewStartTime = [NSDate timeIntervalSinceReferenceDate];
	self.previewLineIndex = 0;
	self.previewWordIndex = -1;
	self.previewAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(amlPreviewTimerTick) userInfo:nil repeats:YES];
}

- (void)stopPreviewAnimation {
	[self.previewAnimationTimer invalidate];
	self.previewAnimationTimer = nil;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.rowHeight = 44.0;

	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
	titleView.backgroundColor = [UIColor clearColor];

	UILabel *previewLabel = [[UILabel alloc] initWithFrame:titleView.bounds];
	previewLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	previewLabel.textAlignment = NSTextAlignmentCenter;
	previewLabel.numberOfLines = 1;
	previewLabel.adjustsFontSizeToFitWidth = YES;
	previewLabel.minimumScaleFactor = 0.55;
	previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[titleView addSubview:previewLabel];
	self.previewLabel = previewLabel;

	self.navigationItem.titleView = titleView;
	self.previewWordIndex = -1;
	[self amlUpdatePreviewLabel];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self amlUpdatePreviewLabel];
	[self startPreviewAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopPreviewAnimation];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[super tableView:tableView didSelectRowAtIndexPath:indexPath];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self amlUpdatePreviewLabel];
	});
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if (!cell) return cell;
	cell.textLabel.numberOfLines = 1;
	cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	cell.detailTextLabel.text = nil;

	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44.0;
}

@end

@implementation DateLyricsExperimentalListController
- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Experimental" target:self];
	}
	return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([[specifier propertyForKey:@"isDestructive"] boolValue]) {
        cell.textLabel.textColor = UIColor.systemRedColor;
    }
    return cell;
}

- (void)showDebugLog {
    NSString *logText = DateLyricsCombinedDebugLogText();
    DateLyricsLogViewController *controller = [DateLyricsLogViewController new];
    controller.logText = DateLyricsRecentLogText(logText);
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)copyDebugLog {
    NSString *logText = DateLyricsRecentLogText(DateLyricsCombinedDebugLogText());
    NSString *title = @"No Debug Log";
    if (logText.length > 0) {
        UIPasteboard.generalPasteboard.string = logText;
        title = @"Debug Log Copied";
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearDebugLog {
    for (NSString *path in DateLyricsDebugLogPaths()) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Debug Log Cleared"
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
