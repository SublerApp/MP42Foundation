//
//  MP42Sample.h
//  Subler
//
//  Created by Damiano Galassi on 29/06/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MP42Track;

typedef NS_OPTIONS(NSUInteger, MP42SampleBufferFlag) {
    MP42SampleBufferFlagEndOfFile = 1 << 0,
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
    uint64_t    timestamp;

    uint32_t    trackId;

    BOOL        isSync;
    BOOL        isForced;
    BOOL        doNotDisplay;

    void        *attachments;
    uint16_t    flags;
}

@end
