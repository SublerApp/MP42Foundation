//
//  MP42MetadataItem.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 25/08/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42MetadataItem.h"
#import "MP42Metadata.h"
#import "MP42Image.h"
#import "NSString+MP42Additions.h"
#import "MP42MetadataUtilities.h"
#import "MP42Utilities.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42MetadataItem

static NSDictionary<NSString *, NSNumber *> *_defaultTypes;
static NSDateFormatter *_formatter;
static NSDateFormatter *_partialFormatter;
static NSCalendar *_calendar;

+ (void)initialize
{
    if (self == [MP42MetadataItem class]) {
        _defaultTypes = @{ MP42MetadataKeyReleaseDate:         @(MP42MetadataItemDataTypeDate),
                           MP42MetadataKeyPurchasedDate:       @(MP42MetadataItemDataTypeString),
                           MP42MetadataKeyCoverArt:            @(MP42MetadataItemDataTypeImage),
                           MP42MetadataKeyCast:                @(MP42MetadataItemDataTypeStringArray),
                           MP42MetadataKeyDirector:            @(MP42MetadataItemDataTypeStringArray),
                           MP42MetadataKeyCodirector:          @(MP42MetadataItemDataTypeStringArray),
                           MP42MetadataKeyProducer:            @(MP42MetadataItemDataTypeStringArray),
                           MP42MetadataKeyScreenwriters:       @(MP42MetadataItemDataTypeStringArray),
                           MP42MetadataKeyTrackNumber:         @(MP42MetadataItemDataTypeIntegerArray),
                           MP42MetadataKeyDiscNumber:          @(MP42MetadataItemDataTypeIntegerArray),
                           MP42MetadataKeyBeatsPerMin:         @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyContentRating:       @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyMediaKind:           @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyHDVideo:             @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyTVEpisodeNumber:     @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyTVSeason:            @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyMovementNumber:      @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyMovementCount:       @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyArtistID:            @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyComposerID:          @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyContentID:           @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyGenreID:             @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyPlaylistID:          @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyAccountKind:         @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyAccountCountry:      @(MP42MetadataItemDataTypeInteger),
                           MP42MetadataKeyGapless:             @(MP42MetadataItemDataTypeBool),
                           MP42MetadataKeyiTunesU:             @(MP42MetadataItemDataTypeBool),
                           MP42MetadataKeyPodcast:             @(MP42MetadataItemDataTypeBool),
                           MP42MetadataKeyShowWorkAndMovement: @(MP42MetadataItemDataTypeBool),
                           MP42MetadataKeyDiscCompilation:     @(MP42MetadataItemDataTypeBool)};
    }

    NSTimeZone *gmt =  [NSTimeZone timeZoneForSecondsFromGMT:0];

    _formatter = [[NSDateFormatter alloc] init];
    _formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    _formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    _formatter.timeZone = gmt;

    _partialFormatter = [[NSDateFormatter alloc] init];
    _partialFormatter.dateFormat = @"yyyy-MM-dd";
    _partialFormatter.timeZone = gmt;

    _calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    _calendar.timeZone = gmt;

}

- (instancetype)initWithIdentifier:(NSString *)identifier
                             value:(id)value
                          dataType:(MP42MetadataItemDataType)dataType
               extendedLanguageTag:(NSString *)extendedLanguageTag
{
    self = [super init];
    if (self) 
    {
        _identifier = [identifier copy];
        _value = [value copy];
        _extendedLanguageTag = [extendedLanguageTag copy];

        if (dataType == MP42MetadataItemDataTypeUnspecified) {
            _dataType = [MP42MetadataItem defaultDataTypeForIdentifier:identifier];
            [self convertToType:_dataType];
        }
        else {
            _dataType = dataType;
        }
    }
    return self;
}

+ (instancetype)metadataItemWithIdentifier:(NSString *)identifier
                                     value:(id<NSObject, NSCopying>)value
                                   dataType:(MP42MetadataItemDataType)dataType
                       extendedLanguageTag:(NSString *)extendedLanguageTag
{
    return [[MP42MetadataItem alloc] initWithIdentifier:identifier value:value dataType:dataType extendedLanguageTag:extendedLanguageTag];
}

