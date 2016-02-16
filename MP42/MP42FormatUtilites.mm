//
//  MP42FormatUtilites.c
//  MP42Foundation
//
//  Created by Damiano Galassi on 10/11/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

#include "MP42FormatUtilites.h"
#include "mbs.h"

#import <CoreAudio/CoreAudio.h>

#pragma mark - AC3

static const int ac3_layout_no_lfe[8] = {
    kAudioChannelLayoutTag_Stereo,
    kAudioChannelLayoutTag_Mono,
    kAudioChannelLayoutTag_Stereo,
    kAudioChannelLayoutTag_ITU_3_0,
    kAudioChannelLayoutTag_ITU_2_1,
    kAudioChannelLayoutTag_ITU_3_1,
    kAudioChannelLayoutTag_ITU_2_2,
    kAudioChannelLayoutTag_ITU_3_2};

static const int ac3_layout_lfe[8] = {
    kAudioChannelLayoutTag_DVD_4,
    kAudioChannelLayoutTag_AC3_1_0_1,
    kAudioChannelLayoutTag_DVD_4,
    kAudioChannelLayoutTag_DVD_10,
    kAudioChannelLayoutTag_DVD_5,
    kAudioChannelLayoutTag_DVD_11,
    kAudioChannelLayoutTag_DVD_6,
    kAudioChannelLayoutTag_ITU_3_2_1};

int readAC3Config(uint64_t acmod, uint64_t lfeon, UInt32 *channelsCount, UInt32 *channelLayoutTag)
{
    if(lfeon) {
        *channelLayoutTag = ac3_layout_lfe[acmod];
    }
    else {
        *channelLayoutTag = ac3_layout_no_lfe[acmod];
    }

    *channelsCount = AudioChannelLayoutTag_GetNumberOfChannels(*channelLayoutTag);

    return 1;
}

static const int eac3_layout_no_lfe[8] = {
    kAudioChannelLayoutTag_Stereo,
    kAudioChannelLayoutTag_Mono,
    kAudioChannelLayoutTag_Stereo,
    kAudioChannelLayoutTag_AC3_3_0,
    kAudioChannelLayoutTag_DVD_2,
    kAudioChannelLayoutTag_AC3_3_1,
    kAudioChannelLayoutTag_DVD_3,
    kAudioChannelLayoutTag_MPEG_5_0_C};

static const int eac3_layout_lfe[8] = {
    kAudioChannelLayoutTag_DVD_4,
    kAudioChannelLayoutTag_AC3_1_0_1,
    kAudioChannelLayoutTag_DVD_4,
    kAudioChannelLayoutTag_AC3_3_0_1,
    kAudioChannelLayoutTag_AC3_2_1_1,
    kAudioChannelLayoutTag_AC3_3_1_1,
    kAudioChannelLayoutTag_DVD_18,
    kAudioChannelLayoutTag_MPEG_5_1_C,
};

#pragma mark - EAC3

int readEAC3Config(const uint8_t *cookie, uint32_t cookieLen, UInt32 *channelsCount, UInt32 *channelLayoutTag)
{
    if (cookieLen < 5) {
        return 0;
    }

    CMemoryBitstream b;
    b.SetBytes((uint8_t *)cookie, cookieLen);

    b.GetBits(13); // data_rate
    b.GetBits(3);  // num_ind_sub

    // we support only one independent substream
    for (int i = 0; i < 1; i++)
    {
        //uint32_t fscod, bsid, asvc, bsmod;
        uint8_t acmod, lfeon;

        b.GetBits(2); // fscod
        b.GetBits(5); // bsid
        b.SkipBits(1); // reserved
        b.GetBits(1); // asvc
        b.GetBits(3); // bsmod

        acmod = b.GetBits(3);
        lfeon = b.GetBits(1);

        b.SkipBits(3); // reserved

        uint8_t num_dep_sub = 0;
        uint16_t chan_loc = 0;

        num_dep_sub = b.GetBits(4);

        if (num_dep_sub > 0 && cookieLen > 5) {
            chan_loc = b.GetBits(9);
        }

        if (acmod == 7 && lfeon && chan_loc != 0) {
            // TODO: complete the list
            if (chan_loc & 0x1) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_B;
            }
            else if (chan_loc & 0x2) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_A;
            }
            else if (chan_loc & 0x4) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_6_1_A;
            }
            else if (chan_loc & 0x8) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_6_1_B;
            }
            else if (chan_loc & 0x10) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_C;
            }
            else if (chan_loc & 0x20) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_D;
            }
            else if (chan_loc & 0x40) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_E;
            }
            else if (chan_loc & 0x80) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_6_1_C;
            }
            else if (chan_loc & 0x100) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_A;
            }
        }
        else {
            if (lfeon) {
                *channelLayoutTag = eac3_layout_lfe[acmod];
            }
            else {
                *channelLayoutTag = eac3_layout_no_lfe[acmod];
            }
        }

        *channelsCount = AudioChannelLayoutTag_GetNumberOfChannels(*channelLayoutTag);
    }

    return 1;
}

