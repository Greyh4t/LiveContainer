#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PrivateIntentCompletion)(id _Nullable result,
                                        NSError * _Nullable error);
typedef void (^SideStoreRefreshCompletion)(NSError * _Nullable error);

@interface PrivateIntentRunner : NSObject

+ (nullable NSProgress *)runWithIdentifier:(NSString *)identifier
                           mangledTypeName:(NSString *)mangledTypeName
                                completion:(PrivateIntentCompletion)completion
    NS_SWIFT_NAME(run(identifier:mangledTypeName:completion:));

+ (BOOL)runSideStoreRefreshWithProgress:(NSProgress *)progress
                             completion:(SideStoreRefreshCompletion)completion
    NS_SWIFT_NAME(runSideStoreRefresh(progress:completion:));

@end

NS_ASSUME_NONNULL_END
