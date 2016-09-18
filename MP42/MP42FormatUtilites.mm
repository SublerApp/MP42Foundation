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

UInt32 getDefaultChannelLayout(UInt32 channelsCount)
{
    // Guess a channel layout
    switch (channelsCount) {
        case 1:
            return kAudioChannelLayoutTag_Mono;
        case 2:
            return kAudioChannelLayoutTag_Stereo;
        case 3:
            return kAudioChannelLayoutTag_MPEG_3_0_A;
        case 4:
            return kAudioChannelLayoutTag_MPEG_4_0_A;
        case 5:
            return kAudioChannelLayoutTag_MPEG_5_0_A;
        case 6:
            return kAudioChannelLayoutTag_MPEG_5_1_A;
        case 7:
            return kAudioChannelLayoutTag_MPEG_6_1_A;
        case 8:
            return kAudioChannelLayoutTag_MPEG_7_1_A;

        default:
            return kAudioChannelLayoutTag_Mono;
    }
}

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
            free(hdr);
            return -1;
        }

        /* this should always be the case, given that our AC-3 parser
         * concatenates dependent frames to their independent parent */
        if (hdr->frame_type == EAC3_FRAME_TYPE_INDEPENDENT) {
            /* substream ids must be incremental */
            if (hdr->substreamid > info->num_ind_sub + 1) {
                free(hdr);
                return -1;
            }

            if (hdr->substreamid == info->num_ind_sub + 1) {
                //info->num_ind_sub++;
                free(hdr);
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

    free(hdr);

    if (!info->num_blocks && num_blocks == 6) {
        return size;
    }
    else if (info->num_blocks + num_blocks > 6) {
        return -2;
    }

    if (!info->num_blocks) {
        // Copy the frame
        info->frame = (uint8_t *)malloc(size);
        if (info->frame == NULL) {
            return -2;
        }
        memcpy(info->frame, frame, size);
        info->size = size;
        info->num_blocks = num_blocks;
        return 0;
    } else {
        info->frame = (uint8_t *)realloc(info->frame, info->size + size);
        if (info->frame == NULL) {
            return -2;
        }
        memcpy(info->frame + info->size, frame, size);
        info->size += size;
        info->num_blocks += num_blocks;

        if (info->num_blocks != 6) {
            return 0;
        }
        info->num_blocks = 0;
    }
    
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

    free(info->frame);

    uint8_t *buffer = cookie.GetBuffer();
    size_t size = cookie.GetBitPosition() / 8;
    CFDataRef cookieData = CFDataCreate(kCFAllocatorDefault, buffer, size);
    free (buffer);

    return cookieData;
}

#pragma mark - MPEG 4 Audio

#define ARRAY_ELEMS(a) (sizeof(a) / sizeof((a)[0]))
#define MKBETAG(a,b,c,d) ((d) | ((c) << 8) | ((b) << 16) | ((unsigned)(a) << 24))

enum AudioObjectType {
    AOT_NULL,
    // Support?                Name
    AOT_AAC_MAIN,              ///< Y                       Main
    AOT_AAC_LC,                ///< Y                       Low Complexity
    AOT_AAC_SSR,               ///< N (code in SoC repo)    Scalable Sample Rate
    AOT_AAC_LTP,               ///< Y                       Long Term Prediction
    AOT_SBR,                   ///< Y                       Spectral Band Replication
    AOT_AAC_SCALABLE,          ///< N                       Scalable
    AOT_TWINVQ,                ///< N                       Twin Vector Quantizer
    AOT_CELP,                  ///< N                       Code Excited Linear Prediction
    AOT_HVXC,                  ///< N                       Harmonic Vector eXcitation Coding
    AOT_TTSI             = 12, ///< N                       Text-To-Speech Interface
    AOT_MAINSYNTH,             ///< N                       Main Synthesis
    AOT_WAVESYNTH,             ///< N                       Wavetable Synthesis
    AOT_MIDI,                  ///< N                       General MIDI
    AOT_SAFX,                  ///< N                       Algorithmic Synthesis and Audio Effects
    AOT_ER_AAC_LC,             ///< N                       Error Resilient Low Complexity
    AOT_ER_AAC_LTP       = 19, ///< N                       Error Resilient Long Term Prediction
    AOT_ER_AAC_SCALABLE,       ///< N                       Error Resilient Scalable
    AOT_ER_TWINVQ,             ///< N                       Error Resilient Twin Vector Quantizer
    AOT_ER_BSAC,               ///< N                       Error Resilient Bit-Sliced Arithmetic Coding
    AOT_ER_AAC_LD,             ///< N                       Error Resilient Low Delay
    AOT_ER_CELP,               ///< N                       Error Resilient Code Excited Linear Prediction
    AOT_ER_HVXC,               ///< N                       Error Resilient Harmonic Vector eXcitation Coding
    AOT_ER_HILN,               ///< N                       Error Resilient Harmonic and Individual Lines plus Noise
    AOT_ER_PARAM,              ///< N                       Error Resilient Parametric
    AOT_SSC,                   ///< N                       SinuSoidal Coding
    AOT_PS,                    ///< N                       Parametric Stereo
    AOT_SURROUND,              ///< N                       MPEG Surround
    AOT_ESCAPE,                ///< Y                       Escape Value
    AOT_L1,                    ///< Y                       Layer 1
    AOT_L2,                    ///< Y                       Layer 2
    AOT_L3,                    ///< Y                       Layer 3
    AOT_DST,                   ///< N                       Direct Stream Transfer
    AOT_ALS,                   ///< Y                       Audio LosslesS
    AOT_SLS,                   ///< N                       Scalable LosslesS
    AOT_SLS_NON_CORE,          ///< N                       Scalable LosslesS (non core)
    AOT_ER_AAC_ELD,            ///< N                       Error Resilient Enhanced Low Delay
    AOT_SMR_SIMPLE,            ///< N                       Symbolic Music Representation Simple
    AOT_SMR_MAIN,              ///< N                       Symbolic Music Representation Main
    AOT_USAC_NOSBR,            ///< N                       Unified Speech and Audio Coding (no SBR)
    AOT_SAOC,                  ///< N                       Spatial Audio Object Coding
    AOT_LD_SURROUND,           ///< N                       Low Delay MPEG Surround
    AOT_USAC,                  ///< N                       Unified Speech and Audio Coding
};

const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};

