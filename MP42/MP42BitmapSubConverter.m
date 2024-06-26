//
//  SBVobSubConverter.m
//  Subler
//
//  Created by Damiano Galassi on 26/03/11.
//  VobSub code taken from Perian VobSubCodec.c
//  Copyright 2022 Damiano Galassi. All rights reserved.
//

#import "MP42BitmapSubConverter.h"

#import "MP42FileImporter.h"
#import "MP42FileImporter+Private.h"
#import "MP42Track.h"
#import "MP42Track+Private.h"

#import "MP42Fifo.h"
#import "MP42SampleBuffer.h"

#import "MP42PrivateUtilities.h"
#import "MP42SubtitleTrack.h"

#import "MP42OCRWrapper.h"
#import "MP42SubUtilities.h"

#include "FFmpegUtils.h"

@import CoreImage;

MP42_OBJC_DIRECT_MEMBERS
@interface MP42BitmapSubConverter ()
{
    NSThread *decoderThread;

    MP42OCRWrapper          *_ocr;
    CIContext               *_imgContext;
    AVCodec                 *avCodec;
    AVCodecContext          *avContext;
    AVPacket                *pkt;

    MP42Fifo<MP42SampleBuffer *> *_inputSamplesBuffer;
    MP42Fifo<MP42SampleBuffer *> *_outputSamplesBuffer;

    UInt32                  paletteG[16];
    NSData                 *srcMagicCookie;

    uint8_t                *codecData;
    unsigned int            bufferSize;

    dispatch_semaphore_t _done;
}

@property (nonatomic, readonly) CIContext *imgContext;

@end

@implementation MP42BitmapSubConverter

@synthesize imgContext = _imgContext;

- (CIContext *)imgContext {
    if (!_imgContext) {
        _imgContext = [[CIContext alloc] init];
    }
    return _imgContext;
}

- (nullable CGImageRef)createfilteredCGImage:(CGImageRef)image CF_RETURNS_RETAINED {
    CIImage *ciImage = [CIImage imageWithCGImage:image];

    // A filter to increase the subtitle image contrast
    CIFilter *contrastFilter = [CIFilter filterWithName:@"CIColorControls"
                                          keysAndValues:kCIInputImageKey, ciImage,
                                            @"inputContrast", @(1.6f),
                                            @"inputBrightness", @(0.4f),
                                            nil];

    // A black image to compose the subtitle over
    CIImage *blackImage = [CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0]];

    CIVector *cropRect =[CIVector vectorWithX:0 Y:0 Z: CGImageGetWidth(image) W: CGImageGetHeight(image)];
    CIFilter *cropFilter = [CIFilter filterWithName:@"CICrop"];
    [cropFilter setValue:blackImage forKey:@"inputImage"];
    [cropFilter setValue:cropRect forKey:@"inputRectangle"];

    // Compose the subtitle over the black background
    CIFilter *compositingFilter = [CIFilter filterWithName:@"CISourceOverCompositing"];
    [compositingFilter setValue:[contrastFilter valueForKey:@"outputImage"] forKey:@"inputImage"];
    [compositingFilter setValue:[cropFilter valueForKey:@"outputImage"] forKey:@"inputBackgroundImage"];

    // Invert the image colors
    CIFilter *invertFilter = [CIFilter filterWithName:@"CIColorInvert"
                                        keysAndValues:kCIInputImageKey, [compositingFilter valueForKey:kCIOutputImageKey],
                                        nil];

    CIImage *filteredImage = [invertFilter valueForKey:kCIOutputImageKey];
    CGImageRef filteredImgRef = [self.imgContext createCGImage:filteredImage fromRect:[filteredImage extent]];

    return filteredImgRef;
}

