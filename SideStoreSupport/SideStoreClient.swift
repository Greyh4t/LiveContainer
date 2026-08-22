//
//  SideStoreClient.swift
//  SideStoreSupport
//
//  Created by s s on 2025/7/20.
//

import Foundation
import AppIntents
import OSLog

enum SideStoreIntentError: LocalizedError {
    case typeNotFound(String)
    case typeIsNotAppIntent(String)

    var errorDescription: String? {
        switch self {
        case .typeNotFound(let name):
            return "SideStore refresh intent type was not found: \(name)"
        case .typeIsNotAppIntent(let name):
            return "SideStore type is not an AppIntent: \(name)"
        }
    }
}

@available(iOS 17.0, *)
private func resolveType(_ mangledTypeName: String) throws -> any Any.Type {
    let bytes = Array(mangledTypeName.utf8)
    let resolvedType: Any.Type? = bytes.withUnsafeBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else {
            return nil
        }

        // Swift exposes the runtime symbol swift_getTypeByMangledNameInContext
        // as _getTypeByMangledNameInContext. The name intentionally omits
        // the "$s" prefix, which is the form accepted for this module.
        return _getTypeByMangledNameInContext(
            baseAddress,
            UInt(buffer.count),
            genericContext: nil,
            genericArguments: nil
        )
    }

    guard let resolvedType else {
        throw SideStoreIntentError.typeNotFound(mangledTypeName)
    }

    return resolvedType
}

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

    // SideStore is already loaded in the current LiveContainer process. Reuse
    // its ordinary refresh bridge; manually performing another AppIntent still
    // creates a nested intent and is cancelled on a background cold launch.
    func callRefreshIntent(mangledTypeName _: String, progress: Progress) async throws {
        try await callBackgroundRefresh(progress: progress)
    }

    // SideStore is loaded in LiveProcess without its own AppIntent execution
    // context. Invoke SideStore's ordinary background-refresh bridge rather than
    // nesting or manually performing another AppIntent.
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