const uint8_t  mpeg4audio_channels[] = {
    0, 1, 2, 3, 4, 5, 6, 8, 2, 3, 4, 7, 8, 24, 8, 12, 10, 12, 14
};

static int parse_config_ALS(CMemoryBitstream &b, MPEG4AudioConfig *c)
{
    if (b.GetRemainingBits() < 112)
        return -1;

    if (b.GetBits(32) != MKBETAG('A','L','S','\0'))
        return -1;

    // override AudioSpecificConfig channel configuration and sample rate
    // which are buggy in old ALS conformance files
    c->sample_rate = b.GetBits(32);

    // skip number of samples
    b.SkipBits(32);

    // read number of channels
    c->chan_config = 0;
    c->channels    = b.GetBits(16) + 1;

    return 0;
}

static inline int get_object_type(CMemoryBitstream &b)
{
    int object_type = b.GetBits(5);
    if (object_type == AOT_ESCAPE)
        object_type = 32 + b.GetBits(6);
    return object_type;
}

static inline int get_sample_rate(CMemoryBitstream &b, int *index)
{
    *index = b.GetBits(4);
    return *index == 0x0f ? b.GetBits(24) :
    mpeg4audio_sample_rates[*index];
}

static inline int get_program_config_element(CMemoryBitstream &b, int *channels)
{
    b.SkipBits(4); // element_instance_tag
    b.SkipBits(2); // object_type
    b.SkipBits(4); // sampling_frequency_index
    int num_front_channel_elements  = b.GetBits(4);
    int num_side_channel_elements   = b.GetBits(4);
    int num_back_channel_elements   = b.GetBits(4);
    int num_lfe_channel_elements    = b.GetBits(2);

    *channels = num_front_channel_elements + num_side_channel_elements + num_back_channel_elements + num_lfe_channel_elements;
    return 0;
}