- (void)VobSubDecoderThreadMainRoutine
{
    @autoreleasepool {
        MP42SampleBuffer *sampleBuffer = nil;

        while ((sampleBuffer = [_inputSamplesBuffer dequeueAndWait])) {
            @autoreleasepool {

                if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                    [_outputSamplesBuffer enqueue:sampleBuffer];
                    break;
                }

                UInt8 *data = (UInt8 *) sampleBuffer->data;
                int ret, got_sub;

                if (sampleBuffer->size < 4) {
                    // Enque an empty subtitle.
                    MP42SampleBuffer *subSample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleBuffer->duration, NO);

                    [_outputSamplesBuffer enqueue:subSample];

                    continue;
                }

                if (codecData == NULL) {
                    codecData = av_malloc(sampleBuffer->size + 2);
                    bufferSize = (unsigned int)sampleBuffer->size + 2;
                }

                // make sure we have enough space to store the packet
                codecData = fast_realloc_with_padding(codecData, &bufferSize, (unsigned int)sampleBuffer->size + 2);

                // the header of a spu PS packet starts 0x000001bd
                // if it's raw spu data, the 1st 2 bytes are the length of the data
                if (data[0] + data[1] == 0) {
                    // remove the MPEG framing
                    sampleBuffer->size = ExtractVobSubPacket(codecData, data, bufferSize, NULL, -1);
                }
                else {
                    memcpy(codecData, sampleBuffer->data, sampleBuffer->size);
                }

                AVSubtitle subtitle;
                pkt->data = codecData;
                pkt->size = bufferSize;
                ret = avcodec_decode_subtitle2(avContext, &subtitle, &got_sub, pkt);
                av_packet_unref(pkt);

                if (ret < 0 || !got_sub) {
                    NSLog(@"Error decoding DVD subtitle %d / %ld", ret, (long)bufferSize);

                    MP42SampleBuffer *subSample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleBuffer->duration, NO);

                    [_outputSamplesBuffer enqueue:subSample];

                    continue;
                }

                // Extract the color palette and forced info
                OSErr err = noErr;
                PacketControlData controlData;

                memcpy(paletteG, srcMagicCookie.bytes, sizeof(UInt32)*16);

                for (int ii = 0; ii <16; ii++ ) {
                    paletteG[ii] = EndianU32_LtoN(paletteG[ii]);
                }

                BOOL forced = NO;
                err = ReadPacketControls(codecData, paletteG, &controlData, &forced);
                int usePalette = 0;

                if (err == noErr) {
                    usePalette = true;
                }

                for (unsigned int i = 0; i < subtitle.num_rects; i++) {
                    AVSubtitleRect *rect = subtitle.rects[i];

                    uint8_t *imageData = calloc(rect->w * rect->h * 4, sizeof(uint8_t));

                    uint8_t *line = (uint8_t *)imageData;
                    uint8_t *sub = rect->data[0];
                    unsigned int w = rect->w;
                    unsigned int h = rect->h;
                    uint32_t *palette = (uint32_t *)rect->data[1];

                    if (usePalette) {
                        for (unsigned int j = 0; j < 4; j++)
                            palette[j] = EndianU32_BtoN(controlData.pixelColor[j]);
                    }

                    for (unsigned int y = 0; y < h; y++) {
                        uint32_t *pixel = (uint32_t *) line;

                        for (unsigned int x = 0; x < w; x++) {
                            pixel[x] = palette[sub[x]];
                        }

                        line += rect->w*4;
                        sub += rect->linesize[0];
                    }

                    // Kill the alpha
                    size_t length = sizeof(uint8_t) * rect->w * rect->h * 4;
                    for (unsigned int ii = 0; ii < length; ii +=4) {
                        imageData[ii] = 255;
                    }

                    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaFirst;
                    CFDataRef imgData = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, imageData, w*h*4, kCFAllocatorNull);
                    CGDataProviderRef provider = CGDataProviderCreateWithCFData(imgData);
                    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                    CGImageRef cgImage = CGImageCreate(w,
                                                       h,
                                                       8,
                                                       32,
                                                       w*4,
                                                       colorSpace,
                                                       bitmapInfo,
                                                       provider,
                                                       NULL,
                                                       NO,
                                                       kCGRenderingIntentDefault);
                    CGColorSpaceRelease(colorSpace);

                    CGImageRef filteredCGImage = [self createfilteredCGImage:cgImage];
                    NSString *text = [_ocr performOCROnCGImage:filteredCGImage ? filteredCGImage : cgImage];

                    uint64_t sampleDuration = sampleBuffer->duration;
                    uint64_t subDuration = sampleBuffer->timescale && subtitle.end_display_time ?
                                                subtitle.end_display_time * (sampleBuffer->timescale / 1000) :
                                                sampleBuffer->duration;

                    if (subDuration > sampleDuration) {
                        subDuration = sampleDuration;
                    }

                    if (text) {
                        MP42SampleBuffer *subSample = copySubtitleSample(sampleBuffer->trackId, text, subDuration, forced, NO, NO, CGSizeMake(0,0), 0);
                        [_outputSamplesBuffer enqueue:subSample];

                        if (subDuration < sampleDuration) {
                            MP42SampleBuffer *emptySample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleDuration - subDuration, forced);
                            [_outputSamplesBuffer enqueue:emptySample];
                        }
                    } else {
                        MP42SampleBuffer *emptySample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleDuration, forced);
                        [_outputSamplesBuffer enqueue:emptySample];
                    }

                    CGImageRelease(cgImage);
                    if (filteredCGImage) {
                        CGImageRelease(filteredCGImage);
                    }
                    CGDataProviderRelease(provider);
                    CFRelease(imgData);
                    
                    free(imageData);
                }
                
                avsubtitle_free(&subtitle);
            }
        }
        dispatch_semaphore_signal(_done);
    }
}