/**
 *  Part of code from ffmpeg ac3 parser.
 */

typedef enum {
    AAC_AC3_PARSE_ERROR_SYNC        = -0x1030c0a,
    AAC_AC3_PARSE_ERROR_BSID        = -0x2030c0a,
    AAC_AC3_PARSE_ERROR_SAMPLE_RATE = -0x3030c0a,
    AAC_AC3_PARSE_ERROR_FRAME_SIZE  = -0x4030c0a,
    AAC_AC3_PARSE_ERROR_FRAME_TYPE  = -0x5030c0a,
    AAC_AC3_PARSE_ERROR_CRC         = -0x6030c0a,
    AAC_AC3_PARSE_ERROR_CHANNEL_CFG = -0x7030c0a,
} AACAC3ParseError;

#define AC3_HEADER_SIZE 7

static const uint8_t eac3_blocks[4] = {
    1, 2, 3, 6
};

/**
 * Table for center mix levels
 * reference: Section 5.4.2.4 cmixlev
 */
static const uint8_t center_levels[4] = { 4, 5, 6, 5 };

/**
 * Table for surround mix levels
 * reference: Section 5.4.2.5 surmixlev
 */
static const uint8_t surround_levels[4] = { 4, 6, 7, 6 };

/** Channel mode (audio coding mode) */
typedef enum {
    AC3_CHMODE_DUALMONO = 0,
    AC3_CHMODE_MONO,
    AC3_CHMODE_STEREO,
    AC3_CHMODE_3F,
    AC3_CHMODE_2F1R,
    AC3_CHMODE_3F1R,
    AC3_CHMODE_2F2R,
    AC3_CHMODE_3F2R
} AC3ChannelMode;

/** Dolby Surround mode */
typedef enum AC3DolbySurroundMode {
    AC3_DSURMOD_NOTINDICATED = 0,
    AC3_DSURMOD_OFF,
    AC3_DSURMOD_ON,
    AC3_DSURMOD_RESERVED
} AC3DolbySurroundMode;

typedef enum {
    EAC3_FRAME_TYPE_INDEPENDENT = 0,
    EAC3_FRAME_TYPE_DEPENDENT,
    EAC3_FRAME_TYPE_AC3_CONVERT,
    EAC3_FRAME_TYPE_RESERVED
} EAC3FrameType;

typedef enum {
    AC3_CUSTOM_CHANNEL_MAP_LFE              = 0x00000001,
    AC3_CUSTOM_CHANNEL_MAP_LFE2             = 0x00000002,
    AC3_CUSTOM_CHANNEL_MAP_LTS_RTS_PAIR     = 0x00000004,
    AC3_CUSTOM_CHANNEL_MAP_VHC              = 0x00000008,
    AC3_CUSTOM_CHANNEL_MAP_VHL_VHR_PAIR     = 0x00000010,
    AC3_CUSTOM_CHANNEL_MAP_LW_RW_PAIR       = 0x00000020,
    AC3_CUSTOM_CHANNEL_MAP_LSD_RSD_PAIR     = 0x00000040,
    AC3_CUSTOM_CHANNEL_MAP_TS               = 0x00000080,
    AC3_CUSTOM_CHANNEL_MAP_CS               = 0x00000100,
    AC3_CUSTOM_CHANNEL_MAP_LRS_RRS_PAIR     = 0x00000200,
    AC3_CUSTOM_CHANNEL_MAP_LC_RC_PAIR       = 0x00000400,
    AC3_CUSTOM_CHANNEL_MAP_RIGHT_SURROUND   = 0x00000800,
    AC3_CUSTOM_CHANNEL_MAP_LEFT_SURROUND    = 0x00001000,
    AC3_CUSTOM_CHANNEL_MAP_RIGHT            = 0x00002000,
    AC3_CUSTOM_CHANNEL_MAP_CENTRE           = 0x00004000,
    AC3_CUSTOM_CHANNEL_MAP_LEFT             = 0x00008000,
} AC3ChanLoc;

