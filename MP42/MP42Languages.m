//
//  MP42Languages.m
//  Subler
//
//  Created by Damiano Galassi on 13/08/12.
//
//

#import "MP42Languages.h"
#import "MP42Utilities.h"

#include <string.h>
#include <ctype.h>

typedef struct iso639_lang_t
{
    char * eng_name;        /* Description in English */
    char * native_name;     /* Description in native language */
    char * iso639_1;        /* ISO-639-1 (2 characters) code */
    char * iso639_2;        /* ISO-639-2/t (3 character) code */
    char * iso639_2b;       /* ISO-639-2/b code (if different from above) */
    short  qtLang;          /* QT Lang Code */

} iso639_lang_t;

#ifdef __cplusplus
extern "C" {
#endif
    /* find language associated with ISO-639-1 language code */
    iso639_lang_t * lang_for_code( int code );
    iso639_lang_t * lang_for_code_s( const char *code );

    /* find language associated with ISO-639-2 language code */
    iso639_lang_t * lang_for_code2( const char *code2 );

    /* find language associated with qt language code */
    iso639_lang_t * lang_for_qtcode( short code );

    /* ISO-639-1 code for language */
    int lang_to_code(const iso639_lang_t *lang);

    iso639_lang_t * lang_for_english( const char * english );
#ifdef __cplusplus
}
#endif

