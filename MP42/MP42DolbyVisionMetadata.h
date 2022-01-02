//
//  MP42DolbyVisionMetadata.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 07/12/21.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#ifndef MP42DolbyVisionMetadata_h
#define MP42DolbyVisionMetadata_h

typedef struct MP42DolbyVisionMetadata {
    uint8_t versionMajor;
    uint8_t versionMinor;
    uint8_t profile;
    uint8_t level;
    bool rpuPresentFlag;
    bool elPresentFlag;
    bool blPresentFlag;
    uint8_t blSignalCompatibilityId;
} MP42DolbyVisionMetadata;

#endif /* MP42DolbyVisionMetadata_h */
