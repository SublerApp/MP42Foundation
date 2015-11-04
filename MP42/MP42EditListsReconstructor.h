//
//  MP42EditListsConstructor.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import "MP42Heap.h"
#import "MP42Sample.h"

/**
 *  Analyzes the sample buffers of a track and tries to recreate an array of edits lists
 *  by analyzing the doNotDisplay and trimAtStart/End flags
 *  TO-DO: doesn't work in all cases yet.
 */
@interface MP42EditListsReconstructor : NSObject {
@private
    MP42Heap *_priorityQueue;

    int64_t              _currentTime;
    int64_t              _delta;
    CMTimeScale          _timescale;
    int64_t              _count;

    CMTimeRange         *edits;
    uint64_t             editsCount;
    uint64_t             editsSize;
    BOOL                 editOpen;
}

- (void)addSample:(MP42SampleBuffer *)sample;
- (void)done;

@property (readonly, nonatomic) CMTimeRange *edits;
@property (readonly, nonatomic) uint64_t editsCount;

@end
