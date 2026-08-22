#import "PrivateIntentRunner.h"
#import "AppIntentsPrivate.h"

#import <bsm/audit.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/task_info.h>
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
        completion(PrivateIntentError(5, @"SideStore background refresh bridge is unavailable"));
        return NO;
    }

    typedef void (*SideStoreRefreshFunction)(id, SEL, NSProgress *, SideStoreRefreshCompletion);
    SideStoreRefreshFunction function = (SideStoreRefreshFunction)objc_msgSend;
    function(bridgeClass, selector, progress, completion);
    return YES;
}

+ (NSProgress *)runWithIdentifier:(NSString *)identifier
                  mangledTypeName:(NSString *)mangledTypeName
                       completion:(PrivateIntentCompletion)completion {
    NSError *error = nil;
    audit_token_t auditToken = {};
    mach_msg_type_number_t auditTokenCount = TASK_AUDIT_TOKEN_COUNT;
    kern_return_t auditTokenResult = task_info(mach_task_self(),
                                                TASK_AUDIT_TOKEN,
                                                (task_info_t)&auditToken,
                                                &auditTokenCount);
    if (auditTokenResult != KERN_SUCCESS) {
        completion(nil, PrivateIntentError(4, [NSString stringWithFormat:@"Unable to obtain process audit token: %d", auditTokenResult]));
        return nil;
    }

    Class actionClass = NSClassFromString(@"LNAction");
    Class optionsClass = NSClassFromString(@"LNActionExecutorOptions");
    Class contextClass = NSClassFromString(@"LNAppContext");
    if (actionClass == Nil || optionsClass == Nil || contextClass == Nil) {
        completion(nil, PrivateIntentError(3, @"Required private class is unavailable"));
        return nil;
    }

    LNAction* action = [[actionClass alloc] initWithIdentifier:identifier
                                                    mangledTypeName:mangledTypeName
                                                      openAppWhenRun:NO
                                                         parameters:@[]];
    LNActionExecutorOptions* options = [[optionsClass alloc] init];
    options.clientLabel = @"PrivateProgressDemo";
    options.kind = 2; // LNActionExecutorOptions kind: App Shortcut
    options.donateToTranscript = NO;

    LNAppContext* context = [[contextClass alloc] init];
    NSProgress *reportingProgress = [NSProgress progressWithTotalUnitCount:1];
    __block LNAppContext *retainedContext = context;
    PrivateIntentCompletion retainedCompletion = ^(id result, NSError *completionError) {
        // LNAppContext owns the in-flight request. Keep it alive until the
        // asynchronous completion callback or the system cancels the action.
        (void)retainedContext;
        completion(result, completionError);
        retainedContext = nil;
    };
    [context performAction:action
                   options:options
         reportingProgress:reportingProgress
                  delegate:nil
                auditToken:&auditToken
         completionHandler:retainedCompletion];
    return reportingProgress;
}

@end
