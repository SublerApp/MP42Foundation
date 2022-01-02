//
//  MP42AC3AudioEncoder.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42AC3AudioEncoder.h"
#import "MP42Fifo.h"
#import "MP42SampleBuffer.h"
#import "MP42PrivateUtilities.h"
#include "sfifo.h"
#include "FFmpegUtils.h"

#define FIFO_DURATION (2.5f)

// A struct to hold info for the data proc
typedef struct AudioFileIO
{
    sfifo_t *ringBuffer;

    float   *inBuffer;
    UInt32  inBufferSize;

    UInt32  inSizePerPacket;
    UInt32  inSamples;
    UInt32  channelsPerFrame;

    AVFrame *frame;
    float *samples;

    UInt64 outputPos;

    bool done;

    AudioStreamPacketDescription * _Nullable pktDescs;
} AudioFileIO;

MP42_OBJC_DIRECT_MEMBERS
@interface MP42AC3AudioEncoder ()
{
    AVCodecContext *_avctx;
    
    __unsafe_unretained id<MP42AudioUnit> _outputUnit;
    MP42AudioUnitOutput _outputType;

    NSData *_magicCookie;
}

@property (nonatomic, readonly) NSUInteger bitrate;

@property (nonatomic, readonly) NSThread *thread;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *inputSamplesBuffer;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *outputSamplesBuffer;

@property (nonatomic, readonly) sfifo_t *ringBuffer;
@property (nonatomic, readonly) AudioFileIO *afio;

@property (nonatomic, readonly, unsafe_unretained) id<MP42AudioUnit> inputUnit;

@end

@implementation MP42AC3AudioEncoder

@synthesize outputUnit = _outputUnit;
@synthesize outputType = _outputType;

@synthesize magicCookie = _magicCookie;

- (instancetype)initWithInputUnit:(id<MP42AudioUnit>)unit bitRate:(NSUInteger)bitRate error:(NSError * __autoreleasing *)error
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

- (BOOL)initConverterWithBitRate:(NSUInteger)bitrate
{
    AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_AC3);
    if (!codec) {
        if ([[NSString stringWithFormat:@"%s", avcodec_configuration()] rangeOfString:@"--enable-encoder=ac3"].location == NSNotFound) {
            NSLog(@"Codec not found. Compile ffmpeg with configuration: %s --enable-encoder=ac3", avcodec_configuration());
        }
        else {
            NSLog(@"Codec not found. Have you registered the encoder with avcodec_register() or avcodec_register_all()?");
        }
        return NO;
    }

    _avctx = avcodec_alloc_context3(codec);
    if (!_avctx) {
        NSLog(@"Could not allocate audio codec context");
        return NO;
    }

    _avctx->bit_rate       = (!bitrate) ? 640000 : bitrate * 1000;
    _avctx->sample_fmt     = AV_SAMPLE_FMT_FLTP;
    _avctx->sample_rate    = 48000;
    
    _avctx->channel_layout = channel_layout_for_channels(codec, _inputFormat.mChannelsPerFrame);
    _avctx->channels       = av_get_channel_layout_nb_channels(_avctx->channel_layout);

    AudioStreamBasicDescription outputFormat;
    bzero(&outputFormat, sizeof(AudioStreamBasicDescription));
    outputFormat.mFormatID = kAudioFormatAC3;
    outputFormat.mSampleRate = _avctx->sample_rate;
    outputFormat.mChannelsPerFrame = _avctx->channels;
    outputFormat.mFramesPerPacket = 1536;
    outputFormat.mBytesPerPacket = 4 * outputFormat.mChannelsPerFrame;
    outputFormat.mBytesPerFrame = outputFormat.mBytesPerPacket * outputFormat.mFramesPerPacket;
    outputFormat.mBitsPerChannel = 16;
    outputFormat.mFormatFlags = kAudioFormatFlagIsFloat;
    _outputFormat = outputFormat;

    if (avcodec_open2(_avctx, codec, NULL) < 0) {
        NSLog(@"Could not open codec");
        return NO;
    }
    
    _ringBuffer = (sfifo_t *) malloc(sizeof(sfifo_t));
    int ringbuffer_len = _inputFormat.mSampleRate * FIFO_DURATION * 4 * 23;
    sfifo_init(_ringBuffer, ringbuffer_len);
    
    _afio = malloc(sizeof(AudioFileIO));
    bzero(_afio, sizeof(AudioFileIO));

    _afio->inBufferSize = 1024 * 64;
    _afio->inBuffer     = malloc(_afio->inBufferSize);

    _afio->inSizePerPacket = _inputFormat.mBytesPerPacket;
    _afio->inSamples = _outputFormat.mFramesPerPacket;
    _afio->channelsPerFrame = _inputFormat.mChannelsPerFrame;

    _afio->ringBuffer = _ringBuffer;

    _afio->frame = av_frame_alloc();
    if (!_afio->frame) {
        NSLog(@"Could not allocate audio frame");
        return NO;
    }
    
    _afio->frame->nb_samples     = _avctx->frame_size;
    _afio->frame->format         = _avctx->sample_fmt;
    _afio->frame->channel_layout = _avctx->channel_layout;
    _afio->frame->channels       = _avctx->channels;
    
    int buffer_size = av_samples_get_buffer_size(NULL, _avctx->channels, _avctx->frame_size,
                                                 _avctx->sample_fmt, 0);
    _afio->samples = av_malloc(buffer_size);
    if (!_afio->samples) {
        NSLog(@"Could not allocate %d bytes for samples buffer", buffer_size);
        return NO;
    }
    int ret = avcodec_fill_audio_frame(_afio->frame, _avctx->channels, _avctx->sample_fmt,
                                       (const uint8_t*)_afio->samples, buffer_size, 0);
    if (ret < 0) {
        NSLog(@"Could not setup audio frame");
        return NO;
    }

    return YES;
}

