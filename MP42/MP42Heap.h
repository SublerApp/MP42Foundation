//
//  MP42Heap.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  A simple heap/priority queue implementations with a static size.
 *  It takes a NSComparator in input.
 */
MP42_OBJC_DIRECT_MEMBERS
@interface MP42Heap<ObjectType> : NSObject

- (instancetype)initWithCapacity:(NSUInteger)numItems comparator:(NSComparator)cmptr;

- (void)insert:(ObjectType)item;
- (nullable ObjectType)extract NS_RETURNS_RETAINED;

- (NSInteger)count;

- (BOOL)isFull;
- (BOOL)isEmpty;

@end

NS_ASSUME_NONNULL_END
