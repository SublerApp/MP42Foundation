//
//  MP42Sample.h
//  Subler
//
//  Created by Damiano Galassi on 29/06/10.
//  Copyright 2010 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MP42Track;

@interface MP42SampleBuffer : NSObject {
    @public
	void        *data;
    uint64_t    size;

    uint64_t    timescale;
    uint64_t    duration;
    int64_t     offset;

    uint64_t    presentationTimestamp;
    uint64_t    timestamp;

    uint32_t    trackId;

    BOOL        isSync;
    BOOL        isForced;

    void        *attachments;
}

@end
