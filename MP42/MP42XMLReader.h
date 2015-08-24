//
//  MP42XMLReader.h
//  Subler
//
//  Created by Damiano Galassi on 25/01/13.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MP42Metadata;

@interface MP42XMLReader : NSObject {
    MP42Metadata *mMetadata;
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;

@property (nonatomic, readonly) MP42Metadata *mMetadata;

@end

NS_ASSUME_NONNULL_END
