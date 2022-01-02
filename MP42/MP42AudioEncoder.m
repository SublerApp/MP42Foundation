//
//  MP42AudioEncoder.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42AudioEncoder.h"
#import "MP42Fifo.h"
#import "MP42SampleBuffer.h"
#import "MP42FormatUtilites.h"

#include "sfifo.h"

#define FIFO_DURATION (2.5f)

// A struct to hold info for the data proc
typedef struct AudioFileIO
{
    sfifo_t *ringBuffer;

    char   *inBuffer;
    UInt32  inBufferSize;

    UInt32  outputMaxSize;

    UInt32  inSizePerPacket;
    UInt32  inSamples;
    UInt32  channelsPerFrame;
    UInt32  numPacketsPerRead;

    UInt64 outputPos;

    bool done;

    AudioStreamPacketDescription * _Nullable pktDescs;
} AudioFileIO;

MP42_OBJC_DIRECT_MEMBERS
@interface MP42AudioEncoder ()
{
    __unsafe_unretained id<MP42AudioUnit> _outputUnit;
    MP42AudioUnitOutput _outputType;

    NSData *_magicCookie;
}

@property (nonatomic, readonly) AudioConverterRef encoder;
@property (nonatomic, readonly) UInt32 bitrate;

@property (nonatomic, readonly) NSThread *thread;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *inputSamplesBuffer;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *outputSamplesBuffer;

@property (nonatomic, readonly) sfifo_t *ringBuffer;
@property (nonatomic, readonly) AudioFileIO *afio;

@property (nonatomic, readonly, unsafe_unretained) id<MP42AudioUnit> inputUnit;

@end

@implementation MP42AudioEncoder

@synthesize outputUnit = _outputUnit;
@synthesize outputType = _outputType;

@synthesize magicCookie = _magicCookie;

- (instancetype)initWithInputUnit:(id<MP42AudioUnit>)unit bitRate:(UInt32)bitRate error:(NSError * __autoreleasing *)error
{
    self = [super init];
    if (self) {
        _inputUnit = unit;
        _inputUnit.outputUnit = self;
        _inputFormat = unit.outputFormat;

        _bitrate = bitRate;

        _inputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];
        _outputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];

        [self start];
    }
    return self;
}

- (void)dealloc
{
    [self disposeConverter];
}

#pragma mark - Encoder Init

- (BOOL)initConverterWithBitRate:(UInt32)bitrate
{
    OSStatus err;
    AudioStreamBasicDescription outputFormat;

    bzero(&outputFormat, sizeof(AudioStreamBasicDescription));
    outputFormat.mFormatID = kAudioFormatMPEG4AAC;
    outputFormat.mSampleRate = (Float64) _inputFormat.mSampleRate;
    outputFormat.mChannelsPerFrame = _inputFormat.mChannelsPerFrame;

    _outputFormat = outputFormat;

    err = AudioConverterNew(&_inputFormat, &_outputFormat, &_encoder);
    if (err || _encoder == NULL) {
        NSLog(@"err: encoder converter init failed");
        _encoder = NULL;
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
    bitrateCounts = tmpsiz / sizeof(AudioValueRange);

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
                              sizeof(tmp), &tmp);

    // Set the input channel layout.
    if (_inputLayout) {
        err = AudioConverterSetProperty(_encoder, kAudioConverterInputChannelLayout, _inputLayoutSize, _inputLayout);
        if (err) {
            NSLog(@"err: kAudioConverterInputChannelLayout From AudioConverter");
        }
    }

    // Get the output channel layout.
    err = AudioConverterGetPropertyInfo(_encoder,
                                        kAudioConverterOutputChannelLayout,
                                        &_outputLayoutSize, NULL);
    if (err) {
        NSLog(@"err: kAudioConverterOutputChannelLayout From AudioConverter");
    }

    _outputLayout = malloc(_outputLayoutSize);
    err = AudioConverterGetProperty(_encoder,
                                    kAudioConverterOutputChannelLayout,
                                    &_outputLayoutSize, _outputLayout);
    if (err) {
        NSLog(@"err: kAudioConverterOutputChannelLayout From AudioConverter");
    }

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

    // Get the prime info
    tmpsiz = sizeof(_primeInfo);
    AudioConverterGetProperty(_encoder,
                              kAudioConverterPrimeInfo,
                              &tmpsiz, &_primeInfo);

    // Set up our fifo
    _ringBuffer = (sfifo_t *) malloc(sizeof(sfifo_t));
    int ringbuffer_len = _inputFormat.mSampleRate * FIFO_DURATION * 4 * 23;
    sfifo_init(_ringBuffer, ringbuffer_len);

    // Set up buffers and data proc info struct
    _afio = malloc(sizeof(AudioFileIO));
    bzero(_afio, sizeof(AudioFileIO));

    _afio->inBufferSize = 32768;
    _afio->inBuffer = (char *) malloc(_afio->inBufferSize);

    _afio->outputMaxSize = outputSizePerPacket;

    _afio->inSizePerPacket = _inputFormat.mBytesPerPacket;
    _afio->inSamples = _outputFormat.mFramesPerPacket;
    _afio->channelsPerFrame = _inputFormat.mChannelsPerFrame;
    _afio->numPacketsPerRead = _afio->inBufferSize / _afio->inSizePerPacket;

    _afio->ringBuffer = _ringBuffer;

    return YES;
}

