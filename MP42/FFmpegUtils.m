//
//  FFmpegUtils.c
//  MP42Foundation
//
//  Created by Damiano Galassi on 23/07/2016.
//
//  Useful utilites from FFmpeg source code.
//

#include "FFmpegUtils.h"

#include <avcodec.h>
#include <AudioToolbox/AudioToolbox.h>

// List of codec IDs we know about and that map to audio fourccs
static const struct {
    OSType mFormatID;
    enum AVCodecID codecID;
} kAudioCodecMap[] =
{
    { kAudioFormatMPEG4AAC, AV_CODEC_ID_AAC },
    { kAudioFormatMPEG4AAC_HE, AV_CODEC_ID_AAC },
    { kAudioFormatMPEGLayer1, AV_CODEC_ID_MP1 },
    { kAudioFormatMPEGLayer2, AV_CODEC_ID_MP2 },
    { kAudioFormatMPEGLayer3, AV_CODEC_ID_MP3 },
    { kAudioFormatAC3, AV_CODEC_ID_AC3 },
    { kAudioFormatEnhancedAC3, AV_CODEC_ID_EAC3 },
    { kAudioFormatFLAC, AV_CODEC_ID_FLAC },
    { 'fLaC', AV_CODEC_ID_FLAC },
    { 'XiVs', AV_CODEC_ID_VORBIS },
    { kAudioFormatOpus, AV_CODEC_ID_OPUS },
    { kAudioFormatAppleLossless, AV_CODEC_ID_ALAC },
    { 'DTS ', AV_CODEC_ID_DTS },
    { 'mlpa', AV_CODEC_ID_TRUEHD },
    { 'trhd', AV_CODEC_ID_TRUEHD },
    { 'mlp ', AV_CODEC_ID_MLP },
    { kAudioFormatALaw, AV_CODEC_ID_PCM_ALAW },
    { kAudioFormatULaw, AV_CODEC_ID_PCM_MULAW },
    {0, AV_CODEC_ID_NONE }
};

// List of codec IDs we know about and that map to audio fourccs
static const struct {
    AudioFormatFlags mFormatFlags;
    UInt32           mBitsPerChannel;
    enum AVCodecID   codecID;
} kAudioPCMCodecMap[] =
{
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,                                    16, AV_CODEC_ID_PCM_S16LE },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,      16, AV_CODEC_ID_PCM_S16BE },
    { kLinearPCMFormatFlagIsPacked,                                                                          16, AV_CODEC_ID_PCM_U16LE },
    { kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,                                            16, AV_CODEC_ID_PCM_U16BE },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,      8,  AV_CODEC_ID_PCM_S8 },
    { kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,                                            8,  AV_CODEC_ID_PCM_U8 },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,                                    32, AV_CODEC_ID_PCM_S32LE },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,      32, AV_CODEC_ID_PCM_S32BE },
    { kLinearPCMFormatFlagIsPacked,                                                                          32, AV_CODEC_ID_PCM_U32LE },
    { kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,                                            32, AV_CODEC_ID_PCM_U32BE },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,                                    24, AV_CODEC_ID_PCM_S24LE },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,      24, AV_CODEC_ID_PCM_S24BE },
    { kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved, 16, AV_CODEC_ID_PCM_S16LE_PLANAR },
    { kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,              32, AV_CODEC_ID_PCM_F32BE },
    { kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,                                            32, AV_CODEC_ID_PCM_F32LE },
    { kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,              64, AV_CODEC_ID_PCM_F64BE },
    { kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,                                            64, AV_CODEC_ID_PCM_F64LE },
    {0, 0, AV_CODEC_ID_NONE }
};

enum AVCodecID ASBDToCodecID(AudioStreamBasicDescription asbd)
{
    if (asbd.mFormatID != kAudioFormatLinearPCM) {
        for (int i = 0; kAudioCodecMap[i].codecID != AV_CODEC_ID_NONE; i++) {
            if (kAudioCodecMap[i].mFormatID == asbd.mFormatID) {
                return kAudioCodecMap[i].codecID;
            }
        }
    }
    else {
        for (int i = 0; kAudioPCMCodecMap[i].codecID != AV_CODEC_ID_NONE; i++) {
            if (kAudioPCMCodecMap[i].mFormatFlags == asbd.mFormatFlags &&
                kAudioPCMCodecMap[i].mBitsPerChannel == asbd.mBitsPerChannel) {
                return kAudioPCMCodecMap[i].codecID;
            }
        }
    }
    return AV_CODEC_ID_NONE;
}

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

static av_cold int get_channel_label(int channel)
{
    uint64_t map = 1 << channel;
    if (map <= AV_CH_LOW_FREQUENCY)
        return channel + 1;
    else if (map <= AV_CH_BACK_RIGHT)
        return channel + 29;
    else if (map <= AV_CH_BACK_CENTER)
        return channel - 1;
    else if (map <= AV_CH_SIDE_RIGHT)
        return channel - 4;
    else if (map <= AV_CH_TOP_BACK_RIGHT)
        return channel + 1;
    else if (map <= AV_CH_STEREO_RIGHT)
        return -1;
    else if (map <= AV_CH_WIDE_RIGHT)
        return channel + 4;
    else if (map <= AV_CH_SURROUND_DIRECT_RIGHT)
        return channel - 23;
    else if (map == AV_CH_LOW_FREQUENCY_2)
        return kAudioChannelLabel_LFE2;
    else
        return -1;
}

