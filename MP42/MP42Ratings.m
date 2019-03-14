//
//  MP42Ratings.m
//  Subler
//
//  Created by Douglas Stebila on 2013-06-02.
//
//

#import "MP42Ratings.h"

@implementation MP42Ratings {
    NSMutableArray *ratingsDictionary;
    NSMutableArray<NSString *> *ratings;
    NSMutableArray<NSString *> *iTunesCodes;
}

+ (MP42Ratings *)defaultManager {
    static dispatch_once_t sharedRatingsPred;
    static MP42Ratings *sharedRatingsManager = nil;
    dispatch_once(&sharedRatingsPred, ^{ sharedRatingsManager = [[self alloc] init]; });
    return sharedRatingsManager;
}

- (instancetype)init
{
    self = [super init];
	if (self) {
		NSString *ratingsJSON = [[NSBundle bundleForClass:[MP42Ratings class]] pathForResource:@"Ratings" ofType:@"json"];
        if (!ratingsJSON) {
            return nil;
        }

        NSData *data = [NSData dataWithContentsOfFile:ratingsJSON];

        if (data) {
            ratingsDictionary = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        } else {
            ratingsDictionary = [[NSMutableArray alloc] init];
        }

        [self updateRatingsCountry];
	}
	return self;
}

- (NSArray *)ratingsCountries {
	NSMutableArray *countries = [[NSMutableArray alloc] init];
	for (NSDictionary *countryRatings in ratingsDictionary) {
		NSString *countryName = countryRatings[@"country"];
		if ([countryName isEqualToString:@"Unknown"]) {
			[countries addObject:@"All countries"];
		} else {
			[countries addObject:countryName];
		}
	}
	return countries;
}

- (void)updateRatingsCountry {
    // construct movie ratings
    ratings = [[NSMutableArray alloc] init];
    iTunesCodes = [[NSMutableArray alloc] init];

    // if a specific country is picked, include the USA ratings at the end
    NSString *selectedCountry = [[NSUserDefaults standardUserDefaults] stringForKey:@"SBRatingsCountry"];
    NSDictionary<NSString *, NSDictionary *> *usaRatings = nil;

    for (NSDictionary *countryRatings in ratingsDictionary) {
        NSString *countryName = countryRatings[@"country"];

        if ([countryName isEqualToString:@"USA"]) {
            usaRatings = countryRatings;
        }

        if (![selectedCountry isEqualToString:@"All countries"]) {
            if (![countryName isEqualToString:@"Unknown"] && ![countryName isEqualToString:selectedCountry]) {
                continue;
            }

        }

        for (NSDictionary *rating in countryRatings[@"ratings"]) {
            [ratings addObject:[NSString stringWithFormat:@"%@ %@: %@", countryName, rating[@"media"], rating[@"description"]]];
            [iTunesCodes addObject:[NSString stringWithFormat:@"%@|%@|%@|", rating[@"prefix"], rating[@"itunes-code"], rating[@"itunes-value"]]];
        }
    }

    if (![selectedCountry isEqualToString:@"All countries"] && ![selectedCountry isEqualToString:@"USA"]) {
        if (usaRatings) {
            for (NSDictionary *rating in usaRatings[@"ratings"]) {
                [ratings addObject:[NSString stringWithFormat:@"%@ %@: %@", @"USA", rating[@"media"], rating[@"description"]]];
                [iTunesCodes addObject:[NSString stringWithFormat:@"%@|%@|%@|", rating[@"prefix"], rating[@"itunes-code"], rating[@"itunes-value"]]];
            }
        }
    }
}

- (NSArray<NSString *> *)ratings {
	return [NSArray arrayWithArray:ratings];
}

- (NSArray<NSString *> *)iTunesCodes {
    return [NSArray arrayWithArray:iTunesCodes];
}

- (NSInteger)ratingIndexForiTunesCode:(NSString *)aiTunesCode {
    NSInteger i = 0;

    for (NSString *code in iTunesCodes) {
        if ([code isEqualToString:aiTunesCode]) {
            return i;
        }
        i++;
    }

	return -1;
}

- (NSInteger)ratingIndexForiTunesCountry:(NSString *)aCountry media:(NSString *)aMedia ratingString:(NSString *)aRatingString {
	NSString *target1 = [[NSString stringWithFormat:@"%@ %@: %@", aCountry, aMedia, aRatingString] lowercaseString];
	NSString *target2 = [[NSString stringWithFormat:@"%@ %@: %@", aCountry, @"movie & TV", aRatingString] lowercaseString];

    NSInteger i = 0;
    for (NSString *iTunesRating in ratings) {
        NSString *lowerCaseRating = iTunesRating.lowercaseString;

        if ([lowerCaseRating isEqualToString:target1] || [lowerCaseRating isEqualToString:target2]) {
            return i;
        }
        else {
            i += 1;
        }
    }

	if (aRatingString != nil) {
		NSLog(@"Unknown rating information: %@", target1);
    }

	for (NSDictionary *countryRatings in ratingsDictionary) {
		if ([countryRatings[@"country"] isEqualToString:aCountry]) {
			for (NSDictionary *rating in countryRatings[@"ratings"]) {
				if ([rating[@"itunes-value"] isEqualToString:@"???"]) {
					return [self ratingIndexForiTunesCode:[NSString stringWithFormat:@"%@|%@|%@|", rating[@"prefix"], rating[@"itunes-code"], rating[@"itunes-value"]]];
				}
			}
		}
	}

	return -1;
}

- (nullable NSString *)ratingStringForiTunesCountry:(NSString *)aCountry media:(NSString *)aMedia ratingString:(NSString *)aRatingString {
    NSInteger index = [self ratingIndexForiTunesCountry:aCountry media:aMedia ratingString:aRatingString];
    if (index > -1) {
        return iTunesCodes[index];
    }
    else {
        return nil;
    }
}

@end
