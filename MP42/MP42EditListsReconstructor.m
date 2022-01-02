//
//  MP42EditListsConstructor.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import "MP42EditListsReconstructor.h"
#import "MP42MediaFormat.h"
#import "MP42Heap.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42EditListsReconstructor
{
@private
    MP42Heap<MP42SampleBuffer *> *_priorityQueue;

    uint64_t    _currentMediaTime;
    CMTimeScale _timescale;

    CMTimeRange *_edits;
    uint64_t    _editsCount;
    uint64_t    _editsSize;

    BOOL        _editOpen;
    BOOL        _emptyEditOpen;
}

- (instancetype)init
{
    self = [super init];

    if (self) {
        _priorityQueue = [[MP42Heap alloc] initWithCapacity:32 comparator:^NSComparisonResult(MP42SampleBuffer * obj1, MP42SampleBuffer * obj2) {
            return obj2->presentationTimestamp - obj1->presentationTimestamp;
        }];
        
        _minOffset = INT64_MAX;
    }

    return self;
}

- (void)dealloc
{
    free(_edits);
}

- (void)addSample:(MP42SampleBuffer *)sample
{
    if (sample->attachments) {

        // Flush the current queue, because pts time is going to be reset
        CFBooleanRef resetDecoderBeforeDecoding = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding);
        if (resetDecoderBeforeDecoding && CFBooleanGetValue(resetDecoderBeforeDecoding) == 1) {
            [self flush];
        }

        // Flush the current queue, because an empty edit is coming
        CFBooleanRef emptyMedia = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_EmptyMedia);
        if (emptyMedia && CFBooleanGetValue(emptyMedia) == 1) {
            [self flush];

            CMTime editStart = CMTimeMake(sample->presentationOutputTimestamp, _timescale);
            [self startEditListAtTime:editStart];
            _emptyEditOpen = YES;
        }
    }

    if (sample->size) {
        [_priorityQueue insert:sample];
    }

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

    if (_editOpen == YES && _emptyEditOpen == NO) {
        CMTime editEnd = CMTimeMake(_currentMediaTime, _timescale);
        [self endEditListAtTime:editEnd empty:NO];

        _currentMediaTime = 0;
    }
}

- (void)done
{
    [self flush];
}

- (void)analyzeSample:(MP42SampleBuffer *)sample {

    if (_timescale == 0) {
        _timescale = sample->timescale;
    }

    if (_currentMediaTime == 0) {
        // Re-align things if the first sample pts is not 0
        _currentMediaTime = sample->presentationTimestamp;
    }
    
    if (sample->offset < _minOffset) {
        _minOffset = sample->offset;
    }

#ifdef AVF_DEBUG
    NSLog(@"T: %llu, D: %lld, P: %lld, PO: %lld O: %lld", _currentMediaTime, sample->decodeTimestamp, sample->presentationTimestamp, sample->presentationOutputTimestamp, sample->offset);
    NSLog(@"%d", sample->flags);
#endif

    CFDictionaryRef trimStart = NULL, trimEnd = NULL;
    if (sample->attachments) {
        trimStart = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtStart);
        trimEnd = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_TrimDurationAtEnd);
    }

    BOOL shouldCloseEmptyEdit = (trimStart || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) == 0)) && _emptyEditOpen == YES && _editOpen == YES;

    if (shouldCloseEmptyEdit) {
        CMTime editEnd = CMTimeMake(sample->presentationOutputTimestamp, _timescale);
        [self endEditListAtTime:editEnd empty:YES];
        _emptyEditOpen = NO;
    }

    BOOL shouldStartNewEdit = trimStart || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) == 0 && _editOpen == NO && _emptyEditOpen == NO);

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
        }

        [self startEditListAtTime:editStart];
    }

    _currentMediaTime += sample->duration;

    BOOL shouldEndEdit = (trimEnd || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) != 0)) && _editOpen == YES && _emptyEditOpen == NO;

    if (shouldEndEdit) {
        CMTime editEnd = CMTimeMake(_currentMediaTime, _timescale);

        if ((sample->flags & MP42SampleBufferFlagDoNotDisplay) != 0) {
            editEnd.value -= sample->duration;
        }

        if (trimEnd) {
            CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
            trimEndTime = CMTimeConvertScale(trimEndTime, _timescale, kCMTimeRoundingMethod_Default);
            editEnd.value -= trimEndTime.value;
        }

        [self endEditListAtTime:editEnd empty:NO];
    }
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
    }
    else {
    }

    if (_edits[_editsCount].duration.value > 0) {
        _editsCount++;
    }
    _editOpen = NO;
}

@end
