//
//  MP42Heap.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2014 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  A simple heap/priority queue implementations with a static size.
 *  It takes a NSComparator in input.
 */
@interface MP42Heap : NSObject {
@private
    id *_array;
    uint64 _size;
    uint64 _len;

    NSComparator _cmptr;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems andComparator:(NSComparator)cmptr;

- (void)insert:(id)item;
- (id)extract NS_RETURNS_RETAINED; 

- (NSInteger)count;

- (BOOL)isFull;
- (BOOL)isEmpty;

@end
