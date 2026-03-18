// Sources/TidyCore/Sync/SyncDirectoryWatcher.swift
import Foundation
import CoreServices

public final class SyncDirectoryWatcher: @unchecked Sendable {
    private let path: String
    private var stream: FSEventStreamRef?
    private let callback: @Sendable (String) -> Void

    public init(path: String, onChange: @escaping @Sendable (String) -> Void) {
        self.path = path
        self.callback = onChange
    }

    public func start() {
        let pathCF = path as CFString
        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(CallbackBox(callback)).toOpaque()

        stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info, let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
                for i in 0..<numEvents {
                    let path = paths[i]
                    if path.hasSuffix(".json") {
                        box.callback(path)
                    }
                }
            },
            &context,
            [pathCF] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    private final class CallbackBox: @unchecked Sendable {
        let callback: @Sendable (String) -> Void
        init(_ callback: @escaping @Sendable (String) -> Void) { self.callback = callback }
    }
}
