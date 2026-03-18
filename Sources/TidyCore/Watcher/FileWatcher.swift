import Foundation
import CoreServices

public enum FileEvent: Sendable {
    case created(path: String, sourceFolder: String?)
    case modified(path: String, sourceFolder: String?)
    case removed(path: String, sourceFolder: String?)
    case movedOut(path: String, sourceFolder: String?)
    case renamed(oldPath: String, newPath: String, sourceFolder: String?)
}

public final class FileWatcher: @unchecked Sendable {
    private let watchPaths: [String]
    private var stream: FSEventStreamRef?
    private let eventContinuation: AsyncStream<FileEvent>.Continuation
    public let events: AsyncStream<FileEvent>

    /// Pending renamed event waiting for its pair.
    /// FSEvents delivers renames as two consecutive events with kFSEventStreamEventFlagItemRenamed.
    private var pendingRename: (path: String, sourceFolder: String?)?

    /// Multi-path initializer. Each path becomes a watched root.
    public init(paths: [String]) {
        self.watchPaths = paths
        var continuation: AsyncStream<FileEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    /// Single-path convenience initializer (backward compatible).
    public convenience init(watchPath: String) {
        self.init(paths: [watchPath])
    }

    /// Determine which watched folder an event path belongs to.
    private func sourceFolder(for path: String) -> String? {
        // Find the longest matching prefix among watched paths.
        var best: String? = nil
        for wp in watchPaths {
            let prefix = wp.hasSuffix("/") ? wp : wp + "/"
            if path.hasPrefix(prefix) || path == wp {
                if best == nil || wp.count > best!.count {
                    best = wp
                }
            }
        }
        return best
    }

    public func start() {
        let pathsToWatch = watchPaths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, eventFlags, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

                for i in 0..<numEvents {
                    let path = paths[i]
                    let flag = flags[i]
                    if flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 { continue }

                    let source = watcher.sourceFolder(for: path)

                    if flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                        // Rename events come in pairs from FSEvents.
                        if let pending = watcher.pendingRename {
                            // Second event of the pair — emit a renamed event.
                            watcher.pendingRename = nil
                            watcher.eventContinuation.yield(
                                .renamed(oldPath: pending.path, newPath: path, sourceFolder: pending.sourceFolder)
                            )
                        } else {
                            // First event of the pair — buffer it.
                            watcher.pendingRename = (path: path, sourceFolder: source)
                        }
                    } else {
                        // If a rename was pending but the next event isn't a rename,
                        // flush it as movedOut (unpaired rename = file left the watched tree).
                        if let pending = watcher.pendingRename {
                            watcher.pendingRename = nil
                            if !FileManager.default.fileExists(atPath: pending.path) {
                                watcher.eventContinuation.yield(
                                    .movedOut(path: pending.path, sourceFolder: pending.sourceFolder)
                                )
                            }
                        }

                        if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                            watcher.eventContinuation.yield(.created(path: path, sourceFolder: source))
                        } else if flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                            watcher.eventContinuation.yield(.modified(path: path, sourceFolder: source))
                        } else if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                            watcher.eventContinuation.yield(.removed(path: path, sourceFolder: source))
                        }
                    }
                }

                // If a rename is still pending after processing all events in this batch,
                // flush it as movedOut (the pair's second event may never arrive).
                if let pending = watcher.pendingRename {
                    watcher.pendingRename = nil
                    if !FileManager.default.fileExists(atPath: pending.path) {
                        watcher.eventContinuation.yield(
                            .movedOut(path: pending.path, sourceFolder: pending.sourceFolder)
                        )
                    }
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        eventContinuation.finish()
    }

    deinit { stop() }
}