- (void)disposeConverter
{
    if (_encoder) {
        AudioConverterDispose(_encoder);
        _encoder = NULL;
    }
    if (_ringBuffer) {
        sfifo_close(_ringBuffer);
        free(_ringBuffer);
        _ringBuffer = NULL;
    }

    if (_afio) {
        free(_afio->inBuffer);
        free(_afio);
        _afio = NULL;
    }

    if (_outputLayout) {
        free(_outputLayout);
        _outputLayout = NULL;
    }

    if (_inputLayout) {
        free(_inputLayout);
        _inputLayout = NULL;
    }
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
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMainRoutine) object:nil];
    [_thread setName:@"AudioToolbox Audio Encoder"];
    [_thread start];
}

#pragma mark - Public methods

- (void)reconfigure
{
    [self disposeConverter];

    _inputFormat = _inputUnit.outputFormat;
    _inputLayoutSize = _inputUnit.outputLayoutSize;
    _inputLayout = malloc(_inputLayoutSize);
    memcpy(_inputLayout, _inputUnit.outputLayout, _inputLayoutSize);

    if (![self initConverterWithBitRate:_bitrate]) {
        return;
    }

    if (![self createMagicCookie]) {
        return;
    }
}

- (nullable NSData *)magicCookie
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
        if (afio->done) {
            ioData->mBuffers[0].mDataByteSize = 0;
            return 0;
        }
        else {
            return 1;
        }
    }

    // Figure out how much to read
    if (*ioNumberDataPackets > afio->numPacketsPerRead) {
        *ioNumberDataPackets = afio->numPacketsPerRead;
    }

    // Read from the fifo
    UInt32 wanted = MIN(*ioNumberDataPackets * afio->inSizePerPacket, availableBytes);
    UInt32 outNumBytes = sfifo_read(afio->ringBuffer, afio->inBuffer, wanted);

    // Put the data pointer into the buffer list
    ioData->mBuffers[0].mData = afio->inBuffer;
    ioData->mBuffers[0].mDataByteSize = outNumBytes;
    ioData->mBuffers[0].mNumberChannels = afio->channelsPerFrame;

    *ioNumberDataPackets = ioData->mBuffers[0].mDataByteSize / afio->inSizePerPacket;

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

    UInt32 availableBytes = sfifo_used(afio->ringBuffer);
    // Check if we need more data
    if (!afio->done &&
        availableBytes < afio->inSamples * afio->inSizePerPacket) {
        return nil;
    }

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
    sample->decodeTimestamp = afio->outputPos * 1024;
    sample->presentationTimestamp = sample->decodeTimestamp;
    sample->presentationOutputTimestamp = sample->decodeTimestamp;
    sample->flags |= MP42SampleBufferFlagIsSync;

    afio->outputPos += ioOutputDataPackets;

    return sample;
}

static MP42SampleBuffer *flush(AudioConverterRef encoder, AudioFileIO *afio)
{
    MP42SampleBuffer *outSample = encode(encoder, afio);
    return outSample;
}

static inline void enqueue(MP42AudioEncoder *self, MP42SampleBuffer *outSample)
{
    if (outSample) {
        if (self->_outputType == MP42AudioUnitOutputPush) {
            [self->_outputUnit addSample:outSample];
        }
        else {
            [self->_outputSamplesBuffer enqueue:outSample];
        }
    }
}

- (void)threadMainRoutine
{
    @autoreleasepool {
        MP42SampleBuffer *sampleBuffer = nil;

        while ((sampleBuffer = [_inputSamplesBuffer dequeueAndWait])) {
            @autoreleasepool {

                MP42SampleBuffer *outSample = nil;

                if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                    if (_encoder) {
                        _afio->done = true;
                        while ((outSample = flush(_encoder, _afio))) {
                            enqueue(self, outSample);
                        }

                        // Update the prime info
                        UInt32 tmpsiz = sizeof(_primeInfo);
                        AudioConverterGetProperty(_encoder,
                                                  kAudioConverterPrimeInfo,
                                                  &tmpsiz, &_primeInfo);
                    }

                    enqueue(self, sampleBuffer);
                    return;
                }
                else {
                    if (_encoder) {
                        sfifo_write(_ringBuffer, sampleBuffer->data, sampleBuffer->size);
                        while ((outSample = encode(_encoder, _afio))) {
                            enqueue(self, outSample);
                        }
                    }
                }
            }
        }
    }
}


@end
