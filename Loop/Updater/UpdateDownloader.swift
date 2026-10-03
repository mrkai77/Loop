//
//  UpdateDownloader.swift
//  Loop
//
//  Created by Kami on 2026-01-22.
//

import AppKit
import Foundation
import Scribe

@Loggable
final class UpdateDownloader: NSObject {
    // MARK: - Properties

    private var urlSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var progressClosure: (@MainActor (UpdateProgress) -> ())?
    private var completionClosure: ((Result<URL, Error>) -> ())?
    private(set) var isDownloading = false
    private var performanceTracker: PerformanceTracker = .init()
    private var loopSupportDirectory: URL { LoopSupportPaths.loopDirectory(homeDirectory: FileManager.default.homeDirectoryForCurrentUser) }

    deinit {
        downloadTask?.cancel()
        downloadTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: - Public Interface

    func downloadUpdate(
        manifest: UpdateManifest,
        progress: @escaping @MainActor (UpdateProgress) -> ()
    ) async throws -> URL {
        guard !isDownloading else {
            throw DownloadError.downloadInProgress
        }

        guard let downloadURL = URL(string: manifest.downloadUrl) else {
            throw DownloadError.invalidURL(manifest.downloadUrl)
        }

        log.info("Starting download - URL: \(manifest.downloadUrl), Version: \(manifest.version)")

        try FileManager.default.createDirectory(
            at: loopSupportDirectory,
            withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            setupDownload(url: downloadURL, progress: progress) { result in
                switch result {
                case let .success(success):
                    continuation.resume(returning: success)
                case let .failure(failure):
                    continuation.resume(throwing: failure)
                }
            }
        }
    }

    func cancel() {
        log.info("Cancelling download")
        isDownloading = false
        downloadTask?.cancel()

        Task {
            await cleanup()
        }
    }

    // MARK: - Private Implementation

    private func setupDownload(
        url: URL,
        progress: @escaping @MainActor (UpdateProgress) -> (),
        completion: @escaping (Result<URL, Error>) -> ()
    ) {
        isDownloading = true
        progressClosure = progress
        completionClosure = completion
        performanceTracker.reset()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 30.0 * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        downloadTask = urlSession?.downloadTask(with: url)
        downloadTask?.resume()
    }

    private nonisolated func handleDownloadCompletion(at location: URL, originalURL: URL) {
        log.info("Download completed - Temp Location: \(location.path)")

        var finalURL: URL

        do {
            finalURL = try FileOperations.moveDownloadedFile(
                from: location,
                originalURL: originalURL,
                to: loopSupportDirectory
            )
            try FileValidator.validateDownloadedFile(at: finalURL)
        } catch {
            handleError(error)
            return
        }

        // Now that the file has been moved synchronously, we can launch a task to complete the update.

        Task {
            do {
                try await handleCompletion(with: finalURL)
            } catch {
                handleError(error)
            }
        }
    }

    private func handleCompletion(with url: URL) async throws {
        completionClosure?(.success(url))
        await cleanup()
    }

    private func handleError(_ error: Error) {
        completionClosure?(.failure(error))
        Task { await cleanup() }
    }

    @MainActor
    private func cleanup() async {
        isDownloading = false
        downloadTask?.cancel()
        downloadTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        progressClosure = nil
        completionClosure = nil
        performanceTracker.reset()
    }
}

// MARK: URLSessionDownloadDelegate

extension UpdateDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            handleError(DownloadError.networkError(.init(URLError.Code(rawValue: httpResponse.statusCode))))
            return
        }

        guard let originalURL = downloadTask.originalRequest?.url else {
            handleError(DownloadError.missingOriginalURL)
            return
        }

        handleDownloadCompletion(at: location, originalURL: originalURL)
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard self.isDownloading else { return }

            let progress = self.performanceTracker.updateProgress(
                bytesWritten: bytesWritten,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )

            self.progressClosure?(progress)
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }

        Task {
            guard self.isDownloading else { return }

            log.error("Download failed: \(error.localizedDescription)")

            let downloadError: DownloadError = (error as? URLError).map(DownloadError.networkError) ?? .unknown(error)
            self.handleError(downloadError)
        }
    }
}

// MARK: - PerformanceTracker