static const iso639_lang_t languages[] =
{ { "Unknown", "", "", "und", "", 32767 },
    { "Abkhazian", "Аҧсуа", "ab", "abk", "", -1 },
    { "Acehnese, Achinese", "Bahsa Acèh", "", "ace", "", -1 },
    { "Acoli", "", "", "ach", "", -1 },
    { "Adangme", "adangbɛ", "", "ada", "", -1 },
    { "Adyghe, Adygei", "адыгэбзэ, адыгабзэ", "", "ady", "", -1 },
    { "Afar", "Qafara", "aa", "aar", "", -1 },
    { "Afrihili", "", "", "afh", "", -1 },
    { "Afrikaans", "Afrikaans", "af", "afr", "", 141 },
    { "Afroasiatic languages", "", "", "afa", "", -1 },
    { "Ainu (Japan)", "アイヌ イタㇰ(イタッㇰ) or ainu itak", "", "ain", "", -1 },
    { "Akan", "", "ak", "aka", "", -1 },
    { "Akkadian", "akkadû, lišānum akkadītum", "", "akk", "", -1 },
    { "Albanian", "Shqip", "sq", "sqi", "alb", 36 },
    { "Aleut", "", "", "ale", "", -1 },
    { "Algonquian languages", "", "", "alg", "", -1 },
    { "Altaic languages", "", "", "tut", "", -1 },
    { "Amharic", "አማርኛ", "am", "amh", "", 85 },
    { "Ancient Greek", "Ἑλληνικά", "", "grc", "", -1 },
    { "Angika", "", "", "anp", "", -1 },
    { "Apache languages", "", "", "apa", "", -1 },
    { "Arabic", "العربية", "ar", "ara", "", 12 },
    { "Aragonese", "Aragonés", "an", "arg", "", -1 },
    { "Arapaho", "Hinóno'eitíít", "", "arp", "", -1 },
    { "Arawak", "", "", "arw", "", -1 },
    { "Armenian", "Հայերեն լեզու", "hy", "hye", "arm", 51 },
    { "Aromanian, Arumanian, Macedo-Romanian", "Armãneashce, Armãneashti, Limba armãneascã", "", "rup", "", -1 },
    { "Artificial languages", "", "", "art", "", -1 },
    { "Assamese", "অসমীয়া", "as", "asm", "", 68 },
    { "Asturian, Bable, Leonese, Asturleonese", "asturianu, Bable, Llionés, Asturllionés", "", "ast", "", -1 },
    { "Athabaskan languages", "", "", "ath", "", -1 },
    { "Australian languages", "", "", "aus", "", -1 },
    { "Austronesian languages", "", "", "map", "", -1 },
    { "Avaric", "авар мацӀ, магӀарул мацӀ", "av", "ava", "", -1 },
    { "Avestan", "avesta", "ae", "ave", "", -1 },
    { "Awadhi", "अवधी", "", "awa", "", -1 },
    { "Aymara", "aymar aru", "ay", "aym", "", 134 },
    { "Azerbaijani", "Azərbaycanca", "az", "aze", "", 49 },
    { "Balinese", "Basa Bali", "", "ban", "", -1 },
    { "Baltic languages", "", "", "bat", "", -1 },
    { "Baluchi", "بلوچی", "", "bal", "", -1 },
    { "Bambara", "bamanankan", "bm", "bam", "", -1 },
    { "Bamileke languages", "", "", "bai", "", -1 },
    { "Banda languages", "", "", "bad", "", -1 },
    { "Bantu languages", "", "", "bnt", "", -1 },
    { "Basa", "ɓasaá", "", "bas", "", -1 },
    { "Bashkir", "башҡорт теле", "ba", "bak", "", -1 },
    { "Basque", "euskara", "eu", "eus", "baq", 129 },
    { "Batak languages", "Hata Batak", "", "btk", "", -1 },
    { "Beja, Bedawiyet", "بداوية", "", "bej", "", -1 },
    { "Belarusian", "Беларуская мова", "be", "bel", "", 46 },
    { "Bemba", "ichiBemba", "", "bem", "", -1 },
    { "Bengali", "বাংলা", "bn", "ben", "", 67 },
    { "Berber languages", "Tamazight / Tamaziɣt", "", "ber", "", -1 },
    { "Bhojpuri", "भोजपुरी", "", "bho", "", -1 },
    { "Bihari languages", "", "bh", "bih", "", -1 },
    { "Bikol", "", "", "bik", "", -1 },
    { "Bini, Edo", "Edo", "", "bin", "", -1 },
    { "Bislama", "Bislama", "bi", "bis", "", -1 },
    { "Blackfoot, Siksika", "siksiká,  ᓱᖽᐧᖿ", "", "bla", "", -1 },
    { "Blin, Bilin", "ብሊና", "", "byn", "", -1 },
    { "Blissymbols, Blissymbolics, Bliss", "", "", "zbl", "", -1 },
    { "Bosnian", "bosanski jezik", "bs", "bos", "", -1 },
    { "Braj", "ब्रज भाषा", "", "bra", "", -1 },
    { "Breton", "brezhoneg", "br", "bre", "", 142 },
    { "Buginese", "ᨅᨔ ᨕᨘᨁᨗ", "", "bug", "", -1 },
    { "Bulgarian", "български език", "bg", "bul", "", 44 },
    { "Buriat", "буряад хэлэн", "", "bua", "", -1 },
    { "Burmese", "မြန်မာစာ", "my", "mya", "bur", 77 },
    { "Caddo", "Hasí:nay", "", "cad", "", -1 },
    { "Catalan, Valencian", "català / valencià", "ca", "cat", "", 130 },
    { "Caucasian languages", "", "", "cau", "", -1 },
    { "Cebuano", "Sinugboanon", "", "ceb", "", -1 },
    { "Celtic languages", "", "", "cel", "", -1 },
    { "Central American Indian languages", "", "", "cai", "", -1 },
    { "Central Khmer", "ភាសាខ្មែរ", "km", "khm", "", 78 },
    { "Chagatai", "جغتای", "", "chg", "", -1 },
    { "Chamic languages", "", "", "cmc", "", -1 },
    { "Chamorro", "Chamoru", "ch", "cha", "", -1 },
    { "Chechen", "нохчийн мотт", "ce", "che", "", -1 },
    { "Cherokee", "ᏣᎳᎩ", "", "chr", "", -1 },
    { "Cheyenne", "Tsêhést", "", "chy", "", -1 },
    { "Chibcha", "", "", "chb", "", -1 },
    { "Chichewa, Chewa, Nyanja", "chiCheŵa, chinyanja", "ny", "nya", "", 92 },
    { "Chinese", "中文 (ZhongWen)", "zh", "zho", "chi", 19 },
    { "Chinook Jargon", "", "", "chn", "", -1 },
    { "Chipewyan, Dene Suline", "Dëne Sųłiné, ᑌᓀᓲᒢᕄᓀ", "", "chp", "", -1 },
    { "Choctaw", "Chahta Anumpa", "", "cho", "", -1 },
    { "Church Slavonic, Church Slavic, Old Church Slavonic, Old Slavonic, Old Bulgarian", "ѩзыкъ словѣньскъ", "cu", "chu", "", -1 },
    { "Chuukese", "", "", "chk", "", -1 },
    { "Chuvash", "чӑваш чӗлхи", "cv", "chv", "", -1 },
    { "Circassian", "Адыгэбзэ", "", "kbd", "", -1 },
    { "Classical Newari, Old Newari, Classical Nepal Bhasa", "", "", "nwc", "", -1 },
    { "Classical Syriac", "", "", "syc", "", -1 },
    { "Coptic", "ⲙⲉⲧⲛ̀ⲣⲉⲙⲛ̀ⲭⲏⲙⲓ", "", "cop", "", -1 },
    { "Cornish", "Kernewek", "kw", "cor", "", -1 },
    { "Corsican", "corsu, lingua corsa", "co", "cos", "", -1 },
    { "Cree", "ᓀᐦᐃᔭᐍᐏᐣ", "cr", "cre", "", -1 },
    { "Creek", "Maskoki, Mvskokē empunakv", "", "mus", "", -1 },
    { "creoles and pidgins", "", "", "crp", "", -1 },
    { "creoles and pidgins, English-based", "", "", "cpe", "", -1 },
    { "creoles and pidgins, French-based", "", "", "cpf", "", -1 },
    { "creoles and pidgins, Portuguese-based", "", "", "cpp", "", -1 },
    { "Crimean Tatar, Crimean Turkish", "qırımtatar tili, къырымтатар тили", "", "crh", "", -1 },
    { "Croatian", "hrvatski jezik", "hr", "hrv", "", 18 },
    { "Cushitic languages", "", "", "cus", "", -1 },
    { "Czech", "čeština (substantive), česky (adverb)", "cs", "ces", "cze", 38 },
    { "Dakota", "Lakhota", "", "dak", "", -1 },
    { "Danish", "dansk", "da", "dan", "", 7 },
    { "Dargwa", "дарган мез", "", "dar", "", -1 },
    { "Delaware", "Lënape", "", "del", "", -1 },
    { "Dinka", "Thuɔŋjäŋ", "", "din", "", -1 },
    { "Divehi, Dhivehi, Maldivian", "ދިވެހިބަސ", "dv", "div", "", -1 },
    { "Dogri", "डोगरी", "", "doi", "", -1 },
    { "Dogrib", "Tłįchǫ", "", "dgr", "", -1 },
    { "Dravidian languages", "", "", "dra", "", -1 },
    { "Duala", "", "", "dua", "", -1 },
    { "Dutch", "Nederlands", "nl", "nld", "dut", 4 },
    { "Dutch, Middle (c. 1050–1350)", "", "", "dum", "", -1 },
    { "Dyula", "Julakan", "", "dyu", "", -1 },
    { "Dzongkha", "རྫོང་ཁ", "dz", "dzo", "", 137 },
    { "Eastern Frisian", "Seeltersk Fräisk, Seeltersk, Fräisk", "", "frs", "", -1 },
    { "Efik", "", "", "efi", "", -1 },
    { "Egyptian (Ancient)", "", "", "egy", "", -1 },
    { "Ekajuk", "", "", "eka", "", -1 },
    { "Elamite", "", "", "elx", "", -1 },
    { "English", "English", "en", "eng", "", 0 },
    { "Erzya", "эрзянь кель", "", "myv", "", -1 },
    { "Esperanto", "Esperanto", "eo", "epo", "", 94 },
    { "Estonian", "eesti keel", "et", "est", "", 27 },
    { "Ewe", "Ɛʋɛgbɛ", "ee", "ewe", "", -1 },
    { "Ewondo", "", "", "ewo", "", -1 },
    { "Fang", "", "", "fan", "", -1 },
    { "Fanti", "", "", "fat", "", -1 },
    { "Faroese", "føroyskt", "fo", "fao", "", 30 },
    { "Fijian", "vosa Vakaviti", "fj", "fij", "", -1 },
    { "Filipino, Pilipino", "Wikang Filipino", "", "fil", "", -1 },
    { "Finnish", "suomi, suomen kieli", "fi", "fin", "", 13 },
    { "Finno-Ugric languages", "", "", "fiu", "", -1 },
    { "Fon", "Fɔngbe", "", "fon", "", -1 },
    { "French", "français, langue française", "fr", "fra", "fre", 1 },
    { "Friulian", "furlan", "", "fur", "", -1 },
    { "Fulah", "Fulfulde, Pulaar, Pular", "ff", "ful", "", -1 },
    { "Ga", "Gã", "", "gaa", "", -1 },
    { "Galibi Carib", "", "", "car", "", -1 },
    { "Galician", "Galego", "gl", "glg", "", 140 },
    { "Ganda", "Luganda", "lg", "lug", "", -1 },
    { "Gayo", "", "", "gay", "", -1 },
    { "Gbaya", "", "", "gba", "", -1 },
    { "Ge'ez", "ግዕዝ", "", "gez", "", -1 },
    { "Georgian", "ქართული ენა (kartuli ena)", "ka", "kat", "geo", 52 },
    { "German", "Deutsch", "de", "deu", "ger", 2 },
    { "Germanic languages", "", "", "gem", "", -1 },
    { "Gilbertese, Kiribati", "taetae ni Kiribati", "", "gil", "", -1 },
    { "Gondi", "Gōndi", "", "gon", "", -1 },
    { "Gorontalo", "", "", "gor", "", -1 },
    { "Gothic", "𐌲𐌿𐍄𐌹𐍃𐌺", "", "got", "", -1 },
    { "Grebo", "", "", "grb", "", -1 },
    { "Greenlandic, Kalaallisut", "kalaallisut, kalaallit oqaasii", "kl", "kal", "", -1 },
    { "Guarani", "Avañe'ẽ", "gn", "grn", "", 133 },
    { "Gujarati", "ગુજરાતી", "gu", "guj", "", 69 },
    { "Gwichʼin", "", "", "gwi", "", -1 },
    { "Haida", "X̲aat Kíl", "", "hai", "", -1 },
    { "Haitian Creole, Haitian", "Kreyòl ayisyen", "ht", "hat", "", -1 },
    { "Hausa", "Hausancī, هَوُسَ", "ha", "hau", "", -1 },
    { "Hawaiian", "‘Ōlelo Hawai‘i", "", "haw", "", -1 },
    { "Hebrew", "עִבְרִית, עברית", "he", "heb", "", 10 },
    { "Herero", "Otjiherero", "hz", "her", "", -1 },
    { "Hiligaynon", "Ilonggo", "", "hil", "", -1 },
    { "Himachali languages", "", "", "him", "", -1 },
    { "Hindi", "हिन्दी", "hi", "hin", "", 21 },
    { "Hiri Motu", "Hiri Motu", "ho", "hmo", "", -1 },
    { "Hittite", "", "", "hit", "", -1 },
    { "Hmong", "Hmoob", "", "hmn", "", -1 },
    { "Hungarian", "magyar", "hu", "hun", "", 26 },
    { "Hupa", "Na:tinixwe Mixine:whe", "", "hup", "", -1 },
    { "Iban", "", "", "iba", "", -1 },
    { "Icelandic", "íslenska", "is", "isl", "ice", 15 },
    { "Ido", "Ido", "io", "ido", "", -1 },
    { "Igbo", "Igbo", "ig", "ibo", "", -1 },
    { "Ijo languages", "", "", "ijo", "", -1 },
    { "Iloko", "", "", "ilo", "", -1 },
    { "Inari Sami", "säämegiella", "", "smn", "", -1 },
    { "Indic languages", "", "", "inc", "", -1 },
    { "Indo-European languages", "", "", "ine", "", -1 },
    { "Indonesian", "Bahasa Indonesia", "id", "ind", "", 81 },
    { "Ingush", "гӀалгӀай мотт", "", "inh", "", -1 },
    { "Interlingua (International Auxiliary Language Association)", "interlingua", "ia", "ina", "", -1 },
    { "Interlingue, Occidental", "Interlingue", "ie", "ile", "", -1 },
    { "Inuktitut", "ᐃᓄᒃᑎᑐᑦ", "iu", "iku", "", 143 },
    { "Inupiaq", "Iñupiaq, Iñupiatun", "ik", "ipk", "", -1 },
    { "Iranian languages", "", "", "ira", "", -1 },
    { "Irish", "Gaeilge", "ga", "gle", "", 35 },
    { "Iroquoian languages", "", "", "iro", "", -1 },
    { "Italian", "italiano", "it", "ita", "", 3 },
    { "Japanese", "日本語 (にほんご)", "ja", "jpn", "", 11 },
    { "Javanese", "basa Jawa (ꦧꦱꦗꦮ)", "jv", "jav", "", 138 },
    { "Judeo-Arabic", "", "", "jrb", "", -1 },
    { "Judæo-Persian", "", "", "jpr", "", -1 },
    { "Kabyle", "Taqbaylit", "", "kab", "", -1 },
    { "Kachin, Jingpho", "Jingpho, Marip", "", "kac", "", -1 },
    { "Kalmyk, Oirat", "хальмг келн", "", "xal", "", -1 },
    { "Kamba", "", "", "kam", "", -1 },
    { "Kannada", "ಕನ್ನಡ", "kn", "kan", "", 73 },
    { "Kanuri", "", "kr", "kau", "", -1 },
    { "Kara-Kalpak", "қарақалпақ тили", "", "kaa", "", -1 },
    { "Karachay-Balkar", "къарачай-малкъар тил", "", "krc", "", -1 },
    { "Karelian", "karjalan kieli", "", "krl", "", -1 },
    { "Karen languages", "", "", "kar", "", -1 },
    { "Kashmiri", "कॉशुर, کٲشُر", "ks", "kas", "", 61 },
    { "Kashubian", "kaszëbsczi jãzëk", "", "csb", "", -1 },
    { "Kawi", "Bhāṣa Kawi", "", "kaw", "", -1 },
    { "Kazakh", "Қазақ тілі", "kk", "kaz", "", 48 },
    { "Khasi", "Khasi", "", "kha", "", -1 },
    { "Khoisan languages", "", "", "khi", "", -1 },
    { "Khotanese, Sakan", "ancient", "", "kho", "", -1 },
    { "Kikuyu, Gikuyu", "Gĩkũyũ", "ki", "kik", "", -1 },
    { "Kimbundu", "", "", "kmb", "", -1 },
    { "Kinyarwanda", "Ikinyarwanda", "rw", "kin", "", 90 },
    { "Kirghiz, Kyrgyz", "кыргыз тили", "ky", "kir", "", 54 },
    { "Klingon", "tlhIngan Hol", "", "tlh", "", -1 },
    { "Komi", "коми кыв", "kv", "kom", "", -1 },
    { "Kongo", "Kikongo", "kg", "kon", "", -1 },
    { "Konkani", "कॊंकणि", "", "kok", "", -1 },
    { "Korean", "한국어 (韓國語), 조선말 (朝鮮語)", "ko", "kor", "", 23 },
    { "Kosraean", "Kosrae", "", "kos", "", -1 },
    { "Kpelle", "kpele", "", "kpe", "", -1 },
    { "Kru languages", "", "", "kro", "", -1 },
    { "Kuanyama, Kwanyama", "", "kj", "kua", "", -1 },
    { "Kumyk", "Кумык", "", "kum", "", -1 },
    { "Kurdish", "Kurdî", "ku", "kur", "", 60 },
    { "Kurukh", "", "", "kru", "", -1 },
    { "Kutenai", "Ktunaxa", "", "kut", "", -1 },
    { "Ladino", "ג'ודיאו-איספאנייול", "", "lad", "", -1 },
    { "Lahnda", "ਲਹਿੰਦੀ", "", "lah", "", -1 },
    { "Lamba", "", "", "lam", "", -1 },
    { "Land Dayak languages", "", "", "day", "", -1 },
    { "Lao", "ພາສາລາວ", "lo", "lao", "", 79 },
    { "Latin", "latine, lingua Latina", "la", "lat", "", 131 },
    { "Latvian", "latviešu valoda", "lv", "lav", "", -1 },
    { "Lezghian", "лезги чӀал", "", "lez", "", -1 },
    { "Limburgish, Limburger, Limburgan", "Limburgs", "li", "lim", "", -1 },
    { "Lingala", "lingala", "ln", "lin", "", -1 },
    { "Lithuanian", "lietuvių kalba", "lt", "lit", "", 24 },
    { "Lojban", "lojban", "", "jbo", "", -1 },
    { "Low German, Low Saxon", "Nederdüütsch, Plattdüütsch", "", "nds", "", -1 },
    { "Lower Sorbian", "dolnoserbski", "", "dsb", "", -1 },
    { "Lozi", "siLozi", "", "loz", "", -1 },
    { "Luba-Katanga", "", "lu", "lub", "", -1 },
    { "Luba-Lulua", "lwaà:", "", "lua", "", -1 },
    { "Luiseño", "", "", "lui", "", -1 },
    { "Lule Sami", "sámegiella", "", "smj", "", -1 },
    { "Lunda", "chiLunda", "", "lun", "", -1 },
    { "Luo (Kenya and Tanzania)", "Dholuo", "", "luo", "", -1 },
    { "Lushai", "", "", "lus", "", -1 },
    { "Luxembourgish, Letzeburgesch", "Lëtzebuergesch", "lb", "ltz", "", -1 },
    { "Maasai", "ɔl Maa", "", "mas", "", -1 },
    { "Macedonian", "македонски јазик", "mk", "mkd", "mac", 43 },
    { "Madurese", "", "", "mad", "", -1 },
    { "Magahi", "", "", "mag", "", -1 },
    { "Maithili", "मैथिली", "", "mai", "", -1 },
    { "Makasar", "", "", "mak", "", -1 },
    { "Malagasy", "Malagasy fiteny", "mg", "mlg", "", 93 },
    { "Malay", "bahasa Melayu, بهاس ملايو", "ms", "msa", "may", 83 },
    { "Malayalam", "മലയാളം", "ml", "mal", "", 72 },
    { "Maltese", "Malti", "mt", "mlt", "", 16 },
    { "Manchu", "ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ ᠪᡝ", "", "mnc", "", -1 },
    { "Mandar", "", "", "mdr", "", -1 },
    { "Mandingo", "", "", "man", "", -1 },
    { "Manipuri", "মৈইতৈইলোন", "", "mni", "", -1 },
    { "Manobo languages", "", "", "mno", "", -1 },
    { "Manx", "Gaelg, Manninagh", "gv", "glv", "", 145 },
    { "Mapudungun, Mapuche", "mapudungun, mapuchedungun", "", "arn", "", -1 },
    { "Marathi", "मराठी", "mr", "mar", "", 66 },
    { "Mari (Russia)", "марий йылме", "", "chm", "", -1 },
    { "Marshallese", "Kajin M̧ajeļ", "mh", "mah", "", -1 },
    { "Marwari", "मारवाड़ी", "", "mwr", "", -1 },
    { "Mayan languages", "", "", "myn", "", -1 },
    { "Mende", "Mɛnde", "", "men", "", -1 },
    { "Mi'kmaq, Micmac", "Míkmaq, Mi'gmaq", "", "mic", "", -1 },
    { "Middle English (1100–1500)", "English", "", "enm", "", -1 },
    { "Middle French (c. 1400—1600)", "", "", "frm", "", -1 },
    { "Middle High German (ca. 1050–1500)", "diutisk", "", "gmh", "", -1 },
    { "Middle Irish (900–1200)", "Gaoidhealg", "", "mga", "", -1 },
    { "Minangkabau", "Baso Minangkabau", "", "min", "", -1 },
    { "Mirandese", "Lhéngua Mirandesa", "", "mwl", "", -1 },
    { "Modern Greek", "Ελληνικά", "el", "ell", "gre", 14 },
    { "Mohawk", "Kanien’keha", "", "moh", "", -1 },
    { "Moksha", "мокшень кяль", "", "mdf", "", -1 },
    { "Mongo", "", "", "lol", "", -1 },
    { "Mongolian", "монгол хэл", "mn", "mon", "", 57 },
    { "Mon–Khmer languages", "", "", "mkh", "", -1 },
    { "Mossi", "Mòoré", "", "mos", "", -1 },
    { "Munda languages", "", "", "mun", "", -1 },
    { "Māori", "te reo Māori", "mi", "mri", "mao", -1 },
    { "N'Ko", "", "", "nqo", "", -1 },
    { "Nahuatl", "nāhuatl, nawatlahtolli", "", "nah", "", -1 },
    { "Nauruan", "Ekakairũ Naoero", "na", "nau", "", -1 },
    { "Navajo, Navaho", "Diné bizaad, Dinékʼehǰí", "nv", "nav", "", -1 },
    { "Ndonga", "Owambo", "ng", "ndo", "", -1 },
    { "Neapolitan", "napulitano", "", "nap", "", -1 },
    { "Nepal Bhasa, Newari", "Nepal Bhasa", "", "new", "", -1 },
    { "Nepali", "नेपाली", "ne", "nep", "", 64 },
    { "Nias", "", "", "nia", "", -1 },
    { "Niger–Congo languages", "", "", "nic", "", -1 },
    { "Nilo-Saharan languages", "", "", "ssa", "", -1 },
    { "Niuean", "ko e vagahau Niuē, faka-Niue", "", "niu", "", -1 },
    { "Nogai", "ногай тили", "", "nog", "", -1 },
    { "North American Indian languages", "", "", "nai", "", -1 },
    { "Northern Frisian", "", "", "frr", "", -1 },
    { "Northern Ndebele", "isiNdebele", "nd", "nde", "", -1 },
    { "Northern Sami", "sámi, sámegiella", "se", "sme", "", -1 },
    { "Northern Sotho, Pedi, Sepedi", "Sesotho sa Leboa, Sepedi", "", "nso", "", -1 },
    { "Norwegian", "norsk", "no", "nor", "", 9 },
    { "Norwegian Bokmål", "bokmål", "nb", "nob", "", -1 },
    { "Norwegian Nynorsk", "nynorsk", "nn", "nno", "", -1 },
    { "Nubian languages", "", "", "nub", "", -1 },
    { "Nyamwezi", "Kinyamwezi", "", "nym", "", -1 },
    { "Nyankole", "", "", "nyn", "", -1 },
    { "Nyoro", "Runyoro", "", "nyo", "", -1 },
    { "Nzima", "", "", "nzi", "", -1 },
    { "Occitan (1500–)", "Occitan", "oc", "oci", "", -1 },
    { "Official Aramaic, Imperial Aramaic (700 BC–300 BC)", "ܐܪܡܝܐ", "", "arc", "", -1 },
    { "Ojibwa", "ᐊᓂᔑᓇᐯᒧᐏᐣ (Anishinaabemowin)", "oj", "oji", "", -1 },
    { "Old English (c. 450–1100)", "Englisc", "", "ang", "", -1 },
    { "Old French (842—c. 1400)", "", "", "fro", "", -1 },
    { "Old High German (ca. 750–1050)", "diutisc", "", "goh", "", -1 },
    { "Old Irish (to 900)", "Goídelc", "", "sga", "", -1 },
    { "Old Norse", "norskr", "", "non", "", -1 },
    { "Old Persian (ca. 600–400 BC)", "", "", "peo", "", -1 },
    { "Old Provençal, Old Occitan (–1500)", "", "", "pro", "", -1 },
    { "Oriya", "ଓଡ଼ିଆ", "or", "ori", "", 71 },
    { "Oromo", "Afaan Oromoo", "om", "orm", "", 87 },
    { "Osage", "", "", "osa", "", -1 },
    { "Ossetian, Ossetic", "ирон ӕвзаг", "os", "oss", "", -1 },
    { "Otomian languages", "", "", "oto", "", -1 },
    { "Pahlavi, (Middle Persian)", "", "", "pal", "", -1 },
    { "Palauan", "tekoi ra Belau", "", "pau", "", -1 },
    { "Pali", "पालि", "pi", "pli", "", -1 },
    { "Pampanga, Kapampangan", "Kapampangan", "", "pam", "", -1 },
    { "Pangasinan", "", "", "pag", "", -1 },
    { "Papiamento", "Papiamentu", "", "pap", "", -1 },
    { "Papuan languages", "", "", "paa", "", -1 },
    { "Pashto language, Pashto", "پښتو", "ps", "pus", "", 59 },
    { "Persian", "فارسی", "fa", "fas", "per", 31 },
    { "Philippine languages", "", "", "phi", "", -1 },
    { "Phoenician", "", "", "phn", "", -1 },
    { "Pohnpeian", "", "", "pon", "", -1 },
    { "Polish", "polski", "pl", "pol", "", 25 },
    { "Portuguese", "português", "pt", "por", "", 8 },
    { "Prakrit", "", "", "pra", "", 70 },
    { "Punjabi, Panjabi", "ਪੰਜਾਬੀ, پنجابی", "pa", "pan", "", -1 },
    { "Quechua", "Runa Simi, Kichwa", "qu", "que", "", 132 },
    { "Rajasthani", "राजस्थानी", "", "raj", "", -1 },
    { "Rapanui", "rapanui, pepito ote henua", "", "rap", "", -1 },
    { "Rarotongan, Cook Islands Maori", "", "", "rar", "", -1 },
    { "Reserved for local use", "", "", "qaa-qtz", "", -1 },
    { "Romance languages", "", "", "roa", "", -1 },
    { "Romanian", "română", "ro", "ron", "rum", 37 },
    { "Romansh", "rumantsch grischun", "rm", "roh", "", -1 },
    { "Romany", "rromani ćhib, Romani šib, Romanó", "", "rom", "", -1 },
    { "Rundi", "Rundi", "rn", "run", "", 91 },
    { "Russian", "русский язык", "ru", "rus", "", 32 },
    { "Salishan languages", "", "", "sal", "", -1 },
    { "Samaritan Aramaic", "ארמית, ܐܪܡܝܐ", "", "sam", "", -1 },
    { "Sami languages", "", "", "smi", "", 29 },
    { "Samoan", "gagana fa'a Samoa", "sm", "smo", "", -1 },
    { "Sandawe", "", "", "sad", "", -1 },
    { "Sango", "yângâ tî sängö", "sg", "sag", "", -1 },
    { "Sanskrit", "संस्कृतम्", "sa", "san", "", 65 },
    { "Santali", "संथाली", "", "sat", "", -1 },
    { "Sardinian", "sardu", "sc", "srd", "", -1 },
    { "Sasak", "", "", "sas", "", -1 },
    { "Scots", "Scots leid, Lallans", "", "sco", "", -1 },
    { "Scottish Gaelic, Gaelic", "Gàidhlig", "gd", "gla", "", 144 },
    { "Selkup", "шӧльӄумыт әты", "", "sel", "", -1 },
    { "Semitic languages", "", "", "sem", "", -1 },
    { "Serbian", "српски језик, srpski jezik", "sr", "srp", "", 42 },
    { "Serer", "", "", "srr", "", -1 },
    { "Shan", "", "", "shn", "", -1 },
    { "Shona", "chiShona", "sn", "sna", "", -1 },
    { "Sichuan Yi, Nuosu", "ꆇꉙ", "ii", "iii", "", -1 },
    { "Sicilian", "Sicilianu", "", "scn", "", -1 },
    { "Sidamo", "Sidámo 'Afó", "", "sid", "", -1 },
    { "Sign languages", "", "", "sgn", "", -1 },
    { "Sindhi", "سنڌي، سندھی, सिन्धी", "sd", "snd", "", 62 },
    { "Sinhalese, Sinhala", "සිංහල", "si", "sin", "", 76 },
    { "Sino-Tibetan languages", "", "", "sit", "", -1 },
    { "Siouan languages", "", "", "sio", "", -1 },
    { "Skolt Sami", "sääʼmǩiõll", "", "sms", "", -1 },
    { "Slave (Athapascan)", "", "", "den", "", -1 },
    { "Slavic languages", "", "", "sla", "", -1 },
    { "Slovak", "slovenčina", "sk", "slk", "slo", 39 },
    { "Slovenian", "slovenščina", "sl", "slv", "", 40 },
    { "Sogdian", "", "", "sog", "", -1 },
    { "Somali", "Soomaaliga, af Soomaali", "so", "som", "", 88 },
    { "Songhay languages", "", "", "son", "", -1 },
    { "Soninke", "Soninkanxaane", "", "snk", "", -1 },
    { "Sorbian languages", "", "", "wen", "", -1 },
    { "South American Indian languages", "", "", "sai", "", -1 },
    { "Southern Altai", "алтай тили", "", "alt", "", -1 },
    { "Southern Ndebele", "isiNdebele", "nr", "nbl", "", -1 },
    { "Southern Sami", "saemien giele", "", "sma", "", -1 },
    { "Southern Sotho", "Sesotho", "st", "sot", "", -1 },
    { "Spanish", "español, castellano", "es", "spa", "", 6 },
    { "Sranan Tongo", "", "", "srn", "", -1 },
    { "Sukuma", "", "", "suk", "", -1 },
    { "Sumerian", "eme-ĝir", "", "sux", "", -1 },
    { "Sundanese", "basa Sunda", "su", "sun", "", 139 },
    { "Susu", "", "", "sus", "", -1 },
    { "Swahili", "Kiswahili", "sw", "swa", "", 89 },
    { "Swati", "siSwati", "ss", "ssw", "", -1 },
    { "Swedish", "svenska", "sv", "swe", "", 5 },
    { "Swiss German, Alemannic, Alsatian", "Schwyzerdütsch, Alemannisch, Elsassisch", "", "gsw", "", -1 },
    { "Syriac (Northeastern Neo-Aramaic)", "ܣܘܪܝܝܐ", "", "syr", "", -1 },
    { "Tagalog", "Wikang Tagalog, ᜏᜒᜃᜅ᜔ ᜆᜄᜎᜓᜄ᜔", "tl", "tgl", "", 82 },
    { "Tahitian", "te reo Tahiti, te reo Māʼohi", "ty", "tah", "", -1 },
    { "Tai languages", "", "", "tai", "", -1 },
    { "Tajik", "тоҷикӣ, تاجیکی", "tg", "tgk", "", 55 },
    { "Tamashek", "Tamajeq", "", "tmh", "", -1 },
    { "Tamil", "தமிழ்", "ta", "tam", "", 74 },
    { "Tatar", "татарча, tatarça, تاتارچا", "tt", "tat", "", 135 },
    { "Telugu", "తెలుగు", "te", "tel", "", 75 },
    { "Tereno", "", "", "ter", "", -1 },
    { "Tetum", "Tetun", "", "tet", "", -1 },
    { "Thai", "ภาษาไทย", "th", "tha", "", 22 },
    { "Tibetan", "བོད་ཡིག", "bo", "bod", "tib", 63 },
    { "Tigre", "Tigré, Khasa", "", "tig", "", -1 },
    { "Tigrinya", "ትግርኛ", "ti", "tir", "", 86 },
    { "Time", "", "", "tem", "", -1 },
    { "Tiv", "", "", "tiv", "", -1 },
    { "Tlingit", "Lingít", "", "tli", "", -1 },
    { "Tok Pisin", "Tok Pisin", "", "tpi", "", -1 },
    { "Tokelau", "Tokelau", "", "tkl", "", -1 },
    { "Tonga (Nyasa)", "chiTonga", "", "tog", "", -1 },
    { "Tonga (Tonga Islands)", "faka-Tonga", "to", "ton", "", 147 },
    { "Tsimshian", "", "", "tsi", "", -1 },
    { "Tsonga", "Xitsonga", "ts", "tso", "", -1 },
    { "Tswana", "Setswana", "tn", "tsn", "", -1 },
    { "Tumbuka", "chiTumbuka", "", "tum", "", -1 },
    { "Tupian languages", "Nheengatu", "", "tup", "", -1 },
    { "Turkish", "Türkçe", "tr", "tur", "", 17 },
    { "Turkish, Ottoman (1500–1928)", "", "", "ota", "", -1 },
    { "Turkmen", "Түркмен", "tk", "tuk", "", 56 },
    { "Tuvalu", "'gana Tuvalu", "", "tvl", "", -1 },
    { "Tuvinian", "тыва дыл", "", "tyv", "", -1 },
    { "Twi", "", "tw", "twi", "", -1 },
    { "Udmurt", "удмурт кыл", "", "udm", "", -1 },
    { "Ugaritic", "", "", "uga", "", -1 },
    { "Uighur, Uyghur", "Uyƣurqə, Uyğurçe, ئۇيغۇرچ", "ug", "uig", "", 136 },
    { "Ukrainian", "українська мова", "uk", "ukr", "", 45 },
    { "Umbundu", "úmbúndú", "", "umb", "", -1 },
    { "Upper Sorbian", "hornjoserbsce", "", "hsb", "", -1 },
    { "Urdu", "اردو", "ur", "urd", "", 20 },
    { "Uzbek", "O'zbek, Ўзбек, أۇزبېك", "uz", "uzb", "", 47 },
    { "Vai", "", "", "vai", "", -1 },
    { "Venda", "Tshivenḓa", "ve", "ven", "", -1 },
    { "Vietnamese", "Tiếng Việt", "vi", "vie", "", 80 },
    { "Volapük", "Volapük", "vo", "vol", "", -1 },
    { "Votic", "vaďďa tšeeli", "", "vot", "", -1 },
    { "Wakashan languages", "", "", "wak", "", -1 },
    { "Walloon", "walon", "wa", "wln", "", -1 },
    { "Waray-Waray", "Winaray, Lineyte-Samarnon", "", "war", "", -1 },
    { "Washo", "", "", "was", "", -1 },
    { "Welsh", "Cymraeg", "cy", "cym", "wel", 128 },
    { "Western Frisian", "frysk", "fy", "fry", "", -1 },
    { "Wolaytta, Wolaitta", "", "", "wal", "", -1 },
    { "Wolof", "Wolof", "wo", "wol", "", -1 },
    { "Xhosa", "isiXhosa", "xh", "xho", "", -1 },
    { "Yakut", "Саха тыла", "", "sah", "", -1 },
    { "Yao", "Chiyao", "", "yao", "", -1 },
    { "Yapese", "", "", "yap", "", -1 },
    { "Yiddish", "ייִדיש", "yi", "yid", "", 41 },
    { "Yoruba", "Yorùbá", "yo", "yor", "", -1 },
    { "Yupik languages", "", "", "ypk", "", -1 },
    { "Zande languages", "Pazande", "", "znd", "", -1 },
    { "Zapotec", "", "", "zap", "", -1 },
    { "Zaza, Dimili, Dimli, Kirdki, Kirmanjki, Zazaki", "", "", "zza", "", -1 },
    { "Zenaga", "Tuḍḍungiyya", "", "zen", "", -1 },
    { "Zhuang, Chuang", "Saɯ cueŋƅ, Saw cuengh", "za", "zha", "", -1 },
    { "Zulu", "isiZulu", "zu", "zul", "", -1 },
    { "Zuni", "Shiwi", "", "zun", "", -1 },
    { NULL, NULL, NULL, NULL, NULL, -1 } };

