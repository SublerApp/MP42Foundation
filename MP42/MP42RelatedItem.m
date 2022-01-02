//
//  MP42RelatedItem.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 09/03/2019.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42RelatedItem.h"

@interface MP42RelatedItem ()

@property (nonatomic, readonly) NSOperationQueue *queue;
@property (nonatomic, readonly) dispatch_queue_t dispatch_queue;

@end

@implementation MP42RelatedItem

- (instancetype)initWithURL:(NSURL *)URL extension:(NSString *)extension
{
    self = [super init];
    if (self) {
        _URL = URL;
        _extension = extension;
        _queue = [[NSOperationQueue alloc] init];
        _dispatch_queue = dispatch_queue_create("org.mp42foundation.relatedItem", DISPATCH_QUEUE_SERIAL);
        _queue.underlyingQueue = _dispatch_queue;
    }
    return self;
}

- (NSURL *)presentedItemURL
{
    return [self.URL.URLByDeletingPathExtension URLByAppendingPathExtension:self.extension];
}

- (NSURL *)primaryPresentedItemURL
{
    return self.URL;
}

- (NSOperationQueue *)presentedItemOperationQueue
{
    return self.queue;
}

@end
