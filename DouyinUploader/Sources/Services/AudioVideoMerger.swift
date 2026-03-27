import Foundation
import AVFoundation

/// 音视频合并工具
/// 将音乐文件作为背景音乐叠加到视频上（保留原声）
/// 音乐短于视频则循环，长于视频则截断
final class AudioVideoMerger {

    var onLog: ((LogLevel, String) -> Void)?

    /// 合并视频和音乐
    /// - Parameters:
    ///   - videoURL: 原始视频文件 URL
    ///   - musicURL: 音乐文件 URL（mp3/m4a）
    ///   - outputURL: 输出文件 URL（nil 则自动生成临时路径）
    /// - Returns: 合并后的视频文件 URL
    func merge(videoURL: URL, musicURL: URL, outputURL: URL? = nil) async throws -> URL {
        log(.info, "开始合并音视频...")

        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)

        // 获取时长
        let videoDuration = try await videoAsset.load(.duration)
        let musicDuration = try await musicAsset.load(.duration)

        log(.info, "视频时长: \(CMTimeGetSeconds(videoDuration))s, 音乐时长: \(CMTimeGetSeconds(musicDuration))s")

        let composition = AVMutableComposition()

        // 1. 添加视频轨道（含原声）
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw MergerError.noVideoTrack
        }
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)

        // 2. 添加原声音频轨道（如果有）
        if let originalAudioTrack = try await videoAsset.loadTracks(withMediaType: .audio).first {
            let compositionOriginalAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try compositionOriginalAudio.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: originalAudioTrack, at: .zero)
        }

        // 3. 添加背景音乐轨道（循环填充到视频时长）
        guard let musicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first else {
            throw MergerError.noAudioTrack
        }

        let compositionMusicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

        let videoSeconds = CMTimeGetSeconds(videoDuration)
        let musicSeconds = CMTimeGetSeconds(musicDuration)

        if musicSeconds >= videoSeconds {
            // 音乐比视频长：截断到视频长度
            try compositionMusicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: musicTrack, at: .zero)
        } else {
            // 音乐比视频短：循环填充
            var insertTime = CMTime.zero
            while CMTimeGetSeconds(insertTime) < videoSeconds {
                let remaining = CMTimeSubtract(videoDuration, insertTime)
                let insertDuration = CMTimeMinimum(musicDuration, remaining)
                try compositionMusicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration), of: musicTrack, at: insertTime)
                insertTime = CMTimeAdd(insertTime, musicDuration)
            }
            log(.info, "音乐循环 \(Int(ceil(videoSeconds / musicSeconds))) 次")
        }

        // 4. 设置音频混合（可调节音乐音量）
        let audioMix = AVMutableAudioMix()
        let musicMixParams = AVMutableAudioMixInputParameters(track: compositionMusicTrack)
        musicMixParams.setVolume(0.3, at: .zero) // 背景音乐音量 30%
        audioMix.inputParameters = [musicMixParams]

        // 5. 导出
        let output = outputURL ?? generateOutputURL(from: videoURL)
        // 删除已存在的输出文件
        try? FileManager.default.removeItem(at: output)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw MergerError.exportSessionFailed
        }
        exportSession.outputURL = output
        exportSession.outputFileType = .mp4
        exportSession.audioMix = audioMix

        log(.info, "导出合并视频...")
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
            log(.info, "合并完成: \(output.lastPathComponent) (\(size / 1024 / 1024)MB)")
            return output
        case .failed:
            throw MergerError.exportFailed(exportSession.error?.localizedDescription ?? "未知错误")
        case .cancelled:
            throw MergerError.exportCancelled
        default:
            throw MergerError.exportFailed("导出状态: \(exportSession.status.rawValue)")
        }
    }

    private func generateOutputURL(from videoURL: URL) -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("douyin_merged", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let name = videoURL.deletingPathExtension().lastPathComponent + "_merged"
        return tempDir.appendingPathComponent(name + ".mp4")
    }

    private func log(_ level: LogLevel, _ message: String) {
        onLog?(level, message)
    }
}

// MARK: - 错误

enum MergerError: LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case exportSessionFailed
    case exportFailed(String)
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "视频文件中没有视频轨道"
        case .noAudioTrack: return "音乐文件中没有音频轨道"
        case .exportSessionFailed: return "无法创建导出会话"
        case .exportFailed(let msg): return "视频导出失败: \(msg)"
        case .exportCancelled: return "视频导出被取消"
        }
    }
}
