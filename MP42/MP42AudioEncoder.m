//
//  MP42AudioEncoder.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import "MP42AudioEncoder.h"
#import "MP42Fifo.h"
#import "MP42Sample.h"
#import "MP42PrivateUtilities.h"

#include "sfifo.h"

#define FIFO_DURATION (2.5f)

// A struct to hold info for the data proc
typedef struct AudioFileIO
{
    sfifo_t *ringBuffer;

    char   *srcBuffer;
    UInt32  srcBufferSize;

    UInt32  outputMaxSize;

    UInt32  srcSizePerPacket;
    UInt32  channelsPerFrame;
    UInt32  numPacketsPerRead;

    AudioStreamPacketDescription * _Nullable pktDescs;
} AudioFileIO;

@interface MP42AudioEncoder ()
{
    __unsafe_unretained id<MP42AudioUnit> _outputUnit;
    MP42AudioUnitOutput _outputType;

    NSData *_magicCookie;
}

@property (nonatomic, readonly) AudioConverterRef encoder;

@property (nonatomic, readonly) NSThread *decoderThread;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *inputSamplesBuffer;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *outputSamplesBuffer;

@property (nonatomic, readonly) sfifo_t *ringBuffer;
@property (nonatomic, readonly) AudioFileIO afio;

@property (nonatomic, readonly, unsafe_unretained) id<MP42AudioUnit> inputUnit;

@property (nonatomic, readwrite) int32_t readerDone;
@property (nonatomic, readwrite) int32_t decoderDone;

@end

@implementation MP42AudioEncoder

@synthesize outputUnit = _outputUnit;
@synthesize outputType = _outputType;

@synthesize magicCookie = _magicCookie;

- (instancetype)initWithInputUnit:(id<MP42AudioUnit>)unit bitRate:(NSUInteger)bitRate error:(NSError **)error
{
    self = [super init];
    if (self) {
        _inputUnit = unit;
        _inputUnit.outputUnit = self;
        _inputFormat = unit.outputFormat;

        if (![self initConverterWithBitRate:bitRate]) {
            return nil;
        }

        if (![self createMagicCookie]) {
            return nil;
        }

        _inputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];
        _outputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];

        [self start];
    }
    return self;
}

- (void)dealloc
{
    if (_encoder) {
        AudioConverterDispose(_encoder);
    }
    if (_ringBuffer) {
        sfifo_close(_ringBuffer);
        free(_ringBuffer);
    }
}

#pragma mark - Encoder Init

