//
//  ScanCredentialsPromptPresenterTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

@MainActor
struct ScanCredentialsPromptPresenterTests {

    /// The prompt only goes on screen once the asking task actually runs, so
    /// every test has to let it get that far before answering it.
    private func waitUntilPresented(_ presenter: ScanCredentialsPromptPresenter) async {
        for _ in 0..<100 where !presenter.isPresented {
            await Task.yield()
        }
    }

    @Test func handsTheTypedCredentialsBackToTheCaller() async {
        let presenter = ScanCredentialsPromptPresenter()
        let asking = Task { await presenter.credentials(retryReason: nil) }

        await waitUntilPresented(presenter)
        #expect(presenter.isPresented)
        presenter.submit(username: "ilyas", password: "hunter2")

        let credentials = await asking.value
        #expect(credentials?.username == "ilyas")
        #expect(credentials?.password == "hunter2")
        #expect(presenter.isPresented == false)
    }

    @Test func aDismissedPromptAnswersWithNothing() async {
        let presenter = ScanCredentialsPromptPresenter()
        let asking = Task { await presenter.credentials(retryReason: nil) }

        await waitUntilPresented(presenter)
        presenter.cancel()

        #expect(await asking.value == nil)
        #expect(presenter.isPresented == false)
    }

    @Test func carriesTheRetryReasonIntoTheSheet() async {
        let presenter = ScanCredentialsPromptPresenter()
        #expect(presenter.retryReason == nil)

        let asking = Task { await presenter.credentials(retryReason: "The server did not accept these credentials.") }
        await waitUntilPresented(presenter)

        #expect(presenter.retryReason == "The server did not accept these credentials.")
        presenter.cancel()
        _ = await asking.value
    }

    @Test func aSecondAskDoesNotLeaveTheFirstCallerWaiting() async {
        let presenter = ScanCredentialsPromptPresenter()
        let first = Task { await presenter.credentials(retryReason: nil) }
        await waitUntilPresented(presenter)

        let second = Task { await presenter.credentials(retryReason: "Try again.") }
        // The first ask is answered with nothing the moment it is replaced.
        #expect(await first.value == nil)

        await waitUntilPresented(presenter)
        presenter.submit(username: "ilyas", password: "hunter2")
        #expect(await second.value?.username == "ilyas")
    }

    @Test func closingASheetNobodyIsWaitingOnDoesNothing() {
        let presenter = ScanCredentialsPromptPresenter()

        // A swipe on a sheet that was already answered by the submit button
        // must not trip over a continuation that is gone.
        presenter.cancel()
        presenter.cancel()
        #expect(presenter.isPresented == false)
    }
}
