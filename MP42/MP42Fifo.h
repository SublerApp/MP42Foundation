//
//  MP42Fifo.h
//  Subler
//
//  Created by Damiano Galassi on 09/08/13.
//
//

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"

NS_ASSUME_NONNULL_BEGIN

MP42_OBJC_DIRECT_MEMBERS
@interface MP42Fifo<__covariant ObjectType> : NSObject

- (instancetype)initWithCapacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;

- (void)enqueue:(ObjectType)item;
- (nullable ObjectType)dequeue NS_RETURNS_RETAINED;
- (nullable ObjectType)dequeueAndWait NS_RETURNS_RETAINED;

- (BOOL)isFull;
- (BOOL)isEmpty;

- (void)drain;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
