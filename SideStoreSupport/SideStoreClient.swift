//
//  SideStoreClient.swift
//  SideStoreSupport
//
//  Created by s s on 2025/7/20.
//

import Foundation

@available(iOS 17.0, *)
struct SideStoreIntentCaller {
    static let shared = SideStoreIntentCaller()

    private func callBackgroundRefresh(progress: Progress) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            PrivateIntentRunner.runSideStoreRefresh(progress: progress) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // Reuse SideStore's underlying refresh operation. Performing another
    // AppIntent here creates a nested intent that iOS cancels in the background.
    func callRefreshIntent(mangledTypeName _: String, progress: Progress) async throws {
        try await callBackgroundRefresh(progress: progress)
    }

    func callRefreshIntent2(identifier _: String, mangledTypeName _: String, progressCallback: (Progress)->Void ) async throws {
        let progress = Progress(totalUnitCount: 1)
        progressCallback(progress)
        try await callBackgroundRefresh(progress: progress)
    }
}

@available(iOS 17.0, *)
@objc extension SideStoreClient {
    @objc(performRefreshForRealWithIdentifier:mangledTypeName:server:)
    func performRefreshForReal(identifier: String, mangledTypeName: String, server: any RefreshServer) {
        Task {
            do {
                var obs: NSKeyValueObservation? = nil
                try await SideStoreIntentCaller.shared.callRefreshIntent2(identifier: identifier, mangledTypeName: mangledTypeName) { progress in
                    obs = progress.observe(\.fractionCompleted, options: [.new]) { progress, change in
                        if let newValue = change.newValue {
                            server.updateProgress(newValue)
                        }
                    }
                }
                obs?.invalidate()
                server.finish(nil)
            } catch {
                server.finish(error.localizedDescription)
            }
        }
    }

}
