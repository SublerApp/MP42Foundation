//
//  MP42Sample.h
//  Subler
//
//  Created by Damiano Galassi on 29/06/10.
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MP42Foundation/MP42Utilities.h>

typedef NS_OPTIONS(uint16_t, MP42SampleBufferFlag) {
    MP42SampleBufferFlagEndOfFile    = 1 << 0,
    MP42SampleBufferFlagIsSync       = 1 << 1,
    MP42SampleBufferFlagIsForced     = 1 << 2,
    MP42SampleBufferFlagDoNotDisplay = 1 << 3
};

typedef NS_OPTIONS(uint32_t, MP42SampleDepType) {
    MP42SampleDepTypeUnknown                      = 0x00, /**< unknown */
    MP42SampleDepTypeHasRedundantCoding           = 0x01, /**< contains redundant coding */
    MP42SampleDepTypeHasNoRedundantCoding         = 0x02, /**< does not contain redundant coding */
    MP42SampleDepTypeHasDependents                = 0x04, /**< referenced by other samples */
    MP42SampleDepTypeHasNoDependents              = 0x08, /**< not referenced by other samples */
    MP42SampleDepTypeIsDependent                  = 0x10, /**< references other samples */
    MP42SampleDepTypeIsIndependent                = 0x20, /**< does not reference other samples */
    MP42SampleDepTypeEarlierDisplayTimesAllowed   = 0x40, /**< subequent samples in GOP may display earlier */
    MP42SampleDepTypeReserved                     = 0x80  /**< reserved */
};

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SampleBuffer : NSObject {
    @public
	void        *data;
    uint32_t    size;

    uint32_t    timescale;
    uint64_t    duration;
    int64_t     offset;

    int64_t     presentationTimestamp;
    int64_t     presentationOutputTimestamp;
    uint64_t    decodeTimestamp;

    MP42TrackId trackId;

    MP42SampleBufferFlag    flags;
    MP42SampleDepType       dependecyFlags;

    void        *attachments;
}

@end
