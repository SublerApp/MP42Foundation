//
//  MP42Ratings.h
//  Subler
//
//  Created by Douglas Stebila on 2013-06-02.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MP42Ratings : NSObject {
@private
	NSMutableArray *ratingsDictionary;
	NSMutableArray<NSString *> *ratings;
	NSMutableArray<NSString *> *iTunesCodes;
}

@property (atomic, readonly) NSArray<NSString *> *ratings;
@property (atomic, readonly) NSArray<NSString *> *iTunesCodes;

+ (MP42Ratings *)defaultManager;

- (void)updateRatingsCountry;
- (NSArray<NSString *> *) ratingsCountries;

- (NSUInteger) unknownIndex;
- (NSUInteger) ratingIndexForiTunesCode:(NSString *)aiTunesCode;
- (NSUInteger) ratingIndexForiTunesCountry:(NSString *)aCountry media:(NSString *)aMedia ratingString:(NSString *)aRatingString;

@end

NS_ASSUME_NONNULL_END
