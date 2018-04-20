//
//  AppDelegate.h
//  CustomLinphone
//
//  Created by yulong on 2018/4/16.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>{
@private
    UIBackgroundTaskIdentifier bgStartId;
    BOOL startedInBackground;
}

@property (strong, nonatomic) UIWindow *window;
@property ProviderDelegate *del;


@end