- (void)disposeConverter
{
    if (_afio)
    {
        if (_afio->samples)
        {
            av_freep(&_afio->samples);
        }
        if (_afio->frame)
        {
            av_frame_free(&_afio->frame);
        }
        free(_afio->inBuffer);
        free(_afio);
        _afio = NULL;

    }
    if (_avctx)
    {
        avcodec_close(_avctx);
        av_free(_avctx);
    }

    if (_ringBuffer) {
        sfifo_close(_ringBuffer);
        free(_ringBuffer);
        _ringBuffer = NULL;
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
    uint64_t fscod = 0;
    uint64_t bsid = 8;
    uint64_t bsmod = 0;
    uint64_t acmod = 7;
    uint64_t lfeon = (_avctx->channel_layout & AV_CH_LOW_FREQUENCY) ? 1 : 0;
    uint64_t bit_rate_code = 15;
    
    switch (_avctx->channels - lfeon)
    {
        case 1:
            acmod = 1;
            break;
        case 2:
            acmod = 2;
            break;
        case 3:
            if (_avctx->channel_layout & AV_CH_BACK_CENTER) acmod = 3;
            else acmod = 4;
            break;
        case 4:
            if (_avctx->channel_layout & AV_CH_BACK_CENTER) acmod = 5;
            else acmod = 6;
            break;
        case 5:
            acmod = 7;
            break;
        default:
            break;
    }
    
    if (_avctx->sample_rate == 48000) fscod = 0;
    else if (_avctx->sample_rate == 44100) fscod = 1;
    else if (_avctx->sample_rate == 32000) fscod = 2;
    else fscod = 3;
    
    NSMutableData *ac3Info = [[NSMutableData alloc] init];
    [ac3Info appendBytes:&fscod length:sizeof(uint64_t)];
    [ac3Info appendBytes:&bsid length:sizeof(uint64_t)];
    [ac3Info appendBytes:&bsmod length:sizeof(uint64_t)];
    [ac3Info appendBytes:&acmod length:sizeof(uint64_t)];
    [ac3Info appendBytes:&lfeon length:sizeof(uint64_t)];
    [ac3Info appendBytes:&bit_rate_code length:sizeof(uint64_t)];
    
    _magicCookie = ac3Info;

    return YES;
}

- (void)start
{
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMainRoutine) object:nil];
    [_thread setName:@"FFmpeg Audio Encoder"];
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

static MP42SampleBuffer *encode(AVCodecContext *context, AudioFileIO *afio)
{
    UInt32 availableBytes = sfifo_used(afio->ringBuffer);
    if (!afio->done &&
        availableBytes < afio->inSamples * afio->inSizePerPacket) {
        return nil;
    }

    UInt32 wanted = MIN(afio->inSamples * afio->inSizePerPacket, availableBytes);
    UInt32 outNumBytes = sfifo_read(afio->ringBuffer, afio->inBuffer, wanted);
    if (outNumBytes == 0)
    {
        return nil;
    }
    
    // Populate the AVFrame with the samples
    float *pEnc = afio->samples;
    float *pIn   = afio->inBuffer;
    int channels = afio->channelsPerFrame;
    int samples  = context->frame_size;
    int outputChannels = context->channels;
    for (int ch = 0; ch < channels; ++ch) {
        for (int i = 0; i < samples; ++i) {
            if (ch < outputChannels) {
                *pEnc++ = pIn[channels * i + ch];
            }
        }
    }

    // Encode
    MP42SampleBuffer *sample = nil;
    if (avcodec_send_frame(context, afio->frame) == 0)
    {
        AVPacket *pkt = av_packet_alloc();
        if (avcodec_receive_packet(context, pkt) == 0)
        {
            sample = [[MP42SampleBuffer alloc] init];
            sample->size = pkt->size;
            sample->duration = pkt->duration;
            sample->decodeTimestamp = afio->outputPos * pkt->duration;
            sample->presentationTimestamp = sample->decodeTimestamp;
            sample->presentationOutputTimestamp = sample->decodeTimestamp;
            sample->data = malloc(pkt->size);
            memcpy(sample->data, pkt->data, pkt->size);
            sample->flags |= MP42SampleBufferFlagIsSync;
            afio->outputPos += 1;
        }
        av_packet_free(&pkt);
    }
    
    return sample;
}

static MP42SampleBuffer *flush(AVCodecContext *context, AudioFileIO *afio)
{
    MP42SampleBuffer *outSample = encode(context, afio);
    return outSample;
}

static inline void enqueue(MP42AC3AudioEncoder *self, MP42SampleBuffer *outSample)
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
                    if (_avctx) {
                        _afio->done = true;
                        while ((outSample = flush(_avctx, _afio))) {
                            enqueue(self, outSample);
                        }
                    }

                    enqueue(self, sampleBuffer);
                    return;
                }
                else {
                    if (_avctx) {
                        sfifo_write(_ringBuffer, sampleBuffer->data, sampleBuffer->size);
                        while ((outSample = encode(_avctx, _afio))) {
                            enqueue(self, outSample);
                        }
                    }
                }
            }
        }
    }
}


@end
