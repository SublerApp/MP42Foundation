//
//  MP42FormatUtilites.c
//  MP42Foundation
//
//  Created by Damiano Galassi on 10/11/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

#include "mbs.h"
#include "MP42FormatUtilites.h"
#include "MP42MediaFormat.h"

#import <CoreAudio/CoreAudio.h>

/* write the data to the target adress & then return a pointer which points after the written data */
uint8_t *write_data(uint8_t *target, uint8_t* data, int32_t data_size)
{
    if(data_size > 0)
        memcpy(target, data, data_size);
    return (target + data_size);
} /* write_data() */

/* write the int32_t data to target & then return a pointer which points after that data */
uint8_t *write_int32(uint8_t *target, int32_t data)
{
    return write_data(target, (uint8_t*)&data, sizeof(data));
} /* write_int32() */

/* write the int16_t data to target & then return a pointer which points after that data */
uint8_t *write_int16(uint8_t *target, int16_t data)
{
    return write_data(target, (uint8_t*)&data, sizeof(data));
} /* write_int16() */

#define MP4ESDescrTag					0x03
#define MP4DecConfigDescrTag			0x04
#define MP4DecSpecificDescrTag			0x05
#define AC3MaxChan						0x05
#define AC3MaxBlkPerFrame				0x06

// from perian
// based off of mov_mp4_read_descr_len from mov.c in ffmpeg's libavformat
static int readDescrLen(UInt8 **buffer)
{
    int len = 0;
    int count = 4;
    while (count--) {
        int c = *(*buffer)++;
        len = (len << 7) | (c & 0x7f);
        if (!(c & 0x80))
            break;
    }
    return len;
}

// based off of mov_mp4_read_descr from mov.c in ffmpeg's libavformat
static int readDescr(UInt8 **buffer, int *tag)
{
    *tag = *(*buffer)++;
    return readDescrLen(buffer);
}

// based off of mov_read_esds from mov.c in ffmpeg's libavformat
ComponentResult ReadESDSDescExt(void* descExt, UInt8 **buffer, int *size, int versionFlags)
{
    UInt8 *esds = (UInt8 *) descExt;
    int tag, len;
    *size = 0;

    if (versionFlags)
        esds += 4;        // version + flags
    readDescr(&esds, &tag);
    esds += 2;        // ID
    if (tag == MP4ESDescrTag)
        esds++;        // priority

    readDescr(&esds, &tag);
    if (tag == MP4DecConfigDescrTag) {
        esds++;        // object type id
        esds++;        // stream type
        esds += 3;    // buffer size db
        esds += 4;    // max bitrate
        esds += 4;    // average bitrate

        len = readDescr(&esds, &tag);
        if (tag == MP4DecSpecificDescrTag) {
            *buffer = (UInt8 *)calloc(1, len + 8);
            if (*buffer) {
                memcpy(*buffer, esds, len);
                *size = len;
            }
        }
    }

    return noErr;
}

// the esds atom creation is based off of the routines for it in ffmpeg's movenc.c
static unsigned int descrLength(unsigned int len)
{
    int i;
    for(i=1; len>>(7*i); i++);
    return len + 1 + i;
}

static uint8_t* putDescr(uint8_t *buffer, int tag, unsigned int size)
{
    int i= descrLength(size) - size - 2;
    *buffer++ = tag;
    for(; i>0; i--)
        *buffer++ = (size>>(7*i)) | 0x80;
    *buffer++ = size & 0x7F;
    return buffer;
}

// ESDS layout:
//  + version             (4 bytes)
//  + ES descriptor
//   + Track ID            (2 bytes)
//   + Flags               (1 byte)
//   + DecoderConfig descriptor
//    + Object Type         (1 byte)
//    + Stream Type         (1 byte)
//    + Buffersize DB       (3 bytes)
//    + Max bitrate         (4 bytes)
//    + VBR/Avg bitrate     (4 bytes)
//    + DecoderSpecific info descriptor
//     + codecPrivate        (codecPrivate->GetSize())
//   + SL descriptor
//    + dunno               (1 byte)

uint8_t *CreateEsdsFromSetupData(uint8_t *codecPrivate, size_t vosLen, size_t *esdsLen, int trackID, bool audio, bool write_version)
{
    int decoderSpecificInfoLen = vosLen ? descrLength(vosLen) : 0;
    int versionLen = write_version ? 4 : 0;

    *esdsLen = versionLen + descrLength(3 + descrLength(13 + decoderSpecificInfoLen) + descrLength(1));
    uint8_t *esds = (uint8_t*)malloc(*esdsLen);
    UInt8 *pos = (UInt8 *) esds;

    // esds atom version (only needed for ImageDescription extension)
    if (write_version)
        pos = write_int32(pos, 0);

    // ES Descriptor
    pos = putDescr(pos, 0x03, 3 + descrLength(13 + decoderSpecificInfoLen) + descrLength(1));
    pos = write_int16(pos, EndianS16_NtoB(trackID));
    *pos++ = 0;        // no flags

    // DecoderConfig descriptor
    pos = putDescr(pos, 0x04, 13 + decoderSpecificInfoLen);

    // Object type indication, see http://gpac.sourceforge.net/tutorial/mediatypes.htm
    if (audio)
        *pos++ = 0x40;        // aac
    else
        *pos++ = 0x20;        // mpeg4 part 2

    // streamtype
    if (audio)
        *pos++ = 0x15;
    else
        *pos++ = 0x11;

    // 3 bytes: buffersize DB (not sure how to get easily)
    *pos++ = 0;
    pos = write_int16(pos, 0);

    // max bitrate, not sure how to get easily
    pos = write_int32(pos, 0);

    // vbr
    pos = write_int32(pos, 0);

    if (vosLen) {
        pos = putDescr(pos, 0x05, vosLen);
        pos = write_data(pos, codecPrivate, vosLen);
    }

    // SL descriptor
    pos = putDescr(pos, 0x06, 1);
    *pos++ = 0x02;

    return esds;
}

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

int readEAC3Config(const uint8_t *cookie, uint32_t cookieLen, UInt32 *channelsCount, UInt32 *channelLayoutTag, UInt8 *numAtmosObjects)
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
        uint8_t acmod, lfeon, bsid;

        b.GetBits(2); // fscod
        bsid = b.GetBits(5); // bsid
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
		} else {
			b.GetBits(1); //reserved
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
		if (bsid >= 16 && cookieLen >= 7 && !num_dep_sub) {
			uint8_t atmos_version = b.GetBits(8);
			if (atmos_version > 0)
				*numAtmosObjects = b.GetBits(8);
		}
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
	uint8_t	skipflde;						//If true, full skip field syntax is present in each audio block
	uint16_t skipl;							//indicates the number of dummy bytes to skip (ignore) before unpacking the mantissas of the current audio block
	uint8_t blkswe;							//If true, full block switch syntax shall be present in each audio block
	uint8_t dithflage;						//If true, full dither flag syntax shall be present in each audio block
	uint8_t  num_objects_oamd;				//OAMD>0 && JOC>0 indicates Atmos
	uint8_t  num_objects_joc;				//OAMD>0 && JOC>0 indicates Atmos
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

void analyze_ac3_atmos(CMemoryBitstream &b, AC3HeaderInfo *phdr);
void analyze_ac3_skipfld(CMemoryBitstream &b, AC3HeaderInfo *phdr);
void analyze_ac3_auxdata(CMemoryBitstream &b, AC3HeaderInfo *phdr);
void parse_eac3_bsi(CMemoryBitstream &gbc, AC3HeaderInfo *hdr);
void parse_eac3_audfrm(CMemoryBitstream &gbc, AC3HeaderInfo *hdr);
void parse_eac3_audblk(CMemoryBitstream &gbc, AC3HeaderInfo *hdr, int blk);

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
        //end syncinfo()
        //bsi()
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
        //next unparsed field - dialnorm
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
        //bsi()
        hdr->frame_type = b.GetBits(2);			//strmtyp
        if (hdr->frame_type == EAC3_FRAME_TYPE_RESERVED) {
            return AAC_AC3_PARSE_ERROR_FRAME_TYPE;
        }

        hdr->substreamid = b.GetBits(3);		//substreamid

        hdr->frame_size = (b.GetBits(11) + 1) << 1;	//frmsiz
        if (hdr->frame_size < AC3_HEADER_SIZE) {
            return AAC_AC3_PARSE_ERROR_FRAME_SIZE;
        }

        hdr->sr_code = b.GetBits(2);			//fscod
        if (hdr->sr_code == 3) {
            int sr_code2 = b.GetBits(2);
            if(sr_code2 == 3) {
                return AAC_AC3_PARSE_ERROR_SAMPLE_RATE;
            }
            hdr->sample_rate = ff_ac3_sample_rate_tab[sr_code2] / 2;
            hdr->sr_shift = 1;
        } else {
            hdr->num_blocks = eac3_blocks[b.GetBits(2)];	//numblkscod
            hdr->sample_rate = ff_ac3_sample_rate_tab[hdr->sr_code];
            hdr->sr_shift = 0;
        }

        hdr->channel_mode = b.GetBits(3);	//acmod
        hdr->lfe_on = b.GetBits(1);			//lfeon
		b.SkipBits(5);						//bsid already taken
		//next unparsed field - dialnorm
        hdr->bit_rate = 8LL * hdr->frame_size * hdr->sample_rate /
        (hdr->num_blocks * 256);
        hdr->channels = ff_ac3_channels_tab[hdr->channel_mode] + hdr->lfe_on;
    }
    hdr->channel_layout = avpriv_ac3_channel_layout_tab[hdr->channel_mode];
    if (hdr->lfe_on) {
        hdr->channel_layout |= AV_CH_LOW_FREQUENCY;
    }
	//location in stream - bsi().dialnorm(5)
	analyze_ac3_atmos(b, hdr);

	return 0;
}

