//
//  MP42Languages.h
//  Subler
//
//  Created by Damiano Galassi on 13/08/12.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct iso639_lang_t
{
    char * eng_name;        /* Description in English */
    char * native_name;     /* Description in native language */
    char * iso639_1;        /* ISO-639-1 (2 characters) code */
    char * iso639_2;        /* ISO-639-2/t (3 character) code */
    char * iso639_2b;       /* ISO-639-2/b code (if different from above) */
    short  qtLang;          /* QT Lang Code */
    
} iso639_lang_t;

#ifdef __cplusplus
extern "C" {
#endif
    /* find language associated with ISO-639-1 language code */
    iso639_lang_t * lang_for_code( int code );
    iso639_lang_t * lang_for_code_s( const char *code );
    
    /* find language associated with ISO-639-2 language code */
    iso639_lang_t * lang_for_code2( const char *code2 );

    /* find language associated with qt language code */
    iso639_lang_t * lang_for_qtcode( short code );
    
    /* ISO-639-1 code for language */
    int lang_to_code(const iso639_lang_t *lang);
    
    iso639_lang_t * lang_for_english( const char * english );
#ifdef __cplusplus
}
#endif

@interface MP42Languages : NSObject {
@private
    NSArray<NSString *> *_languagesArray;
    NSArray<NSString *> *_iso6391languagesArray;
}

+ (MP42Languages *)defaultManager;

/**
 *  Returns the complete languages list
 */
- (NSArray<NSString *> *)languages;

/**
 *  Returns the complete  ISO-639-1 language code list
 */
- (NSArray<NSString *> *)iso6391languages;

+ (nullable NSString *)iso6391CodeFor:(NSString *)aLanguage;

@end

NS_ASSUME_NONNULL_END
