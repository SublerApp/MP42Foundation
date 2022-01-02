//
//  SBTextSample.m
//  MP42
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2022 Damiano Galassi. All rights reserved.
//

#import "MP42TextSample.h"
#import "MP42Utilities.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42TextSample

- (NSComparisonResult)compare:(MP42TextSample *)otherObject
{
    MP42Duration otherTimestamp = otherObject.timestamp;

    if (_timestamp < otherTimestamp)
        return NSOrderedAscending;
    else if (_timestamp > otherTimestamp)
        return NSOrderedDescending;

    return NSOrderedSame;
}

- (void)setTitle:(NSString *)title
{
    if (title == nil) {
        _title = @"";
    } else {
        _title = [title copy];
    }
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt64:_timestamp forKey:@"timestamp"];
    [coder encodeObject:_title forKey:@"title"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    _timestamp = [decoder decodeInt64ForKey:@"timestamp"];
    _title = [decoder decodeObjectOfClass:[NSString class] forKey:@"title"];

    return self;
}

@end
