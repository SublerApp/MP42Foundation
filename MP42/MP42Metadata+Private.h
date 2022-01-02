//
//  MP42Metadata+Private.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 19/09/15.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface MP42Metadata (Private)

- (instancetype)initWithFileHandle:(MP42FileHandle)fileHandle;
- (void)writeMetadataWithFileHandle:(MP42FileHandle)fileHandle;

@end

NS_ASSUME_NONNULL_END
