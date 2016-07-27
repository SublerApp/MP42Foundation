//
//  MP42Sample.h
//  Subler
//
//  Created by Damiano Galassi on 29/06/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, MP42SampleBufferFlag) {
    MP42SampleBufferFlagEndOfFile    = 1 << 0,
    MP42SampleBufferFlagIsSync       = 1 << 1,
    MP42SampleBufferFlagIsForced     = 1 << 2,
    MP42SampleBufferFlagDoNotDisplay = 1 << 3
};

@interface MP42SampleBuffer : NSObject {
    @public
	void        *data;
    uint64_t    size;

    uint64_t    timescale;
    uint64_t    duration;
    int64_t     offset;

    int64_t     presentationTimestamp;
    int64_t     presentationOutputTimestamp;
    uint64_t    decodeTimestamp;

    uint32_t    trackId;

    uint16_t    flags;
    void        *attachments;
}

@end