iso639_lang_t * lang_for_code( int code )
{
    char code_string[2];
    iso639_lang_t * lang;
    
    code_string[0] = tolower( ( code >> 8 ) & 0xFF );
    code_string[1] = tolower( code & 0xFF );
    
    for( lang = (iso639_lang_t*) languages; lang->eng_name; lang++ )
    {
        if( !strncmp( lang->iso639_1, code_string, 2 ) )
        {
            return lang;
        }
    }
    
    return (iso639_lang_t*) languages;
}

iso639_lang_t * lang_for_code_s( const char *code )
{
    char code_string[3];
    iso639_lang_t * lang;
    
    code_string[0] = tolower( code[0] );
    code_string[1] = tolower( code[1] );
    code_string[2] = 0;

    for( lang = (iso639_lang_t*) languages; lang->eng_name; lang++ )
    {
        if( !strncmp( lang->iso639_1, code_string, 2 ) )
        {
            return lang;
        }
    }
    
    return (iso639_lang_t*) languages;
}

iso639_lang_t * lang_for_code2( const char *code )
{
    char code_string[4];
    iso639_lang_t * lang;
    
    code_string[0] = tolower( code[0] );
    code_string[1] = tolower( code[1] );
    code_string[2] = tolower( code[2] );
    code_string[3] = 0;
    
    for( lang = (iso639_lang_t*) languages; lang->eng_name; lang++ )
    {
        if( !strcmp( lang->iso639_2, code_string ) )
        {
            return lang;
        }
        if( lang->iso639_2b && !strcmp( lang->iso639_2b, code_string ) )
        {
            return lang;
        }
    }
    
    return (iso639_lang_t*) languages;
}

