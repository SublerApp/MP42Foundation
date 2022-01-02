//
//  MP42SSAImporter.m
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
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

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42SSAImporter

+ (NSArray<NSString *> *)supportedFileFormats {
    return @[@"ssa", @"ass"];
}

- (instancetype)initWithURL:(NSURL *)fileURL error:(NSError * __autoreleasing *)outError
{
    if ((self = [super initWithURL:fileURL])) {
        MP42SubtitleTrack *track = [[MP42SubtitleTrack alloc] init];

        track.format = kMP42SubtitleCodecType_3GText;
        track.URL = self.fileURL;
        track.timescale = 1000;
        track.alternateGroup = 2;
        track.language = getFilenameLanguage((__bridge CFStringRef)self.fileURL.path);

        NSString *stringFromFileAtURL = [NSString stringWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:NULL];

        if (!stringFromFileAtURL) {
            if (outError) {
                *outError = MP42Error(MP42LocalizedString(@"The file could not be opened.", @"ssa error message"),
                                      MP42LocalizedString(@"The file is not a ssa file, or it does not contain any subtitles.", @"ssa error message"), 100);
            }
            return nil;
        }

        if ([track.language isEqualToString:@"und"]) {
            NSString *guess = guessStringLanguage(stringFromFileAtURL);
            if (guess) {
                track.language = guess;
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

        track.duration = _parser.duration;

        [self addTrack:track];
    }

    return self;
}

- (nullable NSData *)magicCookieForTrack:(MP42Track *)track
{
    return nil;
}

- (void)demux
{
    @autoreleasepool {

        MP42SSAConverter *converter = [[MP42SSAConverter alloc] initWithParser:_parser];

        MP42SubSerializer *ss = [[MP42SubSerializer alloc] init];
        ss.ssa = YES;

        for (MP42SSALine *line in _parser.lines) {
            NSString *text = [converter convertLine:line];
            if (text.length) {
                MP42SubLine *sl = [[MP42SubLine alloc] initWithLine:text start:line.start end: line.end];
                [ss addLine:sl];
            }
        }
        [ss setFinished:YES];

        for (MP42SubtitleTrack *track in self.inputTracks) {
            CGSize trackSize = CGSizeMake(track.trackWidth, track.trackHeight);
            MP42SampleBuffer *sample;

            while (!ss.isEmpty && !self.isCancelled) {
                MP42SubLine *sl = [ss getSerializedPacket];

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
