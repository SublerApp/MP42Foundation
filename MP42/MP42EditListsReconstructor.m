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
    MP42Heap *_priorityQueue;

    uint64_t        _currentTime;
    CMTimeScale     _timescale;
    CMTimeScale     _primingTimescale;

    int64_t     _delta;

    CMTimeRange *_edits;
    uint64_t    _editsCount;
    uint64_t    _editsSize;

    BOOL        _editOpen;

    uint64_t     _priming;
    BOOL         _primingUsed;
}

@synthesize edits = _edits;
@synthesize editsCount = _editsCount;

- (instancetype)init {
    self = [self initWithMediaFormat:0];
    return self;
}

- (instancetype)initWithMediaFormat:(FourCharCode)format {
    self = [super init];
    if (self) {
        _priorityQueue = [[MP42Heap alloc] initWithCapacity:32 andComparator:^NSComparisonResult(MP42SampleBuffer * obj1, MP42SampleBuffer * obj2) {
            return obj2->presentationTimestamp - obj1->presentationTimestamp;
        }];


        if (format == kMP42AudioCodecType_MPEG4AAC) {
            _priming = 2112;
            _primingTimescale = 48000;
        }
        else if (format == kMP42AudioCodecType_MPEG4AAC_HE)
        {
            _priming = 4224;
            _primingTimescale = 48000;
        }
    }
    return self;
}

- (void)addSample:(MP42SampleBuffer *)sample {
    [sample retain];

    if (sample->attachments) {
        // Flush the current queue, because pts time is going to be reset
        CFBooleanRef resetDecoderBeforeDecoding = CFDictionaryGetValue(sample->attachments, kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding);
        if (resetDecoderBeforeDecoding && CFBooleanGetValue(resetDecoderBeforeDecoding) == 1 && _priorityQueue.count) {
            [self flush];
        }
    }

    [_priorityQueue insert:sample];

    if ([_priorityQueue isFull]) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];
        [self analyzeSample:extractedSample];
        [extractedSample release];
    }
}

- (void)flush
{
    while (!_priorityQueue.isEmpty) {
        MP42SampleBuffer *extractedSample = [_priorityQueue extract];
        [self analyzeSample:extractedSample];
        [extractedSample release];
    }

    if (_editOpen == YES) {
        CMTime editEnd = CMTimeMake(_currentTime, _timescale);
        [self endEditListAtTime:editEnd empty:NO];
    }
}

- (void)done {
    [self flush];
}

- (void)analyzeSample:(MP42SampleBuffer *)sample {

#ifdef AVF_DEBUG
    NSLog(@"T: %llu, P: %lld, PO: %lld O: %lld", _currentTime, sample->presentationTimestamp, sample->presentationOutputTimestamp, sample->offset);
#endif

    if (_timescale == 0) {
        _timescale = sample->timescale;
        // Re-align things if the first sample pts is not 0
        if (sample->presentationTimestamp != 0) {
            _currentTime += sample->presentationTimestamp;
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
            [self endEditListAtTime:CMTimeMake(_currentTime, _timescale) empty:NO];
        }

        // Add an empty edit list
        CMTime editStart = CMTimeMake(_currentTime, _timescale);
        [self startEditListAtTime:editStart];
        CMTime editEnd = CMTimeMake(_currentTime + _delta, _timescale);
        [self endEditListAtTime:editEnd empty:YES];
    }

    BOOL shouldStartNewEdit = trimStart || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) == NO && _editOpen == NO);

    if (shouldStartNewEdit) {
        // Close the current edit list
        if (_editOpen == YES) {
            [self endEditListAtTime:CMTimeMake(_currentTime, _timescale) empty:NO];
        }

        // Calculate the new edit start
        CMTime editStart = CMTimeMake(_currentTime, _timescale);

        if (trimStart) {
            CMTime trimStartTime = CMTimeMakeFromDictionary(trimStart);
            trimStartTime = CMTimeConvertScale(trimStartTime, _timescale, kCMTimeRoundingMethod_QuickTime);
            editStart.value += trimStartTime.value;
        }

        if (_priming && _primingUsed == NO) {
            if (_timescale <= 1000) {
                CMTime convertedPriming = CMTimeConvertScale(CMTimeMake(_priming, _primingTimescale),
                                                             _timescale, kCMTimeRoundingMethod_QuickTime);
                editStart.value -= convertedPriming.value;
            }
            else {
                editStart.value -= _priming;
            }
            _primingUsed = YES;
        }

        [self startEditListAtTime:editStart];
    }

    _currentTime += sample->duration;

    BOOL shouldEndEdit = trimEnd || ((sample->flags & MP42SampleBufferFlagDoNotDisplay) == YES && _editOpen == YES);

    if (shouldEndEdit) {
        CMTime editEnd = CMTimeMake(_currentTime, _timescale);

        if (trimEnd) {
            CMTime trimEndTime = CMTimeMakeFromDictionary(trimEnd);
            trimEndTime = CMTimeConvertScale(trimEndTime, _timescale, kCMTimeRoundingMethod_QuickTime);
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