int analyze_ESDS(MPEG4AudioConfig *c, const uint8_t *cookie, uint32_t cookieLen)
{
    int specific_config_bitindex;
    int sync_extension = 1;

    if (cookieLen <= 0) {
        return 1;
    }

    bzero(c, sizeof(MPEG4AudioConfig));

    CMemoryBitstream b;
    b.SetBytes((uint8_t *)cookie, cookieLen);

    try {
        c->object_type = get_object_type(b);
        c->sample_rate = get_sample_rate(b, &c->sampling_index);
        c->chan_config = b.GetBits(4);
        if (c->chan_config < ARRAY_ELEMS(mpeg4audio_channels)) {
            c->channels = mpeg4audio_channels[c->chan_config];
        }
        c->sbr = -1;
        c->ps  = -1;
        if (c->object_type == AOT_SBR || (c->object_type == AOT_PS &&
                                          // check for W6132 Annex YYYY draft MP3onMP4
                                          !(b.PeakBits(3) & 0x03 && !(b.PeakBits(9) & 0x3F)))) {
            if (c->object_type == AOT_PS) {
                c->ps = 1;
            }
            c->ext_object_type = AOT_SBR;
            c->sbr = 1;
            c->ext_sample_rate = get_sample_rate(b, &c->ext_sampling_index);
            c->object_type = get_object_type(b);
            if (c->object_type == AOT_ER_BSAC) {
                c->ext_chan_config = b.GetBits(4);
            }
        } else {
            c->ext_object_type = AOT_NULL;
            c->ext_sample_rate = 0;
        }
        specific_config_bitindex = b.GetBitPosition();

        switch (c->object_type) {
            case 1:
            case 2:
            case 3:
            case 4:
            case 6:
            case 7:
            case 17:
            case 19:
            case 20:
            case 21:
            case 22:
            case 23:
            {
                b.SkipBits(1); // frameLengthFlag

                int dependsOnCoreCoder = b.GetBits(1);
                if (dependsOnCoreCoder) {
                    b.SkipBits(14); // coreCoderDelay
                }

                int extensionFlag = b.GetBits(1);

                if (!c->chan_config) {
                    get_program_config_element(b, &c->channels);
                }

                if ((c->object_type == 6) || (c->object_type == 20)) {
                    b.SkipBits(3);
                }

                if (extensionFlag) {
                    if (c->object_type == 22) {
                        b.SkipBits(5);
                        b.SkipBits(11);
                    }
                    if ((c->object_type == 17)
                        || (c->object_type == 19)
                        || (c->object_type == 20)
                        || (c->object_type == 23)
                        ) {
                        b.SkipBits(1);
                        b.SkipBits(1);
                        b.SkipBits(1);
                    }
                    /*ext_flag = */b.SkipBits(1);
                }
            }
        }

        if (c->object_type == AOT_ALS) {
            b.SkipBits(5);
            if (b.PeakBits(24) != MKBETAG('\0','A','L','S')) {
                b.SkipBits(24);
            }

            specific_config_bitindex = b.GetBitPosition();

            if (parse_config_ALS(b, c)) {
                return -1;
            }
        }

        if (c->ext_object_type != AOT_SBR && sync_extension) {
            while (b.GetRemainingBits() > 15) {
                if (b.PeakBits(11) == 0x2b7) { // sync extension
                    b.GetBits(11);
                    c->ext_object_type = get_object_type(b);
                    if (c->ext_object_type == AOT_SBR && (c->sbr = b.GetBits(1)) == 1) {
                        c->ext_sample_rate = get_sample_rate(b, &c->ext_sampling_index);
                        if (c->ext_sample_rate == c->sample_rate) {
                            c->sbr = -1;
                        }
                    }
                    if (b.GetRemainingBits() > 11 && b.GetBits(11) == 0x548) {
                        c->ps = b.GetBits(1);
                    }
                    break;
                } else {
                    b.SkipBits(1); // skip 1 bit
                }
            }
        }

        //PS requires SBR
        if (!c->sbr) {
            c->ps = 0;
        }
        //Limit implicit PS to the HE-AACv2 Profile
        if ((c->ps == -1 && c->object_type != AOT_AAC_LC) || c->channels & ~0x01) {
            c->ps = 0;
        }

    } catch (int e) {
        return -1;

    }

    return specific_config_bitindex;
}