typedef enum {
    DEC3_CUSTOM_CHANNEL_MAP_LC_RC_PAIR       = 0x00000001,
    DEC3_CUSTOM_CHANNEL_MAP_LRS_RRS_PAIR     = 0x00000002,
    DEC3_CUSTOM_CHANNEL_MAP_CS               = 0x00000004,
    DEC3_CUSTOM_CHANNEL_MAP_TS               = 0x00000008,
    DEC3_CUSTOM_CHANNEL_MAP_LSD_RSD_PAIR     = 0x00000010,
    DEC3_CUSTOM_CHANNEL_MAP_LW_RW_PAIR       = 0x00000020,
    DEC3_CUSTOM_CHANNEL_MAP_VHL_VHR_PAIR     = 0x00000040,
    DEC3_CUSTOM_CHANNEL_MAP_VHC              = 0x00000080,
    DEC3_CUSTOM_CHANNEL_MAP_LFE2             = 0x00000100,
} DEC3ChanLoc;

const uint16_t ff_ac3_dec3_chap_map[16][2] = {
    {AC3_CUSTOM_CHANNEL_MAP_LFE             , NULL},
    {AC3_CUSTOM_CHANNEL_MAP_LFE2            , DEC3_CUSTOM_CHANNEL_MAP_LFE2},
    {AC3_CUSTOM_CHANNEL_MAP_LTS_RTS_PAIR    , NULL},
    {AC3_CUSTOM_CHANNEL_MAP_VHC             , DEC3_CUSTOM_CHANNEL_MAP_VHC},
    {AC3_CUSTOM_CHANNEL_MAP_VHL_VHR_PAIR    , DEC3_CUSTOM_CHANNEL_MAP_VHL_VHR_PAIR},
    {AC3_CUSTOM_CHANNEL_MAP_LW_RW_PAIR      , DEC3_CUSTOM_CHANNEL_MAP_LW_RW_PAIR},
    {AC3_CUSTOM_CHANNEL_MAP_LSD_RSD_PAIR    , DEC3_CUSTOM_CHANNEL_MAP_LSD_RSD_PAIR},
    {AC3_CUSTOM_CHANNEL_MAP_TS              , DEC3_CUSTOM_CHANNEL_MAP_TS},
    {AC3_CUSTOM_CHANNEL_MAP_CS              , DEC3_CUSTOM_CHANNEL_MAP_CS},
    {AC3_CUSTOM_CHANNEL_MAP_LRS_RRS_PAIR    , DEC3_CUSTOM_CHANNEL_MAP_LRS_RRS_PAIR},
    {AC3_CUSTOM_CHANNEL_MAP_LC_RC_PAIR      , DEC3_CUSTOM_CHANNEL_MAP_LC_RC_PAIR},
    {AC3_CUSTOM_CHANNEL_MAP_RIGHT_SURROUND  , NULL},
    {AC3_CUSTOM_CHANNEL_MAP_LEFT_SURROUND   , NULL},
    {AC3_CUSTOM_CHANNEL_MAP_RIGHT           , NULL},
    {AC3_CUSTOM_CHANNEL_MAP_CENTRE          , NULL},
    {AC3_CUSTOM_CHANNEL_MAP_LEFT            , NULL},
};

uint16_t ac3_to_dec3_chan_map(uint16_t ac3_chan_loc) {
    uint16_t dec3_chan_loc = 0;

    for (int i = 0; i < 16; i++) {
        uint16_t chan_loc = ac3_chan_loc & (0x1 << i);
        for (int j = 0; j < 16; j++) {
            if (ff_ac3_dec3_chap_map[j][0] ==  chan_loc) {
                dec3_chan_loc |= ff_ac3_dec3_chap_map[j][1];
            }
        }
    }

    return dec3_chan_loc;
}

/* possible frequencies */
const uint16_t ff_ac3_sample_rate_tab[3] = { 48000, 44100, 32000 };

/* possible bitrates */
const uint16_t ff_ac3_bitrate_tab[19] = {
    32, 40, 48, 56, 64, 80, 96, 112, 128,
    160, 192, 224, 256, 320, 384, 448, 512, 576, 640
};

/**
 * Possible frame sizes.
 * from ATSC A/52 Table 5.18 Frame Size Code Table.
 */
