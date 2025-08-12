//
//  MP42MetadataFormat.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 07/10/2016.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import "MP42MetadataFormat.h"
#import "MP42Metadata.h"

static NSDictionary<NSString *, NSString *> *localizedStrings;

NSString *localizedMetadataKeyName(NSString  *key)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleForClass:[MP42Metadata class]];

        localizedStrings = @{MP42MetadataKeyName: NSLocalizedStringFromTableInBundle(@"Name", @"Localizable", bundle, nil),
                             MP42MetadataKeyTrackSubTitle: NSLocalizedStringFromTableInBundle(@"Track Sub-Title", @"Localizable", bundle, nil),

                             MP42MetadataKeyArtist: NSLocalizedStringFromTableInBundle(@"Artist", @"Localizable", bundle, nil),
                             MP42MetadataKeyAlbumArtist: NSLocalizedStringFromTableInBundle(@"Album Artist", @"Localizable", bundle, nil),
                             MP42MetadataKeyAlbum: NSLocalizedStringFromTableInBundle(@"Album", @"Localizable", bundle, nil),

                             MP42MetadataKeyGrouping: NSLocalizedStringFromTableInBundle(@"Grouping", @"Localizable", bundle, nil),

                             MP42MetadataKeyMediaKind: NSLocalizedStringFromTableInBundle(@"Media Kind", @"Localizable", bundle, nil),
                             MP42MetadataKeyHDVideo: NSLocalizedStringFromTableInBundle(@"HD Video", @"Localizable", bundle, nil),
                             MP42MetadataKeyGapless: NSLocalizedStringFromTableInBundle(@"Gapless", @"Localizable", bundle, nil),
                             MP42MetadataKeyPodcast: NSLocalizedStringFromTableInBundle(@"Podcast", @"Localizable", bundle, nil),

                             MP42MetadataKeyUserComment: NSLocalizedStringFromTableInBundle(@"Comments", @"Localizable", bundle, nil),
                             MP42MetadataKeyUserGenre: NSLocalizedStringFromTableInBundle(@"Genre", @"Localizable", bundle, nil),
                             MP42MetadataKeyReleaseDate: NSLocalizedStringFromTableInBundle(@"Release Date", @"Localizable", bundle, nil),

                             MP42MetadataKeyTrackNumber: NSLocalizedStringFromTableInBundle(@"Track #", @"Localizable", bundle, nil),
                             MP42MetadataKeyDiscNumber: NSLocalizedStringFromTableInBundle(@"Disk #", @"Localizable", bundle, nil),
                             MP42MetadataKeyBeatsPerMin: NSLocalizedStringFromTableInBundle(@"Tempo", @"Localizable", bundle, nil),

                             MP42MetadataKeyTVShow: NSLocalizedStringFromTableInBundle(@"TV Show", @"Localizable", bundle, nil),
                             MP42MetadataKeyTVEpisodeNumber: NSLocalizedStringFromTableInBundle(@"TV Episode #", @"Localizable", bundle, nil),
                             MP42MetadataKeyTVNetwork: NSLocalizedStringFromTableInBundle(@"TV Network", @"Localizable", bundle, nil),
                             MP42MetadataKeyTVEpisodeID: NSLocalizedStringFromTableInBundle(@"TV Episode ID", @"Localizable", bundle, nil),
                             MP42MetadataKeyTVSeason: NSLocalizedStringFromTableInBundle(@"TV Season", @"Localizable", bundle, nil),

                             MP42MetadataKeyDescription: NSLocalizedStringFromTableInBundle(@"Description", @"Localizable", bundle, nil),
                             MP42MetadataKeyLongDescription: NSLocalizedStringFromTableInBundle(@"Long Description", @"Localizable", bundle, nil),
                             MP42MetadataKeySeriesDescription: NSLocalizedStringFromTableInBundle(@"Series Description", @"Localizable", bundle, nil),

                             MP42MetadataKeyRating: NSLocalizedStringFromTableInBundle(@"Rating", @"Localizable", bundle, nil),
                             MP42MetadataKeyRatingAnnotation: NSLocalizedStringFromTableInBundle(@"Rating Annotation", @"Localizable", bundle, nil),
                             MP42MetadataKeyContentRating: NSLocalizedStringFromTableInBundle(@"Content Rating", @"Localizable", bundle, nil),

                             MP42MetadataKeyStudio: NSLocalizedStringFromTableInBundle(@"Studio", @"Localizable", bundle, nil),
                             MP42MetadataKeyCast: NSLocalizedStringFromTableInBundle(@"Cast", @"Localizable", bundle, nil),
                             MP42MetadataKeyDirector: NSLocalizedStringFromTableInBundle(@"Director", @"Localizable", bundle, nil),
                             MP42MetadataKeyCodirector: NSLocalizedStringFromTableInBundle(@"Codirector", @"Localizable", bundle, nil),
                             MP42MetadataKeyProducer: NSLocalizedStringFromTableInBundle(@"Producers", @"Localizable", bundle, nil),
                             MP42MetadataKeyExecProducer: NSLocalizedStringFromTableInBundle(@"Executive Producer", @"Localizable", bundle, nil),
                             MP42MetadataKeyScreenwriters: NSLocalizedStringFromTableInBundle(@"Screenwriters", @"Localizable", bundle, nil),

                             MP42MetadataKeyCopyright: NSLocalizedStringFromTableInBundle(@"Copyright", @"Localizable", bundle, nil),
                             MP42MetadataKeyEncodingTool: NSLocalizedStringFromTableInBundle(@"Encoding Tool", @"Localizable", bundle, nil),
                             MP42MetadataKeyEncodedBy: NSLocalizedStringFromTableInBundle(@"Encoded By", @"Localizable", bundle, nil),

                             MP42MetadataKeyKeywords: NSLocalizedStringFromTableInBundle(@"Keywords", @"Localizable", bundle, nil),
                             MP42MetadataKeyCategory: NSLocalizedStringFromTableInBundle(@"Category", @"Localizable", bundle, nil),

                             MP42MetadataKeyContentID: NSLocalizedStringFromTableInBundle(@"content ID", @"Localizable", bundle, nil),
                             MP42MetadataKeyArtistID: NSLocalizedStringFromTableInBundle(@"artist ID", @"Localizable", bundle, nil),
                             MP42MetadataKeyPlaylistID: NSLocalizedStringFromTableInBundle(@"playlist ID", @"Localizable", bundle, nil),
                             MP42MetadataKeyGenreID: NSLocalizedStringFromTableInBundle(@"genre ID", @"Localizable", bundle, nil),
                             MP42MetadataKeyComposerID: NSLocalizedStringFromTableInBundle(@"composer ID", @"Localizable", bundle, nil),
                             MP42MetadataKeyXID: NSLocalizedStringFromTableInBundle(@"XID", @"Localizable", bundle, nil),
                             MP42MetadataKeyAppleID: NSLocalizedStringFromTableInBundle(@"iTunes Account", @"Localizable", bundle, nil),
                             MP42MetadataKeyAccountKind: NSLocalizedStringFromTableInBundle(@"iTunes Account Type", @"Localizable", bundle, nil),
                             MP42MetadataKeyAccountCountry: NSLocalizedStringFromTableInBundle(@"iTunes Country", @"Localizable", bundle, nil),
                             MP42MetadataKeyPurchasedDate: NSLocalizedStringFromTableInBundle(@"Purchase Date", @"Localizable", bundle, nil),
                             MP42MetadataKeyOnlineExtras: NSLocalizedStringFromTableInBundle(@"Online Extras", @"Localizable", bundle, nil),

                             MP42MetadataKeySongDescription: NSLocalizedStringFromTableInBundle(@"Song Description", @"Localizable", bundle, nil),

                             MP42MetadataKeyArtDirector: NSLocalizedStringFromTableInBundle(@"Art Director", @"Localizable", bundle, nil),
                             MP42MetadataKeyComposer: NSLocalizedStringFromTableInBundle(@"Composer", @"Localizable", bundle, nil),
                             MP42MetadataKeyArranger: NSLocalizedStringFromTableInBundle(@"Arranger", @"Localizable", bundle, nil),
                             MP42MetadataKeyAuthor: NSLocalizedStringFromTableInBundle(@"Lyricist", @"Localizable", bundle, nil),
                             MP42MetadataKeyLyrics: NSLocalizedStringFromTableInBundle(@"Lyrics", @"Localizable", bundle, nil),
                             MP42MetadataKeyAcknowledgement: NSLocalizedStringFromTableInBundle(@"Acknowledgement", @"Localizable", bundle, nil),
                             MP42MetadataKeyConductor: NSLocalizedStringFromTableInBundle(@"Conductor", @"Localizable", bundle, nil),
                             MP42MetadataKeyLinerNotes: NSLocalizedStringFromTableInBundle(@"Linear Notes", @"Localizable", bundle, nil),
                             MP42MetadataKeyRecordCompany: NSLocalizedStringFromTableInBundle(@"Record Company", @"Localizable", bundle, nil),
                             MP42MetadataKeyOriginalArtist: NSLocalizedStringFromTableInBundle(@"Original Artist", @"Localizable", bundle, nil),
                             MP42MetadataKeyPhonogramRights: NSLocalizedStringFromTableInBundle(@"Phonogram Rights", @"Localizable", bundle, nil),
                             MP42MetadataKeySongProducer: NSLocalizedStringFromTableInBundle(@"Song Producer", @"Localizable", bundle, nil),
                             MP42MetadataKeyPerformer: NSLocalizedStringFromTableInBundle(@"Performer", @"Localizable", bundle, nil),
                             MP42MetadataKeyPublisher: NSLocalizedStringFromTableInBundle(@"Publisher", @"Localizable", bundle, nil),
                             MP42MetadataKeySoundEngineer: NSLocalizedStringFromTableInBundle(@"Sound Engineer", @"Localizable", bundle, nil),
                             MP42MetadataKeySoloist: NSLocalizedStringFromTableInBundle(@"Soloist", @"Localizable", bundle, nil),
                             MP42MetadataKeyDiscCompilation: NSLocalizedStringFromTableInBundle(@"Compilation", @"Localizable", bundle, nil),

                             MP42MetadataKeyCredits: NSLocalizedStringFromTableInBundle(@"Credits", @"Localizable", bundle, nil),
                             MP42MetadataKeyThanks: NSLocalizedStringFromTableInBundle(@"Thanks", @"Localizable", bundle, nil),

                             MP42MetadataKeyWorkName: NSLocalizedStringFromTableInBundle(@"Work Name", @"Localizable", bundle, nil),
                             MP42MetadataKeyMovementName: NSLocalizedStringFromTableInBundle(@"Movement Name", @"Localizable", bundle, nil),
                             MP42MetadataKeyMovementNumber: NSLocalizedStringFromTableInBundle(@"Movement Number", @"Localizable", bundle, nil),
                             MP42MetadataKeyMovementCount: NSLocalizedStringFromTableInBundle(@"Movement Count", @"Localizable", bundle, nil),
                             MP42MetadataKeyShowWorkAndMovement: NSLocalizedStringFromTableInBundle(@"Show Work And Movement", @"Localizable", bundle, nil),

                             MP42MetadataKeySortName: NSLocalizedStringFromTableInBundle(@"Sort Name", @"Localizable", bundle, nil),
                             MP42MetadataKeySortArtist: NSLocalizedStringFromTableInBundle(@"Sort Artist", @"Localizable", bundle, nil),
                             MP42MetadataKeySortAlbumArtist: NSLocalizedStringFromTableInBundle(@"Sort Album Artist", @"Localizable", bundle, nil),
                             MP42MetadataKeySortAlbum: NSLocalizedStringFromTableInBundle(@"Sort Album", @"Localizable", bundle, nil),
                             MP42MetadataKeySortComposer: NSLocalizedStringFromTableInBundle(@"Sort Composer", @"Localizable", bundle, nil),
                             MP42MetadataKeySortTVShow: NSLocalizedStringFromTableInBundle(@"Sort TV Show", @"Localizable", bundle, nil)};
    });

    NSString *localizedString = localizedStrings[key];
    return localizedString ? localizedString : key;
}

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

NSString *const MP42MetadataKeyUnofficialSubtitle = @"Unofficial Subtitle";
NSString *const MP42MetadataKeyUnofficialLanguage = @"Unofficial Language";
NSString *const MP42MetadataKeyUnofficialASIN = @"Unofficial ASIN";
NSString *const MP42MetadataKeyUnofficialAbridged = @"Unofficial Abridged";
