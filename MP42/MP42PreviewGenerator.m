//
//  MP42PreviewGenerator.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 08/01/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import "MP42PreviewGenerator.h"
#import "MP42TextSample.h"
#import <QTKit/QTKit.h>
#if __MAC_OS_X_VERSION_MAX_ALLOWED > 1060
#import <AVFoundation/AVFoundation.h>
#endif

@implementation MP42PreviewGenerator

+ (NSArray *)generatePreviewImagesFromChapters:(NSArray *)chapters andFile:(NSURL *)file {
    NSArray *images = nil;
    // If we are on 10.7 or later, use AVFoundation, else QTKit
    if (NSClassFromString(@"AVAsset")) {
        images = [MP42PreviewGenerator generatePreviewImagesAVFoundationFromChapters:chapters andFile:file];
    } else {
        images = [MP42PreviewGenerator generatePreviewImagesQTKitFromChapters:chapters andFile:file];
    }

    return images;
}

+ (NSArray *)generatePreviewImagesQTKitFromChapters:(NSArray *)chapters andFile:(NSURL *)file {
    __block QTMovie *qtMovie;

    // QTMovie objects must always be create on the main thread.
    NSDictionary *movieAttributes = @{QTMovieURLAttribute: file,
                                      QTMovieAskUnresolvedDataRefsAttribute: @NO,
                                      @"QTMovieOpenForPlaybackAttribute": @YES,
                                      @"QTMovieOpenAsyncRequiredAttribute": @NO,
                                      @"QTMovieOpenAsyncOKAttribute": @NO,
                                      QTMovieApertureModeAttribute: QTMovieApertureModeClean};

    if (dispatch_get_current_queue() != dispatch_get_main_queue()) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            qtMovie = [[QTMovie alloc] initWithAttributes:movieAttributes error:nil];
        });
    } else {
        qtMovie = [[QTMovie alloc] initWithAttributes:movieAttributes error:nil];
    }

    if (!qtMovie) {
        return nil;
    }

    for (QTTrack *qtTrack in [qtMovie tracksOfMediaType:@"sbtl"]) {
        [qtTrack setAttribute:@NO forKey:QTTrackEnabledAttribute];
    }

    NSDictionary *attributes = [NSDictionary dictionaryWithObject:QTMovieFrameImageTypeNSImage forKey:QTMovieFrameImageType];
    NSMutableArray *images = [[NSMutableArray alloc] initWithCapacity:chapters.count];

    for (MP42TextSample *chapter in chapters) {
        QTTime chapterTime = {
            chapter.timestamp + 1500, // Add a short offset, hopefully we will get a better image
            1000,                     // if there is a fade
            0
        };

        NSImage *frame = [qtMovie frameImageAtTime:chapterTime withAttributes:attributes error:nil];

        if (frame) {
            [images addObject:frame];
        }
    }

    // Release the movie, we don't want to keep it open while we are writing in it using another library.
    // I am not sure if it is safe to release a QTMovie from a background thread, let's do it on the main just to be sure.
    if (dispatch_get_current_queue() != dispatch_get_main_queue()) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [qtMovie release];
        });
    } else {
        [qtMovie release];
    }

    return [images autorelease];
}

+ (NSArray *)generatePreviewImagesAVFoundationFromChapters:(NSArray *)chapters andFile:(NSURL *)file {
    NSMutableArray *images = [[NSMutableArray alloc] initWithCapacity:[chapters count]];

    // If we are on 10.7, use the AVFoundation path
#if __MAC_OS_X_VERSION_MAX_ALLOWED > 1060
    AVAsset *asset = [AVAsset assetWithURL:file];

    if ([asset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual]) {
        AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.apertureMode = AVAssetImageGeneratorApertureModeCleanAperture;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter  = kCMTimeZero;

        for (MP42TextSample * chapter in chapters) {
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
#endif
    
    return [images autorelease];
}

@end
