//
//  MP42Image.h
//  Subler
//
//  Created by Damiano Galassi on 27/06/13.
//
//

#import <Foundation/Foundation.h>

@class NSImage;

typedef enum MP42TagArtworkType_e {
    MP42_ART_UNDEFINED = 0,
    MP42_ART_BMP       = 1,
    MP42_ART_GIF       = 2,
    MP42_ART_JPEG      = 3,
    MP42_ART_PNG       = 4
} MP42TagArtworkType;

@interface MP42Image : NSObject <NSSecureCoding, NSCopying>

- (instancetype)initWithURL:(NSURL *)url type:(MP42TagArtworkType)type;
- (instancetype)initWithImage:(NSImage *)image;
- (instancetype)initWithData:(NSData *)data type:(MP42TagArtworkType)type;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length type:(MP42TagArtworkType)type;

@property(atomic, readonly) NSImage *image;
@property(atomic, readonly) NSURL *url;
@property(atomic, readonly) NSData *data;
@property(atomic, readonly) MP42TagArtworkType type;

@end