+ (MP42MetadataItemDataType)defaultDataTypeForIdentifier:(NSString *)identifier
{
    MP42MetadataItemDataType dataType = _defaultTypes[identifier].intValue;
    return dataType == 0 ? MP42MetadataItemDataTypeString : dataType;
}

- (void)convertToType:(MP42MetadataItemDataType)dataType
{
    if ([_value isKindOfClass:[NSString class]]) {
        [self convertStringToNativeValue];
    }
    else if ([_value isKindOfClass:[NSNumber class]]) {
        [self convertNumberToNativeValue];
    }
    else if ([_value isKindOfClass:[NSData class]]) {
        [self convertDataToNativeValue];
    }
}

- (void)convertStringToNativeValue
{
    NSString *stringValue = (NSString *)_value;
    switch (_dataType) {
        case MP42MetadataItemDataTypeString:
            break;
        case MP42MetadataItemDataTypeBool:
            _value = @(stringValue.boolValue);
            break;
        case MP42MetadataItemDataTypeInteger:
            _value = @(stringValue.integerValue);
            break;
        case MP42MetadataItemDataTypeDate:
            _value = [_formatter dateFromString:stringValue];
            if (!_value) {
                _value = [_partialFormatter dateFromString:stringValue];
                if (_value) {
                    NSDateComponents *components = [_calendar components:NSUIntegerMax fromDate:(NSDate *)_value];
                    components.hour = 12;
                    _value = [_calendar dateFromComponents:components];
                }
            }
            if (!_value) {
                _value = stringValue;
                _dataType = MP42MetadataItemDataTypeString;
            }
            break;
        case MP42MetadataItemDataTypeStringArray:
            _value = [self stringsArrayFromString:stringValue];
            break;
        case MP42MetadataItemDataTypeIntegerArray:
            _value = [self numbersArrayFromString:stringValue];
            break;
        default:
            NSAssert(NO, @"Unhandled conversion");
    }
}

- (void)convertNumberToNativeValue
{
    NSNumber *numberValue = (NSNumber *)_value;
    switch (_dataType) {
        case MP42MetadataItemDataTypeString:
            _value = numberValue.stringValue;
            break;
        case MP42MetadataItemDataTypeBool:
            _value = @(numberValue.boolValue);
            break;
        case MP42MetadataItemDataTypeInteger:
            break;
        case MP42MetadataItemDataTypeDate:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
            break;
        case MP42MetadataItemDataTypeStringArray:
            _value = @[numberValue.stringValue];
            break;
        case MP42MetadataItemDataTypeIntegerArray:
            _value = @[numberValue, @0];
            break;
        default:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
    }
}

- (void)convertDataToNativeValue
{
    NSData *dataValue = (NSData *)_value;
    switch (_dataType) {
        case MP42MetadataItemDataTypeString:
        {
            if (dataValue.length >= 2) {
                uint8_t *bytes = (uint8_t *)dataValue.bytes;
                int genre = ((bytes[0]) <<  8) | ((bytes[1]));
                _value = genreFromIndex(genre);
            }
            break;
        }
        case MP42MetadataItemDataTypeBool:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
            break;
        case MP42MetadataItemDataTypeInteger:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
            break;
        case MP42MetadataItemDataTypeDate:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
            break;
        case MP42MetadataItemDataTypeStringArray:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
            break;
        case MP42MetadataItemDataTypeIntegerArray:
        {
            if (dataValue.length >= 6) {
                uint8_t *bytes = (uint8_t *)dataValue.bytes;
                int index = ((bytes[2]) <<  8) | ((bytes[3]));
                int total = ((bytes[4]) <<  8) | ((bytes[5]));
                _value = @[@(index), @(total)];
            }
            break;
        }
        default:
            NSAssert(NO, @"Unhandled conversion");
            _value = nil;
    }
}

- (NSArray<NSString *> *)stringsArrayFromString:(NSString *)string
{
    NSString *splitElements  = @",\\s*+";
    NSArray *stringArray = [string MP42_componentsSeparatedByRegex:splitElements];

    NSMutableArray<NSString *> *arrayElements = [NSMutableArray array];

    for (NSString *element in stringArray) {
        [arrayElements addObject:element];
    }

    return arrayElements;
}

