//
//  MP42EditListsConstructor.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import "MP42EditListsReconstructor.h"

@implementation MP42EditListsReconstructor

@synthesize edits;
@synthesize editsCount;

- (instancetype)init {
    self = [super init];
    if (self) {
        _priorityQueue = [[MP42Heap alloc] initWithCapacity:32 andComparator:^NSComparisonResult(id obj1, id obj2) {
            return ((MP42SampleBuffer *)obj2)->presentationTimestamp - ((MP42SampleBuffer *)obj1)->presentationTimestamp;
        }];
        _count = 1;
    }
    return self;
}

- (void)addSample:(MP42SampleBuffer *)sample {
    [sample retain];
    [_priorityQueue insert:sample];

    if ([_priorityQueue isFull]) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];

        if (_timescale == 0) {
            _timescale = extractedSample->timescale;
            _currentTime += extractedSample->offset;
        }

        [self analyzeSample:extractedSample];
        [extractedSample release];
    }
}

- (void)done {
    while (![_priorityQueue isEmpty]) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];
        if (_timescale == 0) {
            _timescale = extractedSample->timescale;
            [self startEditListAtTime:CMTimeMake(extractedSample->presentationTimestamp - extractedSample->timestamp, _timescale)];
        }

        [self analyzeSample:extractedSample];
        [extractedSample release];
    }

    if ([self isEditListOpen]) {
        [self endEditListAtTime:CMTimeMake(_currentTime, _timescale) empty:NO];
    }
}

- (void)analyzeSample:(MP42SampleBuffer *)sample {
    if (sample->attachments) {
#ifdef AVF_DEBUG
        NSLog(@"Attachments found: %@", sample->attachments);
#endif
    }

    CFDictionaryRef trimStart = NULL, trimEnd = NULL;

    if (sample->attachments) {
        // Check if we have to trim the start or end of a sample
        // If so it means we need to start/end an edit
        if ((trimStart = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtStart)) ||
            (sample->doNotDisplay == NO && [self isEditListOpen] == NO)) {
            if ([self isEditListOpen]) {
                [self endEditListAtTime:CMTimeMake(_currentTime, _timescale) empty:NO];
            }

            CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);

            trimStartTime = CMTimeConvertScale(trimStartTime, _timescale, kCMTimeRoundingMethod_Default);
            CMTime editStart = CMTimeMake(_currentTime, _timescale);
            editStart.value += trimStartTime.value;

            [self startEditListAtTime:editStart];
        }
    }

    _currentTime += sample->duration;
    _delta = sample->presentationTimestamp - sample->timestamp;

    if (sample->attachments) {
        if ((trimEnd = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd)) ||
            (sample->doNotDisplay == YES && [self isEditListOpen] == YES)) {
            CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
            trimEndTime = CMTimeConvertScale(trimEndTime, _timescale, kCMTimeRoundingMethod_Default);
            CMTime editEnd = CMTimeMake(_currentTime - trimEndTime.value, _timescale);

            [self endEditListAtTime:editEnd empty:NO];
        }
    }

#ifdef AVF_DEBUG
    NSLog(@"%llu, %llu, %llu, %llu", _count++, _delta, _currentTime, sample->timestamp);
#endif
}

/**
 * Starts a new edit
 */
- (void)startEditListAtTime:(CMTime)time {
    if (editsSize <= editsCount) {
        editsSize += 20;
        edits = (CMTimeRange *) realloc(edits, sizeof(CMTimeRange) * editsSize);
    }
    edits[editsCount] = CMTimeRangeMake(time, kCMTimeInvalid);
    editOpen = YES;
}

/**
 * Closes a opened edit
 */
- (void)endEditListAtTime:(CMTime)time empty:(BOOL)type {
    if (!editOpen) {
        return;
    }

    time.value -= edits[editsCount].start.value;
    edits[editsCount].duration = time;

    if (type) {
        edits[editsCount].start.value = -1;
    }

    if (edits[editsCount].duration.value > 0) {
        editsCount++;
    }
    editOpen = NO;
}

/**
 * Returns if there is an open edit list
 */
- (BOOL)isEditListOpen {
    return editOpen;
}

- (void)dealloc {
    [_priorityQueue release];
    [super dealloc];
}


@end