int remap_layout(AudioChannelLayout *layout, uint64_t in_layout, int count)
{
    int i;
    int c = 0;
    layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
    layout->mNumberChannelDescriptions = count;
    for (i = 0; i < count; i++) {
        int label;
        while (!(in_layout & (1 << c)) && c < 64)
            c++;
        if (c == 64)
            return AVERROR(EINVAL); // This should never happen
        label = get_channel_label(c);
        layout->mChannelDescriptions[i].mChannelLabel = label;
        if (label < 0)
            return AVERROR(EINVAL);
        c++;
    }
    return 0;
}

#ifndef ff_ctzll
#define ff_ctzll ff_ctzll_c
/* We use the De-Bruijn method outlined in:
 * http://supertech.csail.mit.edu/papers/debruijn.pdf. */
static av_always_inline av_const int ff_ctzll_c(long long v)
{
    static const uint8_t debruijn_ctz64[64] = {
        0, 1, 2, 53, 3, 7, 54, 27, 4, 38, 41, 8, 34, 55, 48, 28,
        62, 5, 39, 46, 44, 42, 22, 9, 24, 35, 59, 56, 49, 18, 29, 11,
        63, 52, 6, 26, 37, 40, 33, 47, 61, 45, 43, 21, 23, 58, 17, 10,
        51, 25, 36, 32, 60, 20, 57, 16, 50, 31, 19, 15, 30, 14, 13, 12
    };
    return debruijn_ctz64[(uint64_t)((v & -v) * 0x022FDD63CC95386DU) >> 58];
}
#endif


static int get_channel_id(AudioChannelLabel label)
{
    if (label == 0)
        return -1;
    else if (label <= kAudioChannelLabel_LFEScreen)
        return label - 1;
    else if (label <= kAudioChannelLabel_RightSurround)
        return label + 4;
    else if (label <= kAudioChannelLabel_CenterSurround)
        return label + 1;
    else if (label <= kAudioChannelLabel_RightSurroundDirect)
        return label + 23;
    else if (label <= kAudioChannelLabel_TopBackRight)
        return label - 1;
    else if (label < kAudioChannelLabel_RearSurroundLeft)
        return -1;
    else if (label <= kAudioChannelLabel_RearSurroundRight)
        return label - 29;
    else if (label <= kAudioChannelLabel_RightWide)
        return label - 4;
    else if (label == kAudioChannelLabel_LFE2)
        return ff_ctzll(AV_CH_LOW_FREQUENCY_2);
    else if (label == kAudioChannelLabel_Mono)
        return ff_ctzll(AV_CH_FRONT_CENTER);
    else
        return -1;
}

/*static int compare_channel_descriptions(const void* a, const void* b)
{
    const AudioChannelDescription* da = a;
    const AudioChannelDescription* db = b;
    return get_channel_id(da->mChannelLabel) - get_channel_id(db->mChannelLabel);
}*/

static AudioChannelLayout *convert_layout(AudioChannelLayout *layout, UInt32* size)
{
    AudioChannelLayoutTag tag = layout->mChannelLayoutTag;
    AudioChannelLayout *new_layout;
    if (tag == kAudioChannelLayoutTag_UseChannelDescriptions)
        return layout;
    else if (tag == kAudioChannelLayoutTag_UseChannelBitmap)
        AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForBitmap,
                                   sizeof(UInt32), &layout->mChannelBitmap, size);
    else
        AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag,
                                   sizeof(AudioChannelLayoutTag), &tag, size);
    new_layout = av_malloc(*size);
    if (!new_layout) {
        av_free(layout);
        return NULL;
    }
    if (tag == kAudioChannelLayoutTag_UseChannelBitmap)
        AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForBitmap,
                               sizeof(UInt32), &layout->mChannelBitmap, size, new_layout);
    else
        AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag,
                               sizeof(AudioChannelLayoutTag), &tag, size, new_layout);
    new_layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
    av_free(layout);
    return new_layout;
}

uint64_t convert_layout_to_av(AudioChannelLayout *layout, UInt32 layoutSize)
{
    AudioChannelLayout *layout_copy = av_malloc(layoutSize);
    memcpy(layout_copy, layout, layoutSize);
    uint64_t layout_mask = 0;
    UInt32 i;
    if (!layout_copy)
        return AVERROR(ENOMEM);
    if (!(layout_copy = convert_layout(layout_copy, &layoutSize)))
        return AVERROR(ENOMEM);
    for (i = 0; i < layout_copy->mNumberChannelDescriptions; i++) {
        int channel_id = get_channel_id(layout_copy->mChannelDescriptions[i].mChannelLabel);
        if (channel_id < 0 || channel_id > 64)
            goto done;
        if (layout_mask & (1UL << channel_id))
            goto done;
        layout_mask |= 1UL << channel_id;
        layout_copy->mChannelDescriptions[i].mChannelFlags = i; // Abusing flags as index
    }
done:
    free(layout_copy);
    return layout_mask;
}

uint64_t channel_layout_for_channels(AVCodec *codec, int channels)
{
    const uint64_t *p;
    uint64_t best_ch_layout = 0;
    int best_nb_channells   = 0;
    
    if (!codec->channel_layouts)
        return AV_CH_LAYOUT_STEREO;
    
    p = codec->channel_layouts;
    while (*p) {
        int nb_channels = av_get_channel_layout_nb_channels(*p);
        
        if (nb_channels == channels) return *p;
        
        if (nb_channels > best_nb_channells) {
            best_ch_layout    = *p;
            best_nb_channells = nb_channels;
        }
        p++;
    }
    return best_ch_layout;
}
