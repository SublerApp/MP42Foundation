//
//  MP42EditListsConstructor.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import "MP42EditListsReconstructor.h"

@implementation MP42EditListsReconstructor

@synthesize edits = _edits;
@synthesize editsCount = _editsCount;

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

    if (_timescale == 0) {
        _timescale = sample->timescale;
        // Re-align things if the first sample pts is not 0
        if (sample->offset != 0) {
            _currentTime += sample->offset - sample->timestamp;
        }
    }

    if ([_priorityQueue isFull]) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];
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

    if (_editOpen) {
        [self endEditListAtTime:CMTimeMake(_currentTime, _timescale) empty:NO];
    }
}

- (void)analyzeSample:(MP42SampleBuffer *)sample {
    if (sample->attachments) {
#ifdef AVF_DEBUG
        NSLog(@"Attachments found: %@", sample->attachments);
#endif
    }

    CFDictionaryRef trimStart = NULL, trimEnd = NULL, emptyMedia = NULL;
    if (sample->attachments) {
        trimStart = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtStart);
        trimEnd = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd);
        emptyMedia = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_EmptyMedia);
    }

    if (emptyMedia) {
#ifdef AVF_DEBUG
        NSLog(@"Empty edit");
#endif
    }

    BOOL shouldStartNewEdit = trimStart || (sample->doNotDisplay == NO && _editOpen == NO);

    if (shouldStartNewEdit) {
        // Close the current edit list
        if (_editOpen) {
            [self endEditListAtTime:CMTimeMake(_currentTime, _timescale) empty:NO];
        }

        // Calculate the new edit start
        CMTime editStart = CMTimeMake(_currentTime, _timescale);

        if (trimStart) {
            CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);
            trimStartTime = CMTimeConvertScale(trimStartTime, _timescale, kCMTimeRoundingMethod_Default);
            editStart.value += trimStartTime.value;
        }

        [self startEditListAtTime:editStart];
    }

    _currentTime += sample->duration;

    BOOL shouldEndEdit = trimEnd || (sample->doNotDisplay == YES && _editOpen == YES);

    if (shouldEndEdit) {
        CMTime editEnd = CMTimeMake(_currentTime, _timescale);

        if (trimEnd) {
            CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
            trimEndTime = CMTimeConvertScale(trimEndTime, _timescale, kCMTimeRoundingMethod_Default);
            editEnd.value -= trimEndTime.value;
        }

        [self endEditListAtTime:editEnd empty:NO];
    }

#ifdef AVF_DEBUG
    NSLog(@"%llu, T: %llu, C: %llu, O: %llu", _count++, _currentTime, sample->timestamp, sample->offset);
#endif
}

/**
 * Starts a new edit
 */
- (void)startEditListAtTime:(CMTime)time {
    if (_editsSize <= _editsCount) {
        _editsSize += 20;
        _edits = (CMTimeRange *) realloc(_edits, sizeof(CMTimeRange) * _editsSize);
    }
    _edits[_editsCount] = CMTimeRangeMake(time, kCMTimeInvalid);
    _editOpen = YES;
}

/**
 * Closes a opened edit
 */
- (void)endEditListAtTime:(CMTime)time empty:(BOOL)type {
    if (!_editOpen) {
        return;
    }

    time.value -= _edits[_editsCount].start.value;
    _edits[_editsCount].duration = time;

    if (type) {
        _edits[_editsCount].start.value = -1;
    }

    if (_edits[_editsCount].duration.value > 0) {
        _editsCount++;
    }
    _editOpen = NO;
}

- (void)dealloc {
    [_priorityQueue release];
    [super dealloc];
}


@end
