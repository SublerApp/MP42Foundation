//
//  SBHtmlParser.h
//  Subler
//
//  Created by Damiano Galassi on 13/06/13.
//
//

#import <Foundation/Foundation.h>
#import "MP42Utilities.h"

#define kStyleBold 1
#define kStyleItalic 2
#define kStyleUnderlined 4
#define kStyleColor 8

#define kTagOpen 1
#define kTagClose 2

typedef struct rgba_color {
    u_int8_t r;
    u_int8_t g;
    u_int8_t b;
    u_int8_t a;
} rgba_color;

rgba_color make_color(u_int8_t r, u_int8_t g, u_int8_t b, u_int8_t a);
int compare_color(rgba_color c1, rgba_color c2);

MP42_OBJC_DIRECT_MEMBERS
@interface MP42Style : NSObject<NSCopying>

- (instancetype)initWithStyle:(NSInteger)style type:(NSInteger)type location:(NSUInteger) location color:(rgba_color) color;

@property (nonatomic, readwrite) NSInteger style;
@property (nonatomic, readwrite) rgba_color color;
@property (nonatomic, readwrite) NSInteger type;
@property (nonatomic, readwrite) NSUInteger location;
@property (nonatomic, readwrite) NSUInteger length;

@end

MP42_OBJC_DIRECT_MEMBERS
@interface MP42HtmlParser : NSObject

@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSArray *styles;
@property (nonatomic, readwrite) rgba_color defaultColor;

- (instancetype)initWithString:(NSString *)string;
- (NSInteger) parseNextTag;
- (void)serializeStyles;

@end
