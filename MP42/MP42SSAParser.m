//
//  MP42SSAParser.m
//  SSA parser
//
//  Created by Damiano Galassi on 02/10/2017.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42SSAParser.h"

@interface MP42SSAStyle ()

- (instancetype)initWith:(NSArray<NSString *> *)style formats:(NSArray<NSString *> *)format;

@end

@implementation MP42SSAStyle

- (instancetype)initWith:(NSArray<NSString *> *)style formats:(NSArray<NSString *> *)format
{
    self = [super init];
    if (self) {
        NSUInteger stylesCount = style.count;
        NSUInteger formatsCount = format.count;

        for (NSUInteger index = 0; index < stylesCount && index < formatsCount; index += 1) {
            NSString *value = style[index];
            NSString *formatName = format[index];

            if ([formatName isEqualToString:@"Name"]) {
                _name = value;
            }
            else if ([formatName isEqualToString:@"Fontname"]) {
                _fontName = value;
            }
            else if ([formatName isEqualToString:@"Fontsize"]) {
                _fontSize = value.intValue;
            }
            else if ([formatName isEqualToString:@"PrimaryColour"]) {
                _primaryColour = value.intValue;
            }
            else if ([formatName isEqualToString:@"SecondaryColour"]) {
                _secondaryColour = value.intValue;
            }
            else if ([formatName isEqualToString:@"TertiaryColour"] ||
                     [formatName isEqualToString:@"OutlineColour"] ||
                     [formatName isEqualToString:@"OutlineColor"]) {
                _outlineColour = value.intValue;
            }
            else if ([formatName isEqualToString:@"BackColour"]) {
                _backColour = value.intValue;
            }
            else if ([formatName isEqualToString:@"Bold"]) {
                _bold = value.intValue > 0; // Hack
            }
            else if ([formatName isEqualToString:@"Italic"]) {
                _italic = value.intValue != 0;
            }
            else if ([formatName isEqualToString:@"Underline"]) {
                _underline = value.intValue != 0;
            }
            else if ([formatName isEqualToString:@"StrikeOut"]) {
                _strikeOut = value.intValue == -1 ? YES : NO;
            }
            else if ([formatName isEqualToString:@"ScaleX"]) {
                _scaleX = value.floatValue;
            }
            else if ([formatName isEqualToString:@"ScaleY"]) {
                _scaleY = value.floatValue;
            }
            else if ([formatName isEqualToString:@"Spacing"]) {
                _spacing = value.intValue;
            }
            else if ([formatName isEqualToString:@"Angle"]) {
                _angle = value.floatValue;
            }
            else if ([formatName isEqualToString:@"BorderStyle"]) {
                _borderStyle = value.intValue;
            }
            else if ([formatName isEqualToString:@"Outline"]) {
                _outline = value.intValue;
            }
            else if ([formatName isEqualToString:@"Shadow"]) {
                _shadow = value.intValue;
            }
            else if ([formatName isEqualToString:@"Alignment"]) {
                _alignment = value.intValue;
            }
            else if ([formatName isEqualToString:@"MarginL"]) {
                _marginL = value.intValue;
            }
            else if ([formatName isEqualToString:@"MarginR"]) {
                _marginR = value.intValue;
            }
            else if ([formatName isEqualToString:@"MarginV"]) {
                _marginV = value.intValue;
            }
            else if ([formatName isEqualToString:@"AlphaLevel"]) {
                _alphaLevel = value.intValue;
            }
            else if ([formatName isEqualToString:@"Encoding"]) {
                _encoding = value.intValue;
            }
        }

        if (_name == nil) {
            return nil;
        }
    }

    return self;
}

@end


@interface MP42SSALine ()

- (instancetype)initWithString:(NSString *)string format:(NSArray<NSString *> *)format styles:(NSDictionary<NSString *, MP42SSAStyle *> *)styles mkvStyle:(BOOL)mkvStyle;

@end

@implementation MP42SSALine