const uint16_t ff_ac3_frame_size_tab[38][3] = {
    { 64,   69,   96   },
    { 64,   70,   96   },
    { 80,   87,   120  },
    { 80,   88,   120  },
    { 96,   104,  144  },
    { 96,   105,  144  },
    { 112,  121,  168  },
    { 112,  122,  168  },
    { 128,  139,  192  },
    { 128,  140,  192  },
    { 160,  174,  240  },
    { 160,  175,  240  },
    { 192,  208,  288  },
    { 192,  209,  288  },
    { 224,  243,  336  },
    { 224,  244,  336  },
    { 256,  278,  384  },
    { 256,  279,  384  },
    { 320,  348,  480  },
    { 320,  349,  480  },
    { 384,  417,  576  },
    { 384,  418,  576  },
    { 448,  487,  672  },
    { 448,  488,  672  },
    { 512,  557,  768  },
    { 512,  558,  768  },
    { 640,  696,  960  },
    { 640,  697,  960  },
    { 768,  835,  1152 },
    { 768,  836,  1152 },
    { 896,  975,  1344 },
    { 896,  976,  1344 },
    { 1024, 1114, 1536 },
    { 1024, 1115, 1536 },
    { 1152, 1253, 1728 },
    { 1152, 1254, 1728 },
    { 1280, 1393, 1920 },
    { 1280, 1394, 1920 },
};

/**
 * Map audio coding mode (acmod) to number of full-bandwidth channels.
 * from ATSC A/52 Table 5.8 Audio Coding Mode
 */
const uint8_t ff_ac3_channels_tab[8] = {
    2, 1, 2, 3, 3, 4, 4, 5
};

/**
 * @defgroup channel_masks Audio channel masks
 *
 * A channel layout is a 64-bits integer with a bit set for every channel.
 * The number of bits set must be equal to the number of channels.
 * The value 0 means that the channel layout is not known.
 * @note this data structure is not powerful enough to handle channels
 * combinations that have the same channel multiple times, such as
 * dual-mono.
 *
 * @{
 */
#define AV_CH_FRONT_LEFT             0x00000001
#define AV_CH_FRONT_RIGHT            0x00000002
#define AV_CH_FRONT_CENTER           0x00000004
#define AV_CH_LOW_FREQUENCY          0x00000008
#define AV_CH_BACK_LEFT              0x00000010
#define AV_CH_BACK_RIGHT             0x00000020
#define AV_CH_FRONT_LEFT_OF_CENTER   0x00000040
#define AV_CH_FRONT_RIGHT_OF_CENTER  0x00000080
#define AV_CH_BACK_CENTER            0x00000100
#define AV_CH_SIDE_LEFT              0x00000200
#define AV_CH_SIDE_RIGHT             0x00000400
#define AV_CH_TOP_CENTER             0x00000800
#define AV_CH_TOP_FRONT_LEFT         0x00001000
#define AV_CH_TOP_FRONT_CENTER       0x00002000
#define AV_CH_TOP_FRONT_RIGHT        0x00004000
#define AV_CH_TOP_BACK_LEFT          0x00008000
#define AV_CH_TOP_BACK_CENTER        0x00010000
#define AV_CH_TOP_BACK_RIGHT         0x00020000
#define AV_CH_STEREO_LEFT            0x20000000  ///< Stereo downmix.
#define AV_CH_STEREO_RIGHT           0x40000000  ///< See AV_CH_STEREO_LEFT.
#define AV_CH_WIDE_LEFT              0x0000000080000000ULL
#define AV_CH_WIDE_RIGHT             0x0000000100000000ULL
#define AV_CH_SURROUND_DIRECT_LEFT   0x0000000200000000ULL
#define AV_CH_SURROUND_DIRECT_RIGHT  0x0000000400000000ULL
#define AV_CH_LOW_FREQUENCY_2        0x0000000800000000ULL

/** Channel mask value used for AVCodecContext.request_channel_layout
 to indicate that the user requests the channel order of the decoder output
 to be the native codec channel order. */
#define AV_CH_LAYOUT_NATIVE          0x8000000000000000ULL

/**
 * @}
 * @defgroup channel_mask_c Audio channel layouts
 * @{
 * */
