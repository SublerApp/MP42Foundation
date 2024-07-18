//
//  MP42Image.m
//  Subler
//
//  Created by Damiano Galassi on 27/06/13.
//
//

#import "MP42Image.h"
#import "MP42Utilities.h"

NSPasteboardType const MP42PasteboardTypeArtwork = @"org.subler.artworkdata";

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42Image {
    NSImage *_image;
}

@synthesize url = _url;
@synthesize data = _data;
@synthesize type = _type;

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
    if (self = [super init]) {
        _image = [image copy];
        _type = MP42_ART_PNG;
    }

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
        } else if (_image) {
            NSArray<NSImageRep *> *representations = _image.representations;
            if (representations.count) {
                _data = [NSBitmapImageRep representationOfImageRepsInArray:representations usingType:NSBitmapImageFileTypePNG properties:@{}];
            }
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

- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"<%@: %p> type: %d", [self class], self, _type];
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

- (instancetype)initWithPasteboardPropertyList:(id)propertyList
                                        ofType:(NSPasteboardType)type
{
    if ([type isEqualToString:MP42PasteboardTypeArtwork]) {
        return [NSKeyedUnarchiver unarchivedObjectOfClass:[MP42Image class] fromData:propertyList error:NULL];
    }

    return nil;
}

- (nullable id)pasteboardPropertyListForType:(nonnull NSPasteboardType)type
{
    if ([type isEqualToString:NSPasteboardTypeTIFF]) {
        NSArray<NSImageRep *> *representations = self.image.representations;
        if (representations) {
            return [NSBitmapImageRep representationOfImageRepsInArray:representations
                                                            usingType:NSBitmapImageFileTypeTIFF
                                                           properties:@{}];
        }
    }
    else if ([type isEqualToString:MP42PasteboardTypeArtwork]) {
        return [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:NULL];
    }

    return nil;
}

- (nonnull NSArray<NSPasteboardType> *)writableTypesForPasteboard:(nonnull NSPasteboard *)pasteboard
{
    return @[MP42PasteboardTypeArtwork, NSPasteboardTypeTIFF];
}

+ (nonnull NSArray<NSPasteboardType> *)readableTypesForPasteboard:(nonnull NSPasteboard *)pasteboard
{
    return @[MP42PasteboardTypeArtwork];
}

@end
