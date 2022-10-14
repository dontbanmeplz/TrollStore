#import <UIKit/UIKit.h>

@interface TSSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow * window;
@property (nonatomic, strong) UITabBarController *rootViewController;
- (void)doIPAInstall:(NSString*)ipaPath scene:(UIWindowScene*)scene force:(BOOL)force completion:(void (^)(void))completion;
@end
