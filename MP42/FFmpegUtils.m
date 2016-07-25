//
//  FFmpegUtils.c
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#include "FFmpegUtils.h"

#include <avcodec.h>
#include <pthread.h>
#include <AudioToolbox/AudioToolbox.h>

#define REGISTER_DECODER(x) { \
extern AVCodec ff_##x##_decoder; \
avcodec_register(&ff_##x##_decoder); }

static int ff_lockmgr_cb(void **mutex, enum AVLockOp op)
{
    switch (op) {
        case AV_LOCK_CREATE:
        {
            pthread_mutex_t *ff_mutext = calloc(1, sizeof(pthread_mutex_t));
            *mutex = ff_mutext;
            pthread_mutex_init(*mutex, NULL);
        } break;
        case AV_LOCK_DESTROY:
        {
            pthread_mutex_destroy(*mutex);
            free(*mutex);
        } break;
        case AV_LOCK_OBTAIN:
        {
            pthread_mutex_lock(*mutex);
        } break;
        case AV_LOCK_RELEASE:
        {
            pthread_mutex_unlock(*mutex);
        } break;
        default:
            break;
    }
    return 0;
}

void FFInitFFmpeg()
{
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        av_lockmgr_register(ff_lockmgr_cb);
        REGISTER_DECODER(dvdsub);
        REGISTER_DECODER(pgssub);
        REGISTER_DECODER(aac);
        REGISTER_DECODER(ac3);
        REGISTER_DECODER(eac3);
        REGISTER_DECODER(flac);
        REGISTER_DECODER(vorbis);
    });
}

// List of codec IDs we know about and that map to audio fourccs
static const struct {
    OSType mFormatID;
    enum AVCodecID codecID;
} kAudioCodecMap[] =
{
    { kAudioFormatMPEGLayer1, AV_CODEC_ID_MP1 },
    { kAudioFormatMPEGLayer2, AV_CODEC_ID_MP2 },
    { kAudioFormatMPEGLayer3, AV_CODEC_ID_MP3 },
    { 'ms\0\0' + 0x50, AV_CODEC_ID_MP2 },

    { kAudioFormatLinearPCM, AV_CODEC_ID_PCM_S16LE },
    { kAudioFormatLinearPCM, AV_CODEC_ID_PCM_U8 },
    { kAudioFormatALaw, AV_CODEC_ID_PCM_ALAW },
    { kAudioFormatULaw, AV_CODEC_ID_PCM_MULAW },
    { kAudioFormatMPEG4AAC, AV_CODEC_ID_AAC },
    { 'XiFL', AV_CODEC_ID_FLAC },
    { 'XiVs', AV_CODEC_ID_VORBIS },
    {0, AV_CODEC_ID_NONE }
};

enum AVCodecID FourCCToCodecID(OSType formatID)
{
    for (int i = 0; kAudioCodecMap[i].codecID != AV_CODEC_ID_NONE; i++) {
        if (kAudioCodecMap[i].mFormatID == formatID) {
            return kAudioCodecMap[i].codecID;
        }
    }
    return AV_CODEC_ID_NONE;
}

OSType OSTypeFCodecIDToFourCC(enum AVCodecID codecID)
{
    for (int i = 0; kAudioCodecMap[i].codecID != AV_CODEC_ID_NONE; i++) {
        if (kAudioCodecMap[i].codecID == codecID) {
            return kAudioCodecMap[i].mFormatID;
        }
    }
    return AV_CODEC_ID_NONE;
}

/*
 * Set sample format to the request format if supported by the codec.
 * The planar/packed variant of the requested format is the next best thing.
 */
void hb_ff_set_sample_fmt(AVCodecContext *context, AVCodec *codec,
                          enum AVSampleFormat request_sample_fmt)
{
    if (context != NULL && codec != NULL &&
        codec->type == AVMEDIA_TYPE_AUDIO && codec->sample_fmts != NULL)
    {
        const enum AVSampleFormat *fmt;
        enum AVSampleFormat next_best_fmt;

        next_best_fmt = (av_sample_fmt_is_planar(request_sample_fmt)  ?
                         av_get_packed_sample_fmt(request_sample_fmt) :
                         av_get_planar_sample_fmt(request_sample_fmt));

        context->request_sample_fmt = AV_SAMPLE_FMT_NONE;

        for (fmt = codec->sample_fmts; *fmt != AV_SAMPLE_FMT_NONE; fmt++)
        {
            if (*fmt == request_sample_fmt)
            {
                context->request_sample_fmt = request_sample_fmt;
                break;
            }
            else if (*fmt == next_best_fmt)
            {
                context->request_sample_fmt = next_best_fmt;
            }
        }

        /*
         * When encoding and AVCodec.sample_fmts exists, avcodec_open2()
         * will error out if AVCodecContext.sample_fmt isn't set.
         */
        if (context->request_sample_fmt == AV_SAMPLE_FMT_NONE)
        {
            context->request_sample_fmt = codec->sample_fmts[0];
        }
        context->sample_fmt = context->request_sample_fmt;
    }
}
