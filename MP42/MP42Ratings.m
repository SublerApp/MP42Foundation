//
//  MP42Ratings.m
//  Subler
//
//  Created by Douglas Stebila on 2013-06-02.
//
//

#import "MP42Ratings.h"

@implementation MP42Ratings {
@private
    NSMutableArray *ratingsDictionary;
    NSMutableArray<NSString *> *ratings;
    NSMutableArray<NSString *> *iTunesCodes;
}

@synthesize ratings;
@synthesize iTunesCodes;

+ (MP42Ratings *) defaultManager {
    static dispatch_once_t sharedRatingsPred;
    static MP42Ratings *sharedRatingsManager = nil;
    dispatch_once(&sharedRatingsPred, ^{ sharedRatingsManager = [[self alloc] init]; });
    return sharedRatingsManager;
}

- (instancetype) init {
	if (self = [super init]) {
		NSString *ratingsJSON = [[NSBundle bundleForClass:[MP42Ratings class]] pathForResource:@"Ratings" ofType:@"json"];
        if (!ratingsJSON) {
            [self release];
            return nil;
        }

        NSData *data = [NSData dataWithContentsOfFile:ratingsJSON];

        if (data) {
            ratingsDictionary = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] retain];
        } else {
            ratingsDictionary = [[NSMutableArray alloc] init];
        }

		// construct movie ratings
		ratings = [[NSMutableArray alloc] init];
		iTunesCodes = [[NSMutableArray alloc] init];

		// if a specific country is picked, include the USA ratings at the end
        NSString *selectedCountry = [[NSUserDefaults standardUserDefaults] valueForKey:@"SBRatingsCountry"];
		NSDictionary *usaRatings = nil;

		for (NSDictionary *countryRatings in ratingsDictionary) {
			NSString *countryName = [countryRatings valueForKey:@"country"];

			if ([countryName isEqualToString:@"USA"]) {
				usaRatings = countryRatings;
			}

			if (![selectedCountry isEqualToString:@"All countries"]) {
				if (![countryName isEqualToString:@"Unknown"] && ![countryName isEqualToString:selectedCountry]) {
					continue;
				}
																								
			}

			for (NSDictionary *rating in [countryRatings valueForKey:@"ratings"]) {
				[ratings addObject:[NSString stringWithFormat:@"%@ %@: %@", countryName, [rating valueForKey:@"media"], [rating valueForKey:@"description"]]];
				[iTunesCodes addObject:[NSString stringWithFormat:@"%@|%@|%@|", [rating valueForKey:@"prefix"], [rating valueForKey:@"itunes-code"], [rating valueForKey:@"itunes-value"]]];
			}
		}

		if (![selectedCountry isEqualToString:@"All countries"] && ![selectedCountry isEqualToString:@"USA"]) {
            if (usaRatings) {
                for (NSDictionary *rating in [usaRatings valueForKey:@"ratings"]) {
                    [ratings addObject:[NSString stringWithFormat:@"%@ %@: %@", @"USA", [rating valueForKey:@"media"], [rating valueForKey:@"description"]]];
                    [iTunesCodes addObject:[NSString stringWithFormat:@"%@|%@|%@|", [rating valueForKey:@"prefix"], [rating valueForKey:@"itunes-code"], [rating valueForKey:@"itunes-value"]]];
                }
            }
		}
	}
	return self;
}

- (NSArray *) ratingsCountries {
	NSMutableArray *countries = [[NSMutableArray alloc] init];
	for (NSDictionary *countryRatings in ratingsDictionary) {
		NSString *countryName = [countryRatings valueForKey:@"country"];
		if ([countryName isEqualToString:@"Unknown"]) {
			[countries addObject:@"All countries"];
		} else {
			[countries addObject:countryName];
		}
	}
	return [countries autorelease];
}

- (void)updateRatingsCountry {
	[ratings release];
	[iTunesCodes release];
	[self init];
}

- (NSArray *) ratings {
	return [NSArray arrayWithArray:ratings];
}

- (NSArray *) iTunesCodes {
    return [NSArray arrayWithArray:iTunesCodes];
}

- (NSUInteger) unknownIndex {
	return 0;
}

- (NSUInteger) ratingIndexForiTunesCode:(NSString *)aiTunesCode {
    NSUInteger i = 0;

    for (NSString *code in iTunesCodes) {
        if ([code isEqualToString:aiTunesCode]) {
            return i;
        }
        i++;
    }

	return [self unknownIndex];
}

- (NSUInteger) ratingIndexForiTunesCountry:(NSString *)aCountry media:(NSString *)aMedia ratingString:(NSString *)aRatingString {
	NSString *target1 = [[NSString stringWithFormat:@"%@ %@: %@", aCountry, aMedia, aRatingString] lowercaseString];
	NSString *target2 = [[NSString stringWithFormat:@"%@ %@: %@", aCountry, @"movie & TV", aRatingString] lowercaseString];
	for (NSUInteger i = 0; i < [ratings count]; i++) {
		if ([[[ratings objectAtIndex:i] lowercaseString] isEqualToString:target1] || [[[ratings objectAtIndex:i] lowercaseString] isEqualToString:target2]) {
			return i;
		}
	}

	if (aRatingString != nil) {
		NSLog(@"Unknown rating information: %@", target1);
    }

	for (NSDictionary *countryRatings in ratingsDictionary) {
		if ([[countryRatings valueForKey:@"country"] isEqualToString:aCountry]) {
			for (NSDictionary *rating in [countryRatings valueForKey:@"ratings"]) {
				if ([[rating valueForKey:@"itunes-value"] isEqualToString:@"???"]) {
					return [self ratingIndexForiTunesCode:[NSString stringWithFormat:@"%@|%@|%@|", [rating valueForKey:@"prefix"], [rating valueForKey:@"itunes-code"], [rating valueForKey:@"itunes-value"]]];
				}
			}
		}
	}

	return [self unknownIndex];
}

- (NSString *) ratingStringForiTunesCountry:(NSString *)aCountry media:(NSString *)aMedia ratingString:(NSString *)aRatingString {
    return iTunesCodes[[self ratingIndexForiTunesCountry:aCountry media:aMedia ratingString:aRatingString]];
}

@end