- (instancetype)initWithString:(NSString *)string format:(NSArray<NSString *> *)format styles:(NSDictionary<NSString *, MP42SSAStyle *> *)styles mkvStyle:(BOOL)mkvStyle
{
    self = [super init];
    if (self) {
        NSUInteger formatsCount = format.count;
        NSArray<NSString *> *values = parse(string, formatsCount, mkvStyle);
        NSUInteger valuesCount = values.count;

        for (NSUInteger index = 0; index < valuesCount && index < formatsCount; index += 1) {
            NSString *value = values[index];
            NSString *formatName = format[index];

            if ([formatName isEqualToString:@"Layer"]) {
                _layer = value.intValue;
            }
            else if ([formatName isEqualToString:@"Start"]) {
                _start = ParseSubTime(value.UTF8String, 1000, NO);
            }
            else if ([formatName isEqualToString:@"End"]) {
                _end = ParseSubTime(value.UTF8String, 1000, NO);
            }
            else if ([formatName isEqualToString:@"Style"]) {
                _style = styles[value];
            }
            else if ([formatName isEqualToString:@"Name"]) {
                _name = value;
            }
            else if ([formatName isEqualToString:@"MarginL"]) {
                _marginL = value.intValue;
            }
            else if ([formatName isEqualToString:@"MarginR"]) {
                _marginR = value.intValue;
            }
            else if ([formatName isEqualToString:@"MarginV"]) {
                _marginV = value.intValue;
            }
            else if ([formatName isEqualToString:@"Effect"]) {
                _effect = value;
            }
            else if ([formatName isEqualToString:@"Text"]) {
                _text = value;
            }
        }

        if (!_text) {
            return nil;
        } else {
            _text = [_text stringByReplacingOccurrencesOfString:@"\\h" withString:@" "];
        }
    }

    return self;
}

static NSArray<NSString *> * parse(NSString * string, NSUInteger count, BOOL mkvStyle)
{
    NSScanner *sc = [NSScanner scannerWithString:string];
    NSMutableArray<NSString *> *valuesArray = [NSMutableArray array];

    if (mkvStyle || [sc scanUpToString:@"Dialogue:" intoString:nil] || [sc scanString:@"Dialogue:" intoString:nil]) {
        [sc scanString:@"Dialogue:" intoString:nil];

        NSString *value;

        for (NSUInteger index = 0; index < count - 1; index += 1) {
            if ([sc scanUpToString:@"," intoString:&value]) {
                [valuesArray addObject:value];
            }
            else {
                [valuesArray addObject:@""];
            }
            [sc scanString:@"," intoString:nil];
        }
        
        // Trim '\0' from string end.
        NSUInteger index = string.length;
        unichar c;
        while (index > 0) {
            c = [string characterAtIndex:index - 1];
            if (c == '\0') {
                index--;
            }
            else {
                break;
            }
        }

        NSRange range = NSMakeRange(sc.scanLocation, index - sc.scanLocation);
        value = [sc.string substringWithRange:range];
        if (value) {
            [valuesArray addObject:value];
        }
    }

    return valuesArray;
}

static unsigned ParseSubTime(const char *time, unsigned secondScale, BOOL hasSign)
{
    unsigned hour, minute, second, subsecond, timeval;
    char separator[3];
    int sign = 1;

    if (hasSign && *time == '-') {
        sign = -1;
        time++;
    }

    if (sscanf(time, "%u:%u:%u%[,.:]%u", &hour, &minute, &second, separator, &subsecond) < 5) {
        subsecond = 0;
        if (sscanf(time, "%u:%u:%u", &hour, &minute, &second) < 3) {
            return 0;
        }
    }

    if (second > 60) {
        second = 0;
    }

    while (subsecond > secondScale) {
        subsecond /= 10;
    }

    timeval = hour * 60 * 60 + minute * 60 + second;
    timeval = secondScale * timeval + subsecond * 10;

    return timeval * sign;
}


@end

@interface MP42SSAParser ()

@property (nonatomic, readonly) NSString *info;

@property (nonatomic, readonly) NSArray<NSString *> *format;
@property (nonatomic, readonly) NSMutableArray<MP42SSALine *> *lines_internal;

@property (nonatomic, readonly) BOOL mkvStyle;

@end

@implementation MP42SSAParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        _styles = @{};
        _lines_internal = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithString:(NSString *)string
{
    NSParameterAssert(string);
    self = [self init];
    if (self) {
        string = STStandardizeStringNewlines(string);
        [self parse:string];
    }
    return self;
}

- (instancetype)initWithMKVHeader:(NSString *)header
{
    NSParameterAssert(header);
    self = [self init];
    if (self) {
        [self parseHeader:header];
        _format = @[@"ReadOrder", @"Layer", @"Style", @"Name", @"MarginL",@ "MarginR", @"MarginV", @"Effect", @"Text"];
        _mkvStyle = YES;
    }
    return self;
}

static NSMutableString *STStandardizeStringNewlines(NSString *str)
{
    if (str == nil) {
        return nil;
    }

    NSMutableString *ms = [NSMutableString stringWithString:str];
    [ms replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, ms.length)];
    [ms replaceOccurrencesOfString:@"\r" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, ms.length)];
    return ms;
}

- (void)parse:(NSString *)ssa
{
    [self parseHeader:ssa];
    [self parseLines:ssa];
}

