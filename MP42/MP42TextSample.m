//
//  SBTextSample.m
//  MP42
//
//  Created by Damiano Galassi on 01/11/13.
//  Copyright (c) 2013 Damiano Galassi. All rights reserved.
//

#import "MP42TextSample.h"

@implementation MP42TextSample {
@private
    MP42Duration _timestamp;
    MP42Image *_image;
    NSString *_title;
}

- (NSComparisonResult)compare:(MP42TextSample *)otherObject
{
    MP42Duration otherTimestamp = otherObject.timestamp;

    if (_timestamp < otherTimestamp)
        return NSOrderedAscending;
    else if (_timestamp > otherTimestamp)
        return NSOrderedDescending;

    return NSOrderedSame;
}

- (void)dealloc
{
    [_image release];
    [_title release];
    [super dealloc];
}

@synthesize timestamp = _timestamp;
@synthesize title = _title;
@synthesize image = _image;

- (void)setTitle:(NSString *)title
{
    if (title == nil) {
        _title = @"";
    } else {
        _title = [title copy];
    }
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
    _title = [[decoder decodeObjectForKey:@"title"] retain];

    return self;
}

@end
