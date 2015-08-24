//
//  MP42PreviewGenerator.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 08/01/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import "MP42PreviewGenerator.h"
#import "MP42TextSample.h"
#import <AVFoundation/AVFoundation.h>

@implementation MP42PreviewGenerator

+ (NSArray<NSImage *> *)generatePreviewImagesFromChapters:(NSArray<MP42TextSample *> *)chapters fileURL:(NSURL *)url {
    NSArray<NSImage *> *images = nil;

    images = [MP42PreviewGenerator generatePreviewImagesAVFoundationFromChapters:chapters andFile:url];

    return images;
}

+ (NSArray *)generatePreviewImagesAVFoundationFromChapters:(NSArray *)chapters andFile:(NSURL *)file {
    NSMutableArray *images = [[NSMutableArray alloc] initWithCapacity:[chapters count]];

    AVAsset *asset = [AVAsset assetWithURL:file];

    if ([asset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual]) {
        AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.apertureMode = AVAssetImageGeneratorApertureModeCleanAperture;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter  = kCMTimeZero;

        for (MP42TextSample *chapter in chapters) {
            CMTime time = CMTimeMake([chapter timestamp] + 1800, 1000);
            CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:NULL];
            if (imgRef) {
                NSSize size = NSMakeSize(CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
                NSImage *frame = [[NSImage alloc] initWithCGImage:imgRef size:size];

                [images addObject:frame];
                [frame release];
            }

            CGImageRelease(imgRef);
        }
    }
    
    return [images autorelease];
}

@end
