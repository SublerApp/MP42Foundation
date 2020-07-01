//
//  MP42Fifo.m
//  Subler
//
//  Created by Damiano Galassi on 09/08/13.
//
//

#import "MP42Fifo.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42Fifo {
@private
    id *_array;

    int32_t     _head;
    int32_t     _tail;

    int32_t     _size;
    _Atomic int32_t     _count;

    _Atomic int32_t     _cancelled;

    dispatch_semaphore_t _full;
    dispatch_semaphore_t _empty;

    dispatch_queue_t _queue;
}

- (instancetype)init {
    self = [self initWithCapacity:300];
    return self;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _size = (int32_t)capacity;
        _array = (id *) malloc(sizeof(id) * _size);
        _full = dispatch_semaphore_create(_size - 1);
        _empty = dispatch_semaphore_create(0);
        _queue = dispatch_queue_create("org.subler.FifoQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)enqueue:(id)item {
    if (_cancelled) return;

    [item retain];

    dispatch_semaphore_wait(_full, DISPATCH_TIME_FOREVER);

    dispatch_sync(_queue, ^{
        _array[_tail++] = item;
    });

    if (_tail == _size) {
        _tail = 0;
    }

    _count++;
    dispatch_semaphore_signal(_empty);
}

- (nullable id)dequeue NS_RETURNS_RETAINED {
    if (!_count) return nil;

    __block id item = nil;

    dispatch_sync(_queue, ^{
        item = _array[_head++];
    });

    if (_head == _size) {
        _head = 0;
    }

    _count--;
    dispatch_semaphore_signal(_full);

    return item;
}

- (nullable id)dequeueAndWait NS_RETURNS_RETAINED {
    id item = [self dequeue];

    while (!item) {
        dispatch_semaphore_wait(_empty, DISPATCH_TIME_FOREVER);
        item = [self dequeue];
    }

    return item;
}

- (NSUInteger)count {
    return _count;
}

- (BOOL)isFull {
    return (_count >= _size);
}

- (BOOL)isEmpty {
    return !_count;
}

- (void)drain {
    id item;
    while ((item = [self dequeue])) {
        [item release];
    }
}

- (void)cancel {
    _cancelled = 1;
    [self drain];
}

- (void)dealloc {
    [self drain];

	free(_array);
    dispatch_release(_full);
    dispatch_release(_empty);
    dispatch_release(_queue);

    [super dealloc];
}

@end
