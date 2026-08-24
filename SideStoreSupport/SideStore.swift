//
//  SideStore.swift
//  SideStoreSupport
//
//  Created by s s on 2025/7/20.
//

import Foundation
import AppIntents
import UserNotifications
import Security

@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> CFTypeRef

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(
    _ task: CFTypeRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> Unmanaged<CFTypeRef>?

private func sharedAuthenticationValue(forKey key: String) -> String? {
    let task = SecTaskCreateFromSelf(nil)
    guard let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)?.takeRetainedValue(),
          let groups = value as? [String],
          let accessGroup = groups.first(where: { $0.hasSuffix(".com.kdt.livecontainer.shared") })
    else { return nil }

    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.kdt.livecontainer",
        kSecAttrAccount: key,
        kSecAttrAccessGroup: accessGroup,
        kSecAttrSynchronizable: kSecAttrSynchronizableAny,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne
    ]
    var result: Unmanaged<CFTypeRef>?
    guard LCHostSecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result?.takeRetainedValue() as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
}

@available(iOS 17.0, *)
func performIntentRefresh(identifier: String, mangledTypeName: String, intentProgress: Progress) async throws {
    intentProgress.totalUnitCount = 100
    NSLog("[LCRefresh] route begin process=%@ bundle=%@ isSideStore=%d hasLC_HOME=%d hasLP_HOME=%d intent=%@",
          ProcessInfo.processInfo.processName,
          Bundle.main.bundleIdentifier ?? "nil",
          UserDefaults.isSideStore(),
          getenv("LC_HOME_PATH") != nil,
          getenv("LP_HOME_PATH") != nil,
          identifier)
    if UserDefaults.isSideStore() {
        NSLog("[LCRefresh] route=direct-runtime-bridge")
        try await SideStoreIntentCaller.shared.callRefreshIntent(mangledTypeName: mangledTypeName, progress: intentProgress)
    } else {
        NSLog("[LCRefresh] route=liveprocess-xpc")
        RefreshHandler.shared.progress = intentProgress
        try await RefreshHandler.shared.startRefresh(identifier: identifier, mangledName: mangledTypeName)
    }
}

@available(iOS 17.0, *)
public struct RefreshAllAppsWidgetIntent: AppIntent, ProgressReportingIntent
{
    public static var title: LocalizedStringResource { "Refresh Apps via Widget" }
    public static var isDiscoverable: Bool { false } // Don't show in Shortcuts or Spotlight.
    
    public init() {}
    
    public func perform() async throws -> some IntentResult
    {
        try await performIntentRefresh(identifier: "RefreshAllAppsWidgetIntent", mangledTypeName: "9SideStore26RefreshAllAppsWidgetIntentV", intentProgress: progress)
        return .result()
    }
}

@available(iOS 17.0, *)
public struct RefreshAllAppsIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent, ProgressReportingIntent, ForegroundContinuableIntent
{
    public static let intentClassName = "RefreshAllIntent"
    
    public static var title: LocalizedStringResource = "Refresh All Apps"
    public static var description = IntentDescription("Refreshes your sideloaded apps to prevent them from expiring.")
    
    public init() {}
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Refresh All Apps")
    }
    
    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction {
            DisplayRepresentation(
                title: "Refresh All Apps",
                subtitle: ""
            )
        }
    }
    
    public func perform() async throws -> some IntentResult & ProvidesDialog
    {
        try await performIntentRefresh(identifier: "RefreshAllIntent", mangledTypeName: "9SideStore20RefreshAllAppsIntentV", intentProgress: progress)
        return .result(dialog: "All apps have been refreshed.")
    }
    
}


class RefreshHandler: NSObject, RefreshServer {
    var c: UnsafeContinuation<(), any Error>? = nil
    var launchContinuation: UnsafeContinuation<(), any Error>? = nil
    var progress: Progress? = nil
    var listener: NSXPCListener? = nil
    var sideStorePid: Int32 = 0
    var client: RefreshClient? = nil
    var ext: NSExtension? = nil
    var didFinishLaunching = false
    
    static var shared = RefreshHandler()
    
