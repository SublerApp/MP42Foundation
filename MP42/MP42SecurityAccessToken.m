//
//  SBSecurityAccessToken.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 10/03/2019.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42SecurityAccessToken.h"
#import <MP42Foundation/MP42Utilities.h>

MP42_OBJC_DIRECT_MEMBERS
@interface MP42SecurityAccessToken ()
@property (nonatomic, readonly) id<MP42SecurityScope> object;
@property (nonatomic, readonly) BOOL accessed;
@end

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42SecurityAccessToken

- (instancetype)initWithObject:(id<MP42SecurityScope>)object
{
    self = [super init];
    if (self) {
        _object = object;
        _accessed = [_object startAccessingSecurityScopedResource];
    }
    return self;
}

+ (instancetype)tokenWithObject:(id<MP42SecurityScope>)object
{
    return [[MP42SecurityAccessToken alloc] initWithObject:object];
}

- (void)dealloc
{
    if (_accessed) {
        [_object stopAccessingSecurityScopedResource];
    }
}

+ (nullable NSURL *)URLFromBookmark:(NSData *)bookmark bookmarkDataIsStale:(BOOL * _Nullable)isStale error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(bookmark);

    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil bookmarkDataIsStale:isStale error:error];

    return url;
}

+ (nullable NSData *)bookmarkFromURL:(NSURL *)url options:(NSURLBookmarkCreationOptions)options error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(url);

    NSData *bookmark = [url bookmarkDataWithOptions:options includingResourceValuesForKeys:nil relativeToURL:nil error:error];

    return bookmark;
}

+ (nullable NSData *)bookmarkFromURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
    return [MP42SecurityAccessToken bookmarkFromURL:url options:NSURLBookmarkCreationWithSecurityScope error:error];
}


@end