iso639_lang_t * lang_for_qtcode( short code )
{
    iso639_lang_t * lang;
    
    for( lang = (iso639_lang_t*) languages; lang->eng_name; lang++ )
    {
        if( lang->qtLang == code )
        {
            return lang;
        }
    }
    
    return (iso639_lang_t*) languages;
}

int lang_to_code(const iso639_lang_t *lang)
{
    int code = 0;
    
    if (lang)
        code = (lang->iso639_1[0] << 8) | lang->iso639_1[1];
    
    return code;
}

iso639_lang_t * lang_for_english( const char * english )
{
    iso639_lang_t * lang;
    
    for( lang = (iso639_lang_t *) languages; lang->eng_name; lang++ )
    {
        if( !strcmp( lang->eng_name, english ) )
        {
            return lang;
        }
    }
    
    return (iso639_lang_t *)languages;
}

MP42_OBJC_DIRECT_MEMBERS
@implementation MP42Languages
{
    NSArray<NSString *> *_iso6391languagesArray;
    NSArray<NSString *> *_iso6392languagesArray;
    NSArray<NSString *> *_localizedLanguagesArray;

    // Localized <-> non localized convesion
    NSDictionary<NSString *, NSString *> *_localizedLanguagesToCodeDict;
    NSDictionary<NSString *, NSString *> *_localizedCodeToLanguagesDict;

    // NSLocale code <-> ISO_639_2 conversion
    NSDictionary<NSString *, NSString *> *_codeToISO_639_2Code;
    NSDictionary<NSString *, NSString *> *_ISO_639_2CodeToCode;
}

