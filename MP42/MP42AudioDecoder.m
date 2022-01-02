//
//  MP42AudioDecoder.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42AudioDecoder.h"

#import "MP42AudioTrack.h"
#import "MP42SampleBuffer.h"
#import "MP42Fifo.h"

#include "FFmpegUtils.h"

#include "audio_resample.h"

#include <avcodec.h>
#include <libavutil/downmix_info.h>
#include <libavutil/opt.h>

struct MP42DecodeContext {
    AVCodecContext         *avctx;
    hb_audio_resample_t    *resampler;

    AudioChannelLayout **inputLayout;
    UInt32 *inputLayoutSize;
    AudioStreamBasicDescription *inputFormat;

    AudioChannelLayout **outputLayout;
    UInt32 *outputLayoutSize;
    AudioStreamBasicDescription *outputFormat;

    enum AVMatrixEncoding matrix_encoding;
    uint64_t              out_layout;

    int drop_samples;

    BOOL configured;
    BOOL outputConfigured;
};

typedef struct MP42DecodeContext MP42DecodeContext;

MP42_OBJC_DIRECT_MEMBERS
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

@property (nonatomic, readonly) MP42DecodeContext *context;

@end

@implementation MP42AudioDecoder

@synthesize outputUnit = _outputUnit;
@synthesize outputType = _outputType;

- (instancetype)initWithAudioFormat:(AudioStreamBasicDescription)asbd
                      channelLayout:(AudioChannelLayout *)channelLayout
                  channelLayoutSize:(UInt32)channelLayoutSize
                        mixdownType:(MP42AudioMixdown)mixdownType
                                drc:(float)drc
                     initialPadding:(UInt32)initialPadding
                        magicCookie:(nullable NSData *)magicCookie
                              error:(NSError * __autoreleasing *)error
{
    self = [super init];

    if (self) {
        _inputFormat = asbd;

        enum AVCodecID codecID = ASBDToCodecID(asbd);
        _codec = avcodec_find_decoder(codecID);

        if (!_codec) {
            return nil;
        }

        _avctx = avcodec_alloc_context3(_codec);

        if (!_avctx) {
            return nil;
        }

        if (_avctx && magicCookie) {

            _avctx->extradata = (uint8_t *)av_malloc(magicCookie.length + AV_INPUT_BUFFER_PADDING_SIZE);
            if (!_avctx->extradata) {
                NSLog(@"Could not av_malloc extradata");
                av_freep(&_avctx);
                return nil;
            }
            else if (magicCookie.length < UINT32_MAX) {
                _avctx->extradata_size = (uint32_t)magicCookie.length;
                memcpy(_avctx->extradata, magicCookie.bytes, magicCookie.length);
            }
            else
            {
                NSLog(@"Could not av_malloc extradata");
                av_freep(&_avctx);
                return nil;
            }
        }

        AVDictionary *av_opts = NULL;
        // Dynamic Range Compression
        if (drc >= 0.0f)
        {
            float drc_scale_max = 1.0f;
             // avcodec_open will fail if the value for any of the options is out of
             // range, so assume a conservative maximum of 1 and try to determine the
             // option's actual upper limit.
            if (_codec != NULL && _codec->priv_class != NULL)
            {
                const AVOption *opt;
                opt = av_opt_find2((void*)&_codec->priv_class, "drc_scale", NULL,
                                   AV_OPT_FLAG_DECODING_PARAM|AV_OPT_FLAG_AUDIO_PARAM,
                                   AV_OPT_SEARCH_FAKE_OBJ, NULL);
                if (opt != NULL)
                {
                    drc_scale_max = opt->max;
                }
            }
            if (drc > drc_scale_max)
            {
                drc = drc_scale_max;
            }

            char drc_scale[5]; // "?.??\n"
            snprintf(drc_scale, sizeof(drc_scale), "%.2f", drc);
            av_dict_set(&av_opts, "drc_scale", drc_scale, 0);
        }

        // Copy the input channels layout
        if (channelLayout && channelLayoutSize) {
            _inputLayoutSize = channelLayoutSize;
            _inputLayout = malloc(_inputLayoutSize);
            memcpy(_inputLayout, channelLayout, _inputLayoutSize);
        }

        if (asbd.mFormatID == kAudioFormatLinearPCM)
        {
            _avctx->channels = asbd.mChannelsPerFrame;
            _avctx->channel_layout = convert_layout_to_av(_inputLayout, _inputLayoutSize);
            _avctx->sample_rate = asbd.mSampleRate;
        }

        if (avcodec_open2(_avctx, _codec, &av_opts)) {
            NSLog(@"Error opening audio decoder");
            av_freep(&_avctx);
            av_dict_free(&av_opts);
            return nil;
        }

        av_dict_free(&av_opts);

        // Check the out channel count for the current downmix
        UInt32 channels = _inputFormat.mChannelsPerFrame;
        enum AVMatrixEncoding matrix_encoding = AV_MATRIX_ENCODING_NONE;
        if (channels > 1) {
            if (mixdownType == kMP42AudioMixdown_Mono) {
                channels = 1;
            }
        }
        if (channels > 2) {
            if (mixdownType == kMP42AudioMixdown_Stereo) {
                channels = 2;
            }
            else if (mixdownType == kMP42AudioMixdown_Dolby) {
                matrix_encoding = AV_MATRIX_ENCODING_DOLBY;
                channels = 2;
            }
            else if (mixdownType == kMP42AudioMixdown_DolbyPlII) {
                matrix_encoding = AV_MATRIX_ENCODING_DPLII;
                channels = 2;
            }
        }

        int drop_samples = 0;
        if (initialPadding > 0) {
            drop_samples = initialPadding;
        }

        // Creates the output audio stream basic description.
        // It will be used to configure the next audio unit in the chain.
        AudioStreamBasicDescription outputFormat;
        bzero(&outputFormat, sizeof(AudioStreamBasicDescription));
        outputFormat.mSampleRate = _inputFormat.mSampleRate;
        outputFormat.mFormatID = kAudioFormatLinearPCM ;
        outputFormat.mFormatFlags =  kLinearPCMFormatFlagIsFloat | kAudioFormatFlagsNativeEndian;
        outputFormat.mBytesPerPacket = 4 * channels;
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = outputFormat.mBytesPerPacket * outputFormat.mFramesPerPacket;
        outputFormat.mChannelsPerFrame = channels;
        outputFormat.mBitsPerChannel = 32;

        _outputFormat = outputFormat;

        // Context used by the decoder
        _context = malloc(sizeof(MP42DecodeContext));
        bzero(_context, (sizeof(MP42DecodeContext)));

        _context->avctx = _avctx;
        _context->inputFormat = &_inputFormat;
        _context->inputLayout = &_inputLayout;
        _context->inputLayoutSize = &_inputLayoutSize;
        _context->outputFormat = &_outputFormat;
        _context->outputLayout = &_outputLayout;
        _context->outputLayoutSize = &_outputLayoutSize;
        _context->matrix_encoding = matrix_encoding;
        _context->drop_samples = drop_samples;
        _context->configured = NO;

        // Init the FIFOs
        _inputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];
        _outputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:100];

        [self start];
    }

    return self;
}

