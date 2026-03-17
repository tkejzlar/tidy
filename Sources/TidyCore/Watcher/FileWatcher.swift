import Foundation
import CoreServices

public enum FileEvent: Sendable {
    case created(path: String)
    case modified(path: String)
    case removed(path: String)
    case movedOut(path: String)
}

public final class FileWatcher: @unchecked Sendable {
    private let watchPath: String
    private var stream: FSEventStreamRef?
    private let eventContinuation: AsyncStream<FileEvent>.Continuation
    public let events: AsyncStream<FileEvent>

    public init(watchPath: String) {
        self.watchPath = watchPath
        var continuation: AsyncStream<FileEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func start() {
        let pathsToWatch = [watchPath] as CFArray
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
                guard let info = info, let eventFlags = eventFlags else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

                for i in 0..<numEvents {
                    let path = paths[i]
                    let flag = flags[i]
                    if flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 { continue }
                    if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                        watcher.eventContinuation.yield(.created(path: path))
                    } else if flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                        watcher.eventContinuation.yield(.modified(path: path))
                    } else if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                        watcher.eventContinuation.yield(.removed(path: path))
                    } else if flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                        if !FileManager.default.fileExists(atPath: path) {
                            watcher.eventContinuation.yield(.movedOut(path: path))
                        }
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
