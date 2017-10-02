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

        if ([newTrack.language isEqualToString:@"und"]) {
            NSString *guess = guessStringLanguage(stringFromFileAtURL);
            if (guess) {
                newTrack.language = guess;
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

        SBSubSerializer *ss = [[SBSubSerializer alloc] init];
        [ss setSSA:YES];

        for (MP42SSALine *line in _parser.lines) {
            NSString *text = [converter convertLine:line];
            if (text.length) {
                SBSubLine *sl = [[SBSubLine alloc] initWithLine:text start:line.start end: line.end];
                [ss addLine:sl];
            }
        }
        [ss setFinished:YES];

        for (MP42SubtitleTrack *track in self.inputTracks) {
            CGSize trackSize;
            trackSize.width = track.trackWidth;
            trackSize.height = track.trackHeight;
            MP42SampleBuffer *sample;

            while (!ss.isEmpty && !self.isCancelled) {
                SBSubLine *sl = [ss getSerializedPacket];

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
    return @"SSA demuxer";
}

@end
