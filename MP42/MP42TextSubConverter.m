//
//  MP42TextSubConverter.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2017 Damiano Galassi. All rights reserved.
//

#import "MP42TextSubConverter.h"

#import "MP42FileImporter.h"
#import "MP42FileImporter+Private.h"

#import "MP42Track.h"
#import "MP42SubtitleTrack.h"
#import "MP42Track+Private.h"

#import "MP42Fifo.h"
#import "MP42Sample.h"

#import "MP42SubUtilities.h"
#import "MP42SSAParser.h"
#import "MP42SSAConverter.h"

@interface MP42TextSubConverter ()

@property (nonatomic, readonly) NSThread *decoderThread;
@property (nonatomic, readonly) dispatch_semaphore_t done;

@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *inputSamplesBuffer;

@property (nonatomic, readonly) SBSubSerializer *ss;

@property (nonatomic, readonly) MP42SSAParser *parser;
@property (nonatomic, readonly) MP42SSAConverter *converter;

@property (nonatomic, readonly) MP4TrackId trackID;

@property (nonatomic, readonly) _Atomic int32_t finished;

@end

@implementation MP42TextSubConverter

- (void)TextConverterThreadMainRoutine
{
    @autoreleasepool {
        MP42SampleBuffer *sampleBuffer = nil;

        while ((sampleBuffer = [_inputSamplesBuffer dequeueAndWait])) {
            @autoreleasepool {

                if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                    [_ss setFinished:YES];
                    _finished = 1;
                    break;
                }

                NSString *text = [[NSString alloc] initWithBytes:sampleBuffer->data
                                                          length:sampleBuffer->size
                                                        encoding:NSUTF8StringEncoding];

                if (_converter && text.length) {
                    if (_converter) {
                        MP42SSALine *SSAline = [_parser addLine:text];
                        text = [_converter convertLine:SSAline];
                    }
                }

                if (text.length) {
                    SBSubLine *sl = [[SBSubLine alloc] initWithLine:text
                                                              start:sampleBuffer->decodeTimestamp
                                                                end:sampleBuffer->decodeTimestamp + sampleBuffer->duration];
                    [_ss addLine:sl];
                }
            }
        }
        dispatch_semaphore_signal(_done);
    }
}

- (instancetype)initWithTrack:(MP42SubtitleTrack *)track error:(NSError **)outError
{
    if ((self = [super init])) {
        MP42SubtitleCodecType format = track.format;

        if (format == kMP42SubtitleCodecType_SSA) {
            NSData *cookie = [track.importer magicCookieForTrack:track];
            NSString *cookieString = [[NSString alloc] initWithData:cookie encoding:NSUTF8StringEncoding];
            _parser = [[MP42SSAParser alloc] initWithMKVHeader:cookieString];
            _converter = [[MP42SSAConverter alloc] initWithParser:_parser];
        }

        _ss = [[SBSubSerializer alloc] init];
        _inputSamplesBuffer  = [[MP42Fifo alloc] initWithCapacity:100];
        _done = dispatch_semaphore_create(0);
        _trackID = track.sourceId;

        _decoderThread = [[NSThread alloc] initWithTarget:self selector:@selector(TextConverterThreadMainRoutine) object:nil];
        [_decoderThread setName:@"Text Converter"];
        [_decoderThread start];
    }

    return self;
}

- (void)addSample:(MP42SampleBuffer *)sample
{
    [_inputSamplesBuffer enqueue:sample];
}

- (nullable MP42SampleBuffer *)copyEncodedSample
{
    if (_finished) {
        if (!_ss.isEmpty) {
            SBSubLine *sl = [_ss getSerializedPacket];
            MP42SampleBuffer *sample;

            if ([sl->line isEqualToString:@"\n"]) {
                sample = copyEmptySubtitleSample(_trackID, sl->end_time - sl->begin_time, NO);
            }
            else {
                sample = copySubtitleSample(_trackID, sl->line, sl->end_time - sl->begin_time, sl->forced, NO, YES, CGSizeMake(0, 0), 0);
            }

            return sample;
        }
        else {
            MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
            sample->flags |= MP42SampleBufferFlagEndOfFile;
            sample->trackId = _trackID;

            _finished = 0;

            return sample;
        }
    }

    return nil;
}

- (void)cancel
{
    [_inputSamplesBuffer cancel];
    dispatch_semaphore_wait(_done, DISPATCH_TIME_FOREVER);
}

@end
