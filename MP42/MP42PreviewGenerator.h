//
//  MP42PreviewGenerator.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 08/01/14.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MP42TextSample;

@interface MP42PreviewGenerator : NSObject

+ (NSArray<NSImage *> *)generatePreviewImagesFromChapters:(NSArray<MP42TextSample *> *)chapters fileURL:(NSURL *)url atPosition:(CGFloat)position;

@end

NS_ASSUME_NONNULL_END
