//
//  MP42MetadataItem.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 25/08/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import "MP42MetadataItem.h"
#import "MP42Metadata.h"
#import "MP42Image.h"

@implementation MP42MetadataItem

#import <CoreMedia/CMMetadata.h>

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
        _dataType = dataType;
    }
    return self;
}

+ (instancetype)metadataItemWithIdentifier:(NSString *)identifier
                                     value:(id<NSObject, NSCopying>)value
                                   dataType:(MP42MetadataItemDataType)dataType
                       extendedLanguageTag:(NSString *)extendedLanguageTag
{
    return [[self alloc] initWithIdentifier:identifier value:value dataType:dataType extendedLanguageTag:extendedLanguageTag];
}

@end

@implementation MP42MetadataItem (MP42MetadataItemTypeCoercion)

- (NSString *)stringFromStringArray:(NSArray<NSString *> *)array {
    NSMutableString *result = [NSMutableString string];

    for (NSString *text in array) {

        if (result.length) {
            [result appendString:@", "];
        }

        [result appendString:text];
    }

    return [result copy];
}

- (NSString *)stringFromIntegerArray:(NSArray<NSNumber *> *)array {
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
        {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            return  [formatter stringFromDate:(NSDate *)_value];
        }
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

- (NSData *)dataValue
{
    return nil;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MP42MetadataItem: %@>", _value];
}

@end
