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

#ifdef __cplusplus
}
#endif

#endif /* MP42FormatUtilites_h */
