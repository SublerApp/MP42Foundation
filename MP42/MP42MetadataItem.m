//
//  MP42MetadataItem.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 25/08/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import "MP42MetadataItem.h"

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

- (NSData *)dataValue
{
    return nil;
}

@end
