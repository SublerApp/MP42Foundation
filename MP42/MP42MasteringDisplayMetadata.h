//
//  MP42MasteringDisplayMetadata.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 28/05/21.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#ifndef MP42MasteringDisplayMetadata_h
#define MP42MasteringDisplayMetadata_h

#include <MP42Foundation/MP42Rational.h>

typedef struct MP42MasteringDisplayMetadata {
    MP42Rational display_primaries[3][2];
    MP42Rational white_point[2];
    MP42Rational min_luminance;
    MP42Rational max_luminance;
    int32_t has_primaries;
    int32_t has_luminance;
} MP42MasteringDisplayMetadata;

typedef struct MP42ContentLightMetadata {
    uint32_t MaxCLL;
    uint32_t MaxFALL;
} MP42ContentLightMetadata;

typedef struct MP42AmbientViewingEnviroment {
    uint32_t ambient_illuminance;
    uint16_t ambient_light_x;
    uint16_t ambient_light_y;
} MP42AmbientViewingEnviroment;


// matches payload of ISO/IEC 23008-2:2015(E), D.2.28 Mastering display colour volume SEI message
typedef struct MP42MasteringDisplayMetadataPayload {
    uint16_t display_primaries_gx;
    uint16_t display_primaries_gy;
    uint16_t display_primaries_bx;
    uint16_t display_primaries_by;
    uint16_t display_primaries_rx;
    uint16_t display_primaries_ry;

    uint16_t white_point_x;
    uint16_t white_point_y;

    uint32_t max_display_mastering_luminance;
    uint32_t min_display_mastering_luminance;
} MP42MasteringDisplayMetadataPayload;

typedef struct MP42ContentLightMetadataPayload {
    uint16_t MaxCLL;
    uint16_t MaxFALL;
} MP42ContentLightMetadataPayload;


#endif /* MP42MasteringDisplayMetadata_h */