#define AV_CH_LAYOUT_MONO              (AV_CH_FRONT_CENTER)
#define AV_CH_LAYOUT_STEREO            (AV_CH_FRONT_LEFT|AV_CH_FRONT_RIGHT)
#define AV_CH_LAYOUT_2POINT1           (AV_CH_LAYOUT_STEREO|AV_CH_LOW_FREQUENCY)
#define AV_CH_LAYOUT_2_1               (AV_CH_LAYOUT_STEREO|AV_CH_BACK_CENTER)
#define AV_CH_LAYOUT_SURROUND          (AV_CH_LAYOUT_STEREO|AV_CH_FRONT_CENTER)
#define AV_CH_LAYOUT_3POINT1           (AV_CH_LAYOUT_SURROUND|AV_CH_LOW_FREQUENCY)
#define AV_CH_LAYOUT_4POINT0           (AV_CH_LAYOUT_SURROUND|AV_CH_BACK_CENTER)
#define AV_CH_LAYOUT_4POINT1           (AV_CH_LAYOUT_4POINT0|AV_CH_LOW_FREQUENCY)
#define AV_CH_LAYOUT_2_2               (AV_CH_LAYOUT_STEREO|AV_CH_SIDE_LEFT|AV_CH_SIDE_RIGHT)
#define AV_CH_LAYOUT_QUAD              (AV_CH_LAYOUT_STEREO|AV_CH_BACK_LEFT|AV_CH_BACK_RIGHT)
#define AV_CH_LAYOUT_5POINT0           (AV_CH_LAYOUT_SURROUND|AV_CH_SIDE_LEFT|AV_CH_SIDE_RIGHT)
#define AV_CH_LAYOUT_5POINT1           (AV_CH_LAYOUT_5POINT0|AV_CH_LOW_FREQUENCY)
#define AV_CH_LAYOUT_5POINT0_BACK      (AV_CH_LAYOUT_SURROUND|AV_CH_BACK_LEFT|AV_CH_BACK_RIGHT)
#define AV_CH_LAYOUT_5POINT1_BACK      (AV_CH_LAYOUT_5POINT0_BACK|AV_CH_LOW_FREQUENCY)
#define AV_CH_LAYOUT_6POINT0           (AV_CH_LAYOUT_5POINT0|AV_CH_BACK_CENTER)
#define AV_CH_LAYOUT_6POINT0_FRONT     (AV_CH_LAYOUT_2_2|AV_CH_FRONT_LEFT_OF_CENTER|AV_CH_FRONT_RIGHT_OF_CENTER)
#define AV_CH_LAYOUT_HEXAGONAL         (AV_CH_LAYOUT_5POINT0_BACK|AV_CH_BACK_CENTER)
#define AV_CH_LAYOUT_6POINT1           (AV_CH_LAYOUT_5POINT1|AV_CH_BACK_CENTER)
#define AV_CH_LAYOUT_6POINT1_BACK      (AV_CH_LAYOUT_5POINT1_BACK|AV_CH_BACK_CENTER)
#define AV_CH_LAYOUT_6POINT1_FRONT     (AV_CH_LAYOUT_6POINT0_FRONT|AV_CH_LOW_FREQUENCY)
#define AV_CH_LAYOUT_7POINT0           (AV_CH_LAYOUT_5POINT0|AV_CH_BACK_LEFT|AV_CH_BACK_RIGHT)
#define AV_CH_LAYOUT_7POINT0_FRONT     (AV_CH_LAYOUT_5POINT0|AV_CH_FRONT_LEFT_OF_CENTER|AV_CH_FRONT_RIGHT_OF_CENTER)
#define AV_CH_LAYOUT_7POINT1           (AV_CH_LAYOUT_5POINT1|AV_CH_BACK_LEFT|AV_CH_BACK_RIGHT)
#define AV_CH_LAYOUT_7POINT1_WIDE      (AV_CH_LAYOUT_5POINT1|AV_CH_FRONT_LEFT_OF_CENTER|AV_CH_FRONT_RIGHT_OF_CENTER)
#define AV_CH_LAYOUT_7POINT1_WIDE_BACK (AV_CH_LAYOUT_5POINT1_BACK|AV_CH_FRONT_LEFT_OF_CENTER|AV_CH_FRONT_RIGHT_OF_CENTER)
#define AV_CH_LAYOUT_OCTAGONAL         (AV_CH_LAYOUT_5POINT0|AV_CH_BACK_LEFT|AV_CH_BACK_CENTER|AV_CH_BACK_RIGHT)
#define AV_CH_LAYOUT_HEXADECAGONAL     (AV_CH_LAYOUT_OCTAGONAL|AV_CH_WIDE_LEFT|AV_CH_WIDE_RIGHT|AV_CH_TOP_BACK_LEFT|AV_CH_TOP_BACK_RIGHT|AV_CH_TOP_BACK_CENTER|AV_CH_TOP_FRONT_CENTER|AV_CH_TOP_FRONT_LEFT|AV_CH_TOP_FRONT_RIGHT)
#define AV_CH_LAYOUT_STEREO_DOWNMIX    (AV_CH_STEREO_LEFT|AV_CH_STEREO_RIGHT)


