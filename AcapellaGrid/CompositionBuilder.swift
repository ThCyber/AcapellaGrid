import AVFoundation

/// All takes laid onto a single timeline and rendered as one 2×2 video.
/// Playing one composition through one AVPlayer means the four tracks share a
/// single clock — they cannot drift apart during playback — and export is identical
/// to what you hear.
struct GridComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVMutableAudioMix

    func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        return item
    }
}

enum CompositionBuilder {
    struct Input {
        let cell: Int
        let url: URL
        /// Timeline position of the take's media time 0 (negative trims the head).
        let offset: Double
        let volume: Float
    }

    struct BuildError: LocalizedError {
        var errorDescription: String? { "None of the takes contain video." }
    }

    static let renderSize = CGSize(width: 1920, height: 1080)

    static func cellRect(_ cell: Int) -> CGRect {
        let w = renderSize.width / 2, h = renderSize.height / 2
        return CGRect(x: CGFloat(cell % 2) * w, y: CGFloat(cell / 2) * h, width: w, height: h)
    }

    static func build(_ inputs: [Input], mirror: Bool) async throws -> GridComposition {
        let composition = AVMutableComposition()
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        let timescale: CMTimeScale = 48_000

        for input in inputs {
            let asset = AVURLAsset(url: input.url)
            let duration = try await asset.load(.duration)
            let trim = CMTime(seconds: max(0, -input.offset), preferredTimescale: timescale)
            let delay = CMTime(seconds: max(0, input.offset), preferredTimescale: timescale)
            guard duration > trim else { continue }
            let source = CMTimeRange(start: trim, end: duration)

            if let video = try await asset.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(source, of: video, at: .zero)
                if delay > .zero { track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: delay)) }
                let natural = try await video.load(.naturalSize)
                let (crop, transform) = placement(natural: natural, in: cellRect(input.cell), mirror: mirror)
                let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                instruction.setCropRectangle(crop, at: .zero)
                instruction.setTransform(transform, at: .zero)
                layerInstructions.append(instruction)
            }

            if let audio = try await asset.loadTracks(withMediaType: .audio).first,
               let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(source, of: audio, at: .zero)
                if delay > .zero { track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: delay)) }
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.setVolume(input.volume, at: .zero)
                audioParameters.append(parameters)
            }
        }

        guard !layerInstructions.isEmpty else { throw BuildError() }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = layerInstructions
        instruction.backgroundColor = CGColor(gray: 0.08, alpha: 1)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters

        return GridComposition(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    /// Aspect-fill a source frame into a grid cell: crop the overflow, then scale and move.
    private static func placement(natural: CGSize, in cell: CGRect, mirror: Bool) -> (CGRect, CGAffineTransform) {
        let scale = max(cell.width / natural.width, cell.height / natural.height)
        let visible = CGSize(width: cell.width / scale, height: cell.height / scale)
        let crop = CGRect(x: (natural.width - visible.width) / 2, y: (natural.height - visible.height) / 2,
                          width: visible.width, height: visible.height)
        let transform = mirror
            ? CGAffineTransform(a: -scale, b: 0, c: 0, d: scale, tx: cell.maxX + crop.minX * scale, ty: cell.minY - crop.minY * scale)
            : CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: cell.minX - crop.minX * scale, ty: cell.minY - crop.minY * scale)
        return (crop, transform)
    }
}
