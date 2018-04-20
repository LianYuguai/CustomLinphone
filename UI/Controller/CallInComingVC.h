//
//  CallComingVC.h
//  CustomLinphone
//
//  Created by yulong on 2018/4/19.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CallInComingVC : UIViewController{
@private
    UITapGestureRecognizer *singleFingerTap;
    NSTimer *hideControlsTimer;
    NSTimer *videoDismissTimer;
    BOOL videoHidden;
}
@property(nonatomic, assign) LinphoneCall *call;
@property (weak, nonatomic) IBOutlet UIView *videoView;
@property (weak, nonatomic) IBOutlet UIView *videoPreview;

@end