void analyze_ac3_atmos(CMemoryBitstream &b, AC3HeaderInfo *phdr)
{
	uint32_t savedbitpos = b.GetBitPosition();	//calling routines assume bit pos in b after this fn returns!
	parse_eac3_bsi(b, phdr);					//resets bit_pos to frame start + 2
	parse_eac3_audfrm(b, phdr);					//starts from bit_pos where bsi left off
	//for (int blk = 0; blk < hdr->num_blocks; blk++)
		parse_eac3_audblk(b, phdr, 0 /*blk*/);	//starts from bit_pos where audfrm left off
	analyze_ac3_skipfld(b, phdr);				//shall start from the skipfield
	analyze_ac3_auxdata(b, phdr);				//shall start from the frame end
	b.SetBitPosition(savedbitpos);				//so that analyze_EAC3() does not raise exception
}

int analyze_EAC3(void **context, uint8_t *frame, uint32_t size)
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
        free(hdr);
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
                gbc.SetBytes(frame + cumul_size, (size - cumul_size)/* * 8*/);
                if (ac3_parse_header(gbc, &hdr) < 0) {
                    free(hdr);
                    return -1;
                }
                if (hdr->frame_type != EAC3_FRAME_TYPE_DEPENDENT) {
                    free(hdr);
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
	//hdr->num_objects_xxx freshly updated from stream in ac3_parse_header()
	info->num_objects_oamd = hdr->num_objects_oamd > info->num_objects_oamd ? hdr->num_objects_oamd : info->num_objects_oamd;
	info->num_objects_joc  = hdr->num_objects_joc  > info->num_objects_joc  ? hdr->num_objects_joc  : info->num_objects_joc;

    free(hdr);

    if (!info->num_blocks && num_blocks == 6) {
        return size;
    }
    else if (info->num_blocks + num_blocks > 6) {
        return -2;
    }

    if (!info->num_blocks) {
        // Copy the frame
        if (info->frame) {
            free(info->frame);
        }
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

/**
 *  General approach and part of code from MediaInfoLib ac3 parser.
 *  https://github.com/MediaArea/MediaInfoLib/blob/master/Source/MediaInfo/Audio/File_Ac3.cpp
 */
//---------------------------------------------------------------------------
//E.1.2.2 bsi - Bit stream information
void parse_eac3_bsi(CMemoryBitstream &gbc, AC3HeaderInfo *hdr)
{
	if(hdr->bitstream_id != 16)
		return;

#ifdef DEBUG_PARSER
	printf("***parse_eac3_bsi start bit pos: %d remaining bits: %d\n", gbc.GetBitPosition(), gbc.GetRemainingBits());
#endif
	gbc.SetBitPosition(16);					//skip syncword
	gbc.SkipBits(2+3+11+2+2+3+1);			//strmtyp,substreamid,frmsiz,fscod,numblkscod,acmod,lfeon
	if(gbc.GetBits(1))						//compre ..................................................................................... 1
		gbc.SkipBits(8);					//{compr} ......................................................................... 8
	if(hdr->channel_mode == 0x0) 			/* if 1+1 mode (dual mono, so some items need a second value) */
	{
		gbc.SkipBits(5);					//dialnorm2 ............................................................................... 5
		if(gbc.GetBits(1))					//compr2e ................................................................................. 1
			gbc.SkipBits(8);				//{compr2} .................................................................... 8
	}
	if(hdr->frame_type == 0x1) 				/* if dependent stream */
	{
		if(gbc.GetBits(1))					//chanmape ................................................................................ 1
			gbc.SkipBits(16);				// {chanmap} ................................................................. 16
	}
	/* mixing metadata */
	if(gbc.GetBits(1))						//mixmdate ................................................................................... 1
	{
		if(hdr->channel_mode > 0x2) 		/* if more than 2 channels */
			gbc.SkipBits(2);				//{dmixmod} ................................. 2
		if((hdr->channel_mode & 0x1) && (hdr->channel_mode > 0x2)) /* if three front channels exist */
			gbc.SkipBits(6);				//ltrtcmixlev,lorocmixlev .......................................................................... 3
		if(hdr->channel_mode & 0x4) 		/* if a surround channel exists */
			gbc.SkipBits(6+3);				//ltrtsurmixlev,lorosurmixlev
		if(hdr->lfe_on) 					/* if the LFE channel exists */
		{
			if(gbc.GetBits(1)) 				//lfemixlevcode
				gbc.SkipBits(5);			//lfemixlevcod
		}
		if(hdr->frame_type == 0x0) 			/* if independent stream */
		{
			if(gbc.GetBits(1)) 				//pgmscle
				gbc.SkipBits(6);			//pgmscl
			if(hdr->channel_mode == 0x0) 	/* if 1+1 mode (dual mono, so some items need a second value) */
			{
				if(gbc.GetBits(1)) 			//pgmscl2e
					gbc.SkipBits(6);		//pgmscl2
			}
			if(gbc.GetBits(1)) 				//extpgmscle
				gbc.SkipBits(6);			//extpgmscl
			uint8_t mixdef = gbc.GetBits(2);
			if(mixdef == 0x1) 				/* mixing option 2 */
				gbc.SkipBits(1+1+3);		//premixcmpsel, drcsrc, premixcmpscl
			else if(mixdef == 0x2) 			/* mixing option 3 */ {
				gbc.SkipBits(12);
			}
			else if(mixdef == 0x3) 			/* mixing option 4 */
			{
				uint8_t mixdeflen = gbc.GetBits(5);	//mixdeflen
				if (gbc.GetBits(1))			//mixdata2e
				{
					gbc.SkipBits(1+1+3);	//premixcmpsel,drcsrc,premixcmpscl
					if(gbc.GetBits(1)) 		//extpgmlscle
						gbc.SkipBits(4);	//extpgmlscl
					if(gbc.GetBits(1)) 		//extpgmcscle
						gbc.SkipBits(4);	//extpgmcscl
					if(gbc.GetBits(1)) 		//extpgmrscle
						gbc.SkipBits(4);	//extpgmrscl
					if(gbc.GetBits(1)) 		//extpgmlsscle
						gbc.SkipBits(4);	//extpgmlsscl
					if(gbc.GetBits(1)) 		//extpgmrsscle
						gbc.SkipBits(4);	//extpgmrsscl
					if(gbc.GetBits(1)) 		//extpgmlfescle
						gbc.SkipBits(4);	//extpgmlfescl
					if(gbc.GetBits(1)) 		//dmixscle
						gbc.SkipBits(4);	//dmixscl
					if (gbc.GetBits(1))		//addche
					{
						if(gbc.GetBits(1))	//extpgmaux1scle
							gbc.SkipBits(4);//extpgmaux1scl
						if(gbc.GetBits(1))	//extpgmaux2scle
							gbc.SkipBits(4);//extpgmaux2scl
					}
				}
				if(gbc.GetBits(1))			//mixdata3e
				{
					gbc.SkipBits(5);		//spchdat
					if(gbc.GetBits(1))		//addspchdate
					{
						gbc.SkipBits(5+2);	//spchdat1,spchan1att
						if(gbc.GetBits(1))	//addspchdat1e
							gbc.SkipBits(5+3);	//spchdat2,spchan2att
					}
				}
				//mixdata ........................................ (8*(mixdeflen+2)) - no. mixdata bits
				gbc.SkipBytes(mixdeflen + 2);
				if(gbc.GetBitPosition() & 0x7)
					//mixdatafill ................................................................... 0 - 7
					//used to round up the size of the mixdata field to the nearest byte
					gbc.SkipBits(8 - (gbc.GetBitPosition() & 0x7));
			}
			if(hdr->channel_mode < 0x2) /* if mono or dual mono source */
			{
				if(gbc.GetBits(1))			//paninfoe
					gbc.SkipBits(8+6);		//panmean,paninfo
				if(hdr->channel_mode == 0x0) /* if 1+1 mode (dual mono - some items need a second value) */
				{
					if(gbc.GetBits(1))		//paninfo2e
						gbc.SkipBits(8+6);	//panmean2,paninfo2
				}
			}
			/* mixing configuration information */
			if(gbc.GetBits(1))				//frmmixcfginfoe
			{
				if(hdr->num_blocks == 1) {	//if(numblkscod == 0x0)
					gbc.SkipBits(5);		//blkmixcfginfo[0]
				}
				else
				{
					for(int blk = 0; blk < hdr->num_blocks; blk++)
					{
						if(gbc.GetBits(1))	//blkmixcfginfoe[blk]
							gbc.SkipBits(5);//blkmixcfginfo[blk]
					}
				}
			}
		}
	}
	/* informational metadata */
	if(gbc.GetBits(1))						//infomdate
	{
		gbc.SkipBits(3+1+1);				//bsmod,copyrightb,origbs
		if(hdr->channel_mode == 0x2) 		/* if in 2/0 mode */
			gbc.SkipBits(2+2);				//dsurmod,dheadphonmod
		if(hdr->channel_mode >= 0x6) 		/* if both surround channels exist */
			gbc.SkipBits(2);				//dsurexmod
		if(gbc.GetBits(1))					//audprodie
			gbc.SkipBits(5+2+1);			//mixlevel,roomtyp,adconvtyp
		if(hdr->channel_mode == 0x0)		/* if 1+1 mode (dual mono, so some items need a second value) */
		{
			if(gbc.GetBits(1))				//audprodi2e
				gbc.SkipBits(5+2+1);		//mixlevel2,roomtyp2,adconvtyp2
		}
		if(hdr->sr_code < 0x3) 				/* if not half sample rate */
			gbc.SkipBits(1);				//sourcefscod
	}
	if(hdr->frame_type == 0x0 && hdr->num_blocks != 6)	//(numblkscod != 0x3)
		gbc.SkipBits(1);					//convsync
	if(hdr->frame_type == 0x2) 				/* if bit stream converted from AC-3 */
	{
		uint8_t blkid = 0;
		if(hdr->num_blocks == 6) 			/* 6 blocks per syncframe */
			blkid = 1;
		else
			blkid = gbc.GetBits(1);
		if(blkid)
			gbc.SkipBits(6);				//frmsizecod
	}
	if(gbc.GetBits(1))						//addbsie
	{
		uint8_t addbsil = gbc.GetBits(6) + 1;//addbsil
		gbc.SkipBytes(addbsil);				//addbsi
	}
#ifdef DEBUG_PARSER
	printf("***parse_eac3_bsi end bit pos: %d remaining bits: %d\n", gbc.GetBitPosition(), gbc.GetRemainingBits());
#endif
} 											/* end of bsi */

/** Compute ceil(log2(x)).
 * @param x value used to compute ceil(log2(x))
 * @return computed ceiling of log2(x)
 */
static int ff_log2_c(unsigned int v);
static int av_ceil_log2_c(int x);

static int av_ceil_log2_c(int x)
{
	return ff_log2_c((x - 1) << 1);
}

const uint8_t ff_log2_tab[256] = {
	0,0,1,1,2,2,2,2,3,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
	5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
	6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
	6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
	7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
	7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
	7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
	7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
};

static int ff_log2_c(unsigned int v)
{
	int n = 0;
	if (v & 0xffff0000) {
		v >>= 16;
		n += 16;
	}
	if (v & 0xff00) {
		v >>= 8;
		n += 8;
	}
	n += ff_log2_tab[v];
	
	return n;
}

uint8_t cplinu[AC3MaxBlkPerFrame] = {0,0,0,0,0,0};
uint8_t cplstre[AC3MaxBlkPerFrame] = {0,0,0,0,0,0};
uint8_t chexpstr[AC3MaxBlkPerFrame][AC3MaxChan] = {{0,0,0,0,0},{0,0,0,0,0},{0,0,0,0,0},{0,0,0,0,0},{0,0,0,0,0},{0,0,0,0,0}};
uint8_t cplexpstr[AC3MaxBlkPerFrame] = {0,0,0,0,0,0};
uint8_t lfeexpstr[AC3MaxChan] = {0,0,0,0,0};
uint8_t bamode = 0;
uint8_t snroffststr = 0;
uint8_t frmfgaincode = 0;
uint8_t dbaflde = 0;

//E.1.2.3 audfrm - Audio frame
void parse_eac3_audfrm(CMemoryBitstream &gbc, AC3HeaderInfo *hdr)
{
	if(hdr->bitstream_id != 16)
		return;
#ifdef DEBUG_PARSER
	printf("***parse_eac3_audfrm start bit pos: %d remaining bits: %d\n", gbc.GetBitPosition(), gbc.GetRemainingBits());
#endif
	uint8_t nfchans = hdr->channels - hdr->lfe_on;
	uint8_t expstre, ahte, /*cplahtinu, lfeahtinu,*/ ncplblks = 0;
	
	/* these fields for audio frame exist flags and strategy data */
    if (hdr->num_blocks == 6) { 				/* six blocks per syncframe */
		expstre = gbc.GetBits(1);
		ahte 	= gbc.GetBits(1);
	} else {
		expstre = 1;
		ahte 	= 0;
	}
	snroffststr = gbc.GetBits(2);
	uint8_t transproce = gbc.GetBits(1);
	hdr->blkswe = gbc.GetBits(1);
	hdr->dithflage = gbc.GetBits(1);
	bamode = gbc.GetBits(1);
	frmfgaincode = gbc.GetBits(1);
	dbaflde = gbc.GetBits(1);
	hdr->skipflde = gbc.GetBits(1);
#ifdef DEBUG_PARSER
	printf("skipflde: 0x%0x\n", hdr->skipflde);
#endif
//	if(!hdr->skipflde)
//		return;										//no need to look further, no skipfield in this frame
	uint8_t spxattene = gbc.GetBits(1);
	/* these fields for coupling data */
	//uint8_t feexpstr[AC3MaxBlkPerFrame] = {0,0,0,0,0,0};
	uint8_t cplexpstr[AC3MaxBlkPerFrame] = {0,0,0,0,0,0};
	//uint8_t nchregs[AC3MaxChan] = {0,0,0,0,0};
	uint8_t frmchexpstr[AC3MaxChan] = {0,0,0,0,0};
	uint8_t convexpstr[AC3MaxChan] = {0,0,0,0,0};
	uint8_t chahtinu[AC3MaxChan] = {0,0,0,0,0};
	//uint8_t chintransproc[AC3MaxChan] = {0,0,0,0,0};
	
	if(hdr->channel_mode > 0x1)
	{
		cplinu[0] = gbc.GetBits(1);
		cplstre[0] = 1;
		for(int blk = 1; blk < hdr->num_blocks; blk++)
		{
			if((cplstre[blk] = gbc.GetBits(1)))		//cplstre[blk]
				cplinu[blk] = gbc.GetBits(1);		//cplinu[blk]
			else
				cplinu[blk] = cplinu[blk-1];
		}
	}
	/* these fields for exponent strategy data */
	if(expstre)
	{
		for(int blk = 0; blk < hdr->num_blocks; blk++)
		{
			/* cplexpstr[blk] and chexpstr[blk][ch] derived from table lookups - see Table E.1.8*/
			if(cplinu[blk])
				cplexpstr[blk] = gbc.GetBits(2);
			for(int ch = 0; ch < nfchans; ch++)
				chexpstr[blk][ch] = gbc.GetBits(2);
		}
	} else {
		for(int blk = 0; blk < hdr->num_blocks; blk++)
			ncplblks += cplinu[blk];
		if((hdr->channel_mode > 0x1) && (ncplblks > 0))
			gbc.SkipBits(5);						//frmcplexpstr
		for(int ch = 0; ch < nfchans; ch++)
			frmchexpstr[ch] = gbc.GetBits(5);		//frmchexpstr[ch]
	}
	if(hdr->lfe_on)
	{
		for(int blk = 0; blk < hdr->num_blocks; blk++)
			lfeexpstr[blk] = gbc.GetBits(1);		//lfeexpstr[blk]
	}
	/* These fields for converter exponent strategy data */
	if(hdr->frame_type == 0x0)						//strmtyp == 0x0
	{
		uint8_t convexpstre = 1;
		if(hdr->num_blocks != 6)					//(numblkscod != 0x3)
			convexpstre = gbc.GetBits(1);			//convexpstre
		if(convexpstre)
		{
			for(int ch = 0; ch < nfchans; ch++)
				convexpstr[ch] = gbc.GetBits(5);	//convexpstr[ch]
		}
	}
	/* these fields for AHT data */
	if(ahte)
	{
		//E.2.4.2 Bit stream helper variables
		/* only compute ncplregs if coupling in use for all 6 blocks */
		uint8_t ncplregs = 0, nlferegs = 0, nchregs[16];
		/* AHT is only available in 6 block mode (numblkscod == 0x3) */
		for (int blk = 0; blk < 6; blk++)
		{
			if((cplstre[blk] == 1) || (cplexpstr[blk] != 0 /*reuse*/))
				ncplregs++;
			if(lfeexpstr[blk] !=  0 /*reuse*/)
				nlferegs++;
		}
		for (int ch = 0; ch < nfchans; ch++)
		{
			nchregs[ch] = 0;
			/* AHT is only available in 6 block mode (numblkscod ==0x3) */
			for(int blk = 0; blk < 6; blk++)
			{
				if(chexpstr[blk][ch] != 0 /*reuse*/)
					nchregs[ch]++;
			}
		}
		/* coupling can use AHT only when coupling in use for all blocks */
		/* ncplregs derived from cplstre and cplexpstr - see clause E.2.4.2 */
        if ((ncplblks == 6) && (ncplregs == 1)) {
            gbc.SkipBits(1); //cplahtinu = gbc.GetBits(1);
        } else {
			//cplahtinu = 0;
        }
		for (int ch = 0; ch < nfchans; ch++)
		{	/* nchregs derived from chexpstr - see clause E.2.4.2 */
			if(nchregs[ch])
				chahtinu[ch] = gbc.GetBits(1);		//chahtinu[ch]
			else
				chahtinu[ch] = 0;
		}
		if(hdr->lfe_on)
		{
			/* nlferegs derived from lfeexpstr - see clause E.2.4.2 */
            if (nlferegs) {
                gbc.SkipBits(1); //lfeahtinu = gbc.GetBits(1);			//lfeahtinu
            } else {
				//lfeahtinu = 0;
            }
		}
	}
	/* these fields for audio frame SNR offset data */
	if(snroffststr == 0x0)
		gbc.SkipBits(6+4);							//frmcsnroffst,frmfsnroffst
	/* these fields for audio frame transient pre-noise processing data */
	if(transproce)
	{
		for(int ch = 0; ch < nfchans; ch++)
		{
			if(gbc.GetBits(1))				//chintransproc[ch]
				gbc.SkipBits(10+8);			//transprocloc[ch],transproclen[ch]
		}
	}
	/* These fields for spectral extension attenuation data */
	if(spxattene)
	{
		for(int ch = 0; ch < nfchans; ch++)
		{
			if(gbc.GetBits(1))				//chinspxatten[ch]
				gbc.SkipBits(5);			//spxattencod[ch]
		}
	}
	/* these fields for block start information */
	uint8_t blkstrtinfoe = 0;
	if(hdr->num_blocks != 1)				//(numblkscod != 0x0)
		blkstrtinfoe = gbc.GetBits(1);		//blkstrtinfoe
	if(blkstrtinfoe)
	{
		/* nblkstrtbits determined from frmsiz (see clause E.1.3.2.27) */
		int nblkstrtbits = (int)((hdr->num_blocks - 1) * (4 + av_ceil_log2_c(hdr->frame_size >> 1)));
		gbc.SkipBits(nblkstrtbits);			//blkstrtinfo .......................................... nblkstrtbits
	}
	/* these fields for syntax state initialization */
//	for(int ch = 0; ch < nfchans; ch++)
//	{
//		firstspxcos[ch] = 1;
//		firstcplcos[ch] = 1;
//	}
//	firstcplleak = 1;
#ifdef DEBUG_PARSER
	printf("***parse_eac3_audfrm end bit pos: %d remaining bits: %d\n", gbc.GetBitPosition(), gbc.GetRemainingBits());
#endif
} 											/* end of e-ac-3 audfrm */

void parse_eac3_audblk(CMemoryBitstream &gbc, AC3HeaderInfo *hdr, int blk)
{
    if (hdr->bitstream_id != 16) {
		return;
    }

	uint8_t nfchans = hdr->channels - hdr->lfe_on;
	uint8_t spxinu = 0, chinspx[AC3MaxChan], spxbegf, spxendf, ncplsubnd = 0, cplbndstrc[32], cplbegf = 0, cplendf = 0, ecplinu = 0, ecpl_begin_subbnd = 0, ecpl_end_subbnd = 0, spx_begin_subbnd = 0, spx_end_subbnd = 0, chincpl[16], phsflginu = 0, ecplbegf;

	/* these fields for syntax state initialization */
	uint8_t firstspxcos[AC3MaxChan] = {1,1,1,1,1};
	uint8_t firstcplcos[AC3MaxChan] = {1,1,1,1,1};
	uint8_t chbwcod[AC3MaxChan] = {0,0,0,0,0};

    bzero(chinspx, sizeof(uint8_t) * AC3MaxChan);
    bzero(cplbndstrc, sizeof(uint8_t) * 32);
    bzero(chincpl, sizeof(uint8_t) * 16);
	
	uint8_t firstcplleak = 1;
#ifdef DEBUG_PARSER
	printf("***parse_eac3_audblk start bit pos: %d remaining bits: %d\n", gbc.GetBitPosition(), gbc.GetRemainingBits());
#endif
	/* these fields for block switch and dither flags */
    if (hdr->blkswe) {
        gbc.SkipBits(1*nfchans);					//blksw[ch]
    }
	//else
		//for(ch = 0; ch < nfchans; ch++) {blksw[ch] = 0}
    if (hdr->dithflage) {
        gbc.SkipBits(1*nfchans);					//dithflag[ch]
    }
	//else
		//for(ch = 0; ch < nfchans; ch++) {dithflag[ch] = 1} /* dither on */
	/* these fields for dynamic range control */
    if (gbc.GetBits(1))	{								//dynrnge
		gbc.SkipBits(8);								//dynrng
    }
    if (hdr->channel_mode == 0x0) {									/* if 1+1 mode */
        if(gbc.GetBits(1)) {								//dynrng2e
			gbc.SkipBits(8);							//dynrng2
        }
	}
	/* these fields for spectral extension strategy information */
	uint8_t spxstre;
    if (blk == 0) {
		spxstre = 1;
    } else {
		spxstre = gbc.GetBits(1);						//spxstre
    }

	uint8_t spxbndstrc[32];
	if (spxstre) {
		if((spxinu = gbc.GetBits(1)))					//spxinu
		{
            if (hdr->channel_mode == 0x1) {
				chinspx[0] = 1;
            } else {
                for (int ch = 0; ch < nfchans; ch++) {
					chinspx[ch] = gbc.GetBits(1);		//chinspx[ch]
                }
			}
			gbc.SkipBits(2);							//spxstrtf
			spxbegf = gbc.GetBits(3);					//spxbegf
			spxendf = gbc.GetBits(3);					//spxendf
			if (spxbegf < 6) {
				spx_begin_subbnd = spxbegf + 2;
			} else {
				spx_begin_subbnd = spxbegf * 2 - 3;
			}
			if (spxendf < 3) {
				spx_end_subbnd = spxendf + 5;
			} else {
				spx_end_subbnd = spxendf * 2 + 3;
			}
            if (gbc.GetBits(1)) {							//spxbndstrce
                for (int bnd = spx_begin_subbnd + 1; bnd < spx_end_subbnd ; bnd++) {
					spxbndstrc[bnd] = gbc.GetBits(1);	//spxbndstrc[bnd]
                }
			}
        } else {/* !spxinu */
			for (int ch = 0; ch < nfchans; ch++) {
				chinspx[ch] = 0;
				firstspxcos[ch] = 1;
			}
		}
	}
	//E.2.6.2 Sub-band structure for spectral extension
	uint8_t nspxbnds = 1;
	uint8_t spxbndsztab[32];
	spxbndsztab[0] = 12;
	for (int bnd = spx_begin_subbnd + 1; bnd < spx_end_subbnd; bnd ++) {
		if (spxbndstrc[bnd] == 0) {
			spxbndsztab[nspxbnds] = 12;
			nspxbnds++;
		} else {
			spxbndsztab[nspxbnds - 1] += 12;
		}
	}
	//end E.2.6.2 Sub-band structure for spectral extension
	/* these fields for spectral extension coordinates */
	if (spxinu) {
		uint8_t spxcoe[16];
		for (int ch = 0; ch < nfchans; ch++) {
			if (chinspx[ch]) {
				if (firstspxcos[ch]) {
					spxcoe[ch] = 1;
					firstspxcos[ch] = 0;
                } else {								/* !firstspxcos[ch] */
					spxcoe[ch] = gbc.GetBits(1);	//spxcoe[ch]
                }
				if(spxcoe[ch]) {
					gbc.SkipBits(5+2);				//spxblnd[ch],mstrspxco[ch]
					/* nspxbnds determined from spx_begin_subbnd, spx_end_subbnd, and spxbndstrc[ ] */
                    for (int bnd = 0; bnd < nspxbnds; bnd++) {
						gbc.SkipBits(2+2);			//spxcoexp[ch][bnd],spxcomant[ch][bnd]
                    }
				}
            } else {									/* !chinspx[ch] */
				firstspxcos[ch] = 1;
            }
		}
	}
	/* These fields for coupling strategy and enhanced coupling strategy information */
	if (cplstre[blk]) {
		if (cplinu[blk]) {
			uint8_t ecplinu = gbc.GetBits(1);
			if (hdr->channel_mode == 0x2) {
				chincpl[0] = 1;
				chincpl[1] = 1;
			} else {
                for (int ch = 0; ch < nfchans; ch++) {
					chincpl[ch] = gbc.GetBits(1);
                }
			}
			if (ecplinu == 0) 						/* standard coupling in use */
			{
				if(hdr->channel_mode == 0x2) 		/* if in 2/0 mode */
					phsflginu = gbc.GetBits(1);
				cplbegf = gbc.GetBits(4);
				if(spxinu == 0) 					/* if SPX not in use */
					cplendf = gbc.GetBits(4);
				else /* SPX in use */
				{
					if(spxbegf < 6)					/* note that in this case the value of cplendf may be negative */
						cplendf = spxbegf - 2;
					else
						cplendf = (spxbegf * 2) - 7;
				}
				ncplsubnd = 3 + cplendf - cplbegf;
				if(gbc.GetBits(1))					//cplbndstrce
					gbc.SkipBits(1*ncplsubnd);
			} else { 								/* enhanced coupling in use */
				ecplbegf = gbc.GetBits(4);
				if(ecplbegf < 3) {
					ecpl_begin_subbnd = ecplbegf * 2;
				} else if(ecplbegf < 13) {
					ecpl_begin_subbnd = ecplbegf + 2;
				} else {
					ecpl_begin_subbnd = ecplbegf * 2 - 10;
				}
                if (spxinu == 0) { 					/* if SPX not in use */
					uint8_t ecplendf = gbc.GetBits(4);
					ecpl_end_subbnd = ecplendf + 7;
				} else {							/* SPX in use */
                    if (spxbegf < 6) {
						ecpl_end_subbnd = spxbegf + 5;
                    } else {
						ecpl_end_subbnd = spxbegf * 2;
                    }
				}
                if (gbc.GetBits(1)) {			//ecplbndstrce
					for (int sbnd = MAX(9, ecpl_begin_subbnd + 1); sbnd < ecpl_end_subbnd; sbnd++)
						gbc.SkipBits(1);		//ecplbndstrc[sbnd]
				}
			} /* ecplinu[blk] */
		} else { /* !cplinu[blk] */
			for(int ch = 0; ch < nfchans; ch++)
			{
				chincpl[ch] = 0;
				firstcplcos[ch] = 1;
			}
			firstcplleak = 1;
			phsflginu = 0;
			ecplinu = 0;
		}
	} /* cplstre[blk] */
	/* These fields for coupling coordinates */
	if (cplinu[blk]) {
		uint8_t cplcoe[16];
        bzero(cplcoe, sizeof(uint8_t) * 16);
        if (ecplinu == 0) { 						/* standard coupling in use */
			//4.4.3.13 cplbndstrc[sbnd] - Coupling band structure - 1 bit
			//ncplbnd = (ncplsubnd - (cplbndstrc[1] + ... + cplbndstrc[ncplsubnd - 1]))
			int ncplbnd = 0;
            for (int i = 1; i < ncplsubnd; i++) {
				ncplbnd += cplbndstrc[i];
            }
			ncplbnd = ncplsubnd - ncplbnd;
			//end 4.4.3.13 cplbndstrc[sbnd] - Coupling band structure - 1 bit
			for (int ch = 0; ch < nfchans; ch++) {
				if (chincpl[ch]) {
					if (firstcplcos[ch]) {
						cplcoe[ch] = 1;
						firstcplcos[ch] = 0;
                    } else {						/* !firstcplcos[ch] */
						cplcoe[ch] = gbc.GetBits(1);
                    }
					if (cplcoe[ch]) {
						gbc.SkipBits(2);			//mstrcplco[ch]
						/* ncplbnd derived from ncplsubnd and cplbndstrc */
                        for (int bnd = 0; bnd < ncplbnd; bnd++) {
							gbc.SkipBits(4+4);		//cplcoexp[ch][bnd],//cplcomant[ch][bnd]
                        }
					} /* cplcoe[ch] */
				} else /* !chincpl[ch] */
					firstcplcos[ch] = 1;
			} /* ch */
			if ((hdr->channel_mode == 0x2) && phsflginu && (cplcoe[0] || cplcoe[1])) {
				//for(int bnd = 0; bnd < ncplbnd; bnd++)
					gbc.SkipBits(1*ncplbnd);	//phsflg[bnd]
			}
		} else { /* enhanced coupling in use */
			int firstchincpl = -1;
			gbc.SkipBits(1);					//reserved
			uint8_t ecplparam1e[16], rsvdfieldse[16];
			for(int ch = 0; ch < nfchans; ch++)
			{
				if(chincpl[ch])
				{
					if(firstchincpl == -1)
						firstchincpl = ch;
					if(firstcplcos[ch])
					{
						ecplparam1e[ch] = 1;
						if (ch > firstchincpl)
							rsvdfieldse[ch] = 1;
						else
							rsvdfieldse[ch] = 0;
						firstcplcos[ch] = 0;
					} else { /* !firstcplcos[ch] */
						ecplparam1e[ch] = gbc.GetBits(1);
						if(ch > firstchincpl)
							rsvdfieldse[ch] = gbc.GetBits(1);
						else
							rsvdfieldse[ch] = 0;
					}
					//E.1.3.3.19 ecplbndstrc[sbnd] - Enhanced coupling band (and sub-band) structure - 1 bit
					uint8_t necplbnd = ecpl_end_subbnd - ecpl_begin_subbnd;
					if(ecplparam1e[ch])
					{
						/* necplbnd derived from ecpl_begin_subbnd, ecpl_end_subbnd, and ecplbndstrc */
						//for(int bnd = 0; bnd < necplbnd; bnd++)
							gbc.SkipBits(5*necplbnd);		//ecplamp[ch][bnd]
					}
					if(rsvdfieldse[ch])
						gbc.SkipBits(9 * (necplbnd - 1));	//reserved ................ 9 x (necplbnd - 1)
					if(ch > firstchincpl)
						gbc.SkipBits(1);					//reserved
				} else										/* !chincpl[ch] */
					firstcplcos[ch] = 1;
			} /* ch */
		} /* ecplinu[blk] */
	} /* cplinu[blk] */
	/* these fields for rematrixing operation in the 2/0 mode */
    if(hdr->channel_mode == 0x2) { /* if in 2/0 mode */
		uint8_t rematstr;
        if (blk == 0) {
			rematstr = 1;
        } else {
			rematstr = gbc.GetBits(1);						//rematstr
        }
		if (rematstr) {
			uint8_t nrematbd = 0;
			//E.2.3.2 nrematbd - Number of rematrixing bands
			if(cplinu[blk]) {
				if (ecplinu) {
					if 		(ecplbegf == 0)	{nrematbd = 0;}
					else if (ecplbegf == 1)	{nrematbd = 1;}
					else if (ecplbegf == 2)	{nrematbd = 2;}
					else if (ecplbegf < 5)	{nrematbd = 3;}
					else 					{nrematbd = 4;}
				} else { /* standard coupling */
					if 		(cplbegf == 0)	{nrematbd = 2;}
					else if (cplbegf < 3)	{nrematbd = 3;}
					else 					{nrematbd = 4;}
				}
			} else if (spxinu) {
				if (spxbegf < 2)	{nrematbd = 3;}
				else 				{nrematbd = 4;}
			} else {
				nrematbd = 4;
            }
			//end E.2.3.2 nrematbd - Number of rematrixing bands
			/* nrematbd determined from cplinu, ecplinu, spxinu, cplbegf, ecplbegf and spxbegf */
			//for(int bnd = 0; bnd < nrematbd; bnd++)
				gbc.SkipBits(1*nrematbd);					//rematflg[bnd]
		}
	}
	/* this field for channel bandwidth code */
	for (int ch = 0; ch < nfchans; ch++) {
		if (chexpstr[blk][ch] != 0 /*reuse*/) {
            if ((!chincpl[ch]) && (!chinspx[ch])) {
				chbwcod[ch] = gbc.GetBits(6);				//chbwcod[ch]
            }
		}
	}
	/* these fields for exponents */
	const uint8_t ecplsubbndtab[] = {13, 19, 25, 31, 37, 49, 61, 73, 85, 97, 109, 121, 133, 145, 157, 169, 181, 193, 205, 217, 229, 241, 253};
	uint8_t ecplstartmant = ecplsubbndtab[ecpl_begin_subbnd];
	uint8_t ecplendmant = ecplsubbndtab[ecpl_end_subbnd];
	uint8_t cplstrtmant = (cplbegf * 12) + 37;
	uint8_t cplendmant = ((cplendf + 3) * 12) + 37;
	uint8_t endmant[16], nchgrps[16];

    bzero(nchgrps, sizeof(uint8_t) * 16);
	//4.4.3.29 lfeexps[grp] - Low frequency effects channel exponents - 4 bits or 7 bits -> The total number of lfe channel exponents (nlfemant) is 7

	if(cplinu[blk]) /* exponents for the coupling channel */
	{
		if(cplexpstr[blk] != 0 /*reuse*/)
		{
			gbc.SkipBits(4);					//cplabsexp
			uint8_t ncplgrps = 0;
			//E.2.3.5 ncplgrps - Number of coupled exponent groups
			if (ecplinu)
			{
				//Table 6.4: Exponent strategy coding 00=reuse, 01=D15, 10=D25, 11=D45
				if 		(cplexpstr[blk] == 1 /*D15*/) {ncplgrps = (ecplendmant - ecplstartmant) /  3;}
				else if (cplexpstr[blk] == 2 /*D25*/) {ncplgrps = (ecplendmant - ecplstartmant) /  6;}
				else if (cplexpstr[blk] == 3 /*D45*/) {ncplgrps = (ecplendmant - ecplstartmant) / 12;}
			} else { /* standard coupling */
				/* see clause 6.1.3 */
				if 		(cplexpstr[blk] == 1 /*D15*/) {ncplgrps = (cplendmant - cplstrtmant) /  3;}
				else if (cplexpstr[blk] == 2 /*D25*/) {ncplgrps = (cplendmant - cplstrtmant) /  6;}
				else if (cplexpstr[blk] == 3 /*D45*/) {ncplgrps = (cplendmant - cplstrtmant) / 12;}
			}
			//end E.2.3.5 ncplgrps - Number of coupled exponent groups
			/* ncplgrps derived from cplexpstr, cplbegf, cplendf, ecplinu, ecpl_begin_subbnd, and ecpl_end_subbnd */
			//for(int grp = 0; grp < ncplgrps; grp++)
				gbc.SkipBits(7*ncplgrps);		//cplexps[grp]
		}
	}
    for (int ch = 0; ch < nfchans; ch++) {		/* exponents for full bandwidth channels */
		if (chexpstr[blk][ch] != 0 /*reuse*/) {
			gbc.SkipBits(4);					//exps[ch][0]
			//6.1.3 Exponent decoding
			if(cplinu[blk] == 1)
				endmant[ch] = cplstrtmant; 		/* (ch is coupled) */
			else
				endmant[ch] = ((chbwcod[ch] + 12) * 3) + 37; /* (ch is not coupled) */
			if 		(cplexpstr[blk] == 1 /*D15*/) {nchgrps[ch] = trunc((endmant[ch] - 1)     /  3);}
			else if (cplexpstr[blk] == 2 /*D25*/) {nchgrps[ch] = trunc((endmant[ch] - 1 + 3) /  6);}
			else if (cplexpstr[blk] == 3 /*D45*/) {nchgrps[ch] = trunc((endmant[ch] - 1 + 9) / 12);}
			//end 6.1.3 Exponent decoding
			/* nchgrps derived from chexpstr[ch], and endmant[ch] */
            for (int grp = 1; grp <= nchgrps[ch]; grp++) {
				gbc.GetBits(7);					//exps[ch][grp]
            }
			gbc.GetBits(2);						//gainrng[ch]
		}
	}
    if (hdr->lfe_on) {							/* exponents for the low frequency effects channel */
		if (lfeexpstr[blk] != 0 /*reuse*/) {
			gbc.SkipBits(4);					//lfeexps[0]
			//nlfegrps = 2
			for (int grp = 1; grp <= 2; grp++) {
				gbc.SkipBits(7);				//lfeexps[grp]
			}
		}
	}
	/* these fields for bit-allocation parametric information */
	if (bamode) {
        if (gbc.GetBits(1)) {					//baie
			gbc.SkipBits(2+2+2+2+2);			//sdcycod,fdcycod,sgaincod,dbpbcod,floorcod
        }
	} else {
		//sdcycod = 0x2
		//fdcycod = 0x1
		//sgaincod = 0x1
		//dbpbcod = 0x2
		//floorcod = 0x7
	}
	if (snroffststr == 0x0) {
		//if(cplinu[blk]) {cplfsnroffst = frmfsnroffst}
		//for(ch = 0; ch < nfchans; ch++) {fsnroffst[ch] = frmfsnroffst}
		//if(lfeon) {lfefsnroffst = frmfsnroffst}
	} else {
		uint8_t snroffste;
        if (blk == 0) {
			snroffste = 1;
        } else {
			snroffste = gbc.GetBits(1);
        }
		if (snroffste) {
			gbc.SkipBits(6);					//csnroffst
			if (snroffststr == 0x1) {
				gbc.SkipBits(4);				//blkfsnroffst
				//cplfsnroffst = blkfsnroffst
				//for(ch = 0; ch < nfchans; ch++) {fsnroffst[ch] = blkfsnroffst}
				//lfefsnroffst = blkfsnroffst
			} else if(snroffststr == 0x2) {
                if (cplinu[blk]) {
					gbc.SkipBits(4);			//cplfsnroffst
                }
				//for(int ch = 0; ch < nfchans; ch++)
					gbc.GetBits(4*nfchans);		//fsnroffst[ch]
                if (hdr->lfe_on) {
					gbc.SkipBits(4);			//lfefsnroffst
                }
			}
		}
	}
	uint8_t fgaincode;
    if (frmfgaincode) {
		fgaincode = gbc.GetBits(1);
    } else {
		fgaincode = 0;
        }
	if (fgaincode)
	{
        if (cplinu[blk]) {
			gbc.GetBits(3);						//cplfgaincod
        }
		//for(int ch = 0; ch < nfchans; ch++)
			gbc.GetBits(3*nfchans);				//fgaincod[ch]
        if (hdr->lfe_on) {
			gbc.SkipBits(3);					//lfefgaincod
        }
	} else {
		//if(cplinu[blk]) {cplfgaincod = 0x4}
		//for(ch= 0; ch < nfchans; ch++) {fgaincod[ch] = 0x4}
		//if(lfeon) {lfefgaincod = 0x4}
	}
	if (hdr->frame_type == 0x0)					//strmtyp == 0x0
	{
        if (gbc.GetBits(1)) {					//convsnroffste
			gbc.GetBits(10);					//convsnroffst
        }
	}
	if (cplinu[blk])
	{
		uint8_t cplleake;
		if (firstcplleak)
		{
			cplleake = 1;
			//firstcplleak = 0;
        } else {								/* !firstcplleak */
			cplleake = gbc.GetBits(1);			//cplleake
        }
        if (cplleake) {
			gbc.SkipBits(3+3);					//cplfleak,cplsleak
        }
	}
	/* these fields for delta bit allocation information */
	if(dbaflde)
	{
		uint8_t deltnseg[AC3MaxChan], deltbae[AC3MaxChan];
		if(gbc.GetBits(1))						//deltbaie
		{
			uint8_t cpldeltbae = 0;
			if(cplinu[blk])
				cpldeltbae = gbc.GetBits(2);
			for(int ch = 0; ch < nfchans; ch++)
				deltbae[ch] = gbc.GetBits(2);
			if(cplinu[blk])
			{
				if(cpldeltbae == 1 /*new info follows*/)
				{
					uint8_t cpldeltnseg = gbc.GetBits(3);
					for(int seg = 0; seg <= cpldeltnseg; seg++)
						gbc.GetBits(5+4+3);			//cpldeltoffst[seg],cpldeltlen[seg],cpldeltba[seg]					}
				}
			}
			for(int ch = 0; ch < nfchans; ch++)
			{
				if(deltbae[ch] == 1 /*new info follows*/) //Table 4.11: Delta bit allocation exist states
				{
					deltnseg[ch] = gbc.GetBits(3);
					for(int seg = 0; seg <= deltnseg[ch]; seg++)
						gbc.GetBits(5+4+3);					//deltoffst[ch][seg],deltlen[ch][seg],deltba[ch][seg]					}
				}
			}
		}	/* if(deltbaie) */
	}		/* if(dbaflde) */
	/* these fields for inclusion of unused dummy data */
	if (hdr->skipflde) {
		uint8_t skiple = gbc.GetBits(1);
#ifdef DEBUG_PARSER
		printf("skiple: 0x%0x\n", skiple);
#endif
        if (skiple) {									//NB! both skipflde and skiple must exist for the skipfld to be embedded!
			hdr->skipl = gbc.GetBits(9) * 8;			//because value indicates skip field length in BYTES
#ifdef DEBUG_PARSER
			printf("skipl: 0x%0x (%d)\n", hdr->skipl, hdr->skipl);
#endif
			//skipfld ...................................................................... skipl × 8
			//we leave bit pos here and return to call EMDF parser in outer routine
		}
	}
#ifdef DEBUG_PARSER
	printf("***parse_eac3_audblk end bit pos: %d remaining bits: %d\n", gbc.GetBitPosition(), gbc.GetRemainingBits());
#endif
	//the rest uninteresting but first we need to parse EMDF inside skip field!
} /* end of audblk */

uint32_t variable_bits(CMemoryBitstream &b, uint8_t n_bits)
{
	uint32_t value = 0;
	uint8_t  read_more = 0;
	
	do {
		value += b.GetBits(n_bits);		//value += read ...................................................................... n_bits
		read_more = b.GetBits(1);		//read_more ............................................................................... 1
		if (read_more) {
			value <<= n_bits;
			value += (1 << n_bits);
		}
	} while(read_more);
	return value;
}

bool parse_ac3_oamd(CMemoryBitstream &b, uint32_t emdf_payload_size, uint8_t *num_objects_oamd)
{
	uint8_t object_count = 0;
	uint32_t start_bitPos = b.GetBitPosition();
	
	uint8_t oa_md_version_bits = b.GetBits(2);	//oa_md_version_bits; ........................................................................ 2
	if (oa_md_version_bits == 0x3) {
        b.SkipBits(3); //oa_md_version_bits += b.GetBits(3);		//oa_md_version_bits_ext; .................................................................... 3
	}
	object_count = b.GetBits(5);				//object_count_bits; ......................................................................... 5
	if (object_count == 0x1F) {
		object_count += b.GetBits(7);			//object_count_bits_ext; ..................................................................... 7
	}
	object_count++; 							//object_count = object_count_bits + 1 - object_count indicates the total number of objects in the bitstream
	object_count = MIN(object_count, 16);		//ugly hack, but tvOS 12 public beta only seems to accept 0x10(16) as maximum
	if (object_count > *num_objects_oamd) {
		*num_objects_oamd = object_count;		//update only if more objects discovered than the previous value (unclear, if object count can fluctuate in given stream?)
	}
#ifdef DEBUG_PARSER
	printf("found oamd_object_count: 0x%0x\n", object_count);
#endif
	emdf_payload_size -= b.GetBitPosition() - start_bitPos;
	b.SkipBits(emdf_payload_size);				//rest of payload not interesting
	return object_count ? true : false;
}

bool parse_ac3_joc(CMemoryBitstream &b, uint32_t emdf_payload_size, uint8_t *num_objects_joc)
{
	uint8_t object_count = 0;
	uint32_t start_bitPos = b.GetBitPosition();

	//joc_dmx_config_idx; .......................................................................... 3
	b.SkipBits(3);
	//joc_num_objects_bits; ........................................................................ 6
	object_count = b.GetBits(3) + 1; 			//joc_num_objects = joc_num_objects_bits+ 1
	if(object_count > *num_objects_joc) {
		*num_objects_joc = object_count;		//update only if more objects discovered than the previous value (unclear, if object count can fluctuate in given stream?)
	}
#ifdef DEBUG_PARSER
	printf("found joc_object_count: 0x%0x\n", object_count);
#endif
	emdf_payload_size -= b.GetBitPosition() - start_bitPos;
	b.SkipBits(emdf_payload_size);				//rest of payload not interesting
	return object_count ? true : false;
}

const char* Ac3_emdf_payload_id[32]=
{
	"Container End",
	"Programme loudness data",
	"Programme information",
	"E-AC-3 substream structure",
	"Dynamic range compression data for portable devices",
	"Programme Language",
	"External Data",
	"Headphone rendering data",
	"-",
	"-",
	"-",
	"OAMD",
	"-",
	"-",
	"JOC",
	"-","-","-","-","-","-","-","-","-","-","-","-","-","-","-","-","-"
};

bool parse_ac3_emdf(CMemoryBitstream &b, AC3HeaderInfo *hdr)
{
	//NB! b.head still points to emdf syncword because we peeked and did not get the bits!
	//Could use CMemoryBitstream.PutBytes() to create a copy of CMBS	
	uint16_t	emdf_sync = b.GetBits(16); 					//syncword 0x5838
    if (emdf_sync != 0x5838) {
        printf("WTF");
    }
	uint32_t	emdf_container_length = b.GetBits(16) * 8;	//emdf_container_length
	//bool		have_oamd = false, have_joc = false;		//for the lack of better, lets expect only sequence OAMD-JOC-END
#ifdef DEBUG_PARSER
	printf("found EMDF container length: 0x%0x (%u)\n", emdf_container_length, emdf_container_length);
#endif
	if(emdf_container_length > b.GetRemainingBits())
		return false;
	if(b.GetBits(2))					//the emdf_version field shall be set to '0'
		return false;
	if(b.GetBits(3) == 0x7)				//key_id irrelevant but may have extended bits
		variable_bits(b, 3);
	for(;;)								//work until payload id 0x00 (Container End) is detected
	{
		uint8_t emdf_payload_id = b.GetBits(5);
#ifdef DEBUG_PARSER
		printf("found EMDF Payload 0x%x (%s) at bit pos: 0x%0x (%d)\n", emdf_payload_id, Ac3_emdf_payload_id[emdf_payload_id & 0x1F], b.GetBitPosition(), b.GetBitPosition());
#endif
		if (!emdf_payload_id)			//0x00 = Container End -> loop exit condition!
			break;
		//For now, lets consider only triplets OAMD-JOC-END
        if (emdf_payload_id > 7 && emdf_payload_id != 11 && emdf_payload_id != 14) {
			return false;
        }
        if (emdf_payload_id == 0x1F) {
			emdf_payload_id += variable_bits(b, 5);
        }
		//emdf_payload_config()
		bool smploffste = b.GetBits(1);
        if (smploffste) {
			b.SkipBits(12);
        }
        if (b.GetBits(1)) {				//duratione
			variable_bits(b, 11);		//duration
        }
		//ETSI TS 103 420 V1.1.1 (2016-07), 8.2 Requirements on EMDF container requires codecdatae = 1 and groupid equal for OAMD payload and JOC payload !!
        if (b.GetBits(1)) { 				//groupide
			/*uint32_t groupid =*/ variable_bits(b, 2);		//groupid
        }
		b.SkipBits(1); 					//codecdatae
		if(!b.GetBits(1)) 				//discard_unknown_payload
		{
			bool payload_frame_aligned = false;
			if(!smploffste)
			{
				payload_frame_aligned = b.GetBits(1);
				if(payload_frame_aligned)
					b.SkipBits(2);		//create_duplicate, remove_duplicate
			}
			if (smploffste || payload_frame_aligned)
				b.SkipBits(7);			//priority, proc_allowed
		}
		//end emdf_payload_config()
		uint32_t emdf_payload_size = variable_bits(b, 8) * 8;
#ifdef DEBUG_PARSER
		printf("EMDF Payload size: 0x%x (%d)\n", emdf_payload_size, emdf_payload_size);
#endif
        if (emdf_payload_size > emdf_container_length) {
			return false;
        }
		//for (i = 0; i < emdf_payload_size; i++)
		//{
		//	emdf_payload_byte .................................................................... 8
		//}
		if (emdf_payload_id == 11) {
			parse_ac3_oamd(b, emdf_payload_size, &hdr->num_objects_oamd);
			// have_oamd = true;
		} else if (emdf_payload_id == 14) {
			parse_ac3_joc(b, emdf_payload_size, &hdr->num_objects_joc);
			// have_joc = true;
		} else {
			b.SkipBits(emdf_payload_size);
		}
	}
	//emdf_protection()
	uint8_t protection_length_primary = b.GetBits(2);
	switch(protection_length_primary)
	{
		case 0: return false;
		case 1: protection_length_primary =   8; break;
		case 2: protection_length_primary =  32; break;
		case 3: protection_length_primary = 128; break;
		default: ;
	}
	uint8_t protection_bits_secondary = b.GetBits(2);
	switch(protection_bits_secondary)
	{
		case 0: protection_bits_secondary =   0; break;
		case 1: protection_bits_secondary =   8; break;
		case 2: protection_bits_secondary =  32; break;
		case 3: protection_bits_secondary = 128; break;
		default: ;
	}
	b.SkipBits(protection_length_primary);
	b.SkipBits(protection_bits_secondary);
	return hdr->num_objects_oamd && hdr->num_objects_joc ? true : false;
}

//Atmos in E-AC-3 is detected by looking for OAMD payload (see ETSI TS 103 420)
// in EMDF container in skipfld inside audblk() of E-AC-3 frame (see ETSI TS 102 366)
void analyze_ac3_skipfld(CMemoryBitstream &b, AC3HeaderInfo *hdr)
{	//Let's take a look at frame's auxdata()
	uint16_t	emdf_syncword;

	if(hdr->bitstream_id != 16)
		return;
	while(b.GetRemainingBits() > 16) {
		emdf_syncword = b.PeakBits(16);
		if(emdf_syncword == 0x5838) {					//NB! b.head still points to emdf syncword because we peeked and did not get the bits!
#ifdef DEBUG_PARSER
			printf("parsing bitstream_id: 0x%X frame_type: 0x%0X substreamid: 0x%0X\n", hdr->bitstream_id, hdr->frame_type, hdr->substreamid);
			printf("SKIPFLD: found EMDF syncword 0x%x at bit pos: 0x%0x (%d)\n", emdf_syncword, b.GetBitPosition(), b.GetBitPosition());
#endif
			if(parse_ac3_emdf(b, hdr))
				break;
//			else										//false positive
//				b.SkipBits(1);
		} else {
			b.SkipBits(1);								//NB! EMDF syncword may start anywhere in stream, also mid-byte!
		}
	}
}
//---------------------------------------------------------------------------
//Atmos in E-AC-3 is detected by looking for OAMD payload (see ETSI TS 103 420) in EMDF container in auxdata() of E-AC-3 frame (see ETSI TS 102 366)
void analyze_ac3_auxdata(CMemoryBitstream &b, AC3HeaderInfo *hdr)
{	//Let's take a look at frame's auxdata()
	uint16_t	auxdatal, emdf_syncword;
	
	if(hdr->bitstream_id != 16)
		return;
	b.SetBitPosition((hdr->frame_size * 8) - 18);
	/*4.4.4 auxdata - Auxiliary data field
	 Thus the aux data decoder (which may not decode any audio) may
	 simply look to the end of the AC-3 syncframe to find auxdatal, backup auxdatal bits (from the beginning of auxdatal)
	 in the data stream, and then unpack auxdatal bits moving forward in the data stream.
	 */
	 if(b.GetBits(1)) { 								//auxdatae
		b.SkipBits(-14); 								//back up to beginning of auxdatal field
		auxdatal = b.GetBits(14);						//auxdatal
		b.SkipBits(-auxdatal); 							//back up to beginning of auxdatal payload
		while(b.GetRemainingBits() > 16) {
		//while(b.GetBitPosition() + 16 < hdr->frame_size * 8) {
			emdf_syncword = b.PeakBits(16);
			if(emdf_syncword == 0x5838)
			{					//NB! b.head still points to emdf syncword because we peeked and did not get the bits!
				uint16_t emdf_container_length = b.PeakBits(32) & 0xFFFF;
				if(emdf_container_length > hdr->frame_size - ((b.GetBitPosition() + 7) >> 3))
				{
					b.SkipBits(1);
					continue;
				}
#ifdef DEBUG_PARSER
				printf("parsing bitstream_id: 0x%X frame_type: 0x%0X substreamid: 0x%0X\n", hdr->bitstream_id, hdr->frame_type, hdr->substreamid);
				printf("AUXDATA: found EMDF syncword 0x%x at bit pos: 0x%0x (%d)\n", emdf_syncword, b.GetBitPosition(), b.GetBitPosition());
#endif
				if(parse_ac3_emdf(b, hdr))
					break;
//				else										//false positive
//					b.SkipBits(1);
			} else
				b.SkipBits(1);								//NB! EMDF syncword may start anywhere in stream, also mid-byte!
		}
	}
}

uint8_t get_num_objects_EAC3(void *context)
{
	struct eac3_info *info = (struct eac3_info *) context;
	uint8_t nrobjects = info->num_objects_oamd && info->num_objects_joc ? info->num_objects_oamd : 0;
	
	return nrobjects;
}

CFDataRef createCookie_EAC3(void *context)
{
    struct eac3_info *info = (struct eac3_info *) context;

    // Recreate the dec3 atom
    CMemoryBitstream cookie;
    cookie.AllocBytes(32);
    cookie.PutBits(info->data_rate, 13);    // data_rate
    cookie.PutBits(info->num_ind_sub, 3);   // num_ind_sub

    for (int i = 0; i <= info->num_ind_sub; i++) {
        cookie.PutBits(info->substream[i].fscod, 2);
        // this is required to enforce Atmos for AC-3-embedded E-AC-3 substream
        cookie.PutBits((info->num_objects_oamd ? 16 : info->substream[i].bsid), 5); //Atmos requires BSID 16!

        cookie.PutBits(0, 1); // reserved
		//end byte #1
        cookie.PutBits(0, 1); // asvc

        cookie.PutBits(info->substream[i].bsmod, 3);
        cookie.PutBits(info->substream[i].acmod, 3);
        cookie.PutBits(info->substream[i].lfeon, 1);
		//end byte #2
        cookie.PutBits(0, 3); // reserved

        cookie.PutBits((info->num_objects_oamd ? 0 : info->substream[i].num_dep_sub), 4); // num_dep_sub seems to be 0 for Atmos

        if (!info->substream[i].num_dep_sub || (info->num_objects_oamd && info->num_objects_joc)) {
            cookie.PutBits(0, 1); // reserved
        } else {
            cookie.PutBits(info->substream[i].chan_loc, 9); // chan_loc
        }
		if (info->num_objects_oamd && info->num_objects_joc) {
			cookie.PutBits(1, 8); 						// Atmos version?
			cookie.PutBits(info->num_objects_oamd, 8); 	// numAtmosObjects
		}
    }

    free(info->frame);
    info->frame = NULL;
    uint8_t *buffer = cookie.GetBuffer();
    size_t size = cookie.GetBitPosition() / 8;
	CFDataRef cookieData = CFDataCreate(kCFAllocatorDefault, buffer, size);
	free (buffer);

    return cookieData;
}

void free_EAC3_context(void *context)
{
    struct eac3_info *info = (struct eac3_info *) context;
    free(info->frame);

    info->frame = NULL;
    free(context);
}

#pragma mark - WAVEFORMATEX

#define WAVE_FORMAT_PCM          0x0001
#define WAVE_FORMAT_IEEE_FLOAT   0x0003
#define WAVE_FORMAT_ALAW         0x0006
#define WAVE_FORMAT_MULAW        0x0007
#define WAVE_FORMAT_EXTENSIBLE   0xFFFE

#define SPEAKER_FRONT_LEFT               0x1
#define SPEAKER_FRONT_RIGHT              0x2
#define SPEAKER_FRONT_CENTER             0x4
#define SPEAKER_LOW_FREQUENCY            0x8
#define SPEAKER_BACK_LEFT                0x10
#define SPEAKER_BACK_RIGHT               0x20
#define SPEAKER_FRONT_LEFT_OF_CENTER     0x40
#define SPEAKER_FRONT_RIGHT_OF_CENTER    0x80
#define SPEAKER_BACK_CENTER              0x100
#define SPEAKER_SIDE_LEFT                0x200
#define SPEAKER_SIDE_RIGHT               0x400
#define SPEAKER_TOP_CENTER               0x800
#define SPEAKER_TOP_FRONT_LEFT           0x1000
#define SPEAKER_TOP_FRONT_CENTER         0x2000
#define SPEAKER_TOP_FRONT_RIGHT          0x4000
#define SPEAKER_TOP_BACK_LEFT            0x8000
#define SPEAKER_TOP_BACK_CENTER          0x10000
#define SPEAKER_TOP_BACK_RIGHT           0x20000

#define KSAUDIO_SPEAKER_DIRECTOUT 0 //(no speakers)
#define KSAUDIO_SPEAKER_MONO (SPEAKER_FRONT_CENTER)
#define KSAUDIO_SPEAKER_STEREO (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT)
#define KSAUDIO_SPEAKER_QUAD (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT | SPEAKER_BACK_LEFT | SPEAKER_BACK_RIGHT)
#define KSAUDIO_SPEAKER_SURROUND (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT | SPEAKER_FRONT_CENTER | SPEAKER_BACK_CENTER)
#define KSAUDIO_SPEAKER_5POINT1 (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT | SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY | SPEAKER_BACK_LEFT | SPEAKER_BACK_RIGHT)
#define KSAUDIO_SPEAKER_5POINT1_SURROUND (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT | SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY | SPEAKER_SIDE_LEFT | SPEAKER_SIDE_RIGHT)
#define KSAUDIO_SPEAKER_7POINT1 (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT | SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY | SPEAKER_BACK_LEFT | SPEAKER_BACK_RIGHT | SPEAKER_FRONT_LEFT_OF_CENTER | SPEAKER_FRONT_RIGHT_OF_CENTER)
#define KSAUDIO_SPEAKER_7POINT1_SURROUND (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT | SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY | SPEAKER_BACK_LEFT | SPEAKER_BACK_RIGHT | SPEAKER_SIDE_LEFT | SPEAKER_SIDE_RIGHT)

FourCharCode readWaveFormat(waveformatextensible_t *ex) {
    uint32_t format = 0;

    if (ex->Format.wFormatTag == 0xFFFE) {
        format = ex->SubFormat.Data1;
    } else {
        format = ex->Format.wFormatTag;
    }

    switch (format) {
        case WAVE_FORMAT_PCM:
        case WAVE_FORMAT_IEEE_FLOAT:
            return kMP42AudioCodecType_LinearPCM;

        case WAVE_FORMAT_ALAW:
            return kMP42AudioCodecType_ALaw;

        case WAVE_FORMAT_MULAW:
            return kMP42AudioCodecType_ULaw;

        default:
            return kMP42MediaType_Unknown;
    }
}

UInt32 readWaveChannelLayout(waveformatextensible_t *ex)
{
    if (ex->Format.wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        switch (ex->dwChannelMask) {
            case KSAUDIO_SPEAKER_DIRECTOUT:
                return 0;
            case KSAUDIO_SPEAKER_MONO:
                return kAudioChannelLayoutTag_Mono;
            case KSAUDIO_SPEAKER_STEREO:
                return kAudioChannelLayoutTag_Stereo;
            case KSAUDIO_SPEAKER_QUAD:
                return kAudioChannelLayoutTag_Quadraphonic;
            case KSAUDIO_SPEAKER_SURROUND:
                return kAudioChannelLayoutTag_MPEG_4_0_A;
            case KSAUDIO_SPEAKER_5POINT1:
                return kAudioChannelLayoutTag_MPEG_5_1_A;
            case KSAUDIO_SPEAKER_5POINT1_SURROUND:
                return kAudioChannelLayoutTag_MPEG_5_1_A;
            case KSAUDIO_SPEAKER_7POINT1:
                return kAudioChannelLayoutTag_MPEG_7_1_A;
            case KSAUDIO_SPEAKER_7POINT1_SURROUND:
                return kAudioChannelLayoutTag_MPEG_7_1_A;
        }
    }
    return 0;
}

int analyze_WAVEFORMATEX(const uint8_t *cookie, uint32_t cookieLen, waveformatextensible_t *ex)
{
    CMemoryBitstream b;
    b.SetBytes((u_int8_t *)cookie, cookieLen);
    bzero(ex, sizeof(waveformatextensible_t));

    try {
        ex->Format.wFormatTag = EndianU16_BtoN(b.GetBits(16));
        ex->Format.nChannels = EndianU16_BtoN(b.GetBits(16));
        ex->Format.nSamplesPerSec = EndianU32_BtoN(b.GetBits(32));
        ex->Format.nAvgBytesPerSec = EndianU32_BtoN(b.GetBits(32));
        ex->Format.nBlockAlign = EndianU16_BtoN(b.GetBits(16));
        ex->Format.wBitsPerSample = EndianU16_BtoN(b.GetBits(16));
        ex->Format.cbSize = EndianU16_BtoN(b.GetBits(16));

        if (ex->Format.wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
            ex->Samples.wValidBitsPerSample = EndianU16_BtoN(b.GetBits(16));
            ex->dwChannelMask = EndianU32_BtoN(b.GetBits(32));

            ex->SubFormat.Data1 = EndianU32_BtoN(b.GetBits(32));
            ex->SubFormat.Data2 = EndianU16_BtoN(b.GetBits(16));
            ex->SubFormat.Data3 = EndianU16_BtoN(b.GetBits(16));

            ex->SubFormat.Data4[0] = b.GetBits(8);
            ex->SubFormat.Data4[1] = b.GetBits(8);
            ex->SubFormat.Data4[2] = b.GetBits(8);
            ex->SubFormat.Data4[3] = b.GetBits(8);
            ex->SubFormat.Data4[4] = b.GetBits(8);
            ex->SubFormat.Data4[5] = b.GetBits(8);
            ex->SubFormat.Data4[6] = b.GetBits(8);
            ex->SubFormat.Data4[7] = b.GetBits(8);
        }
    }
    catch (int e) {
        return 1;
    }

    return 0;
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

#pragma mark - AVC

typedef struct AVCConfig {
    UInt8 configurationVersion;

    UInt8 AVCProfileIndication;
    UInt8 profile_compatibility;
    UInt8 AVCLevelIndication;

    UInt8 lengthSizeMinusOne;

    UInt8 numOfSequenceParameterSets;
    UInt8 numOfPictureParameterSets;

    struct NAL_units *NAL_units;
} AVCConfig;


int analyze_AVC(const uint8_t *cookie, uint32_t cookieLen)
{
    int result = 0;

    AVCConfig *info = (AVCConfig *)malloc (sizeof(AVCConfig));
    bzero(info, sizeof(AVCConfig));

    CMemoryBitstream b;
    b.SetBytes((uint8_t *)cookie, cookieLen);

    try {
        info->configurationVersion = b.GetBits(8);
        info->AVCProfileIndication = b.GetBits(8);
        info->profile_compatibility = b.GetBits(8);
        info->AVCLevelIndication = b.GetBits(8);

        b.SkipBits(6);
        info->lengthSizeMinusOne = b.GetBits(2);
        b.SkipBits(3);

        info->numOfSequenceParameterSets = b.GetBits(5);

        for (int i = 0; i < info->numOfSequenceParameterSets; i++) {
            UInt16 sequenceParameterSetLength = b.GetBits(16);
            b.SkipBits(8 * sequenceParameterSetLength);
        }

        info->numOfPictureParameterSets = b.GetBits(8);

        for (int i = 0; i < info->numOfPictureParameterSets; i++) {
            UInt16 pictureParameterSetLength = b.GetBits(16);
            b.SkipBits(8 * pictureParameterSetLength);
        }
    }
    catch (int e) {
        result = 1;
    }


    return result;
}


#pragma mark - HEVC

struct NAL_units{
    UInt8 array_completeness;
    UInt8 NAL_unit_type;
    UInt16 numNalus;
};

#define NAL_UNIT_VPS 32
#define NAL_UNIT_SPS 33
#define NAL_UNIT_PPS 34

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

int parse_HEVC(const uint8_t *cookie, uint32_t cookieLen, bool *completeness, bool forceCompleteness)
{
    int result = 0;
    bool complete = true;

    HEVCConfig *info = (HEVCConfig *)malloc (sizeof(HEVCConfig));
    bzero(info, sizeof(HEVCConfig));

    CMemoryBitstream b;
    b.SetBytes((uint8_t *)cookie, cookieLen);

    try {
        if (forceCompleteness) {
            b.PutBits(1, 8);
        } else {
            info->configurationVersion = b.GetBits(8);
        }
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
            bool unitIsComplete = true;
            u_int32_t completenessPos = b.GetBitPosition();

            info->NAL_units[j].array_completeness = b.GetBits(1);

            if (info->NAL_units[j].array_completeness == 0) {
                unitIsComplete = false;
            }

            b.SkipBits(1); // reserved 0

            info->NAL_units[j].NAL_unit_type = b.GetBits(6);
            info->NAL_units[j].numNalus = b.GetBits(16);

            if (info->NAL_units[j].NAL_unit_type == NAL_UNIT_VPS ||
                info->NAL_units[j].NAL_unit_type == NAL_UNIT_SPS ||
                info->NAL_units[j].NAL_unit_type == NAL_UNIT_PPS) {
                if (forceCompleteness && info->NAL_units[j].numNalus > 0) {
                    u_int32_t currentPos = b.GetBitPosition();
                    b.SetBitPosition(completenessPos);
                    b.PutBits(1, 1);
                    b.SetBitPosition(currentPos);
                } else {
                    complete = unitIsComplete;
                }
            }

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

int analyze_HEVC(const uint8_t *cookie, uint32_t cookieLen, bool *completeness) {
    return parse_HEVC(cookie, cookieLen, completeness, false);
}

void force_HEVC_completeness(const uint8_t *cookie, uint32_t cookieLen) {
    bool completeness = 0;
    parse_HEVC(cookie, cookieLen, &completeness, true);
}
