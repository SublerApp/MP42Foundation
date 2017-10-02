//
//  MP42SrtImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import "MP42SSAImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42File.h"

#import "MP42SSAParser.h"
#import "MP42SSAConverter.h"

#import "MP42SubUtilities.h"
#import "MP42Languages.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Private.h"

@interface MP42SSAImporter ()

@property (nonatomic, readonly) MP42SSAParser *parser;
@property (nonatomic, readonly) SBSubSerializer *ss;

@end

@implementation MP42SSAImporter

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"ssa", @"ass"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)outError
{
    if ((self = [super initWithURL:fileURL])) {
        MP42SubtitleTrack *newTrack = [[MP42SubtitleTrack alloc] init];

        newTrack.format = kMP42SubtitleCodecType_3GText;
        newTrack.URL = self.fileURL;
        newTrack.alternateGroup = 2;
        newTrack.language = getFilenameLanguage((__bridge CFStringRef)self.fileURL.path);

        NSString *stringFromFileAtURL = [NSString stringWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:NULL];

        if (!stringFromFileAtURL) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be opened.", @"ssa error message"),
                                      MP42LocalizedString(@"The file is not a ssa file, or it does not contain any subtitles.", @"ssa error message"), 100);
            }
            return nil;
        }

        // Check if a 10.10 only class is available, NSLinguisticTagger crashes on 10.9
        // if the string contains some characters.
        if ([newTrack.language isEqualToString:@"und"] && NSClassFromString(@"NSVisualEffectView")) {
			// we couldn't deduce language from the fileURL
			// -> Let's look into the file itself

			if (stringFromFileAtURL) { // try auto determining
                NSArray *tagschemes = @[NSLinguisticTagSchemeLanguage];
                NSCountedSet *languagesSet = [NSCountedSet new];
				NSLinguisticTagger *tagger = [[NSLinguisticTagger alloc] initWithTagSchemes:tagschemes options:0];

				[stringFromFileAtURL enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {

					if (line.length > 1) {

                        tagger.string = line;

                        NSOrthography *ortho = [tagger orthographyAtIndex:0 effectiveRange:NULL];
                        NSString *dominantLanguage = ortho.dominantLanguage;

						if (dominantLanguage && ![dominantLanguage isEqualToString:@"und"]) {
							[languagesSet addObject:dominantLanguage];
						}
					}
				}];

				NSArray *sortedValues = [languagesSet.allObjects sortedArrayUsingComparator:^(id obj1, id obj2) {
					NSUInteger n = [languagesSet countForObject:obj1];
					NSUInteger m = [languagesSet countForObject:obj2];
					return (n <= m)? (n < m)? NSOrderedAscending : NSOrderedSame : NSOrderedDescending;
				}];

				NSString *language = sortedValues.lastObject;

                if (language) {
                    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en"];
                    NSString *languageName = [locale displayNameForKey:NSLocaleLanguageCode
															 value:language];

                    if (languageName) {
                        newTrack.language = [MP42Languages.defaultManager extendedTagForLang:languageName];
                    }
                }
			}
		}

        _parser = [[MP42SSAParser alloc] initWithString:stringFromFileAtURL];

        if (!_parser.lines.count) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be opened.", @"ssa error message"),
                                      MP42LocalizedString(@"The file is not a ssa file, or it does not contain any subtitles.", @"ssa error message"), 100);
            }
            return nil;
        }

        newTrack.duration = _parser.duration;

        [self addTrack:newTrack];
    }

    return self;
}

- (nullable NSData *)magicCookieForTrack:(MP42Track *)track
{
    return nil;
}

- (NSUInteger)timescaleForTrack:(MP42Track *)track
{
    return 1000;
}

- (NSSize)sizeForTrack:(MP42Track *)track
{
    return NSMakeSize([(MP42SubtitleTrack *)track trackWidth], [(MP42SubtitleTrack *) track trackHeight]);
}

- (void)demux
{
    @autoreleasepool {

        MP42SSAConverter *converter = [[MP42SSAConverter alloc] initWithParser:_parser];

        _ss = [[SBSubSerializer alloc] init];
        [_ss setSSA:YES];

        for (MP42SSALine *line in _parser.lines) {
            NSString *text = [converter convertLine:line];
            if (text.length) {
                SBSubLine *sl = [[SBSubLine alloc] initWithLine:text start:line.start end: line.end];
                [_ss addLine:sl];
            }
        }
        [_ss setFinished:YES];

        for (MP42SubtitleTrack *track in self.inputTracks) {
            CGSize trackSize;
            trackSize.width = track.trackWidth;
            trackSize.height = track.trackHeight;
            MP42SampleBuffer *sample;

            while (!_ss.isEmpty && !self.isCancelled) {
                SBSubLine *sl = [_ss getSerializedPacket];

                if ([sl->line isEqualToString:@"\n"]) {
                    sample = copyEmptySubtitleSample(track.sourceId, sl->end_time - sl->begin_time, NO);
                }
                else {
                    int top = (sl->top == INT_MAX) ? trackSize.height : sl->top;
                    sample = copySubtitleSample(track.sourceId, sl->line, sl->end_time - sl->begin_time, sl->forced, NO, YES, trackSize, top);
                }

                [self enqueue:sample];
            }
        }
        
        self.progress = 100.0;
        
        [self setDone];
    }
}

- (NSString *)description
{
    return @"SRT demuxer";
}

@end
