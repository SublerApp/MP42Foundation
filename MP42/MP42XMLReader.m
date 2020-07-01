//
//  MP42XMLReader.m
//  Subler
//
//  Created by Damiano Galassi on 25/01/13.
//
//

#import "MP42XMLReader.h"
#import "MP42Metadata.h"
#import "MP42Utilities.h"

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42XMLReader

- (nullable instancetype)initWithURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
    if (self = [super init]) {
        NSXMLDocument *xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:error];
        if (xml) {
            NSError *err;
            _mMetadata = [[MP42Metadata alloc] init];
            NSArray *nodes = [xml nodesForXPath:@"./movie" error:&err];
            if ([nodes count] == 1)
                [self metadataForNode:[nodes objectAtIndex:0]];
            
            nodes = [xml nodesForXPath:@"./video" error:&err];
            if ([nodes count] == 1)
                [self metadata2ForNode:[nodes objectAtIndex:0]];
        } else {
            return nil;
        }
    }
    return self;
}

#pragma mark Parse metadata

- (NSString *) nodes:(NSXMLElement *)node forXPath:(NSString *)query joinedBy:(NSString *)joiner {
    NSError *err;
    NSArray *tag = [node nodesForXPath:query error:&err];
    if ([tag count]) {
        NSMutableArray *elements = [[NSMutableArray alloc] initWithCapacity:tag.count];
        NSEnumerator *tagEnum = [tag objectEnumerator];
        NSXMLNode *element;
        while ((element = [tagEnum nextObject])) {
            [elements addObject:[element stringValue]];
        }
        return [elements componentsJoinedByString:@", "];
    } else {
        return nil;
    }
}

- (void)addMetadataItemWithString:(NSString *)value identifier:(NSString *)identifier
{
    MP42MetadataItem *item = [MP42MetadataItem metadataItemWithIdentifier:identifier
                                                                    value:value
                                                                 dataType:MP42MetadataItemDataTypeUnspecified
                                                      extendedLanguageTag:nil];
    [self.mMetadata addMetadataItem:item];
}

- (void)metadataForNode:(NSXMLElement *)node {
    [self addMetadataItemWithString:@"9" identifier:MP42MetadataKeyMediaKind];
    NSArray *tag;
    NSError *err;
    // initial fields from general movie search
    tag = [node nodesForXPath:@"./title" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyName];
    tag = [node nodesForXPath:@"./year" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyReleaseDate];
    tag = [node nodesForXPath:@"./outline" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyDescription];
    tag = [node nodesForXPath:@"./plot" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyLongDescription];
    tag = [node nodesForXPath:@"./certification" error:&err];
    if ([tag count] && [[[tag objectAtIndex:0] stringValue] length]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyRating];
    tag = [node nodesForXPath:@"./genre" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyUserGenre];
    tag = [node nodesForXPath:@"./credits" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyArtist];
    tag = [node nodesForXPath:@"./director" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyDirector];
    tag = [node nodesForXPath:@"./studio" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyStudio];

    // additional fields from detailed movie info
    NSString *joined;
    joined = [self nodes:node forXPath:@"./cast/actor/@name" joinedBy:@","];
    if (joined) [self addMetadataItemWithString:joined identifier:MP42MetadataKeyCast];
}

- (void)metadata2ForNode:(NSXMLElement *)node {
    [self addMetadataItemWithString:@"9" identifier:MP42MetadataKeyMediaKind];
    NSArray *tag;
    NSError *err;
    // initial fields from general movie search
    tag = [node nodesForXPath:@"./content_id" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyContentID];
    tag = [node nodesForXPath:@"./genre" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyUserGenre];
    tag = [node nodesForXPath:@"./name" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyName];
    tag = [node nodesForXPath:@"./release_date" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyReleaseDate];
    tag = [node nodesForXPath:@"./encoding_tool" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyEncodingTool];
    tag = [node nodesForXPath:@"./copyright" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyCopyright];

    NSString *joined;
    joined = [self nodes:node forXPath:@"./producers/producer_name" joinedBy:@","];
    if (joined) [self addMetadataItemWithString:joined identifier:MP42MetadataKeyProducer];
    
    joined = [self nodes:node forXPath:@"./directors/director_name" joinedBy:@","];
    if (joined) {
        [self addMetadataItemWithString:joined identifier:MP42MetadataKeyDirector];
        [self addMetadataItemWithString:joined identifier:MP42MetadataKeyArtist];
    }
    
    joined = [self nodes:node forXPath:@"./casts/cast" joinedBy:@","];
    if (joined) [self addMetadataItemWithString:joined identifier:MP42MetadataKeyCast];

    tag = [node nodesForXPath:@"./studio" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyStudio];
    tag = [node nodesForXPath:@"./description" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyDescription];
    tag = [node nodesForXPath:@"./long_description" error:&err];
    if ([tag count]) [self addMetadataItemWithString:[[tag objectAtIndex:0] stringValue] identifier:MP42MetadataKeyLongDescription];

    joined = [self nodes:node forXPath:@"./categories/category" joinedBy:@","];
    if (joined) [self addMetadataItemWithString:joined identifier:MP42MetadataKeyCategory];
}

@end