- (void)PGSDecoderThreadMainRoutine
{
    @autoreleasepool {
        MP42SampleBuffer *sampleBuffer = nil;

        while ((sampleBuffer = [_inputSamplesBuffer dequeueAndWait])) {
            @autoreleasepool {

                if (sampleBuffer->flags & MP42SampleBufferFlagEndOfFile) {
                    [_outputSamplesBuffer enqueue:sampleBuffer];
                    break;
                }

                AVSubtitle subtitle;
                pkt->data = sampleBuffer->data;
                pkt->size = sampleBuffer->size;

                int ret, got_sub;
                ret = avcodec_decode_subtitle2(avContext, &subtitle, &got_sub, pkt);
                av_packet_unref(pkt);

                if (ret < 0 || !got_sub || !subtitle.num_rects) {
                    MP42SampleBuffer *subSample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleBuffer->duration, NO);

                    [_outputSamplesBuffer enqueue:subSample];

                    continue;
                }

                NSMutableString *text = [NSMutableString string];
                BOOL forced = NO;

                for (unsigned i = 0; i < subtitle.num_rects; i++) {
                    AVSubtitleRect *rect = subtitle.rects[i];
                    if (rect->w == 0 || rect->h == 0) {
                        MP42SampleBuffer *subSample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleBuffer->duration, NO);
                        [_outputSamplesBuffer enqueue:subSample];

                        continue;
                    }

                    uint32_t *imageData = calloc(rect->w * rect->h * 4, sizeof(uint32_t));
                    memset(imageData, 0, rect->w * rect->h * 4);

                    // Remove the alpha channel
                    for (int yy = 0; yy < rect->h; yy++) {
                        for (int xx = 0; xx < rect->w; xx++) {
                            uint32_t argb;
                            int pixel;
                            uint8_t color;

                            pixel = yy * rect->w + xx;
                            color = rect->data[0][pixel];
                            argb = ((uint32_t *)rect->data[1])[color];

                            imageData[yy * rect->w + xx] = EndianU32_BtoN(argb);
                        }
                    }

                    if (rect->flags & AV_SUBTITLE_FLAG_FORCED) {
                        forced = YES;
                    }

                    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaFirst;
                    CFDataRef imgData = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, (uint8_t*)imageData,rect->w * rect->h * 4, kCFAllocatorNull);
                    CGDataProviderRef provider = CGDataProviderCreateWithCFData(imgData);
                    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                    CGImageRef cgImage = CGImageCreate(rect->w,
                                                       rect->h,
                                                       8,
                                                       32,
                                                       rect->w * 4,
                                                       colorSpace,
                                                       bitmapInfo,
                                                       provider,
                                                       NULL,
                                                       NO,
                                                       kCGRenderingIntentDefault);
                    CGColorSpaceRelease(colorSpace);

                    CGImageRef filteredCGImage = [self createfilteredCGImage:cgImage];

                    NSString *ocrText;
                    if ((ocrText = [_ocr performOCROnCGImage:filteredCGImage ? filteredCGImage : cgImage])) {
                        if (text.length) {
                            [text appendString:@"\n"];
                        }
                        [text appendString:ocrText];
                    }

                    CGImageRelease(cgImage);
                    CGDataProviderRelease(provider);
                    CFRelease(imgData);
                    if (filteredCGImage) {
                        CFRelease(filteredCGImage);
                    }
                    
                    free(imageData);
                }

                MP42SampleBuffer *subSample = nil;
                if (text.length) {
                    subSample = copySubtitleSample(sampleBuffer->trackId, text, sampleBuffer->duration, forced, NO, NO, CGSizeMake(0,0), 0);
                }
                else {
                    subSample = copyEmptySubtitleSample(sampleBuffer->trackId, sampleBuffer->duration, forced);
                }

                [_outputSamplesBuffer enqueue:subSample];

                avsubtitle_free(&subtitle);
            }
        }
        dispatch_semaphore_signal(_done);
    }
}

