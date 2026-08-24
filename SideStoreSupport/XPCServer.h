//
//  XPCServer.h
//  LiveContainer
//
//  Created by s s on 2025/7/20.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UserNotifications/UserNotifications.h>

__attribute__((swift_attr("@Sendable")))
@protocol RefreshServer
- (void)updateProgress:(double)value;
- (void)finish:(NSString*)error;
- (void)onConnection:(NSXPCConnection*)connection;
- (void)finishedLaunching;
- (void)addNotificationRequest:(UNNotificationRequest*)request;
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray<NSString*>*)identifiers;
@end

@protocol RefreshClient
- (void)refreshAllAppsWithIdentifier:(NSString*)identifier
                     mangledTypeName:(NSString *)mangledTypeName
                               adsid:(NSString * _Nullable)adsid
                          xcodeToken:(NSString * _Nullable)xcodeToken
                  anisetteIdentifier:(NSString * _Nullable)anisetteIdentifier
                       anisetteAdiPb:(NSString * _Nullable)anisetteAdiPb;
@end

@interface LiveProcessSideStoreHandler : NSObject
@property (class, readonly, strong) LiveProcessSideStoreHandler* shared;
@property NSXPCConnection* connection;
@property NSObject<RefreshServer>* server;

@end

NSXPCListener* startAnonymousListener(NSObject<RefreshServer>* reporter);
NSData* bookmarkForURL(NSURL* url);
OSStatus LCHostSecItemCopyMatching(CFDictionaryRef query, CFTypeRef _Nullable * _Nullable result);

void installSideStoreHooks(void);
void installSideStoreNotificationHooks(void);

@interface SideStoreClient : NSObject<RefreshClient>
@property (class, readonly) SideStoreClient* shared;
- (void) relaunchLC;
@end