/**
 * Map audio coding mode (acmod) to channel layout mask.
 */
const uint16_t avpriv_ac3_channel_layout_tab[8] = {
    AV_CH_LAYOUT_STEREO,
    AV_CH_LAYOUT_MONO,
    AV_CH_LAYOUT_STEREO,
    AV_CH_LAYOUT_SURROUND,
    AV_CH_LAYOUT_2_1,
    AV_CH_LAYOUT_4POINT0,
    AV_CH_LAYOUT_2_2,
    AV_CH_LAYOUT_5POINT0
};

/**
 * @struct AC3HeaderInfo
 * Coded AC-3 header values up to the lfeon element, plus derived values.
 */
typedef struct AC3HeaderInfo {
    /** @name Coded elements
     * @{
     */
    uint16_t sync_word;
    uint16_t crc1;
    uint8_t sr_code;
    uint8_t bitstream_id;
    uint8_t bitstream_mode;
    uint8_t channel_mode;
    uint8_t lfe_on;
    uint8_t frame_type;
    int substreamid;                        ///< substream identification
    int center_mix_level;                   ///< Center mix level index
    int surround_mix_level;                 ///< Surround mix level index
    uint16_t channel_map;
    int num_blocks;                         ///< number of audio blocks
    int dolby_surround_mode;
    /** @} */

    /** @name Derived values
     * @{
     */
    uint8_t sr_shift;
    uint16_t sample_rate;
    uint32_t bit_rate;
    uint8_t channels;
    uint16_t frame_size;
    uint64_t channel_layout;
    /** @} */
} AC3HeaderInfo;

static int ac3_parse_header(CMemoryBitstream &b, AC3HeaderInfo **phdr)
{
    int frame_size_code;
    AC3HeaderInfo *hdr;

    if (!*phdr) {
        *phdr = (AC3HeaderInfo *)malloc(sizeof(AC3HeaderInfo));
    }
    if (!*phdr) {
        return 1;
    }
    hdr = *phdr;

    memset(hdr, 0, sizeof(*hdr));

    hdr->sync_word = b.GetBits(16);
    if (hdr->sync_word != 0x0B77) {
        return AAC_AC3_PARSE_ERROR_SYNC;
    }

    /* read ahead to bsid to distinguish between AC-3 and E-AC-3 */
    b.SkipBits(24);
    hdr->bitstream_id = b.GetBits(5);
    b.SetBitPosition(b.GetBitPosition() - 29);
    if (hdr->bitstream_id > 16) {
        return AAC_AC3_PARSE_ERROR_BSID;
    }

    hdr->num_blocks = 6;

    /* set default mix levels */
    hdr->center_mix_level   = 5;  // -4.5dB
    hdr->surround_mix_level = 6;  // -6.0dB

    /* set default dolby surround mode */
    hdr->dolby_surround_mode = AC3_DSURMOD_NOTINDICATED;

    if (hdr->bitstream_id <= 10) {
        /* Normal AC-3 */
        hdr->crc1 = b.GetBits(16);
        hdr->sr_code = b.GetBits(2);
        if (hdr->sr_code == 3) {
            return AAC_AC3_PARSE_ERROR_SAMPLE_RATE;
        }

        frame_size_code = b.GetBits(6);
        if (frame_size_code > 37) {
            return AAC_AC3_PARSE_ERROR_FRAME_SIZE;
        }

        b.SkipBits(5); // skip bsid, already got it

        hdr->bitstream_mode = b.GetBits(3);
        hdr->channel_mode = b.GetBits(3);

        if (hdr->channel_mode == AC3_CHMODE_STEREO) {
            hdr->dolby_surround_mode = b.GetBits(2);
        } else {
            if((hdr->channel_mode & 1) && hdr->channel_mode != AC3_CHMODE_MONO) {
                hdr->  center_mix_level =   center_levels[b.GetBits(2)];
            }
            if(hdr->channel_mode & 4) {
                hdr->surround_mix_level = surround_levels[b.GetBits(2)];
            }
        }
        hdr->lfe_on = b.GetBits(1);

        hdr->sr_shift = MAX(hdr->bitstream_id, 8) - 8;
        hdr->sample_rate = ff_ac3_sample_rate_tab[hdr->sr_code] >> hdr->sr_shift;
        hdr->bit_rate = (ff_ac3_bitrate_tab[frame_size_code>>1] * 1000) >> hdr->sr_shift;
        hdr->channels = ff_ac3_channels_tab[hdr->channel_mode] + hdr->lfe_on;
        hdr->frame_size = ff_ac3_frame_size_tab[frame_size_code][hdr->sr_code] * 2;
        hdr->frame_type = EAC3_FRAME_TYPE_AC3_CONVERT; //EAC3_FRAME_TYPE_INDEPENDENT;
        hdr->substreamid = 0;
    }
    else {
        /* Enhanced AC-3 */
        hdr->crc1 = 0;
        hdr->frame_type = b.GetBits(2);
        if (hdr->frame_type == EAC3_FRAME_TYPE_RESERVED) {
            return AAC_AC3_PARSE_ERROR_FRAME_TYPE;
        }

        hdr->substreamid = b.GetBits(3);

        hdr->frame_size = (b.GetBits(11) + 1) << 1;
        if (hdr->frame_size < AC3_HEADER_SIZE) {
            return AAC_AC3_PARSE_ERROR_FRAME_SIZE;
        }

        hdr->sr_code = b.GetBits(2);
        if (hdr->sr_code == 3) {
            int sr_code2 = b.GetBits(2);
            if(sr_code2 == 3) {
                return AAC_AC3_PARSE_ERROR_SAMPLE_RATE;
            }
            hdr->sample_rate = ff_ac3_sample_rate_tab[sr_code2] / 2;
            hdr->sr_shift = 1;
        } else {
            hdr->num_blocks = eac3_blocks[b.GetBits(2)];
            hdr->sample_rate = ff_ac3_sample_rate_tab[hdr->sr_code];
            hdr->sr_shift = 0;
        }

        hdr->channel_mode = b.GetBits(3);
        hdr->lfe_on = b.GetBits(1);

        hdr->bit_rate = 8LL * hdr->frame_size * hdr->sample_rate /
        (hdr->num_blocks * 256);
        hdr->channels = ff_ac3_channels_tab[hdr->channel_mode] + hdr->lfe_on;
    }
    hdr->channel_layout = avpriv_ac3_channel_layout_tab[hdr->channel_mode];
    if (hdr->lfe_on) {
        hdr->channel_layout |= AV_CH_LOW_FREQUENCY;
    }
    
    return 0;
}