#pragma mark - HEVC

struct NAL_units{
    UInt8 array_completeness;
    UInt8 NAL_unit_type;
    UInt16 numNalus;
};


typedef struct HEVCConfig {
    UInt8 configurationVersion;

    UInt8 general_profile_space;
    UInt8 general_tier_flag;
    UInt8 general_profile_idc;
    UInt32 general_profile_compatibility_flags;
    UInt64 general_constraint_indicator_flags;
    UInt8 general_level_idc;

    UInt16 min_spatial_segmentation_idc;
    UInt8 parallelismType;

    UInt8 chromaFormat;
    UInt8 bitDepthLumaMinus8;
    UInt8 bitDepthChromaMinus8;

    UInt16 avgFrameRate;
    UInt8 constantFrameRate;

    UInt8 numTemporalLayers;
    UInt8 temporalIdNested;

    UInt8 lengthSizeMinusOne;
    UInt8 numOfArrays;

    struct NAL_units *NAL_units;
} HEVCConfig;

int analyze_HEVC(const uint8_t *cookie, uint32_t cookieLen, bool *completeness)
{
    int result = 0;
    bool complete = true;

    HEVCConfig *info = (HEVCConfig *)malloc (sizeof(HEVCConfig));
    bzero(info, sizeof(HEVCConfig));

    CMemoryBitstream b;
    b.SetBytes((uint8_t *)cookie, cookieLen);

    try {
        info->configurationVersion = b.GetBits(8);
        info->general_profile_space = b.GetBits(2);
        info->general_tier_flag = b.GetBits(1);
        info->general_profile_idc = b.GetBits(5);
        info->general_profile_compatibility_flags = b.GetBits(32);

        info->general_constraint_indicator_flags = b.GetBits(32) << 16;
        info->general_constraint_indicator_flags += b.GetBits(16);
        info->general_level_idc = b.GetBits(8);

        b.SkipBits(4); // reserved 1111b
        info->min_spatial_segmentation_idc = b.GetBits(12);
        b.SkipBits(6); // reserved 111111b
        info->parallelismType = b.GetBits(2);
        b.SkipBits(6); // reserved 111111b
        info->chromaFormat = b.GetBits(2);
        b.SkipBits(5); // reserved 11111b
        info->bitDepthLumaMinus8 = b.GetBits(3);
        b.SkipBits(5); // reserved 11111b
        info->bitDepthChromaMinus8 = b.GetBits(3);

        info->avgFrameRate = b.GetBits(16);
        info->constantFrameRate = b.GetBits(2);

        info->numTemporalLayers = b.GetBits(3);
        info->temporalIdNested = b.GetBits(1);

        info->lengthSizeMinusOne = b.GetBits(2);
        info->numOfArrays = b.GetBits(8);

        info->NAL_units = (struct NAL_units *)malloc(sizeof(struct NAL_units) * info->numOfArrays);

        for (UInt8 j = 0; j < info->numOfArrays; j++) {
            info->NAL_units[j].array_completeness = b.GetBits(1);
            if (info->NAL_units[j].array_completeness == 0) {
                complete = false;
            }

            b.SkipBits(1); // reserved 0

            info->NAL_units[j].NAL_unit_type = b.GetBits(6);
            info->NAL_units[j].numNalus = b.GetBits(16);

            for (UInt8 i = 0; i < info->NAL_units[j].numNalus; i++) {
                UInt16 nalUnitLength = b.GetBits(16);
                b.SkipBits(8 * nalUnitLength);
            }
        }
    }
    catch (int e) {
        result = 1;
    }

    free(info->NAL_units);
    free(info);

    *completeness = complete;

    return 0;
}