    func startRefresh(identifier: String, mangledName: String) async throws {
        NSLog("[LCRefresh] xpc start pid=%d pidAlive=%d listener=%d client=%d launching=%d activeRefresh=%d",
              sideStorePid, sideStorePid > 0 && getpgid(sideStorePid) > 0,
              listener != nil, client != nil, launchContinuation != nil, c != nil)
        if sideStorePid <= 0 || getpgid(sideStorePid) <= 0, let c {
            NSLog("[LCRefresh] stale refresh continuation found; failing it")
            c.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit unexpectedly"]))
            self.c = nil
        }
        
        if c != nil {
            throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Another refresh task is in progress."])
        }
        
        if listener == nil {
            guard let listener = startAnonymousListener(self) else {
                NSLog("[LCRefresh] anonymous listener creation failed")
                throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create the SideStore background listener."])
            }
            self.listener = listener
            NSLog("[LCRefresh] anonymous listener ready")
        }
        guard let listener = self.listener else {
            throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "SideStore background listener is unavailable."])
        }

        // launch SideStore if it's not running
        if (sideStorePid <= 0 || getpgid(sideStorePid) <= 0) && launchContinuation == nil {
            let lcHome = String(cString:getenv("LC_HOME_PATH"))
            let sideStoreHomeURL = URL(fileURLWithPath: lcHome).appendingPathComponent("Documents/SideStore")
            guard let bookmarkData = bookmarkForURL(sideStoreHomeURL) else {
                NSLog("[LCRefresh] SideStore directory bookmark creation failed")
                throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access the built-in SideStore data directory."])
            }

            // start LiveProcess
            let extensionItem = NSExtensionItem()
            extensionItem.userInfo = [
                "selected": "builtinSideStore",
                "bookmarks": [bookmarkData],
                "endpoint": listener.endpoint
            ]

            guard let liveProcessURL = UserDefaults.lcMainBundle().builtInPlugInsURL?.appendingPathComponent("LiveProcess.appex"),
                  let liveProcessBundle = Bundle(url: liveProcessURL)
            else {
                NSLog("Unable to locate LiveProcess bundle")
                throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate LiveProcess bundle. To use the Refresh All Apps shortcut, reinstall LiveContainer+SideStore with LiveProcess installed. If you use SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use PlumeImpactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep all extensions, i.e. DO NOT Remove any extension."])
            }
            
            var ext : NSExtension?
            do {
                ext = try NSExtension(identifier: liveProcessBundle.bundleIdentifier)
            } catch {
                NSLog("Failed to start extension \(error)")
                throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to start extension \(error). To use the Refresh All Apps shortcut, reinstall LiveContainer+SideStore with LiveProcess installed. If you use SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use Impactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep all extensions, i.e. DO NOT Remove any extension."])
            }
            guard let ext else {
                return
            }
            self.ext = ext
            self.didFinishLaunching = false
            NSLog("[LCRefresh] beginning LiveProcess extension request")
            
            ext.setRequestInterruptionBlock { _ in
                NSLog("[LCRefresh] LiveProcess request interrupted pid=%d", self.sideStorePid)
                self.c?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit unexpectedly"]))
                self.c = nil
                self.sideStorePid = 0
                self.launchContinuation?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit while starting"]))
                self.launchContinuation = nil
                self.client = nil
                self.didFinishLaunching = false
            }
            
            let uuid = await ext.beginRequest(withInputItems: [extensionItem])
            sideStorePid = ext.pid(forRequestIdentifier: uuid)
            NSLog("[LCRefresh] LiveProcess request began pid=%d", sideStorePid)
            
            try await withUnsafeThrowingContinuation { c in
                if self.didFinishLaunching {
                    NSLog("[LCRefresh] LiveProcess launch completed before continuation installation")
                    c.resume()
                    return
                }
                self.launchContinuation = c
                DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                    if let c = self.launchContinuation {
                        c.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore failed to start in reasonable time"]))
                        self.launchContinuation = nil
                        ext._kill(9)
                    }
                }
            }
        }
        guard let client = self.client else {
            NSLog("[LCRefresh] no XPC client after launch pid=%d", sideStorePid)
            throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore failed to connect."])
        }

        try await withUnsafeThrowingContinuation { c in
            self.c = c
            let adsid = sharedAuthenticationValue(forKey: "appleIDAdsid")
            let xcodeToken = sharedAuthenticationValue(forKey: "appleIDXcodeToken")
            let anisetteIdentifier = sharedAuthenticationValue(forKey: "identifier")
            let anisetteAdiPb = sharedAuthenticationValue(forKey: "adiPb")
            NSLog("[LCRefresh] sending refresh request intent=%@ hasADSID=%d hasXcodeToken=%d hasIdentifier=%d hasAdiPb=%d",
                  identifier, adsid != nil, xcodeToken != nil, anisetteIdentifier != nil, anisetteAdiPb != nil)
            client.refreshAllApps(withIdentifier: identifier,
                                  mangledTypeName: mangledName,
                                  adsid: adsid,
                                  xcodeToken: xcodeToken,
                                  anisetteIdentifier: anisetteIdentifier,
                                  anisetteAdiPb: anisetteAdiPb)
        }
        
    }
    
    func updateProgress(_ value: Double) {
        progress?.completedUnitCount = Int64(value*100)
    }
    
    func finish(_ error: String?) {
        if let error {
            NSLog("[LCRefresh] refresh finished with error=%@", error)
            c?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
            c = nil
        } else {
            NSLog("[LCRefresh] refresh finished successfully")
            c?.resume()
            c = nil
        }
    }
    
    func onConnection(_ connection: NSXPCConnection!) {
        NSLog("[LCRefresh] XPC client connected")
        connection.remoteObjectInterface = NSXPCInterface(with: RefreshClient.self)
        client = connection.remoteObjectProxy as? RefreshClient
    }
    
    func finishedLaunching() {
        NSLog("[LCRefresh] LiveProcess reported finishedLaunching client=%d", client != nil)
        didFinishLaunching = true
        launchContinuation?.resume()
        launchContinuation = nil
    }

    func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Failed to add SideStore notification: \(error)")
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
}