struct eac3_info {
    uint8_t *frame;
    uint32_t size;

    uint8_t ec3_done;
    uint8_t num_blocks;

    /* Layout of the EC3SpecificBox */
    /* maximum bitrate */
    uint16_t data_rate;
    /* number of independent substreams */
    uint8_t  num_ind_sub;
    struct {
        /* sample rate code (see ff_ac3_sample_rate_tab) 2 bits */
        uint8_t fscod;
        /* bit stream identification 5 bits */
        uint8_t bsid;
        /* one bit reserved */
        /* audio service mixing (not supported yet) 1 bit */
        /* bit stream mode 3 bits */
        uint8_t bsmod;
        /* audio coding mode 3 bits */
        uint8_t acmod;
        /* sub woofer on 1 bit */
        uint8_t lfeon;
        /* 3 bits reserved */
        /* number of dependent substreams associated with this substream 4 bits */
        uint8_t num_dep_sub;
        /* channel locations of the dependent substream(s), if any, 9 bits */
        uint16_t chan_loc;
        /* if there is no dependent substream, then one bit reserved instead */
    } substream[1]; /* TODO: support 8 independent substreams */
};


int analyze_EAC3(void **context ,uint8_t *frame, uint32_t size)
{
    CMemoryBitstream b;
    AC3HeaderInfo *hdr = NULL;
    struct eac3_info *info = NULL;
    int num_blocks;

    if (!*context) {
        *context = (struct eac3_info *)malloc(sizeof(*info));
        memset(*context, 0, sizeof(*info));
    }
    if (!*context) {
        return 1;
    }
    info = (struct eac3_info *)*context;

    b.SetBytes(frame, size);
    if (ac3_parse_header(b, &hdr) < 0) {
        return -1;
    }

    info->data_rate = MAX(info->data_rate, hdr->bit_rate / 1000);
    num_blocks = hdr->num_blocks;

    /* fill the info needed for the "dec3" atom */
    if (!info->ec3_done) {
        /* AC-3 substream must be the first one */
        if (hdr->bitstream_id <= 10 && hdr->substreamid != 0) {
            return -1;
        }

        /* this should always be the case, given that our AC-3 parser
         * concatenates dependent frames to their independent parent */
        if (hdr->frame_type == EAC3_FRAME_TYPE_INDEPENDENT) {
            /* substream ids must be incremental */
            if (hdr->substreamid > info->num_ind_sub + 1) {
                return -1;
            }

            if (hdr->substreamid == info->num_ind_sub + 1) {
                //info->num_ind_sub++;
                return -1;
            } else if (hdr->substreamid < info->num_ind_sub ||
                       (hdr->substreamid == 0 && info->substream[0].bsid)) {
                info->ec3_done = 1;
                goto concatenate;
            }
        }

        info->substream[hdr->substreamid].fscod = hdr->sr_code;
        info->substream[hdr->substreamid].bsid  = hdr->bitstream_id;
        info->substream[hdr->substreamid].bsmod = hdr->bitstream_mode;
        info->substream[hdr->substreamid].acmod = hdr->channel_mode;
        info->substream[hdr->substreamid].lfeon = hdr->lfe_on;

        /* Parse dependent substream(s), if any */
        if (size != hdr->frame_size) {
            int cumul_size = hdr->frame_size;
            int parent = hdr->substreamid;

            while (cumul_size != size) {
                int i;
                CMemoryBitstream gbc;
                gbc.SetBytes(frame + cumul_size, (size - cumul_size) * 8);

                if (ac3_parse_header(gbc, &hdr) < 0) {
                    return -1;
                }
                if (hdr->frame_type != EAC3_FRAME_TYPE_DEPENDENT) {
                    return -1;
                }
                cumul_size += hdr->frame_size;
                info->substream[parent].num_dep_sub++;

                /* header is parsed up to lfeon, but custom channel map may be needed */
                /* skip bsid */
                gbc.SkipBits(5);

                /* skip volume control params */
                for (i = 0; i < (hdr->channel_mode ? 1 : 2); i++) {
                    gbc.SkipBits(5); // skip dialog normalization
                    if (gbc.GetBits(1)) {
                        gbc.SkipBits(8); // skip compression gain word
                    }
                }
                /* get the dependent stream channel map, if exists */
                if (gbc.GetBits(1)) {
                    uint16_t value = gbc.GetBits(16);
                    info->substream[parent].chan_loc = ac3_to_dec3_chan_map(value);
                }
                else {
                    info->substream[parent].chan_loc |= hdr->channel_mode;
                }
            }
        }
    }

concatenate:

    if (!info->num_blocks && num_blocks == 6) {
        return size;
    }
    else if (info->num_blocks + num_blocks > 6) {
        return -2;
    }

    /*if (!info->num_blocks) {
        int ret;
        if ((ret = av_copy_packet(&info->pkt, pkt)) < 0)
            return ret;
        info->num_blocks = num_blocks;
        return 0;
    } else {
        int ret;
        if ((ret = av_grow_packet(&info->pkt, pkt->size)) < 0)
            return ret;
        memcpy(info->pkt.data + info->pkt.size - pkt->size, pkt->data, pkt->size);
        info->num_blocks += num_blocks;
        info->pkt.duration += pkt->duration;
        if ((ret = av_copy_packet_side_data(&info->pkt, pkt)) < 0)
            return ret;
        if (info->num_blocks != 6)
            return 0;
        av_packet_unref(pkt);
        if ((ret = av_copy_packet(pkt, &info->pkt)) < 0)
            return ret;
        av_packet_unref(&info->pkt);
        info->num_blocks = 0;
    }*/
    
    return 0;
}

