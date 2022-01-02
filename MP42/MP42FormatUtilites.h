//
//  MP42FormatUtilites.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 10/11/15.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

#ifndef MP42FormatUtilites_h
#define MP42FormatUtilites_h

#import "MP42MediaFormat.h"

#ifdef __cplusplus
extern "C" {
#endif
    uint8_t *CreateEsdsFromSetupData(uint8_t *codecPrivate, size_t vosLen, size_t *esdsLen, int trackID, bool audio, bool write_version);
    ComponentResult ReadESDSDescExt(void* descExt, UInt8 **buffer, int *size, int versionFlags);

    UInt32 getDefaultChannelLayout(UInt32 channelsCount);

    int readAC3Config(uint64_t acmod, uint64_t lfeon, UInt32 *channelsCount, UInt32 *channelLayoutTag);
	int readEAC3Config(const uint8_t *cookie, uint32_t cookieLen, UInt32 *channelsCount, UInt32 *channelLayoutTag, UInt8 *ec3ExtensionType, UInt8 *complexityIndex);

    int analyze_EAC3(void **context ,uint8_t *frame, uint32_t size);
    CFDataRef createCookie_EAC3(void *context);
	uint8_t get_num_objects_EAC3(void *context);
    void free_EAC3_context(void *context);

    typedef struct {
        uint16_t wFormatTag;
        uint16_t nChannels;
        uint32_t nSamplesPerSec;
        uint32_t nAvgBytesPerSec;
        uint16_t nBlockAlign;
        uint16_t wBitsPerSample;
        uint16_t cbSize;
    } waveformatex_t;

    typedef struct {
        uint32_t  Data1;
        uint16_t  Data2;
        uint16_t  Data3;
        uint8_t   Data4[8];
    } waveformatex_guid_t;

    typedef struct {
        waveformatex_t Format;
        union {
            uint16_t wValidBitsPerSample;
            uint16_t wSamplesPerBlock;
            uint16_t wReserved;
        } Samples;
        uint32_t                dwChannelMask;
        waveformatex_guid_t     SubFormat;
    } waveformatextensible_t;

    FourCharCode readWaveFormat(waveformatextensible_t *ex);
    UInt32 readWaveChannelLayout(waveformatextensible_t *ex);

    int analyze_WAVEFORMATEX(const uint8_t *cookie, uint32_t cookieLen, waveformatextensible_t *ex);

    typedef struct MPEG4AudioConfig {
        int object_type;
        int sampling_index;
        int sample_rate;
        int chan_config;
        int sbr; ///< -1 implicit, 1 presence
        int ext_object_type;
        int ext_sampling_index;
        int ext_sample_rate;
        int ext_chan_config;
        int channels;
        int ps;  ///< -1 implicit, 1 presence
        int frame_length_short;
    } MPEG4AudioConfig;

#define EC3Extension_JOC  1
#define EC3Extension_None 0
	
	typedef struct eac3_info {
		uint8_t *frame;
		uint32_t size;
		
		uint8_t ec3_done;
		uint8_t num_blocks;
		
		/* Layout of the EC3SpecificBox */
		/* maximum bitrate */
		uint16_t data_rate;
		/* number of independent substreams */
		uint8_t  num_ind_sub;
		/*
		 See ETSI TS 103 420 V1.2.1 (2018-10)
		 8.3.2 Semantics
		 8.3.2.1 flag_ec3_extension_type_a
		 The element flag_ec3_extension_type_a is a flag that, if set to true, indicates the enhanced AC-3 extension as defined in the present document.
		 8.3.2.2 complexity_index_type_a
		 The element complexity_index_type_a is an unsigned integer that indicates the decoding complexity of the enhanced AC-3 extension defined in the present document.
		 The value of this field shall be equal to the total number of bed objects, ISF objects and dynamic objects indicated by the parameters in the program_assignment section of the object audio metadata payload.
		 The maximum value of this field shall be 16.
		 */
		uint8_t  ec3_extension_type;			// 0x01 -> E-AC3 JOC extension
		uint8_t  complexity_index;				// 0 <= complexity_index <= 16
		struct {
			/* sample rate code (see ff_ac3_sample_rate_tab) 2 bits */
			uint8_t fscod;
			/* bit stream identification 5 bits */
			uint8_t bsid;
			/* one bit reserved */
			/* audio service mixing (not supported yet) 1 bit */
			/* bit stream mode 3 bits */
			uint8_t bsmod;
			/* audio coding mode 3 bits */
			uint8_t acmod;
			/* sub woofer on 1 bit */
			uint8_t lfeon;
			/* 3 bits reserved */
			/* number of dependent substreams associated with this substream 4 bits */
			uint8_t num_dep_sub;
			/* channel locations of the dependent substream(s), if any, 9 bits */
			uint16_t chan_loc;
			/* if there is no dependent substream, then one bit reserved instead */
		} substream[1]; /* TODO: support 8 independent substreams */
	} EAC3Info;

    int analyze_ESDS(MPEG4AudioConfig *c, const uint8_t *cookie, uint32_t cookieLen);

    int analyze_AVC(const uint8_t *cookie, uint32_t cookieLen);

    int analyze_HEVC(const uint8_t *frame, uint32_t cookieLen, bool *completeness);
    void force_HEVC_completeness(const uint8_t *cookie, uint32_t cookieLen);

#ifdef __cplusplus
}
#endif

#endif /* MP42FormatUtilites_h */
