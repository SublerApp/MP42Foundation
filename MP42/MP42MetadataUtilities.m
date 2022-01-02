//
//  MP42MetadataUtilities.m
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/01/17.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct genreType_t {
    uint8_t index;
    const char *short_name;
    const char *english_name;
} genreType_t;

static const genreType_t genreType_strings[] = {
    {1,   "blues",             "Blues" },
    {2,   "classicrock",       "Classic Rock" },
    {3,   "country",           "Country" },
    {4,   "dance",             "Dance" },
    {5,   "disco",             "Disco" },
    {6,   "funk",              "Funk" },
    {7,   "grunge",            "Grunge" },
    {8,   "hiphop",            "Hop-Hop" },
    {9,   "jazz",              "Jazz" },
    {10,  "metal",             "Metal" },
    {11,  "newage",            "New Age" },
    {12,  "oldies",            "Oldies" },
    {13,  "other",             "Other" },
    {14,  "pop",               "Pop" },
    {15,  "rand_b",            "R&B" },
    {16,  "rap",               "Rap" },
    {17,  "reggae",            "Reggae" },
    {18,  "rock",              "Rock" },
    {19,  "techno",            "Techno" },
    {20,  "industrial",        "Industrial" },
    {21,  "alternative",       "Alternative" },
    {22,  "ska",               "Ska" },
    {23,  "deathmetal",        "Death Metal" },
    {24,  "pranks",            "Pranks" },
    {25,  "soundtrack",        "Soundtrack" },
    {26,  "eurotechno",        "Euro-Techno" },
    {27,  "ambient",           "Ambient" },
    {28,  "triphop",           "Trip-Hop" },
    {29,  "vocal",             "Vocal" },
    {30,  "jazzfunk",          "Jazz+Funk" },
    {31,  "fusion",            "Fusion" },
    {32,  "trance",            "Trance" },
    {33,  "classical",         "Classical" },
    {34,  "instrumental",      "Instrumental" },
    {35,  "acid",              "Acid" },
    {36,  "house",             "House" },
    {37,  "game",              "Game" },
    {38,  "soundclip",         "Sound Clip" },
    {39,  "gospel",            "Gospel" },
    {40,  "noise",             "Noise" },
    {41,  "alternrock",        "AlternRock" },
    {42,  "bass",              "Bass" },
    {43,  "soul",              "Soul" },
    {44,  "punk",              "Punk" },
    {45,  "space",             "Space" },
    {46,  "meditative",        "Meditative" },
    {47,  "instrumentalpop",   "Instrumental Pop" },
    {48,  "instrumentalrock",  "Instrumental Rock" },
    {49,  "ethnic",            "Ethnic" },
    {50,  "gothic",            "Gothic" },
    {51,  "darkwave",          "Darkwave" },
    {52,  "technoindustrial",  "Techno-Industrial" },
    {53,  "electronic",        "Electronic" },
    {54,  "popfolk",           "Pop-Folk" },
    {55,  "eurodance",         "Eurodance" },
    {56,  "dream",             "Dream" },
    {57,  "southernrock",      "Southern Rock" },
    {58,  "comedy",            "Comedy" },
    {59,  "cult",              "Cult" },
    {60,  "gangsta",           "Gangsta" },
    {61,  "top40",             "Top 40" },
    {62,  "christianrap",      "Christian Rap" },
    {63,  "popfunk",           "Pop/Funk" },
    {64,  "jungle",            "Jungle" },
    {65,  "nativeamerican",    "Native American" },
    {66,  "cabaret",           "Cabaret" },
    {67,  "newwave",           "New Wave" },
    {68,  "psychedelic",       "Psychedelic" },
    {69,  "rave",              "Rave" },
    {70,  "showtunes",         "Showtunes" },
    {71,  "trailer",           "Trailer" },
    {72,  "lofi",              "Lo-Fi" },
    {73,  "tribal",            "Tribal" },
    {74,  "acidpunk",          "Acid Punk" },
    {75,  "acidjazz",          "Acid Jazz" },
    {76,  "polka",             "Polka" },
    {77,  "retro",             "Retro" },
    {78,  "musical",           "Musical" },
    {79,  "rockand_roll",      "Rock & Roll" },

    {80,  "hardrock",          "Hard Rock" },
    {81,  "folk",              "Folk" },
    {82,  "folkrock",          "Folk-Rock" },
    {83,  "nationalfolk",      "National Folk" },
    {84,  "swing",             "Swing" },
    {85,  "fastfusion",        "Fast Fusion" },
    {86,  "bebob",             "Bebob" },
    {87,  "latin",             "Latin" },
    {88,  "revival",           "Revival" },
    {89,  "celtic",            "Celtic" },
    {90,  "bluegrass",         "Bluegrass" },
    {91,  "avantgarde",        "Avantgarde" },
    {92,  "gothicrock",        "Gothic Rock" },
    {93,  "progressiverock",   "Progressive Rock" },
    {94,  "psychedelicrock",   "Psychedelic Rock" },
    {95,  "symphonicrock",     "SYMPHONIC_ROCK" },
    {96,  "slowrock",          "Slow Rock" },
    {97,  "bigband",           "Big Band" },
    {98,  "chorus",            "Chorus" },
    {99,  "easylistening",     "Easy Listening" },
    {100, "acoustic",          "Acoustic" },
    {101, "humour",            "Humor" },
    {102, "speech",            "Speech" },
    {103, "chanson",           "Chason" },
    {104, "opera",             "Opera" },
    {105, "chambermusic",      "Chamber Music" },
    {106, "sonata",            "Sonata" },
    {107, "symphony",          "Symphony" },
    {108, "bootybass",         "Booty Bass" },
    {109, "primus",            "Primus" },
    {110, "porngroove",        "Porn Groove" },
    {111, "satire",            "Satire" },
    {112, "slowjam",           "Slow Jam" },
    {113, "club",              "Club" },
    {114, "tango",             "Tango" },
    {115, "samba",             "Samba" },
    {116, "folklore",          "Folklore" },
    {117, "ballad",            "Ballad" },
    {118, "powerballad",       "Power Ballad" },
    {119, "rhythmicsoul",      "Rhythmic Soul" },
    {120, "freestyle",         "Freestyle" },
    {121, "duet",              "Duet" },
    {122, "punkrock",          "Punk Rock" },
    {123, "drumsolo",          "Drum Solo" },
    {124, "acapella",          "A capella" },
    {125, "eurohouse",         "Euro-House" },
    {126, "dancehall",         "Dance Hall" },
    {255, "none",              "none" },

    {0, "undefined", NULL } // must be last
};

NSString * genreFromIndex(NSInteger index)
{
    if ((index >= 0 && index < 127) || index == 255) {
        genreType_t *genre = (genreType_t *) genreType_strings;
        genre += index - 1;
        return @(genre->english_name);
    }
    else {
        return nil;
    }
}

NSInteger genreIndexFromString(NSString *genreString)
{
    NSInteger genreIndex = 0, k = 0;

    for (genreType_t *genreList = (genreType_t *) genreType_strings; genreList->english_name; genreList++, k++ ) {
        if ([genreString isEqualToString:@(genreList->english_name)]) {
            genreIndex = k + 1;
        }
    }
    return genreIndex;
}