CFDataRef createCookie_EAC3(void *context)
{
    struct eac3_info *info = (struct eac3_info *) context;

    // Recreate the dec3 atom
    CMemoryBitstream cookie;
    cookie.AllocBytes(32);
    cookie.PutBits(info->data_rate, 13); // data_rate
    cookie.PutBits(info->num_ind_sub, 3);  // num_ind_sub

    for (int i = 0; i <= info->num_ind_sub; i++) {
        cookie.PutBits(info->substream[i].fscod, 2);
        cookie.PutBits(info->substream[i].bsid, 5);

        cookie.PutBits(0, 1); // reserved
        cookie.PutBits(0, 1); // asvc

        cookie.PutBits(info->substream[i].bsmod, 3);
        cookie.PutBits(info->substream[i].acmod, 3);
        cookie.PutBits(info->substream[i].lfeon, 1);

        cookie.PutBits(0, 3); // reserved

        cookie.PutBits(info->substream[i].num_dep_sub, 4); // num_dep_sub

        if (!info->substream[i].num_dep_sub) {
            cookie.PutBits(0, 1); // reserved
        }
        else {
            cookie.PutBits(info->substream[i].chan_loc, 9); // chan_loc
        }
    }

    return CFDataCreate(kCFAllocatorDefault, cookie.GetBuffer(), cookie.GetBitPosition() / 8);
}
