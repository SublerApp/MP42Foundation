//
//  MP42EditListsConstructor.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import "MP42SampleBuffer.h"

/**
 *  Analyzes the sample buffers of a track and tries to recreate an array of edits lists
 *  by analyzing the doNotDisplay and trimAtStart/End flags
 *  TO-DO: doesn't work in all cases yet.
 */
MP42_OBJC_DIRECT_MEMBERS
@interface MP42EditListsReconstructor : NSObject

- (void)addSample:(MP42SampleBuffer *)sample;
- (void)done;

@property (readonly, nonatomic) CMTimeRange *edits;
@property (readonly, nonatomic) uint64_t editsCount;

@property (readonly, nonatomic) int64_t minOffset;

@end
