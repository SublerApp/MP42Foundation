//
//  SBAudioConverter.h
//  Subler
//
//  Created by Damiano Galassi on 16/09/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "sfifo.h"
#include "downmix.h"
#import "MP42ConverterProtocol.h"
#import "MP42Fifo.h"

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42AudioTrack;

extern NSString * const SBMonoMixdown;
extern NSString * const SBStereoMixdown;
extern NSString * const SBDolbyMixdown;
extern NSString * const SBDolbyPlIIMixdown;

// a struct to hold info for the data proc
static struct AudioFileIO
{    
    AudioConverterRef converter;
    AudioStreamBasicDescription inputFormat;
    AudioStreamBasicDescription outputFormat;

    sfifo_t          *fifo;

	SInt64          pos;
	char *			srcBuffer;
	UInt32			srcBufferSize;
	UInt32			srcSizePerPacket;
	UInt32			numPacketsPerRead;

    AudioStreamBasicDescription     srcFormat;
    AudioStreamPacketDescription     * _Nullable pktDescs;

    MP42Fifo<MP42SampleBuffer *>    *inputSamplesBuffer;

    MP42SampleBuffer      *sample;
    int                   fileReaderDone;
} AudioFileIO;

@interface MP42AudioConverter : NSObject <MP42ConverterProtocol> {
    NSThread *decoderThread;
    NSThread *encoderThread;

    sfifo_t fifo;

    BOOL readerDone;
    BOOL encoderDone;

    int32_t       _cancelled;

    Float64     sampleRate;
    UInt32      inputChannelsCount;
    UInt32      outputChannelCount;

    NSUInteger  downmixType;
    NSUInteger  layout;
    hb_chan_map_t *ichanmap;

    MP42Fifo<MP42SampleBuffer *> *_inputSamplesBuffer;
    MP42Fifo<MP42SampleBuffer *> *_outputSamplesBuffer;

    NSData *outputMagicCookie;

    struct AudioFileIO decoderData;
    struct AudioFileIO encoderData;
}

- (instancetype)initWithTrack:(MP42AudioTrack *)track andMixdownType:(NSString *)mixdownType error:(NSError **)error;

- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

- (NSData *)magicCookie;

- (void)cancel;
- (BOOL)encoderDone;

- (void)setInputDone;

NS_ASSUME_NONNULL_END

@end
