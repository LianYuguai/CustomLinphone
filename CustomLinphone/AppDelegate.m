//
//  AppDelegate.m
//  CustomLinphone
//
//  Created by yulong on 2018/4/16.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import "AppDelegate.h"
#import "LinphoneManager.h"
#import "CallInComingVC.h"
@interface AppDelegate ()<LinphoneDelegate>

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    UIApplication *app = [UIApplication sharedApplication];
    UIApplicationState state = app.applicationState;
    
    LinphoneManager *instance = [LinphoneManager instance];
    instance.delegate = self;
    BOOL background_mode = [instance lpConfigBoolForKey:@"backgroundmode_preference"];
    BOOL start_at_boot = [instance lpConfigBoolForKey:@"start_at_boot_preference"];
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_x_Max) {
        self.del = [[ProviderDelegate alloc] init];
        [LinphoneManager.instance setProviderDelegate:self.del];
    }
    
    if (state == UIApplicationStateBackground) {
        // we've been woken up directly to background;
        if (!start_at_boot || !background_mode) {
            // autoboot disabled or no background, and no push: do nothing and wait for a real launch
            //output a log with NSLog, because the ortp logging system isn't activated yet at this time
            NSLog(@"Linphone launch doing nothing because start_at_boot or background_mode are not activated.", NULL);
            return YES;
        }
    }
    bgStartId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        DLog(@"Background task for application launching expired.");
        [[UIApplication sharedApplication] endBackgroundTask:bgStartId];
    }];
    
    [LinphoneManager.instance startLinphoneCore];
    //    LinphoneManager.instance.iapManager.notificationCategory = @"expiry_notification";
    // initialize UI
    [self.window makeKeyAndVisible];
//    [RootViewManager setupWithPortrait:(PhoneMainView *)self.window.rootViewController];
//    [PhoneMainView.instance startUp];
//    [PhoneMainView.instance updateStatusBar:nil];
    
    if (bgStartId != UIBackgroundTaskInvalid)
        [[UIApplication sharedApplication] endBackgroundTask:bgStartId];
    
    //Enable all notification type. VoIP Notifications don't present a UI but we will use this to show local nofications later
    UIUserNotificationSettings *notificationSettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert| UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
    
    //register the notification settings
    [application registerUserNotificationSettings:notificationSettings];
    
    //output what state the app is in. This will be used to see when the app is started in the background
    DLog(@"app launched with state : %li", (long)application.applicationState);
    DLog(@"FINISH LAUNCHING WITH OPTION : %@", launchOptions.description);
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    LinphoneManager.instance.conf = TRUE;
    linphone_core_terminate_all_calls(LC);
    
    // destroyLinphoneCore automatically unregister proxies but if we are using
    // remote push notifications, we want to continue receiving them
    if (LinphoneManager.instance.pushNotificationToken != nil) {
        // trick me! setting network reachable to false will avoid sending unregister
        const MSList *proxies = linphone_core_get_proxy_config_list(LC);
        BOOL pushNotifEnabled = NO;
        while (proxies) {
            const char *refkey = linphone_proxy_config_get_ref_key(proxies->data);
            pushNotifEnabled = pushNotifEnabled || (refkey && strcmp(refkey, "push_notification") == 0);
            proxies = proxies->next;
        }
        // but we only want to hack if at least one proxy config uses remote push..
        if (pushNotifEnabled) {
            linphone_core_set_network_reachable(LC, FALSE);
        }
    }

    [[LinphoneManager instance] destroyLinphoneCore];
     
}
#pragma mark LinphoneDelegate
//  登陆状态变化回调
- (void)onRegisterStateChange:(LinphoneCallState) state message:(const char*) message{
    
}

// 发起来电回调
- (void)onOutgoingCall:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message{

}

// 收到来电回调
- (void)onIncomingCall:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message{
    CallInComingVC *vc = [CallInComingVC new];
    vc.call = call;
    [self.window.rootViewController presentViewController:vc animated:YES completion:^{
        
    }];

}

// 接听回调
-(void)onAnswer:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message{
    
}

// 释放通话回调
- (void)onHangUp:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message{
    
}

// 呼叫失败回调
- (void)onDialFailed:(LinphoneCallState)state withMessage:(NSDictionary *) message{
    
}


@end
