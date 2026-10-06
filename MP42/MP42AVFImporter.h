//
//  MP42AVFmporter.h
//  Subler
//
//  Created by Damiano Galassi on 31/01/10.
//  Copyright 2022 Damiano Galassi All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42FileImporter.h"

@interface MP42AVFImporter : MP42FileImporter

- (nullable instancetype)initWithURL:(NSURL * _Nonnull)fileURL
                     progressHandler:(nullable MP42FileImporterProgressHandler)progressHandler
                               error:(NSError * _Nullable * _Nullable)error;

@end

