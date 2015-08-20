//
//  MP42Fifo.h
//  Subler
//
//  Created by Damiano Galassi on 09/08/13.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MP42Fifo : NSObject {
@private
    id *_array;

    int32_t     _head;
    int32_t     _tail;

    int32_t     _count;
    int32_t     _size;

    int32_t     _cancelled;

    dispatch_semaphore_t _full;
    dispatch_semaphore_t _empty;
}

- (instancetype)init;
- (instancetype)initWithCapacity:(NSUInteger)numItems;

- (void)enqueue:(id)item;
- (nullable id)deque NS_RETURNS_RETAINED;
- (nullable id)dequeAndWait NS_RETURNS_RETAINED;

- (NSInteger)count;

- (BOOL)isFull;
- (BOOL)isEmpty;

- (void)drain;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
