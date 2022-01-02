//
//  MP42PreviewGenerator.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 08/01/14.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import "MP42PreviewGenerator.h"
#import "MP42TextSample.h"
#import <AVFoundation/AVFoundation.h>

#define MINIMUM_OFFSET  1800

@implementation MP42PreviewGenerator

+ (NSArray<NSImage *> *)generatePreviewImagesFromChapters:(NSArray<MP42TextSample *> *)chapters fileURL:(NSURL *)url atPosition:(CGFloat)position {
    NSArray<NSImage *> *images = nil;

    images = [MP42PreviewGenerator generatePreviewImagesAVFoundationFromChapters:chapters andFile:url atPosition:position];

    return images;
}

+ (NSArray *)generatePreviewImagesAVFoundationFromChapters:(NSArray<MP42TextSample *> *)chapters andFile:(NSURL *)file atPosition:(CGFloat)position {
    NSMutableArray *images = [[NSMutableArray alloc] initWithCapacity:[chapters count]];
    
    AVAsset *asset = [AVAsset assetWithURL:file];
    
    if ([asset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual]) {
        AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.apertureMode = AVAssetImageGeneratorApertureModeCleanAperture;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter  = kCMTimeZero;

        CGFloat offset;
        MP42Duration assetDuration = CMTimeGetSeconds(asset.duration) * 1000;

        for (NSUInteger idx = 0; idx < chapters.count; idx++)
        {
            MP42TextSample *chapter = chapters[idx];

            if (chapter.timestamp > assetDuration) {
                break;
            }

            MP42Duration nextChapterTimestamp = (idx < chapters.count - 1) ? chapters[idx+1].timestamp : assetDuration;

            if (position <= 0.0) {
                offset = MINIMUM_OFFSET;
            }
            else if (position >= 1.0) {
                offset = ((nextChapterTimestamp - chapter.timestamp) * position) - MINIMUM_OFFSET;
            }
            else {
                offset = (nextChapterTimestamp - chapter.timestamp) * position;
            }

            CMTime time = CMTimeMake(chapter.timestamp + MAX(MINIMUM_OFFSET, offset), 1000);

            CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:NULL];
            if (imgRef) {
                NSSize size = NSMakeSize(CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
                NSImage *frame = [[NSImage alloc] initWithCGImage:imgRef size:size];
                
                [images addObject:frame];
            }
            
            CGImageRelease(imgRef);
        }
    }
    
    return images;
}

@end
