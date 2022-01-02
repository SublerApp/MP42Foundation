//
//  MP42Heap.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 29/06/14.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import "MP42Heap.h"

static void swap(id *i, id *j) {
	id temp = *i;
	*i = *j;
	*j = temp;
}

static uint64 parent(uint64 i) {
    return (i + 1) / 2 - 1;
}

static uint64 left(uint64 i) {
    return i * 2 + 1;
}

static uint64 right(uint64 i) {
    return i * 2 + 2;
}

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42Heap {
@private
    id *_array;
    uint64 _size;
    uint64 _len;

    NSComparator _cmptr;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems comparator:(NSComparator)cmptr {
    self = [super init];
    if (self) {
        _size = numItems;
        _len = 0;
        _array = (id *)malloc(sizeof(id) * _size);
        _cmptr = Block_copy(cmptr);
    }
    return self;
}

- (void)insert:(id)item {
    NSAssert(_len < _size, @"Heap full");

    [item retain];
    _array[_len++] = item;

    uint64 i = _len - 1;

    while (i != 0 && _cmptr(_array[i], _array[parent(i)]) >= NSOrderedDescending) {
        swap(&_array[i], &_array[parent(i)]);
        i = parent(i);
    }

    return;
}

- (id)extract NS_RETURNS_RETAINED {
    if (!_len) {
        return nil;
    }

    id temp = _array[0];
    _array[0] = _array[--_len];
    [self heapify];
    return temp;
}

- (void)heapify {
    uint64 i = 0;

    while (1) {
        uint64 largest = i;
        uint64 l = left(i);
        uint64 r = right(i);

        if (l < _len && _cmptr(_array[l], _array[largest]) >= NSOrderedDescending) {
            largest = l;
        }
        if (r < _len && _cmptr(_array[r], _array[largest]) >= NSOrderedDescending) {
            largest = r;
        }

        if (largest != i) {
            swap(&_array[i], &_array[largest]);
            i = largest;
        } else {
            break;
        }
    }
}

- (NSInteger)count {
    return _len;
}

- (BOOL)isFull {
    return _len == _size;
}

- (BOOL)isEmpty {
    return _len == 0;
}

- (void)dealloc {
    free(_array);
    Block_release(_cmptr);
    [super dealloc];
}

@end