- (void)dealloc
{
    if (_avctx) {
        free(_avctx->extradata);
        avcodec_close(_avctx);
        av_freep(&_avctx);
    }

    if (_context) {
        if (_context->resampler) {
            hb_audio_resample_free(_context->resampler);
        }
    }

    free(_inputLayout);
    free(_outputLayout);
    free(_context);
}

- (void)start
{
    _decoderThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMainRoutine) object:nil];
    [_decoderThread setName:@"FFmpeg Audio Decoder"];
    [_decoderThread start];
}

#pragma mark - Public methods

- (void)reconfigure
{
    return;
}

- (void)addSample:(MP42SampleBuffer *)sample
{
    [_inputSamplesBuffer enqueue:sample];
}

- (nullable MP42SampleBuffer *)copyEncodedSample
{
    return [_outputSamplesBuffer dequeue];
}

#pragma mark - Decode

static AVPacket * packetFromSampleBuffer(MP42SampleBuffer *sample)
{
    AVPacket *pkt = av_packet_alloc();
    pkt->data = sample->data;
    pkt->size = sample->size;
    pkt->dts = sample->decodeTimestamp;
    pkt->duration = sample->duration;

    return pkt;
}

static MP42SampleBuffer * sampleBufferFromFrame(uint8_t *output_data, int output_data_size)
{
    MP42SampleBuffer *sample = [[MP42SampleBuffer alloc] init];

    sample->data = output_data;
    sample->size = output_data_size;

    return sample;
}