#pragma mark - Header

- (void)parseHeader:(NSString *)header
{
    NSString *info;
    NSString *styles;
    NSString *format;

    NSScanner *sc = [NSScanner scannerWithString:header];
    [sc setCharactersToBeSkipped:nil];

    if ([sc scanUpToString:@"[V4+ Styles]" intoString:&info]) {
        _info = [self parseInfo:info];
    }

    if ([sc scanUpToString:@"[Events]" intoString:&styles]) {
        _styles = [self parseStyles:styles];
    }

    format = [sc.string substringFromIndex:sc.scanLocation];
    if (format.length) {
        _format = [self parseFormat:format];
    }
}

- (NSString *)parseInfo:(NSString *)info
{
    return info;
}

- (NSDictionary<NSString *, MP42SSAStyle *> *)parseStyles:(NSString *)stylesHeader
{
    NSScanner *sc = [NSScanner scannerWithString:stylesHeader];
    NSMutableArray<NSString *> *formatsArray = [NSMutableArray array];
    NSMutableDictionary<NSString *, MP42SSAStyle *> *stylesDict = [NSMutableDictionary dictionary];

    if ([sc scanUpToString:@"Format:" intoString:nil] || [sc scanString:@"Format:" intoString:nil]) {
        [sc scanString:@"Format:" intoString:nil];
        NSString *formats;
        if ([sc scanUpToString:@"\n" intoString:&formats]) {
            NSScanner *formatScanner = [NSScanner scannerWithString:formats];
            NSString *formatName;
            while ([formatScanner scanUpToString:@"," intoString:&formatName]) {
                [formatScanner scanString:@"," intoString:nil];
                [formatsArray addObject:formatName];
            }
        }
    }

    while ([sc scanUpToString:@"Style:" intoString:nil] || [sc scanString:@"Style:" intoString:nil]) {
        [sc scanString:@"Style:" intoString:nil];
        NSString *styles;
        if ([sc scanUpToString:@"\n" intoString:&styles]) {
            NSMutableArray<NSString *> *stylesValueArray = [NSMutableArray array];

            NSScanner *stylesScanner = [NSScanner scannerWithString:styles];
            NSString *styleValue;
            while ([stylesScanner scanUpToString:@"," intoString:&styleValue]) {
                [stylesScanner scanString:@"," intoString:nil];
                [stylesValueArray addObject:styleValue];
            }

            MP42SSAStyle *style = [[MP42SSAStyle alloc] initWith:stylesValueArray formats:formatsArray];
            if (style) {
                stylesDict[style.name] = style;
            }
        }
    }

    return stylesDict;
}

- (NSArray<NSString *> *)parseFormat:(NSString *)format
{
    NSScanner *sc = [NSScanner scannerWithString:format];
    NSMutableArray<NSString *> *formatsArray = [NSMutableArray array];

    if ([sc scanUpToString:@"Format:" intoString:nil] || [sc scanString:@"Format:" intoString:nil]) {
        [sc scanString:@"Format:" intoString:nil];
        NSString *formats;
        if ([sc scanUpToString:@"\n" intoString:&formats]) {
            NSScanner *formatScanner = [NSScanner scannerWithString:formats];
            NSString *formatName;
            while ([formatScanner scanUpToString:@"," intoString:&formatName]) {
                [formatScanner scanString:@"," intoString:nil];
                [formatsArray addObject:formatName];
            }
        }
    }

    return formatsArray;
}

- (void)parseLines:(NSString *)lines
{
    NSScanner *sc = [NSScanner scannerWithString:lines];
    NSMutableArray<MP42SSALine *> *linesArray = [NSMutableArray array];

    [sc scanUpToString:@"[Events]" intoString:nil];
    [sc scanUpToString:@"Dialogue: " intoString:nil];

    NSString *lineString;

    while ([sc scanUpToString:@"\n" intoString:&lineString]) {
        MP42SSALine *line = [[MP42SSALine alloc] initWithString:lineString format:_format styles:_styles mkvStyle:NO];
        if (line) {
            [linesArray addObject:line];
            unsigned end = line.end;
            if (end > _duration) {
                _duration = end;
            }
        }
    }

    _lines_internal = linesArray;
}

#pragma mark - Line

- (NSArray<MP42SSALine *> *)lines {
    return [_lines_internal copy];
}

- (MP42SSALine *)addLine:(NSString *)lineString
{
    MP42SSALine *line = [[MP42SSALine alloc] initWithString:lineString format:_format styles:_styles mkvStyle:_mkvStyle];
    if (line) {
        [_lines_internal addObject:line];
    }
    return line;
}

@end
