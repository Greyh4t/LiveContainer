#import "PrivateIntentRunner.h"
#import <objc/message.h>

static NSString *const PrivateIntentErrorDomain = @"PrivateIntentRunner";



static NSError *PrivateIntentError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:PrivateIntentErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@implementation PrivateIntentRunner

+ (BOOL)runSideStoreRefreshWithProgress:(NSProgress *)progress
                             completion:(SideStoreRefreshCompletion)completion {
    Class bridgeClass = NSClassFromString(@"SideStoreLiveProcessRefreshBridge");
    SEL selector = NSSelectorFromString(@"refreshAllAppsWithProgress:completion:");
    NSLog(@"[LCRefresh] runtime lookup class=%d selector=%d", bridgeClass != Nil,
          bridgeClass != Nil && [bridgeClass respondsToSelector:selector]);
    if (bridgeClass == Nil || ![bridgeClass respondsToSelector:selector]) {
        completion(PrivateIntentError(5, @"SideStore background refresh is unavailable"));
        return NO;
    }

    typedef void (*SideStoreRefreshFunction)(id, SEL, NSProgress *, SideStoreRefreshCompletion);
    SideStoreRefreshCompletion loggedCompletion = ^(NSError *error) {
        if (error) {
            NSLog(@"[LCRefresh] runtime callback domain=%@ code=%ld description=%@",
                  error.domain, (long)error.code, error.localizedDescription);
        } else {
            NSLog(@"[LCRefresh] runtime callback success");
        }
        completion(error);
    };
    ((SideStoreRefreshFunction)objc_msgSend)(bridgeClass, selector, progress, loggedCompletion);
    return YES;
}

@end