- (BOOL)initConverterWithBitRate:(NSUInteger)bitrate
{
    OSStatus err;
    AudioStreamBasicDescription outputFormat;

    bzero(&outputFormat, sizeof(AudioStreamBasicDescription));
    outputFormat.mFormatID = kAudioFormatMPEG4AAC;
    outputFormat.mSampleRate = (Float64) _inputFormat.mSampleRate;
    outputFormat.mChannelsPerFrame = _inputFormat.mChannelsPerFrame;

    _outputFormat = outputFormat;

    err = AudioConverterNew(&_inputFormat, &_outputFormat, &_encoder);
    if (err) {
        NSLog(@"err: encoder converter init failed");
        return NO;
    }

    UInt32 tmp, tmpsiz = sizeof(tmp);

    // Set encoder quality to maximum.
    tmp = kAudioConverterQuality_Max;
    AudioConverterSetProperty(_encoder, kAudioConverterCodecQuality,
                              sizeof(tmp), &tmp);

    // Set encoder bitrate control mode to constrained variable.
    tmp = kAudioCodecBitRateControlMode_VariableConstrained;
    AudioConverterSetProperty(_encoder, kAudioCodecPropertyBitRateControlMode,
                              sizeof(tmp), &tmp);

    // Set bitrate.
    if (!bitrate) bitrate = 80;

    // Get available bitrates.
    AudioValueRange *bitrates;
    ssize_t bitrateCounts;
    err = AudioConverterGetPropertyInfo(_encoder, kAudioConverterApplicableEncodeBitRates,
                                        &tmpsiz, NULL);
    if (err) {
        NSLog(@"err: kAudioConverterApplicableEncodeBitRates From AudioConverter");
    }
    bitrates = malloc(tmpsiz);
    err = AudioConverterGetProperty(_encoder, kAudioConverterApplicableEncodeBitRates,
                                    &tmpsiz, bitrates);
    if (err) {
        NSLog(@"err: kAudioConverterApplicableEncodeBitRates From AudioConverter");
    }
    bitrateCounts = tmpsiz / sizeof( AudioValueRange );

    // Set bitrate.
    tmp = bitrate * outputFormat.mChannelsPerFrame * 1000;
    if (tmp < bitrates[0].mMinimum) {
        tmp = bitrates[0].mMinimum;
    }
    if (tmp > bitrates[bitrateCounts-1].mMinimum) {
        tmp = bitrates[bitrateCounts-1].mMinimum;
    }
    free(bitrates);

    AudioConverterSetProperty(_encoder, kAudioConverterEncodeBitRate,
                              sizeof( tmp ), &tmp);

    // Get real input.
    tmpsiz = sizeof(_inputFormat);
    AudioConverterGetProperty(_encoder,
                              kAudioConverterCurrentInputStreamDescription,
                              &tmpsiz, &_inputFormat);

    // Get real output.
    tmpsiz = sizeof(_outputFormat);
    AudioConverterGetProperty(_encoder,
                              kAudioConverterCurrentOutputStreamDescription,
                              &tmpsiz, &_outputFormat);

    // Get the output max size
    int outputSizePerPacket = _outputFormat.mBytesPerPacket;
    UInt32 size = sizeof(outputSizePerPacket);
    err = AudioConverterGetProperty(_encoder, kAudioConverterPropertyMaximumOutputPacketSize,
                                    &size, &outputSizePerPacket);
    if (err) {
        NSLog(@"err: kAudioConverterPropertyMaximumOutputPacketSize");
    }

    // Set up our fifo
    _ringBuffer = (sfifo_t *) malloc(sizeof(sfifo_t));
    int ringbuffer_len = _inputFormat.mSampleRate * FIFO_DURATION * 4 * 23;
    sfifo_init(_ringBuffer, ringbuffer_len);

    // Set up buffers and data proc info struct
    struct AudioFileIO encoderData;
    encoderData.srcBufferSize = 32768;
    encoderData.srcBuffer = (char *) malloc(encoderData.srcBufferSize);

    encoderData.outputMaxSize = outputSizePerPacket;

    encoderData.srcSizePerPacket = _inputFormat.mBytesPerPacket;
    encoderData.channelsPerFrame = _inputFormat.mChannelsPerFrame;
    encoderData.numPacketsPerRead = encoderData.srcBufferSize / encoderData.srcSizePerPacket;

    encoderData.pktDescs = NULL;
    encoderData.ringBuffer = _ringBuffer;

    _afio = encoderData;

    return YES;
}

- (BOOL)createMagicCookie
{
    OSStatus err;

    // Grab the cookie from the converter.
    UInt32 cookieSize = 0;
    err = AudioConverterGetPropertyInfo(_encoder, kAudioConverterCompressionMagicCookie, &cookieSize, NULL);

    // If there is an error here, then the format doesn't have a cookie, so on we go
    if (!err && cookieSize) {
        char  *cookie = (char *) malloc(cookieSize);
        UInt8 *cookieBuffer;

        err = AudioConverterGetProperty(_encoder, kAudioConverterCompressionMagicCookie, &cookieSize, cookie);
        if (err) {
            NSLog(@"err: Get Cookie From AudioConverter");
        }
        else {
            int ESDSsize;
            ReadESDSDescExt(cookie, &cookieBuffer, &ESDSsize, 1);
            _magicCookie = [NSData dataWithBytes:cookieBuffer length:ESDSsize];

            free(cookieBuffer);
            free(cookie);

            return YES;
        }
    }
    return NO;
}

- (void)start
{
    _decoderThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMainRoutine) object:nil];
    [_decoderThread setName:@"AudioToolbox Audio Encoder"];
    [_decoderThread start];
}

#pragma mark - Public methods

- (NSData *)magicCookie
{
    return _magicCookie;
}

- (void)addSample:(MP42SampleBuffer *)sample
{
    [_inputSamplesBuffer enqueue:sample];
}

