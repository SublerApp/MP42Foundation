//
//  MP42MetadataFormat.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 07/10/2016.
//  Copyright © 2016 Damiano Galassi. All rights reserved.
//

#import "MP42MetadataFormat.h"

NSString *const MP42MetadataKeyName = @"Name";
NSString *const MP42MetadataKeyTrackSubTitle = @"Track Sub-Title";

NSString *const MP42MetadataKeyAlbum = @"Album";
NSString *const MP42MetadataKeyAlbumArtist = @"Album Artist";
NSString *const MP42MetadataKeyArtist = @"Artist";

NSString *const MP42MetadataKeyGrouping = @"Grouping";
NSString *const MP42MetadataKeyUserComment = @"Comments";
NSString *const MP42MetadataKeyUserGenre = @"Genre";
NSString *const MP42MetadataKeyReleaseDate = @"Release Date";

NSString *const MP42MetadataKeyTrackNumber = @"Track #";
NSString *const MP42MetadataKeyDiscNumber = @"Disk #";
NSString *const MP42MetadataKeyBeatsPerMin = @"Tempo";

NSString *const MP42MetadataKeyKeywords = @"Keywords";
NSString *const MP42MetadataKeyCategory = @"Category";
NSString *const MP42MetadataKeyCredits = @"Credits";
NSString *const MP42MetadataKeyThanks = @"Thanks";
NSString *const MP42MetadataKeyCopyright = @"Copyright";

NSString *const MP42MetadataKeyDescription = @"Description";
NSString *const MP42MetadataKeyLongDescription = @"Long Description";
NSString *const MP42MetadataKeySeriesDescription = @"Series Description";
NSString *const MP42MetadataKeySongDescription = @"Song Description";

NSString *const MP42MetadataKeyRating = @"Rating";
NSString *const MP42MetadataKeyRatingAnnotation = @"Rating Annotation";
NSString *const MP42MetadataKeyContentRating = @"Content Rating";

NSString *const MP42MetadataKeyEncodedBy = @"Encoded By";
NSString *const MP42MetadataKeyEncodingTool = @"Encoding Tool";

NSString *const MP42MetadataKeyCoverArt = @"Cover Art";
NSString *const MP42MetadataKeyMediaKind = @"Media Kind";
NSString *const MP42MetadataKeyGapless = @"Gapless";
NSString *const MP42MetadataKeyHDVideo = @"HD Video";
NSString *const MP42MetadataKeyiTunesU = @"iTunes U";
NSString *const MP42MetadataKeyPodcast = @"Podcast";

NSString *const MP42MetadataKeyStudio = @"Studio";
NSString *const MP42MetadataKeyCast = @"Cast";
NSString *const MP42MetadataKeyDirector = @"Director";
NSString *const MP42MetadataKeyCodirector = @"Codirector";
NSString *const MP42MetadataKeyProducer = @"Producers";
NSString *const MP42MetadataKeyExecProducer = @"Executive Producer";
NSString *const MP42MetadataKeyScreenwriters = @"Screenwriters";

NSString *const MP42MetadataKeyTVShow = @"TV Show";
NSString *const MP42MetadataKeyTVEpisodeNumber = @"TV Episode #";
NSString *const MP42MetadataKeyTVNetwork = @"TV Network";
NSString *const MP42MetadataKeyTVEpisodeID = @"TV Episode ID";
NSString *const MP42MetadataKeyTVSeason = @"TV Season";

NSString *const MP42MetadataKeyArtDirector = @"Art Director";
NSString *const MP42MetadataKeyComposer = @"Composer";
NSString *const MP42MetadataKeyArranger = @"Arranger";
NSString *const MP42MetadataKeyAuthor = @"Lyricist";
NSString *const MP42MetadataKeyLyrics = @"Lyrics";
NSString *const MP42MetadataKeyAcknowledgement = @"Acknowledgement";
NSString *const MP42MetadataKeyConductor = @"Conductor";
NSString *const MP42MetadataKeyLinerNotes = @"Linear Notes";
NSString *const MP42MetadataKeyRecordCompany = @"Record Company";
NSString *const MP42MetadataKeyOriginalArtist = @"Original Artist";
NSString *const MP42MetadataKeyPhonogramRights = @"Phonogram Rights";
NSString *const MP42MetadataKeySongProducer = @"Song Producer";
NSString *const MP42MetadataKeyPerformer = @"Performer";
NSString *const MP42MetadataKeyPublisher = @"Publisher";
NSString *const MP42MetadataKeySoundEngineer = @"Sound Engineer";
NSString *const MP42MetadataKeySoloist = @"Soloist";
NSString *const MP42MetadataKeyDiscCompilation = @"Compilation";

NSString *const MP42MetadataKeyWorkName = @"Work Name";
NSString *const MP42MetadataKeyMovementName = @"Movement Name";
NSString *const MP42MetadataKeyMovementNumber = @"Movement Number";
NSString *const MP42MetadataKeyMovementCount = @"Movement Count";
NSString *const MP42MetadataKeyShowWorkAndMovement = @"Show Work And Movement";

NSString *const MP42MetadataKeyXID = @"XID";
NSString *const MP42MetadataKeyArtistID = @"artist ID";
NSString *const MP42MetadataKeyComposerID = @"composer ID";
NSString *const MP42MetadataKeyContentID = @"content ID";
NSString *const MP42MetadataKeyGenreID = @"genre ID";
NSString *const MP42MetadataKeyPlaylistID = @"playlist ID";
NSString *const MP42MetadataKeyAppleID = @"iTunes Account";
NSString *const MP42MetadataKeyAccountKind = @"iTunes Account Type";
NSString *const MP42MetadataKeyAccountCountry = @"iTunes Country";
NSString *const MP42MetadataKeyPurchasedDate = @"Purchase Date";
NSString *const MP42MetadataKeyOnlineExtras = @"Online Extras";

NSString *const MP42MetadataKeySortName = @"Sort Name";
NSString *const MP42MetadataKeySortArtist = @"Sort Artist";
NSString *const MP42MetadataKeySortAlbumArtist = @"Sort Album Artist";
NSString *const MP42MetadataKeySortAlbum = @"Sort Album";
NSString *const MP42MetadataKeySortComposer = @"Sort Composer";
NSString *const MP42MetadataKeySortTVShow = @"Sort TV Show";
