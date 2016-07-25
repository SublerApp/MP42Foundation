//
//  MP42AudioDecoder.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import "MP42AudioDecoder.h"

#import "MP42AudioTrack.h"
#import "MP42Sample.h"
#import "MP42Fifo.h"

#include "FFmpegUtils.h"

#include <avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>

@interface MP42AudioDecoder ()
{
    __unsafe_unretained id<MP42AudioUnit> _outputUnit;
    MP42AudioUnitOutput outputType;
}

@property (nonatomic, readonly) AVCodec *codec;
@property (nonatomic, readonly) AVCodecContext *avctx;

@property (nonatomic, readonly) NSThread *decoderThread;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *inputSamplesBuffer;
@property (nonatomic, readonly) MP42Fifo<MP42SampleBuffer *> *outputSamplesBuffer;

@property (nonatomic, readonly) SwrContext *swr;

@property (nonatomic, readwrite) int32_t readerDone;
@property (nonatomic, readwrite) int32_t decoderDone;

@end

@implementation MP42AudioDecoder

@synthesize outputUnit = _outputUnit;
@synthesize outputType = _outputType;

- (instancetype)initWithAudioFormat:(AudioStreamBasicDescription)asbd mixdownType:(NSString *)mixdownType magicCookie:(NSData *)magicCookie error:(NSError **)error;
{
    self = [super init];

    if (self) {
        FFInitFFmpeg();

        _inputFormat = asbd;

        enum AVCodecID codecID = FourCCToCodecID(asbd.mFormatID);
        _codec = avcodec_find_decoder(codecID);

        if (!_codec) {
            return nil;
        }

        _avctx = avcodec_alloc_context3(_codec);

        if (!_avctx) {
            return nil;
        }

        hb_ff_set_sample_fmt(_avctx, _codec, AV_SAMPLE_FMT_FLT);

        if (_avctx && magicCookie) {

            _avctx->extradata = (uint8_t*)av_malloc(magicCookie.length + AV_INPUT_BUFFER_PADDING_SIZE);
            if (!_avctx->extradata) {
                NSLog(@"Could not av_malloc extradata");
            }
            else {
                _avctx->extradata_size = magicCookie.length;
                memcpy(_avctx->extradata, magicCookie.bytes, magicCookie.length);
            }
        }

        if (avcodec_open2(_avctx, _codec, NULL)) {
            NSLog(@"Error opening audio decoder");
            av_freep(&_avctx);
            return nil;
        }

        // We want float interleaved, FFmpeg usually prefers
        // float planar, so we need to convert it.
        if (_avctx->sample_fmt != AV_SAMPLE_FMT_FLT) {
            // Set up SWR context once you've got codec information
            _swr = swr_alloc();
            av_opt_set_int(_swr, "in_channel_layout",  AV_CH_LAYOUT_STEREO, 0);
            av_opt_set_int(_swr, "out_channel_layout", AV_CH_LAYOUT_STEREO,  0);
            av_opt_set_int(_swr, "in_sample_rate",     _inputFormat.mSampleRate, 0);
            av_opt_set_int(_swr, "out_sample_rate",    _inputFormat.mSampleRate, 0);
            av_opt_set_sample_fmt(_swr, "in_sample_fmt",  _avctx->sample_fmt, 0);
            av_opt_set_sample_fmt(_swr, "out_sample_fmt", AV_SAMPLE_FMT_FLT,  0);
            swr_init(_swr);
        }

        // Creates the output audio stream basic description.
        // It will be used to configure the next audio unit in the chain.
        AudioStreamBasicDescription outputFormat;
        bzero(&outputFormat, sizeof(AudioStreamBasicDescription));
        outputFormat.mSampleRate = _inputFormat.mSampleRate;
        outputFormat.mFormatID = kAudioFormatLinearPCM ;
        outputFormat.mFormatFlags =  kLinearPCMFormatFlagIsFloat | kAudioFormatFlagsNativeEndian;
        outputFormat.mBytesPerPacket = 4 * _inputFormat.mChannelsPerFrame;
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = outputFormat.mBytesPerPacket * outputFormat.mFramesPerPacket;
        outputFormat.mChannelsPerFrame = _inputFormat.mChannelsPerFrame;
        outputFormat.mBitsPerChannel = 32;

        _outputFormat = outputFormat;

        _inputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];
        _outputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];

        [self start];
    }

    return self;
}

