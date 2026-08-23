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
    if (bridgeClass == Nil || ![bridgeClass respondsToSelector:selector]) {
        completion(PrivateIntentError(5, @"SideStore background refresh is unavailable"));
        return NO;
    }

    typedef void (*SideStoreRefreshFunction)(id, SEL, NSProgress *, SideStoreRefreshCompletion);
    ((SideStoreRefreshFunction)objc_msgSend)(bridgeClass, selector, progress, completion);
    return YES;
}

@end