static void convertChannelLayout(MP42DecodeContext *context)
{
    // Create the AudioChannelLayout from the FFmpeg channel layout
    UInt32 layout_size = sizeof(AudioChannelLayout) +
    sizeof(AudioChannelDescription) * context->outputFormat->mChannelsPerFrame;
    AudioChannelLayout *outputLayout = malloc(layout_size);
    bzero(outputLayout, layout_size);
    remap_layout(outputLayout, context->out_layout, context->outputFormat->mChannelsPerFrame);

    *context->outputLayoutSize = layout_size;
    *context->outputLayout = outputLayout;
}

static void configurePCMDescriptors(MP42DecodeContext *context, AVFrame *frame)
{
    AudioChannelLayout *inputLayout = *context->inputLayout;

    int nb_channels = AudioChannelLayoutTag_GetNumberOfChannels(inputLayout->mChannelLayoutTag);

    if (nb_channels == 1) {
        context->out_layout = AV_CH_LAYOUT_MONO;
    }
    else {
        context->out_layout = AV_CH_LAYOUT_STEREO;
    }

    // Set the output channel layout
    context->out_layout = AV_CH_LAYOUT_STEREO;
    if (context->outputFormat->mChannelsPerFrame < context->inputFormat->mChannelsPerFrame) {
        if (context->outputFormat->mChannelsPerFrame == 2) {
            context->out_layout = AV_CH_LAYOUT_STEREO;
        }
        else if (context->outputFormat->mChannelsPerFrame == 1) {
            context->out_layout = AV_CH_LAYOUT_MONO;
        }
    }
    else if (frame->channel_layout) {
        context->out_layout = convert_layout_to_av(*context->inputLayout, *context->inputLayoutSize);;
    }

    // Create the AudioChannelLayout from the FFmpeg channel layout
    convertChannelLayout(context);

    if (context->inputFormat->mSampleRate > 48000) {
        context->outputFormat->mSampleRate = 48000;
    }
}

static void configureDescriptors(MP42DecodeContext *context, AVFrame *frame)
{
    // Get real channels number and layout
    int nb_channels = av_get_channel_layout_nb_channels(frame->channel_layout);
    int sample_rate = frame->sample_rate;
    int container_sample_rate = context->inputFormat->mSampleRate;

    // Reset the channels per frame and sample rate
    if (context->inputFormat->mChannelsPerFrame == context->outputFormat->mChannelsPerFrame) {
        context->outputFormat->mChannelsPerFrame = nb_channels;
        context->inputFormat->mChannelsPerFrame = nb_channels;
    }
    context->inputFormat->mSampleRate = sample_rate;

    if (sample_rate > 48000) {
        sample_rate = 48000;
    }

    if (sample_rate < container_sample_rate) {
        context->outputFormat->mSampleRate = sample_rate;
    }
    context->outputFormat->mBytesPerPacket = 4 * context->outputFormat->mChannelsPerFrame;
    context->outputFormat->mBytesPerFrame = context->outputFormat->mBytesPerPacket * context->outputFormat->mFramesPerPacket;

    // Set the output channel layout
    context->out_layout = AV_CH_LAYOUT_STEREO;
    if (context->outputFormat->mChannelsPerFrame < context->inputFormat->mChannelsPerFrame) {
        if (context->outputFormat->mChannelsPerFrame == 2) {
            context->out_layout = AV_CH_LAYOUT_STEREO;
        }
        else if (context->outputFormat->mChannelsPerFrame == 1) {
            context->out_layout = AV_CH_LAYOUT_MONO;
        }
    }
    else if (frame->channel_layout) {
        context->out_layout = frame->channel_layout;
    }

    // Create the AudioChannelLayout from the FFmpeg channel layout
    convertChannelLayout(context);
}

