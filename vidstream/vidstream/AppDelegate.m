//
//  AppDelegate.m
//  vidtest
//
//  Created by User on 10/19/20.
//

#import "AppDelegate.h"
#import "ViewController.h"
@interface AppDelegate ()

@end

@implementation AppDelegate



- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    ViewController *view = [[ViewController alloc] init];
    //application.windows[0].rootViewController = view;
    
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds ];
    //self.window = window;
    
    
    //self.window.rootViewController = view;
    window.rootViewController = view;
    [window makeKeyAndVisible];
    self.window = window;
    
    return YES;
}



@end
