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

    uint64_t        _currentTime;
    CMTimeScale     _timescale;

    int64_t     _delta;

    CMTimeRange *_edits;
    uint64_t    _editsCount;
    uint64_t    _editsSize;

    BOOL        _editOpen;

    FourCharCode _format;
    uint64_t     _priming;
    BOOL         _primingUsed;
}

- (instancetype)initWithMediaFormat:(NSString *)format;

- (void)addSample:(MP42SampleBuffer *)sample;
- (void)done;

@property (readonly, nonatomic) CMTimeRange *edits;
@property (readonly, nonatomic) uint64_t editsCount;

@end
