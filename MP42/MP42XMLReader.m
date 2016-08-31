//
//  MP42XMLReader.m
//  Subler
//
//  Created by Damiano Galassi on 25/01/13.
//
//

#import "MP42XMLReader.h"
#import "MP42Metadata.h"

@implementation MP42XMLReader

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error
{
    if (self = [super init]) {
        NSXMLDocument *xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:NULL];
        if (xml) {
            NSError *err;
            _mMetadata = [[MP42Metadata alloc] init];
            NSArray *nodes = [xml nodesForXPath:@"./movie" error:&err];
            if ([nodes count] == 1)
                [self metadata:_mMetadata forNode:[nodes objectAtIndex:0]];
            
            nodes = [xml nodesForXPath:@"./video" error:&err];
            if ([nodes count] == 1)
                [self metadata2:_mMetadata forNode:[nodes objectAtIndex:0]];
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

- (MP42Metadata *) metadata:(MP42Metadata *)metadata forNode:(NSXMLElement *)node {
    metadata.mediaKind = 9; // movie
    NSArray *tag;
    NSError *err;
    // initial fields from general movie search
    tag = [node nodesForXPath:@"./title" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyName];
    tag = [node nodesForXPath:@"./year" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyReleaseDate];
    tag = [node nodesForXPath:@"./outline" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyDescription];
    tag = [node nodesForXPath:@"./plot" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyLongDescription];
    tag = [node nodesForXPath:@"./certification" error:&err];
    if ([tag count] && [[[tag objectAtIndex:0] stringValue] length]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyRating];
    tag = [node nodesForXPath:@"./genre" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyUserGenre];
    tag = [node nodesForXPath:@"./credits" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyArtist];
    tag = [node nodesForXPath:@"./director" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyDirector];
    tag = [node nodesForXPath:@"./studio" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyStudio];

    // additional fields from detailed movie info
    NSString *joined;
    joined = [self nodes:node forXPath:@"./cast/actor/@name" joinedBy:@","];
    if (joined) [metadata setTag:joined forKey:MP42MetadataKeyCast];

    return metadata;
}

- (MP42Metadata *) metadata2:(MP42Metadata *)metadata forNode:(NSXMLElement *)node {
    metadata.mediaKind = 9; // movie
    NSArray *tag;
    NSError *err;
    // initial fields from general movie search
    tag = [node nodesForXPath:@"./content_id" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyContentID];
    tag = [node nodesForXPath:@"./genre" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyUserGenre];
    tag = [node nodesForXPath:@"./name" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyName];
    tag = [node nodesForXPath:@"./release_date" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyReleaseDate];
    tag = [node nodesForXPath:@"./encoding_tool" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyEncodingTool];
    tag = [node nodesForXPath:@"./copyright" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyCopyright];

    NSString *joined;
    joined = [self nodes:node forXPath:@"./producers/producer_name" joinedBy:@","];
    if (joined) [metadata setTag:joined forKey:MP42MetadataKeyProducer];
    
    joined = [self nodes:node forXPath:@"./directors/director_name" joinedBy:@","];
    if (joined) [metadata setTag:joined forKey:MP42MetadataKeyDirector], [metadata setTag:joined forKey:MP42MetadataKeyArtist];
    
    joined = [self nodes:node forXPath:@"./casts/cast" joinedBy:@","];
    if (joined) [metadata setTag:joined forKey:MP42MetadataKeyCast];

    tag = [node nodesForXPath:@"./studio" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyStudio];
    tag = [node nodesForXPath:@"./description" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyDescription];
    tag = [node nodesForXPath:@"./long_description" error:&err];
    if ([tag count]) [metadata setTag:[[tag objectAtIndex:0] stringValue] forKey:MP42MetadataKeyLongDescription];

    joined = [self nodes:node forXPath:@"./categories/category" joinedBy:@","];
    if (joined) [metadata setTag:joined forKey:MP42MetadataKeyCategory];
    
    return metadata;
}

@end