static int resample(MP42DecodeContext *context, AVFrame *frame, uint8_t **output_data, int *output_data_size)
{
    int ret = 0;
    if (!context->configured) {
        if (context->inputFormat->mFormatID == kAudioFormatLinearPCM) {
            configurePCMDescriptors(context, frame);
        }
        else {
            configureDescriptors(context, frame);
        }
        // We want float interleaved.
        context->resampler = hb_audio_resample_init(AV_SAMPLE_FMT_FLT,
                                                    context->out_layout,
                                                    context->matrix_encoding,
                                                    context->outputFormat->mSampleRate,
                                                    0);
        context->configured = YES;
    }

    if (!context->resampler) {
        return 1;
    }

    AVFrameSideData *side_data;
    if ((side_data =
         av_frame_get_side_data(frame, AV_FRAME_DATA_DOWNMIX_INFO)) != NULL)
    {
        double          surround_mix_level, center_mix_level;
        AVDownmixInfo * downmix_info;

        downmix_info = (AVDownmixInfo *)side_data->data;
        if (context->matrix_encoding == AV_MATRIX_ENCODING_DOLBY ||
            context->matrix_encoding == AV_MATRIX_ENCODING_DPLII)
        {
            surround_mix_level = downmix_info->surround_mix_level_ltrt;
            center_mix_level   = downmix_info->center_mix_level_ltrt;
        }
        else
        {
            surround_mix_level = downmix_info->surround_mix_level;
            center_mix_level   = downmix_info->center_mix_level;
        }
        hb_audio_resample_set_mix_levels(context->resampler,
                                         surround_mix_level,
                                         center_mix_level,
                                         downmix_info->lfe_mix_level);
    }

    hb_audio_resample_set_channel_layout(context->resampler,
                                        frame->channel_layout);
    hb_audio_resample_set_sample_rate(context->resampler,
                                    frame->sample_rate);
    hb_audio_resample_set_sample_fmt(context->resampler,
                                    frame->format);

    if (hb_audio_resample_update(context->resampler)) {
        NSLog(@"decavcodec: hb_audio_resample_update() failed");
        return 1;
    }
    ret = hb_audio_resample(context->resampler,
                            (const uint8_t **)frame->extended_data, frame->nb_samples,
                            output_data, output_data_size);


    if (ret == 0 && context->drop_samples > 0)
    {
        // drop audio samples that are part of the encoder delay
        int channels = context->outputFormat->mChannelsPerFrame;
        int sample_size = channels * sizeof(float);
        int samples = *output_data_size / sample_size;
        if (samples <= context->drop_samples)
        {
            *output_data_size = 0;
            free(*output_data);
            context->drop_samples -= samples;
        }
        else
        {
            int size = context->drop_samples * sample_size;
            memmove(*output_data, *output_data + size, *output_data_size - size);
            *output_data_size -= size;
            context->drop_samples = 0;
        }
    }

    return ret;
}

static int send_packet(MP42DecodeContext *context, MP42SampleBuffer *inSample)
{
    int ret;

    AVPacket *pkt = packetFromSampleBuffer(inSample);
    ret = avcodec_send_packet(context->avctx, pkt);
    av_packet_free(&pkt);

    // In particular, we don't expect AVERROR(EAGAIN), because we read all
    // decoded frames with avcodec_receive_frame() until done.
    if (ret < 0) {
        printf("%s\n", av_err2str(ret));
        return ret == AVERROR_EOF ? 0 : ret;
    }
    return ret;
}

static int receive_frame(MP42DecodeContext *context, MP42SampleBuffer **outSample)
{
    int ret;

    AVFrame *frame = av_frame_alloc();
    ret = avcodec_receive_frame(context->avctx, frame);
    if (!ret) {
        uint8_t *output_data = NULL;
        int output_data_size = 0;
        ret = resample(context, frame, &output_data, &output_data_size);
        if (!ret && output_data_size) {
            *outSample = sampleBufferFromFrame(output_data, output_data_size);
        }
        else {
            *outSample = nil;
        }
    }
    av_frame_free(&frame);

    if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
        printf("%s\n", av_err2str(ret));
        return ret;
    }

    return ret;
}

static inline void enqueue(MP42AudioDecoder *self, MP42SampleBuffer *outSample)
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
                    enqueue(self, sampleBuffer);
                    return;
                }
                else {
                    send_packet(_context, sampleBuffer);
                    while (!receive_frame(_context, &outSample)) {
                        if (_context->outputConfigured == NO && outSample) {
                            [_outputUnit reconfigure];
                            _context->outputConfigured = YES;
                        }
                        enqueue(self, outSample);
                    }
                }
            }
        }
    }
}

@end
