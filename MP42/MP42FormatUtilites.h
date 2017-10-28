//
//  MP42FormatUtilites.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 10/11/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

#ifndef MP42FormatUtilites_h
#define MP42FormatUtilites_h

#ifdef __cplusplus
extern "C" {
#endif
    uint8_t *CreateEsdsFromSetupData(uint8_t *codecPrivate, size_t vosLen, size_t *esdsLen, int trackID, bool audio, bool write_version);
    ComponentResult ReadESDSDescExt(void* descExt, UInt8 **buffer, int *size, int versionFlags);

    UInt32 getDefaultChannelLayout(UInt32 channelsCount);

    int readAC3Config(uint64_t acmod, uint64_t lfeon, UInt32 *channelsCount, UInt32 *channelLayoutTag);
    int readEAC3Config(const uint8_t *cookie, uint32_t cookieLen, UInt32 *channelsCount, UInt32 *channelLayoutTag);

    int analyze_EAC3(void **context ,uint8_t *frame, uint32_t size);
    CFDataRef createCookie_EAC3(void *context);
    void free_EAC3_context(void *context);

    typedef struct {
        uint16_t wFormatTag;
        uint16_t nChannels;
        uint32_t nSamplesPerSec;
        uint32_t nAvgBytesPerSec;
        uint16_t nBlockAlign;
        uint16_t wBitsPerSample;
        uint16_t cbSize;
    } waveformatex_t;

    typedef struct {
        uint32_t  Data1;
        uint16_t  Data2;
        uint16_t  Data3;
        uint8_t   Data4[8];
    } waveformatex_guid_t;

    typedef struct {
        waveformatex_t Format;
        union {
            uint16_t wValidBitsPerSample;
            uint16_t wSamplesPerBlock;
            uint16_t wReserved;
        } Samples;
        uint32_t                dwChannelMask;
        waveformatex_guid_t     SubFormat;
    } waveformatextensible_t;

    FourCharCode readWaveFormat(waveformatextensible_t *ex);
    UInt32 readWaveChannelLayout(waveformatextensible_t *ex);

    int analyze_WAVEFORMATEX(const uint8_t *cookie, uint32_t cookieLen, waveformatextensible_t *ex);

    typedef struct MPEG4AudioConfig {
        int object_type;
        int sampling_index;
        int sample_rate;
        int chan_config;
        int sbr; ///< -1 implicit, 1 presence
        int ext_object_type;
        int ext_sampling_index;
        int ext_sample_rate;
        int ext_chan_config;
        int channels;
        int ps;  ///< -1 implicit, 1 presence
        int frame_length_short;
    } MPEG4AudioConfig;

    int analyze_ESDS(MPEG4AudioConfig *c, const uint8_t *cookie, uint32_t cookieLen);

    int analyze_AVC(const uint8_t *cookie, uint32_t cookieLen);

    int analyze_HEVC(const uint8_t *frame, uint32_t cookieLen, bool *completeness);
    void force_HEVC_completeness(const uint8_t *cookie, uint32_t cookieLen);

#ifdef __cplusplus
}
#endif

#endif /* MP42FormatUtilites_h */
