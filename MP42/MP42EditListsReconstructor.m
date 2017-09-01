//
//  MP42EditListsConstructor.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import "MP42EditListsReconstructor.h"
#import "MP42MediaFormat.h"
#import "MP42Heap.h"

@implementation MP42EditListsReconstructor {
@private
    MP42Heap<MP42SampleBuffer *> *_priorityQueue;

    uint64_t    _currentMediaTime;
    CMTimeScale _timescale;

    int64_t     _delta;

    uint64_t  _previousPresentationOutputTimeStamp;
    uint64_t  _emptyEditPresentationOutputTimestamp;

    CMTimeRange *_edits;
    uint64_t    _editsCount;
    uint64_t    _editsSize;

    BOOL        _editOpen;
}

- (instancetype)init {
    self = [self initWithMediaFormat:0];
    return self;
}

- (instancetype)initWithMediaFormat:(FourCharCode)format {
    self = [super init];
    if (self) {
        _priorityQueue = [[MP42Heap alloc] initWithCapacity:32 comparator:^NSComparisonResult(MP42SampleBuffer * obj1, MP42SampleBuffer * obj2) {
            return obj2->presentationTimestamp - obj1->presentationTimestamp;
        }];
    }
    return self;
}

- (void)dealloc
{
    free(_edits);
}

- (void)addSample:(MP42SampleBuffer *)sample {

    if (sample->attachments) {
        // Flush the current queue, because pts time is going to be reset
        CFBooleanRef resetDecoderBeforeDecoding = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding);
        if (resetDecoderBeforeDecoding && CFBooleanGetValue(resetDecoderBeforeDecoding) == 1) {
            [self flush];
        }
    }

    [_priorityQueue insert:sample];

    if ([_priorityQueue isFull]) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];
        [self analyzeSample:extractedSample];
    }
}

- (void)flush
{
    while (!_priorityQueue.isEmpty) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];
        [self analyzeSample:extractedSample];
    }

    if (_editOpen == YES) {
        CMTime editEnd = CMTimeMake(_currentMediaTime, _timescale);
        [self endEditListAtTime:editEnd empty:NO];
    }

#ifdef AVF_DEBUG
    NSLog(@"Flush Done");
#endif
}

- (void)done {
    [self flush];
}

- (void)analyzeSample:(MP42SampleBuffer *)sample {

#ifdef AVF_DEBUG
    NSLog(@"T: %llu, D: %lld, P: %lld, PO: %lld O: %lld", _currentMediaTime, sample->decodeTimestamp, sample->presentationTimestamp, sample->presentationOutputTimestamp, sample->offset);
#endif

    if (_timescale == 0) {
        _timescale = sample->timescale;
        // Re-align things if the first sample pts is not 0
        if (sample->presentationTimestamp != 0) {
            _currentMediaTime += sample->presentationTimestamp;
        }
    }

    CFDictionaryRef trimStart = NULL, trimEnd = NULL;
    if (sample->attachments) {
        trimStart = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtStart);
        trimEnd = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd);
    }

    // Check if we need to add an empty edit list.
    if (sample->presentationOutputTimestamp > sample->presentationTimestamp + _delta) {
        _delta = sample->presentationOutputTimestamp - sample->presentationTimestamp;

        if (_editOpen == YES) {
            [self endEditListAtTime:CMTimeMake(_currentMediaTime, _timescale) empty:NO];
        }

        if ([self isLastEditEmpty]) {
            // If there is already an empty edit list as the last list, append the duration to it
            uint64_t editDuration = sample->presentationOutputTimestamp - _emptyEditPresentationOutputTimestamp;
            [self expandLastEmptyEdit: CMTimeMake(editDuration, _timescale)];
        }
        else {
            // Add an empty edit list
            uint64_t editDuration = sample->presentationOutputTimestamp - _previousPresentationOutputTimeStamp;

            CMTime editStart = CMTimeMake(_currentMediaTime, _timescale);
            [self startEditListAtTime:editStart];
            CMTime editEnd = CMTimeMake(_currentMediaTime + editDuration, _timescale);
            [self endEditListAtTime:editEnd empty:YES];
            _emptyEditPresentationOutputTimestamp = sample->presentationOutputTimestamp + sample->duration;
        }
    }

    BOOL shouldStartNewEdit = trimStart || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) == NO && _editOpen == NO);

    uint64_t trimmedDuration = sample->duration;

    if (shouldStartNewEdit) {
        // Close the current edit list
        if (_editOpen == YES) {
            [self endEditListAtTime:CMTimeMake(_currentMediaTime, _timescale) empty:NO];
        }

        // Calculate the new edit start
        CMTime editStart = CMTimeMake(_currentMediaTime, _timescale);

        if (trimStart) {
            CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);
            trimStartTime = CMTimeConvertScale(trimStartTime, _timescale, kCMTimeRoundingMethod_Default);
            editStart.value += trimStartTime.value;
            trimmedDuration -= trimStartTime.value;
        }

        [self startEditListAtTime:editStart];
    }

    _currentMediaTime += sample->duration;

    BOOL shouldEndEdit = trimEnd || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) == YES && _editOpen == YES);

    if (shouldEndEdit) {
        CMTime editEnd = CMTimeMake(_currentMediaTime, _timescale);

        if (trimEnd) {
            CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
            trimEndTime = CMTimeConvertScale(trimEndTime, _timescale, kCMTimeRoundingMethod_Default);
            editEnd.value -= trimEndTime.value;
            trimmedDuration -= trimEndTime.value;
        }

        [self endEditListAtTime:editEnd empty:NO];
    }

    _previousPresentationOutputTimeStamp = sample->presentationOutputTimestamp + trimmedDuration;
}

/*
 * Check if the last edit is an empty edit
 */
- (BOOL)isLastEditEmpty {
    if (_editsCount == 0) { return NO; }
    return _edits[_editsCount - 1].start.value == -1;
}

- (void)expandLastEmptyEdit:(CMTime)time {
    _edits[_editsCount - 1].duration.value += time.value;
#ifdef AVF_DEBUG
    NSLog(@"Expanded empty edit");
#endif
}

/**
 * Starts a new edit
 */
- (void)startEditListAtTime:(CMTime)time {
    NSAssert(!_editOpen, @"Trying to open an edit list when one is already open.");

    if (_editsSize <= _editsCount) {
        _editsSize += 20;
        _edits = (CMTimeRange *) realloc(_edits, sizeof(CMTimeRange) * _editsSize);
    }
    _edits[_editsCount] = CMTimeRangeMake(time, kCMTimeInvalid);
    _editOpen = YES;

#ifdef AVF_DEBUG
    NSLog(@"Started an edit");
#endif
}

/**
 * Closes a open edit
 */
- (void)endEditListAtTime:(CMTime)time empty:(BOOL)type {
    NSAssert(_editOpen, @"Trying to close an edit list when there isn't a open one");

    time.value -= _edits[_editsCount].start.value;
    _edits[_editsCount].duration = time;

    if (type) {
        _edits[_editsCount].start.value = -1;
#ifdef AVF_DEBUG
        NSLog(@"Closed empty edit");
#endif
    }
    else {
#ifdef AVF_DEBUG
        NSLog(@"Closed edit");
#endif
    }

    if (_edits[_editsCount].duration.value > 0) {
        _editsCount++;
    }
    _editOpen = NO;
}

@end
