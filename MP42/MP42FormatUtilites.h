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

    int readAC3Config(uint64_t acmod, uint64_t lfeon, UInt32 *channelsCount, UInt32 *channelLayoutTag);
    int readEAC3Config(const uint8_t *cookie, uint32_t cookieLen, UInt32 *channelsCount, UInt32 *channelLayoutTag);

    int analyze_EAC3(void **context ,uint8_t *frame, uint32_t size);
    CFDataRef createCookie_EAC3(void *context);


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

    int analyze_HEVC(const uint8_t *frame, uint32_t cookieLen, bool *completeness);

#ifdef __cplusplus
}
#endif

#endif /* MP42FormatUtilites_h */