- (instancetype)initWithTrack:(MP42SubtitleTrack *)track error:(NSError * __autoreleasing *)outError
{
    if ((self = [super init])) {
        MP42SubtitleCodecType format = track.format;

        if (format == kMP42SubtitleCodecType_VobSub) {
            avCodec = avcodec_find_decoder(AV_CODEC_ID_DVD_SUBTITLE);
        }
        else if (format == kMP42SubtitleCodecType_PGS) {
            avCodec = avcodec_find_decoder(AV_CODEC_ID_HDMV_PGS_SUBTITLE);
        }

        if (avCodec) {
            avContext = avcodec_alloc_context3(NULL);
            pkt = av_packet_alloc();

            if (avcodec_open2(avContext, avCodec, NULL)) {
                NSLog(@"Error opening subtitle decoder");
                av_freep(&avContext);
                return nil;
            }
        } else {
            return nil;
        }

        _outputSamplesBuffer = [[MP42Fifo alloc] initWithCapacity:20];
        _inputSamplesBuffer  = [[MP42Fifo alloc] initWithCapacity:20];
        _done = dispatch_semaphore_create(0);

        srcMagicCookie = [track.importer magicCookieForTrack:track];

        _ocr = [[MP42OCRWrapper alloc] initWithLanguage:track.language];

        if (format == kMP42SubtitleCodecType_VobSub) {
            // Launch the vobsub decoder thread.
            decoderThread = [[NSThread alloc] initWithTarget:self selector:@selector(VobSubDecoderThreadMainRoutine) object:nil];
            [decoderThread setName:@"VobSub Decoder"];
            [decoderThread start];
        }
        else if (format == kMP42SubtitleCodecType_PGS) {
            // Launch the pgs decoder thread.
            decoderThread = [[NSThread alloc] initWithTarget:self selector:@selector(PGSDecoderThreadMainRoutine) object:nil];
            [decoderThread setName:@"PGS Decoder"];
            [decoderThread start];
        }
    }

    return self;
}

- (void)addSample:(MP42SampleBuffer *)sample
{
    [_inputSamplesBuffer enqueue:sample];
}

- (nullable MP42SampleBuffer *)copyEncodedSample
{
    return [_outputSamplesBuffer dequeue];
}

- (void)cancel
{
    [_inputSamplesBuffer cancel];
    [_outputSamplesBuffer cancel];

    dispatch_semaphore_wait(_done, DISPATCH_TIME_FOREVER);
}

- (void)dealloc
{
    if (avContext) {
        avcodec_close(avContext);
        av_freep(&avContext);
    }
    if (pkt) {
        av_packet_free(&pkt);
    }
    if (codecData) {
        av_freep(&codecData);
    }
}

@end