- (NSArray<NSNumber *> *)numbersArrayFromString:(NSString *)string
{
    int index = 0, count = 0;
    char separator[3];

    sscanf(string.UTF8String,"%u%[/- ]%u", &index, separator, &count);

    return @[@(index), @(count)];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt:1 forKey:@"MP42MetadataItemVersion"];

    [coder encodeObject:_identifier forKey:@"MP42Identifier"];
    [coder encodeObject:_value forKey:@"MP42Value"];
    [coder encodeInt64:_dataType forKey:@"MP42DataType"];
    [coder encodeObject:_extendedLanguageTag forKey:@"MP42LanguageTag"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];

    _identifier = [decoder decodeObjectOfClass:[NSString class] forKey:@"MP42Identifier"];
    _value = [decoder decodeObjectOfClasses:[NSSet setWithObjects:[NSString class], [NSDate class], [NSNumber class], [NSArray class], [MP42Image class], nil] forKey:@"MP42Value"];
    _dataType = [decoder decodeInt64ForKey:@"MP42DataType"];
    _extendedLanguageTag = [decoder decodeObjectOfClass:[NSString class] forKey:@"MP42LanguageTag"];

    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    MP42MetadataItem *copy = [[MP42MetadataItem allocWithZone:zone] init];

    copy->_identifier = [_identifier copy];
    copy->_value = [(id)_value copy];
    copy->_dataType = _dataType;
    copy->_extendedLanguageTag = [_extendedLanguageTag copy];

    return copy;
}

@end

@implementation MP42MetadataItem (MP42MetadataItemTypeCoercion)

- (NSString *)stringFromStringArray:(NSArray<NSString *> *)array
{
    NSMutableString *result = [NSMutableString string];

    for (NSString *text in array) {

        if (result.length) {
            [result appendString:@", "];
        }

        [result appendString:text];
    }

    return [result copy];
}

- (NSString *)stringFromIntegerArray:(NSArray<NSNumber *> *)array
{
    NSMutableString *result = [NSMutableString string];

    for (NSNumber *number in array) {

        if (result.length) {
            [result appendString:@"/"];
        }

        [result appendString:number.stringValue];
    }

    return [result copy];
}

- (NSString *)stringValue
{
    switch (_dataType) {
        case MP42MetadataItemDataTypeString:
            return (NSString *)_value;
        case MP42MetadataItemDataTypeBool:
        case MP42MetadataItemDataTypeInteger:
            return [(NSNumber *)_value stringValue];
        case MP42MetadataItemDataTypeDate:
            return [_formatter stringFromDate:(NSDate *)_value];
        case MP42MetadataItemDataTypeStringArray:
            return [self stringFromStringArray:(NSArray *)_value];
        case MP42MetadataItemDataTypeIntegerArray:
            return [self stringFromIntegerArray:(NSArray *)_value];
        default:
            return nil;
    }
}

- (NSNumber *)numberValue
{
    switch (_dataType) {
        case MP42MetadataItemDataTypeString:
            return @([(NSString *)_value integerValue]);
        case MP42MetadataItemDataTypeBool:
        case MP42MetadataItemDataTypeInteger:
            return (NSNumber *)_value;
        default:
            return nil;
    }
}

- (NSDate *)dateValue
{
    switch (_dataType) {
        case MP42MetadataItemDataTypeDate:
            return (NSDate *)_value;
        case MP42MetadataItemDataTypeString:
        {
            NSDate *date = [_formatter dateFromString:(NSString *)_value];
            if (!date) {
                date = [_partialFormatter dateFromString:(NSString *)_value];
            }
            return date;
        }

        default:
            return nil;
    }
}

- (NSArray *)arrayValue
{
    switch (_dataType) {
        case MP42MetadataItemDataTypeIntegerArray:
        case MP42MetadataItemDataTypeStringArray:
            return (NSArray *)_value;

        default:
            return nil;
    }
}

- (MP42Image *)imageValue
{
    switch (_dataType) {
        case MP42MetadataItemDataTypeImage:
            return (MP42Image *)_value;

        default:
            return nil;
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MP42MetadataItem: %@>", _value];
}

@end