- (void)dealloc
{
    if (_avctx) {
        avcodec_close(_avctx);
        av_freep(&_avctx);
    }

    if (_swr) {
        swr_free(&_swr);
    }
}

- (void)start
{
    _decoderThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMainRoutine) object:nil];
    [_decoderThread setName:@"FFmpeg Audio Decoder"];
    [_decoderThread start];
}

#pragma mark - Public methods

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

#pragma mark - Decode

static AVPacket * packetFromSampleBuffer(MP42SampleBuffer *sample)
{
    AVPacket *pkt = av_packet_alloc();
    pkt->data = sample->data;
    pkt->size = sample->size;
    pkt->pts = sample->timestamp;
    pkt->dts = AV_NOPTS_VALUE;

    return pkt;
}

static MP42SampleBuffer * sampleBufferFromFrame(AVFrame *frame, SwrContext *swr)
{
    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];

    int out_samples;
    int out_sample_rate = 44100;
    int out_nb_channels = 2;
    enum AVSampleFormat out_sample_format = AV_SAMPLE_FMT_FLT;

    // if sample rate changes, number of samples is different
    if (out_sample_rate !=  frame->sample_rate) {
        //int delay = swr_get_delay(swr, frame->sample_rate);
        //            out_samples = av_rescale_rnd(swr_get_delay(swr_context, avctx->sample_rate) +
        //                                 frame->nb_samples, out_sample_rate, avctx->sample_rate, AV_ROUND_UP);
        out_samples = av_rescale_rnd(frame->nb_samples, out_sample_rate, frame->sample_rate, AV_ROUND_UP);
    }
    else {
        out_samples = frame->nb_samples;
    }

    int plane_size;
    int planar = av_sample_fmt_is_planar(frame->format);

    int output_data_size = av_samples_get_buffer_size(&plane_size, 2,
                                                      out_samples,
                                                      out_sample_format, 1);

    uint8_t *outputBuffer = malloc(output_data_size + AV_INPUT_BUFFER_PADDING_SIZE);

    // if resampling is needed, call swr_convert
    if (swr) {

        out_samples = swr_convert(swr, &outputBuffer, out_samples,
                                  (const uint8_t **)frame->extended_data, frame->nb_samples);

        // recompute output_data_size following swr_convert result (number of samples actually converted)
        output_data_size = av_samples_get_buffer_size(&plane_size, out_nb_channels,
                                                      out_samples,
                                                      out_sample_format, 1);
    }
    else {
        memcpy(outputBuffer, frame->extended_data[0], plane_size);

        if (planar && frame->channels > 1) {
            uint8_t *out = outputBuffer + plane_size;
            for (int ch = 1; ch < frame->channels; ch++) {
                memcpy(out, frame->extended_data[ch], plane_size);
                out += plane_size;
            }
        }
    }

    sample->data = outputBuffer;
    sample->size = output_data_size;

    return sample;
}

static int decode(AVCodecContext *avctx, SwrContext *swr, MP42SampleBuffer *inSample, MP42SampleBuffer **outSample)
{
    int ret;

    AVPacket *pkt = packetFromSampleBuffer(inSample);
    ret = avcodec_send_packet(avctx, pkt);
    av_packet_free(&pkt);

    // In particular, we don't expect AVERROR(EAGAIN), because we read all
    // decoded frames with avcodec_receive_frame() until done.
    if (ret < 0) {
        printf("%s\n", av_err2str(ret));
        return ret == AVERROR_EOF ? 0 : ret;
    }

    AVFrame *frame = av_frame_alloc();
    ret = avcodec_receive_frame(avctx, frame);
    if (!ret) {
        *outSample = sampleBufferFromFrame(frame, swr);
    }
    av_frame_free(&frame);

    if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
        printf("%s\n", av_err2str(ret));
        return ret;
    }

    return 0;
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
                    outSample = sampleBuffer;
                    lastSample = YES;
                }
                else {
                    decode(_avctx, _swr, sampleBuffer, &outSample);
                }

                if (outSample) {
                    if (_outputType == MP42AudioUnitOutputPush) {
                        [_outputUnit addSample:outSample];
                    }
                    else {
                        [_outputSamplesBuffer enqueue:outSample];
                    }
                }

                if (lastSample) {
                    return;
                }
            }
        }
    }
}

@end
