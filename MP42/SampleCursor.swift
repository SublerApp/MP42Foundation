//
//  SampleCursor.swift
//  MP42Foundation
//
//  Created by Damiano Galassi on 12/03/2020.
//  Copyright © 2022 Damiano Galassi. All rights reserved.
//

import Foundation
import CMP42

private struct Edit {
    /// The media start time of the edit segment in track time scale units of the track in the mp4 file.
    let mediaStart: MP4Timestamp

    /// The duration of the edit segment in track time scale units of the track in the mp4 file.
    let duration: MP4Duration

    /// the dwell value of the specified track edit segment.
    /// A value of true  indicates that during this edit segment the media will be paused;
    /// a value of false indicates that during this edit segment the media will be played at its normal rate.
    let dwell: Bool

    /// Edit list version.0 is 32bit, 1 is 64bit.
    let version: UInt64

    var isEmpty: Bool {
        switch (version, mediaStart) {
        case (0, UInt64(UInt32.max)):
            return true
        case (1, UInt64.max):
            return true
        default:
            return false
        }
    }
}

@objc(MP42SampleCursor) public class SampleCursor: NSObject {

    private let fileHandle: MP4FileHandle
    private let trackId: MP4TrackId

    private let edits: [Edit]

    private let movieTimescale: UInt32
    private let trackTimescale: UInt32

    private let numOfSamples: UInt32

    @objc public init?(fileHandle: MP4FileHandle, trackId: MP4TrackId) {
        self.fileHandle = fileHandle
        self.trackId = trackId

        self.movieTimescale = MP4GetTimeScale(fileHandle)
        self.trackTimescale = MP4GetTrackTimeScale(fileHandle, trackId)

        self.numOfSamples = MP4GetTrackNumberOfSamples(fileHandle, trackId)

        if (self.numOfSamples == 0) {
            return nil
        }

        self.edits = Self.readEdits(fileHandle, trackId, movieTimescale)

        self.currentTime = 0

        self.currentEdit = -1
        self.currentEditDuration = 0
        self.currentTrimStart = 0

        self.currentSampleId = 0
        self.currentSampleDuration = 0

        self.presentationTimeStamp = 0
        self.decodeTimeStamp = 0

        super.init()

        reset()
    }

    private static func readEdits(_ fileHandle: MP4FileHandle, _ trackId: MP4TrackId, _ movieTimescale: UInt32) -> [Edit] {
        let numberOfEdits = MP4GetTrackNumberOfEdits(fileHandle, trackId)

        if (numberOfEdits > 0) {
            let range = 1...numberOfEdits

            var editListVersion: UInt64 = 0
            MP4GetTrackIntegerProperty(fileHandle, trackId, "edts.elst.version", &editListVersion)

            let edits = range.map { editId -> Edit in
                let mediaStart = MP4GetTrackEditMediaStart(fileHandle, trackId, editId)
                let duration = MP4GetTrackEditDuration(fileHandle, trackId, editId)
                let durationInTrackTimescale = MP4ConvertToTrackDuration(fileHandle, trackId, duration, movieTimescale)
                let dwell = MP4GetTrackEditDwell(fileHandle, trackId, editId)
                return Edit(mediaStart: mediaStart, duration: durationInTrackTimescale, dwell: dwell == 1, version: editListVersion)
            }

            return edits
        } else {
            let duration = MP4GetTrackDuration(fileHandle, trackId)
            return [Edit(mediaStart: 0, duration: duration, dwell: false, version: 1)]
        }
    }

    private var currentTime: MP4Timestamp

    private var currentEdit: Int
    private var currentEditDuration: MP4Duration
    private var currentTrimStart: MP4Duration

    @objc public private(set) var currentSampleId: MP4SampleId
    @objc public private(set) var currentSampleDuration: MP4Duration

    @objc public private(set) var presentationTimeStamp: MP4Timestamp
    @objc public private(set) var decodeTimeStamp: MP4Timestamp

    private func skipEmptyEdits() {
        while currentEdit < edits.endIndex  {
            let edit = edits[currentEdit]
            if edit.isEmpty {
                currentTime += edit.duration
                currentEdit += 1
            } else {
                break
            }
        }
    }

    private func resetMediaTime() {
        let edit = edits[currentEdit]
        currentSampleId = MP4GetSampleIdFromTime(fileHandle, trackId, edit.mediaStart, 0)
        let time = MP4GetSampleTime(fileHandle, trackId, currentSampleId)
        currentSampleId -= 1

        if edit.isEmpty == false {
            currentTrimStart = edit.mediaStart - time
        } else {
            currentTrimStart = 0
        }
        currentEditDuration = 0
    }

    private func nextEdit() {
        currentEdit += 1
        guard currentEdit < edits.endIndex else { return }
        skipEmptyEdits()
        resetMediaTime()
    }

    private func reset() {
        currentTime = 0

        currentEdit = -1
        currentEditDuration = 0
        currentTrimStart = 0

        currentSampleId = 0
        currentSampleDuration = 0

        presentationTimeStamp = 0
        decodeTimeStamp = 0

        nextEdit()

        _ = stepInDecodeOrder(byCount: 1)
    }

    @objc public func stepInDecodeOrder(byCount stepCount: Int64) -> Int64 {
        guard currentEdit < edits.endIndex else { return 0 }

        var stepped: Int64 = 0

        for _ in 0..<stepCount {

            currentSampleId += 1

            let duration = MP4GetSampleDuration(fileHandle, trackId, currentSampleId)
            let offset = MP4GetSampleRenderingOffset(fileHandle, trackId, currentSampleId)

            decodeTimeStamp = currentTime
            presentationTimeStamp = currentTime + offset

            let edit = edits[currentEdit]

            if (edit.dwell) {
                currentSampleDuration = edit.duration
                nextEdit()
            } else if (currentSampleId >= numOfSamples || currentEditDuration + duration >= edit.duration) {
                currentSampleDuration = edit.duration - currentEditDuration
                if (currentSampleDuration > currentTrimStart) {
                    currentSampleDuration -= currentTrimStart
                }
                nextEdit()
            } else {
                currentSampleDuration = duration - currentTrimStart
                currentTrimStart = 0
            }

            currentEditDuration += currentSampleDuration
            currentTime += currentSampleDuration
            stepped += 1
        }

        return stepped
    }
}
