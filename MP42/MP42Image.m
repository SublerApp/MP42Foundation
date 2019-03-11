//
//  MP42Image.m
//  Subler
//
//  Created by Damiano Galassi on 27/06/13.
//
//

#import "MP42Image.h"
#import <Quartz/Quartz.h>

@interface MP42Image ()

@property (atomic, readonly) NSString *uuid;

@end

@implementation MP42Image {
    NSImage *_image;
}

@synthesize url = _url;
@synthesize data = _data;
@synthesize type = _type;
@synthesize uuid = _uuid;

- (instancetype)initWithURL:(NSURL *)url type:(MP42TagArtworkType)type
{
    if (self = [super init]) {
        _url = url;
        _type = type;
    }

    return self;
}

- (instancetype)initWithImage:(NSImage *)image
{
    if (self = [super init])
        _image = [image copy];
    
    return self;
}

- (instancetype)initWithData:(NSData *)data type:(MP42TagArtworkType)type
{
    if (self = [super init]) {
        _data = [data copy];
        _type = type;
    }
    
    return self;
}

- (instancetype)initWithBytes:(const void*)bytes length:(NSUInteger)length type:(MP42TagArtworkType)type
{
    if (self = [super init]) {
        _data = [[NSData alloc] initWithBytes:bytes length:length];
        _type = type;
    }

    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    MP42Image *copy = nil;

    if (_data) {
        copy = [[MP42Image alloc] initWithData:[_data copy] type:_type];
    } else if (_image) {
        copy = [[MP42Image alloc] initWithImage:[_image copy]];
    } else if (_url) {
        copy = [[MP42Image alloc] initWithURL:[_url copy] type:_type];
    }

    return copy;
}

- (nullable NSImage *)imageFromData:(NSData *)data
{
    NSImage *image = nil;
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:data];
    if (imageRep != nil) {
        image = [[NSImage alloc] initWithSize:[imageRep size]];
        [image addRepresentation:imageRep];
    }

    return image;
}

- (NSData *)data {
    @synchronized(self) {
        if (_data) {
            return _data;
        } else if (_url) {
            NSError *outError = nil;
            _data = [NSData dataWithContentsOfURL:_url options:NSDataReadingUncached error:&outError];
        }
    }

    return _data;
}

- (NSImage *)image
{
    @synchronized(self) {
        if (_image)
            return _image;
        else if (self.data) {
            _image = [self imageFromData:_data];
        }
    }

    return _image;
}

- (NSString *)imageRepresentationType
{
    return IKImageBrowserNSImageRepresentationType;
}

- (NSString *)uuid
{
    @synchronized(self) {
        if (_uuid == nil) {
            _uuid = [[NSProcessInfo processInfo] globallyUniqueString];
        }
    }

    return _uuid;
}

- (NSString *)imageUID
{
    return self.uuid;
}

- (id)imageRepresentation
{
    return self.image;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_data) {
        [coder encodeObject:_data forKey:@"MP42Image_Data"];
    }
    else {
        [coder encodeObject:_image forKey:@"MP42Image"];
    }
    
    [coder encodeInteger:_type forKey:@"MP42ImageType"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    _image = [decoder decodeObjectOfClass:[NSImage class] forKey:@"MP42Image"];
    _data = [decoder decodeObjectOfClass:[NSData class] forKey:@"MP42Image_Data"];

    _type = [decoder decodeIntForKey:@"MP42ImageType"];

    return self;
}

@end
