//
//  SBVobSubConverter.h
//  Subler
//
//  Created by Damiano Galassi on 26/03/11.
//  Copyright 2011 Damiano Galassi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MP42ConverterProtocol.h"
#import "MP42Fifo.h"

#include <avcodec.h>

NS_ASSUME_NONNULL_BEGIN

@class MP42SampleBuffer;
@class MP42SubtitleTrack;
@class MP42OCRWrapper;

@interface MP42BitmapSubConverter : NSObject <MP42ConverterProtocol> {
    NSThread *decoderThread;
    NSThread *encoderThread;

    MP42OCRWrapper          *_ocr;
    CIContext               *_imgContext;
	AVCodec                 *avCodec;
	AVCodecContext          *avContext;

    MP42Fifo<MP42SampleBuffer *> *_inputSamplesBuffer;
    MP42Fifo<MP42SampleBuffer *> *_outputSamplesBuffer;

	UInt32                  paletteG[16];
    NSData                 *srcMagicCookie;

    uint8_t                *codecData;
    unsigned int            bufferSize;

    int32_t     _readerDone;
    int32_t     _encoderDone;
    dispatch_semaphore_t _done;
}

- (instancetype)initWithTrack:(MP42SubtitleTrack *)track error:(NSError **)outError;

- (void)addSample:(MP42SampleBuffer *)sample;
- (nullable MP42SampleBuffer *)copyEncodedSample;

- (void)cancel;

- (BOOL)encoderDone;
- (void)setInputDone;

@end

NS_ASSUME_NONNULL_END
