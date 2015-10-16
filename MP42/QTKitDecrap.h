//
//  QTKitDecrap.h
//  Subler
//
//  Created by Damiano Galassi on 13/12/12.
//  Almost all the constants from QTMetadataItem all broken, @ instead of ©.
//  Plus define a QTKit costant.

#import <QTKit/QTKit.h>

extern NSString * const QTTrackLanguageAttribute;	// NSNumber (long)

@interface QTMovie (QTMovieSublerExtras)

- (QTTrack *)trackWithTrackID:(NSInteger)trackID;

@end

@implementation QTMovie (QTMovieSublerExtras)

- (QTTrack *)trackWithTrackID:(NSInteger)trackID
{
    for (QTTrack *track in [self tracks])
        if (trackID == [[track attributeForKey:QTTrackIDAttribute] integerValue])
            return track;

    return nil;
}

@end
