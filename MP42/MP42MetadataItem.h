//
//  MP42MetadataItem.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 25/08/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MP42MetadataItemDataType) {
    MP42MetadataItemDataTypeString,
    MP42MetadataItemDataTypeBool,
    MP42MetadataItemDataTypeInteger,
    MP42MetadataItemDataTypeDate,
    MP42MetadataItemDataTypePlist,
    MP42MetadataItemDataTypeImage,
};

@interface MP42MetadataItem : NSObject

+ (instancetype)metadataItemWithIdentifier:(NSString *)identifier
                                     value:(id<NSObject, NSCopying>)value
                                  dataType:(MP42MetadataItemDataType)dataType
                       extendedLanguageTag:(nullable NSString *)extendedLanguageTag;

/* Indicates the identifier of the metadata item. Publicly defined identifiers are declared in AVMetadataIdentifiers.h. */
@property (nonatomic, readonly, copy) NSString *identifier;

/* provides the value of the metadata item */
@property (nonatomic, readonly, copy, nullable) id<NSObject, NSCopying> value;

/* indicates the data type of the metadata item's value. */
@property (nonatomic, readonly) MP42MetadataItemDataType dataType;

/* indicates the IETF BCP 47 (RFC 4646) language identifier of the metadata item; may be nil if no language tag information is available */
@property (nonatomic, readonly, copy, nullable) NSString *extendedLanguageTag;

@end

@interface MP42MetadataItem (MP42MetadataItemTypeCoercion)

/* provides the value of the metadata item as a string; will be nil if the value cannot be represented as a string */
@property (nonatomic, readonly, nullable) NSString *stringValue;

/* provides the value of the metadata item as an NSNumber. If the metadata item's value can't be coerced to a number, @"numberValue" will be nil. */
@property (nonatomic, readonly, nullable) NSNumber *numberValue;

/* provides the value of the metadata item as an NSDate. If the metadata item's value can't be coerced to a date, @"dateValue" will be nil. */
@property (nonatomic, readonly, nullable) NSDate *dateValue;

/* provides the raw bytes of the value of the metadata item */
@property (nonatomic, readonly, nullable) NSData *dataValue;

@end

NS_ASSUME_NONNULL_END
