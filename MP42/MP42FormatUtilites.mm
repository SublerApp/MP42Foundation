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
            else if (chan_loc & 0x3) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_6_1_A;
            }
            else if (chan_loc & 0x4) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_6_1_B;
            }
            else if (chan_loc & 0x5) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_C;
            }
            else if (chan_loc & 0x6) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_D;
            }
            else if (chan_loc & 0x7) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_7_1_E;
            }
            else if (chan_loc & 0x8) {
                *channelLayoutTag = kAudioChannelLayoutTag_EAC3_6_1_C;
            }
            else if (chan_loc & 0x9) {
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

CFDataRef createCookie_EAC3(uint8_t *frame, uint32_t size)
{
    CMemoryBitstream b;
    b.SetBytes(frame, size);

    uint64_t syncword, substreamid, strmtyp, frmsiz, fscod, bsid, bsmod, acmod, lfeon;
    uint16_t chanmap = 0;

    syncword = b.GetBits(16);

    if (syncword != 0xb77) {
        return NULL;
    }

    strmtyp = b.GetBits(2); // strmtyp
    substreamid = b.GetBits(3); // substreamid

    frmsiz = b.GetBits(11);
    fscod = b.GetBits(2);

    if (fscod == 0x3) {
        b.GetBits(2); // fscod2
    }
    else {
        b.GetBits(2); // numblkscod
    }

    acmod = b.GetBits(3);
    lfeon = b.GetBits(1);
    bsid = b.GetBits(5);

    b.GetBits(5); // dialnorm
    uint8_t compre = b.GetBits(1); // compre
    if (compre) {
        b.GetBits(8); // compr
    }

    if (acmod == 0x0) {
        b.GetBits(5); // dialnorm2
        uint8_t compre2e = b.GetBits(1); // compre2e
        if (compre2e) {
            b.GetBits(8); // compr2
        }
    }

    if (strmtyp == 0x1) {
        uint8_t chanmape = b.GetBits(1);
        if (chanmape) {
            chanmap = b.GetBits(16);
        }
    }

    bsmod = 0;

    // Recreate the dec3 atom
    CMemoryBitstream cookie;
    cookie.AllocBytes(32);
    cookie.PutBits(0, 13); // data_rate
    cookie.PutBits(0, 3);  // num_ind_sub

    cookie.PutBits(fscod, 2);
    cookie.PutBits(bsid, 5);
    cookie.PutBits(0, 1); // reserved

    cookie.PutBits(1, 1); // asvc todo
    cookie.PutBits(bsmod, 3);
    cookie.PutBits(acmod, 3);
    cookie.PutBits(lfeon, 1);

    cookie.PutBits(0, 3); // reserved

    cookie.PutBits(0, 4); // num_dep_sub
    cookie.PutBits(0, 1); // reserved

    return CFDataCreate(NULL, cookie.GetBuffer(), cookie.GetNumberOfBytes());
}