+ (MP42Languages *)defaultManager
{
    static dispatch_once_t pred;
    static MP42Languages *sharedLanguagesManager = nil;

    dispatch_once(&pred, ^{
        sharedLanguagesManager = [[self alloc] init];
        [sharedLanguagesManager buildCache];
    });
    return sharedLanguagesManager;
}

- (NSArray<NSString *> *)commonLanguages
{
    return @[@"und", @"en", @"fr", @"de", @"ja", @"it", @"nl",
             @"sv" , @"es" , @"da" , @"pt", @"no", @"he",
             @"ar", @"fi", @"el", @"is", @"mt", @"tr",
             @"hr", @"zh", @"ur", @"hi", @"th", @"ko", @"lt", @"pl",
             @"hu", @"et", @"lv", @"se", @"fo", @"fa", @"ro", @"ru",
             @"ga", @"sr", @"sq", @"bg", @"cs", @"sk", @"sl"];
}

- (void)buildCache
{
    NSMutableSet<NSString *> *languagesSet = [NSMutableSet set];

    NSMutableDictionary<NSString *, NSString *> *codeToISO_639_2Code = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *ISO_639_2CodeToCode = [NSMutableDictionary dictionary];

    // First add the languages from our languages list
    for (iso639_lang_t *_languages = (iso639_lang_t *) languages; _languages->iso639_2; _languages++) {
        NSString *code = nil;
        if (strlen(_languages->iso639_1)) {
            code = @(_languages->iso639_1);
            NSString *code2 = @(_languages->iso639_2);
            codeToISO_639_2Code[code] = code2;
            ISO_639_2CodeToCode[code2] = code;
        }
        else {
            code = @(_languages->iso639_2);
            codeToISO_639_2Code[code] = code;
            ISO_639_2CodeToCode[code] = code;
        }

        [languagesSet addObject:code];
    }

    // Then add the extended language tags from NSLocale
    [languagesSet addObjectsFromArray:NSLocale.availableLocaleIdentifiers];

    _codeToISO_639_2Code = [codeToISO_639_2Code copy];
    _ISO_639_2CodeToCode = [ISO_639_2CodeToCode copy];

    // Create the localized list
    NSLocale *locale = NSLocale.currentLocale;
    NSMutableArray<NSString *> *localizedLanguages = [NSMutableArray array];

    NSMutableDictionary<NSString *, NSString *> *localizedLangToCodeDict = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *codeToLocalizedLangDict = [NSMutableDictionary dictionary];

    for (NSString *code in languagesSet) {
        NSString *fixedCode = [code stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
        NSString *localizedName = [locale displayNameForKey:NSLocaleIdentifier value:fixedCode];

        if (!localizedName) {
            localizedName = fixedCode;
        }

        localizedLangToCodeDict[localizedName] = fixedCode;
        codeToLocalizedLangDict[fixedCode] = localizedName;

        [localizedLanguages addObject:localizedName];
    }

    // Sort the list and add the most common languages at the top
    [localizedLanguages sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    for (NSString *code in [[self commonLanguages] reverseObjectEnumerator]) {
        NSString *localizedLang = [locale displayNameForKey:NSLocaleLanguageCode value:code];
        if (localizedLang) {
            [localizedLanguages removeObject:localizedLang];
            [localizedLanguages insertObject:localizedLang atIndex:0];
        }
    }

    _localizedLanguagesToCodeDict = [localizedLangToCodeDict copy];
    _localizedCodeToLanguagesDict = [codeToLocalizedLangDict copy];

    _localizedLanguagesArray = localizedLanguages;
}

#pragma mark - Localization

- (NSString *)extendedTagForLocalizedLang:(NSString *)language
{
    NSString *code = _localizedLanguagesToCodeDict[language];
    if (!code) {
        code = language;
    }
    return code;
}

- (NSString *)localizedLangForExtendedTag:(NSString *)code
{
    NSString *language = _localizedCodeToLanguagesDict[code];
    if (!language) {
        if ([code isEqualToString:@"cmn-Hans"]) {
            language = _localizedCodeToLanguagesDict[@"zh-Hans"];
        }
        else if ([code isEqualToString:@"cmn-Hant"]) {
            language = _localizedCodeToLanguagesDict[@"zh-Hant"];
        }
        else {
            language = code;
        }
    }
    return language;
}

#pragma mark - Language lists

- (NSArray<NSString *> *)ISO_639_1Languages {
    if (!_iso6391languagesArray) {
        NSMutableArray *languagesArray = [[NSMutableArray alloc] init];

        for (iso639_lang_t *_languages = (iso639_lang_t *) languages; _languages->iso639_2; _languages++) {
            if (strlen(_languages->iso639_1))
                [languagesArray addObject:@(_languages->iso639_1)];
        }

        [languagesArray removeObjectsInArray:[self commonLanguages]];

        for (NSString *lang in [[self commonLanguages] reverseObjectEnumerator]) {
            [languagesArray insertObject:lang atIndex:0];
        }
        [languagesArray removeObjectAtIndex:0];
        _iso6391languagesArray = [languagesArray copy];
    }

    return [_iso6391languagesArray copy];
}

- (NSArray<NSString *> *)ISO_639_2Languages {
    if (!_iso6392languagesArray) {
        NSMutableArray *languagesArray = [[NSMutableArray alloc] init];

        for (iso639_lang_t *_languages = (iso639_lang_t *) languages; _languages->iso639_2; _languages++) {
            [languagesArray addObject:@(_languages->iso639_2)];
        }

        [languagesArray removeObjectsInArray:[self commonLanguages]];

        for (NSString *lang in [[self commonLanguages] reverseObjectEnumerator]) {
            [languagesArray insertObject:lang atIndex:0];
        }
        _iso6392languagesArray = [languagesArray copy];
    }

    return [_iso6392languagesArray copy];
}

- (NSArray<NSString *> *)localizedExtendedLanguages {
    return [_localizedLanguagesArray copy];
}

#pragma mark - Validation

- (BOOL)validateExtendedTag:(NSString *)tag {
    NSString *fixedTag = [tag stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    return [NSLocale.availableLocaleIdentifiers containsObject:fixedTag];
}

- (nullable NSString *)normalizedExtendedTag:(NSString *)tag {
    NSString *fixedTag = [tag stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    for (NSString *identifier in NSLocale.availableLocaleIdentifiers) {
        if ([identifier caseInsensitiveCompare:fixedTag] == NSOrderedSame) {
            return [identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
        }
    }
    return tag;
}


#pragma mark - Conversions

+ (nullable NSString *)ISO_639_1CodeForLang:(NSString *)language {
    iso639_lang_t *_languages;
    for (_languages = (iso639_lang_t *) languages; _languages->eng_name; _languages++) {
		if ([[NSString stringWithUTF8String:_languages->eng_name] isEqualToString:language]) {
			return [NSString stringWithUTF8String:_languages->iso639_1];
		}
	}
	return nil;
}

+ (NSString *)langForISO_639_1Code:(NSString *)language
{
    iso639_lang_t *lang = lang_for_code_s(language.UTF8String);
    return @(lang->eng_name);
}

- (NSString *)ISO_639_2CodeForExtendedTag:(NSString *)code
{
    NSDictionary<NSString *, NSString *> *components = [NSLocale componentsFromLocaleIdentifier:code];
    NSString *languageCode = components[@"kCFLocaleLanguageCodeKey"];
    NSString *code2 = _codeToISO_639_2Code[languageCode];
    if (!code2) {
        code2 = @"und";
    }
    return code2;
}

- (NSString *)extendedTagForLang:(NSString *)language
{
    iso639_lang_t *lang = lang_for_english(language.UTF8String);
    return [self extendedTagForISO_639_2:@(lang->iso639_2)];
}

- (NSString *)extendedTagForQTCode:(NSString *)code
{
    iso639_lang_t *lang = lang_for_qtcode(code.integerValue);
    if (strlen(lang->iso639_1)) {
        return @(lang->iso639_1);
    }
    else {
        return @(lang->iso639_2);
    }
}

- (NSString *)extendedTagForISO_639_1:(NSString *)code
{
    iso639_lang_t *lang = lang_for_code_s(code.UTF8String);
    if (strlen(lang->iso639_1)) {
        return @(lang->iso639_1);
    }
    else {
        return @(lang->iso639_2);
    }
}

- (NSString *)extendedTagForISO_639_2:(NSString *)code2
{
    NSString *code = _ISO_639_2CodeToCode[code2];
    if (!code) {
        code = @"und";
    }
    return code;
}

- (NSString *)extendedTagForISO_639_2b:(NSString *)code2
{
    iso639_lang_t *lang = lang_for_code2(code2.UTF8String);
    if (lang) {
        return [self extendedTagForISO_639_2:@(lang->iso639_2)];
    }
    else {
        return @"und";
    }
}

@end
