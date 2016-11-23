//
//  MP42Languages.h
//  Subler
//
//  Created by Damiano Galassi on 13/08/12.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MP42Languages : NSObject

@property (class, readonly) MP42Languages *defaultManager;

+ (nullable NSString *)ISO_639_1CodeForLang:(NSString *)language;
+ (NSString *)langForISO_639_1Code:(NSString *)language;

+ (NSString *)ISO_639_2CodeForLang:(NSString *)language;
+ (NSString *)langForISO_639_2Code:(NSString *)code;

+ (NSString *)ISO_639_2CodeForISO_639_1:(NSString *)code;
+ (NSString *)ISO_639_2CodeForQTCode:(NSString *)code;

/**
 *  Returns the complete languages list
 */
- (NSArray<NSString *> *)languages;

/**
 *  Returns the complete languages list in the current locale
 */
- (NSArray<NSString *> *)localizedLanguages;

/**
 *  Returns the complete ISO-639-1 language code list
 */
- (NSArray<NSString *> *)ISO_639_1Languages;


- (NSString *)ISO_639_2CodeForLocalizedLang:(NSString *)language;
- (NSString *)localizedLangForISO_639_2Code:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
