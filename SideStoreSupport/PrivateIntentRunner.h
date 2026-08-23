#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SideStoreRefreshCompletion)(NSError * _Nullable error);

@interface PrivateIntentRunner : NSObject

+ (BOOL)runSideStoreRefreshWithProgress:(NSProgress *)progress
                             completion:(SideStoreRefreshCompletion)completion
    NS_SWIFT_NAME(runSideStoreRefresh(progress:completion:));

@end

NS_ASSUME_NONNULL_END
