// Tests/TidyCoreTests/Watcher/SettleTimerTests.swift
import Testing
@testable import TidyCore

@Suite("SettleTimer")
struct SettleTimerTests {
    @Test("reports file as unsettled immediately after touch")
    func unsettledImmediately() async {
        let timer = SettleTimer(settleSeconds: 5)
        await timer.touch(path: "/Downloads/file.pdf")
        let settled = await timer.isSettled(path: "/Downloads/file.pdf")
        #expect(settled == false)
    }

    @Test("reports file as settled after enough time passes")
    func settledAfterDelay() async throws {
        let timer = SettleTimer(settleSeconds: 0.1)
        await timer.touch(path: "/Downloads/file.pdf")
        try await Task.sleep(for: .milliseconds(150))
        let settled = await timer.isSettled(path: "/Downloads/file.pdf")
        #expect(settled == true)
    }

    @Test("resets settle time on re-touch")
    func resetOnReTouch() async throws {
        let timer = SettleTimer(settleSeconds: 0.2)
        await timer.touch(path: "/Downloads/file.pdf")
        try await Task.sleep(for: .milliseconds(100))
        await timer.touch(path: "/Downloads/file.pdf")
        try await Task.sleep(for: .milliseconds(100))
        let settled = await timer.isSettled(path: "/Downloads/file.pdf")
        #expect(settled == false)
    }

    @Test("tracks multiple files independently")
    func multipleFiles() async throws {
        let timer = SettleTimer(settleSeconds: 0.1)
        await timer.touch(path: "/Downloads/a.pdf")
        try await Task.sleep(for: .milliseconds(150))
        await timer.touch(path: "/Downloads/b.pdf")
        #expect(await timer.isSettled(path: "/Downloads/a.pdf") == true)
        #expect(await timer.isSettled(path: "/Downloads/b.pdf") == false)
    }

    @Test("removes tracking for a path")
    func remove() async {
        let timer = SettleTimer(settleSeconds: 5)
        await timer.touch(path: "/Downloads/file.pdf")
        await timer.remove(path: "/Downloads/file.pdf")
        let settled = await timer.isSettled(path: "/Downloads/file.pdf")
        #expect(settled == true)
    }
}