private struct PerformanceTracker {
    private var lastProgressUpdate: Date?
    private var speedSamples: CircularBuffer<Double> = .init(capacity: 5)

    mutating func reset() {
        lastProgressUpdate = Date()
        speedSamples.clear()
    }

    mutating func updateProgress(
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) -> UpdateProgress {
        let now = Date()
        let percentage = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        // Update speed calculation
        if let lastUpdate = lastProgressUpdate {
            let timeDelta = now.timeIntervalSince(lastUpdate)
            if timeDelta > 0.5 { // Update every 500ms
                let speed = Double(bytesWritten) / timeDelta / 1_048_576 // MB/s
                speedSamples.append(speed)
                lastProgressUpdate = now
            }
        } else {
            lastProgressUpdate = now
        }

        let downloadSpeed = calculateAverageSpeed()
        let estimatedTimeRemaining = calculateETA(speed: downloadSpeed, remainingBytes: totalBytesExpectedToWrite - totalBytesWritten)

        return UpdateProgress(
            phase: .downloading,
            percentage: percentage,
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            estimatedTimeRemaining: estimatedTimeRemaining,
            downloadSpeed: downloadSpeed
        )
    }

    private func calculateAverageSpeed() -> Double? {
        let samples = speedSamples.elements
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func calculateETA(speed: Double?, remainingBytes: Int64) -> TimeInterval? {
        guard let speed, speed > 0 else { return nil }
        return Double(remainingBytes) / (speed * 1_048_576)
    }
}

// MARK: - FileOperations

@Loggable(style: .static)
private enum FileOperations {
    static func moveDownloadedFile(from tempLocation: URL, originalURL: URL, to loopDir: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: tempLocation.path) else {
            log.error("Downloaded file does not exist at \(tempLocation.path)")
            throw DownloadError.fileValidationFailed("File doesn't exist at temporary download directory")
        }

        // Preserve original filename instead of renaming to "LoopUpdate.zip"
        let originalFilename = originalURL.lastPathComponent
        let finalURL = loopDir.appendingPathComponent(originalFilename)
        let tempFinalURL = loopDir.appendingPathComponent("\(originalFilename).tmp")

        log.info("Moving downloaded file - From: \(tempLocation.path), To: \(finalURL.path), Original: \(originalURL.absoluteString)")

        // Move to Application Support/Loop/Loop.zip.tmp
        try? FileManager.default.removeItem(at: tempFinalURL)
        try FileManager.default.moveItem(at: tempLocation, to: tempFinalURL)

        // Rename to to Application Support/Loop/Loop.zip
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: tempFinalURL, to: finalURL)

        log.info("File moved successfully to: \(finalURL.path)")

        return finalURL
    }
}

// MARK: - FileValidator

private enum FileValidator {
    static func validateDownloadedFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DownloadError.fileValidationFailed("Downloaded file does not exist")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
            throw DownloadError.fileValidationFailed("Downloaded file is empty")
        }
    }
}

// MARK: - DownloadError

enum DownloadError: LocalizedError {
    case downloadInProgress
    case invalidURL(String)
    case environmentError(String)
    case insufficientDiskSpace(available: Int64, required: Int64)
    case fileValidationFailed(String)
    case networkError(URLError)
    case missingOriginalURL
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .downloadInProgress:
            return "A download is already in progress"
        case let .invalidURL(url):
            return "Invalid download URL: \(url)"
        case let .environmentError(message):
            return "Environment error: \(message)"
        case let .insufficientDiskSpace(available, required):
            let availableMB = available / 1_048_576
            let requiredMB = required / 1_048_576
            return "Insufficient disk space: \(availableMB)MB available, \(requiredMB)MB required"
        case let .fileValidationFailed(reason):
            return "File validation failed: \(reason)"
        case let .networkError(urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .missingOriginalURL:
            return "Download task is missing its original URL"
        case let .unknown(error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - CircularBuffer

private struct CircularBuffer<T> {
    private var buffer: [T] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    var elements: [T] { buffer }

    mutating func append(_ element: T) {
        buffer.append(element)
        if buffer.count > capacity {
            buffer.removeFirst()
        }
    }

    mutating func clear() {
        buffer.removeAll()
    }
}
