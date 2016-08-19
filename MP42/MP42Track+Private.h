//
//  MP42Track+Private.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 19/09/15.
//  Copyright © 2015 Damiano Galassi. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface MP42Track (Private)

- (instancetype)initWithMediaType:(MP42MediaType)mediaType;
- (instancetype)initWithSourceURL:(NSURL *)URL trackID:(NSInteger)trackID fileHandle:(MP42FileHandle)fileHandle;
- (BOOL)writeToFile:(MP42FileHandle)fileHandle error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
