//
//  MP42MkvFileImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2010 Damiano Galassi All rights reserved.
//

#import "MP42SrtImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42File.h"
#import "MP42SubUtilities.h"
#import "MP42Languages.h"

#import "mp4v2.h"
#import "MP42PrivateUtilities.h"
#import "MP42Track+Muxer.h"
#import "MP42Track+Private.h"

@implementation MP42SrtImporter {
@private
    SBSubSerializer *_ss;
    BOOL _verticalPlacement;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"srt"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)outError
{
    if ((self = [super initWithURL:fileURL])) {
        NSInteger success = 0;
        MP4Duration duration = 0;

        MP42SubtitleTrack *newTrack = [[MP42SubtitleTrack alloc] init];

        newTrack.format = kMP42SubtitleCodecType_3GText;
        newTrack.URL = self.fileURL;
        newTrack.alternate_group = 2;
        newTrack.language = getFilenameLanguage((CFStringRef)self.fileURL.path);

        // Check if a 10.10 only class is available, NSLinguisticTagger crashes on 10.9
        // if the string contains some characters.
        if ([newTrack.language isEqualToString:@"und"] && NSClassFromString(@"NSVisualEffectView")) {
			// we couldn't deduce language from the fileURL
			// -> Let's look into the file itself

			NSString *stringFromFileAtURL = [[NSString alloc]
											 initWithContentsOfURL:fileURL
											 encoding:NSUTF8StringEncoding
											 error:nil];
			if (stringFromFileAtURL) { // try auto determining
                NSArray *tagschemes = @[NSLinguisticTagSchemeLanguage];
                NSCountedSet *languagesSet = [NSCountedSet new];
				NSLinguisticTagger *tagger = [[NSLinguisticTagger alloc] initWithTagSchemes:tagschemes options:0];

				[stringFromFileAtURL enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {

					if (line.length > 1) {

						[tagger setString:line];
						[tagger tagAtIndex:0 scheme:NSLinguisticTagSchemeLanguage tokenRange:NULL sentenceRange:NULL];

						NSOrthography *ortho = [tagger orthographyAtIndex:0 effectiveRange:NULL];

						if (ortho && ![ortho.dominantLanguage isEqualToString:@"und"]) {
							[languagesSet addObject:ortho.dominantLanguage];
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
                    [locale release];
                }
			}
		}

        _ss = [[SBSubSerializer alloc] init];
        if ([self.fileURL.pathExtension caseInsensitiveCompare: @"srt"] == NSOrderedSame) {
            success = LoadSRTFromURL(self.fileURL, _ss, &duration);
        } else if ([self.fileURL.pathExtension caseInsensitiveCompare: @"smi"] == NSOrderedSame) {
            success = LoadSMIFromURL(self.fileURL, _ss, 1);
        }

        [newTrack setDuration:duration];

        if (!success) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be opened.", @"srt error message"),
                                      MP42LocalizedString(@"The file is not a srt file, or it does not contain any subtitles.", @"srt error message"), 100);
            }
            
            [newTrack release];
            [self release];

            return nil;
        }

        [_ss setFinished:YES];
        
        if ([_ss positionInformation]) {
            newTrack.verticalPlacement = YES;
            _verticalPlacement = YES;
        }
        if ([_ss forced]) {
            newTrack.someSamplesAreForced = YES;
        }

        [self addTrack:newTrack];
        [newTrack release];
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
      return NSMakeSize([(MP42SubtitleTrack*)track trackWidth], [(MP42SubtitleTrack*) track trackHeight]);
}

- (void)demux
{
    @autoreleasepool {
        MP42SampleBuffer *sample;

        for (MP42SubtitleTrack *track in self.inputTracks) {
            CGSize trackSize;
            trackSize.width = track.trackWidth;
            trackSize.height = track.trackHeight;

            while (![_ss isEmpty] && !_cancelled) {
                SBSubLine *sl = [_ss getSerializedPacket];

                if ([sl->line isEqualToString:@"\n"]) {
                    sample = copyEmptySubtitleSample(track.sourceId, sl->end_time - sl->begin_time, NO);
                }
                else {
                    int top = (sl->top == INT_MAX) ? trackSize.height : sl->top;
                    sample = copySubtitleSample(track.sourceId, sl->line, sl->end_time - sl->begin_time, sl->forced, _verticalPlacement, YES, trackSize, top);
                }

                [self enqueue:sample];
                [sample release];
            }
        }
        
        _progress = 100.0;
        
        [self setDone];
    }
}

- (NSString *)description
{
    return @"SRT demuxer";
}

- (void) dealloc
{
    [_ss release];

    [super dealloc];
}

@end
