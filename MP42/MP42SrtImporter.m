//
//  MP42SrtImporter.m
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
#import "MP42Track+Private.h"

@implementation MP42SrtImporter {
@private
    SBSubSerializer *_ss;
    BOOL _verticalPlacement;
}

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"srt", @"smi"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError **)outError
{
    if ((self = [super initWithURL:fileURL])) {
        NSInteger success = 0;
        MP4Duration duration = 0;

        MP42SubtitleTrack *newTrack = [[MP42SubtitleTrack alloc] init];

        newTrack.format = kMP42SubtitleCodecType_3GText;
        newTrack.URL = self.fileURL;
        newTrack.alternateGroup = 2;
        newTrack.language = getFilenameLanguage((__bridge CFStringRef)self.fileURL.path);

        if ([newTrack.language isEqualToString:@"und"]) {
			NSString *stringFromFileAtURL = [[NSString alloc]
											 initWithContentsOfURL:fileURL
											 encoding:NSUTF8StringEncoding
											 error:nil];
			if (stringFromFileAtURL) { // try auto determining
                NSString *guess = guessStringLanguage(stringFromFileAtURL);
                if (guess) {
                    newTrack.language = guess;
                }
            }
        }

        _ss = [[SBSubSerializer alloc] init];
        if ([self.fileURL.pathExtension caseInsensitiveCompare: @"srt"] == NSOrderedSame) {
            success = LoadSRTFromURL(self.fileURL, _ss, &duration);
        } else if ([self.fileURL.pathExtension caseInsensitiveCompare: @"smi"] == NSOrderedSame) {
            success = LoadSMIFromURL(self.fileURL, _ss, 1);
        }

        newTrack.duration = duration;

        if (!success) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be opened.", @"srt error message"),
                                      MP42LocalizedString(@"The file is not a srt file, or it does not contain any subtitles.", @"srt error message"), 100);
            }
            
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
        MP42SampleBuffer *sample;

        for (MP42SubtitleTrack *track in self.inputTracks) {
            CGSize trackSize;
            trackSize.width = track.trackWidth;
            trackSize.height = track.trackHeight;

            while (!_ss.isEmpty && !self.isCancelled) {
                SBSubLine *sl = [_ss getSerializedPacket];

                if ([sl->line isEqualToString:@"\n"]) {
                    sample = copyEmptySubtitleSample(track.sourceId, sl->end_time - sl->begin_time, NO);
                }
                else {
                    int top = (sl->top == INT_MAX) ? trackSize.height : sl->top;
                    sample = copySubtitleSample(track.sourceId, sl->line, sl->end_time - sl->begin_time, sl->forced, _verticalPlacement, YES, trackSize, top);
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