- (nullable MP42SampleBuffer *)copyEncodedSample
{
    return [_outputSamplesBuffer dequeue];
}

- (void)cancel
{
    [_inputSamplesBuffer cancel];
}

#pragma mark - Encoder

OSStatus EncoderDataProc(AudioConverterRef               inAudioConverter,
                         UInt32 *                        ioNumberDataPackets,
                         AudioBufferList *               ioData,
                         AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription,
                         void * __nullable               inUserData)
{
    AudioFileIO *afio = inUserData;
    UInt32 availableBytes = sfifo_used(afio->ringBuffer);

    if (!availableBytes) {
        *ioNumberDataPackets = 0;
        return 1;
    }

    // Figure out how much to read
    if (*ioNumberDataPackets > afio->numPacketsPerRead) {
        *ioNumberDataPackets = afio->numPacketsPerRead;
    }

    // Read from the fifo
    UInt32 wanted = MIN(*ioNumberDataPackets * afio->srcSizePerPacket, availableBytes);
    UInt32 outNumBytes = sfifo_read(afio->ringBuffer, afio->srcBuffer, wanted);

    // Put the data pointer into the buffer list
    ioData->mBuffers[0].mData = afio->srcBuffer;
    ioData->mBuffers[0].mDataByteSize = outNumBytes;
    ioData->mBuffers[0].mNumberChannels = afio->channelsPerFrame;

    *ioNumberDataPackets = ioData->mBuffers[0].mDataByteSize / afio->srcSizePerPacket;

    if (outDataPacketDescription) {
        if (afio->pktDescs) {
            *outDataPacketDescription = afio->pktDescs;
        }
        else {
            *outDataPacketDescription = NULL;
        }
    }

    return noErr;
}

static MP42SampleBuffer *encode(AudioConverterRef encoder, AudioFileIO *afio)
{
    OSStatus err = noErr;
    AudioStreamPacketDescription odesc = {0, 0, 0};
    UInt32 ioOutputDataPackets = 1;

    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];
    sample->size = afio->outputMaxSize;
    sample->data = malloc(afio->outputMaxSize);

    // Set up output buffer list
    AudioBufferList fillBufList;
    fillBufList.mNumberBuffers = 1;
    fillBufList.mBuffers[0].mNumberChannels = afio->channelsPerFrame;
    fillBufList.mBuffers[0].mDataByteSize = sample->size;
    fillBufList.mBuffers[0].mData = sample->data;

    // Convert data
    err = AudioConverterFillComplexBuffer(encoder, EncoderDataProc,
                                          afio, &ioOutputDataPackets,
                                          &fillBufList, &odesc);
    if (err != noErr && err != 1) {
        NSLog(@"err: unexpected error in AudioConverterFillComplexBuffer(): %ld", (long)err);
    }

    if (ioOutputDataPackets == 0) {
        return nil;
    }

    sample->size = fillBufList.mBuffers[0].mDataByteSize;
    sample->duration = 1024;
    sample->offset = 0;
    //sample->timestamp = outputPos;
    sample->isSync = YES;

    return sample;
    //outputPos += ioOutputDataPackets;
}

- (void)threadMainRoutine
{
    @autoreleasepool {
        MP42SampleBuffer *sampleBuffer = nil;

        while ((sampleBuffer = [_inputSamplesBuffer dequeueAndWait])) {
            @autoreleasepool {

                MP42SampleBuffer *outSample = nil;
                BOOL lastSample = NO;

                if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                    lastSample = YES;
                }
                else {
                    sfifo_write(_ringBuffer, sampleBuffer->data, sampleBuffer->size);
                }

                while ((outSample = encode(_encoder, &_afio))) {
                    if (_outputType == MP42AudioUnitOutputPush) {
                        [_outputUnit addSample:outSample];
                    }
                    else {
                        [_outputSamplesBuffer enqueue:outSample];
                    }
                }

                if (lastSample) {
                    if (_outputType == MP42AudioUnitOutputPush) {
                        [_outputUnit addSample:sampleBuffer];
                    }
                    else {
                        [_outputSamplesBuffer enqueue:sampleBuffer];
                    }
                    return;
                }
            }
        }
    }
}


@end
