//
//  CallComingVC.m
//  CustomLinphone
//
//  Created by yulong on 2018/4/19.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import "CallInComingVC.h"
#import <UserNotifications/UserNotifications.h>
@interface CallInComingVC ()<UIActionSheetDelegate>

@end

@implementation CallInComingVC

static void hideSpinner(LinphoneCall *call, void *user_data) {
    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    

}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    // Set windows (warn memory leaks)
    linphone_core_set_native_video_window_id(LC, (__bridge void *)(_videoView));
    linphone_core_set_native_preview_window_id(LC, (__bridge void *)(_videoPreview));
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(callUpdateEvent:)
                                               name:kLinphoneCallUpdate
                                             object:nil];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIDevice currentDevice] setProximityMonitoringEnabled:FALSE];
    // Remove observer
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (void)callUpdateEvent:(NSNotification *)notif {
    LinphoneCall *call = [[notif.userInfo objectForKey:@"call"] pointerValue];
    LinphoneCallState state = [[notif.userInfo objectForKey:@"state"] intValue];
    [self callUpdate:call state:state animated:TRUE];
}
- (void)callUpdate:(LinphoneCall *)call state:(LinphoneCallState)state animated:(BOOL)animated {
    
    static LinphoneCall *currentCall = NULL;
    if (!currentCall || linphone_core_get_current_call(LC) != currentCall) {
        currentCall = linphone_core_get_current_call(LC);
    }
    
    // Fake call update
    if (call == NULL) {
        return;
    }
    
    BOOL shouldDisableVideo =
    (!currentCall || !linphone_call_params_video_enabled(linphone_call_get_current_params(currentCall)));
    if (videoHidden != shouldDisableVideo) {
        if (!shouldDisableVideo) {
            LinphoneCall *call = linphone_core_get_current_call(LC);
            // linphone_call_params_get_used_video_codec return 0 if no video stream enabled
            if (call != NULL && linphone_call_params_get_used_video_codec(linphone_call_get_current_params(call))) {
                linphone_call_set_next_video_frame_decoded_callback(call, hideSpinner, (__bridge void *)(self));
            }
        } else {
            LinphoneCall *call = linphone_core_get_current_call(LC);
            // linphone_call_params_get_used_video_codec return 0 if no video stream enabled
            if (call != NULL && linphone_call_params_get_used_video_codec(linphone_call_get_current_params(call))) {
                linphone_call_set_next_video_frame_decoded_callback(call, hideSpinner, (__bridge void *)(self));
            }
        }
    }
    
    if (state != LinphoneCallPausedByRemote) {
//        _pausedByRemoteView.hidden = YES;
    }
    
    switch (state) {
        case LinphoneCallIncomingReceived:
        case LinphoneCallOutgoingInit:
        case LinphoneCallConnected:
        case LinphoneCallStreamsRunning: {
            // check video
            if (!linphone_call_params_video_enabled(linphone_call_get_current_params(call))) {
                const LinphoneCallParams *param = linphone_call_get_current_params(call);
                const LinphoneCallAppData *callAppData =
                (__bridge const LinphoneCallAppData *)(linphone_call_get_user_data(call));
                if (state == LinphoneCallStreamsRunning && callAppData->videoRequested &&
                    linphone_call_params_low_bandwidth_enabled(param)) {
                    // too bad video was not enabled because low bandwidth
                    UIAlertController *errView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Low bandwidth", nil)
                                                                                     message:NSLocalizedString(@"Video cannot be activated because of low bandwidth "
                                                                                                               @"condition, only audio is available",
                                                                                                               nil)
                                                                              preferredStyle:UIAlertControllerStyleAlert];
                    
                    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Continue", nil)
                                                                            style:UIAlertActionStyleDefault
                                                                          handler:^(UIAlertAction * action) {}];
                    
                    [errView addAction:defaultAction];
                    [self presentViewController:errView animated:YES completion:nil];
                    callAppData->videoRequested = FALSE; /*reset field*/
                }
            }
            break;
        }
        case LinphoneCallUpdatedByRemote: {
            const LinphoneCallParams *current = linphone_call_get_current_params(call);
            const LinphoneCallParams *remote = linphone_call_get_remote_params(call);
            
            /* remote wants to add video */
            if ((linphone_core_video_display_enabled(LC) && !linphone_call_params_video_enabled(current) &&
                 linphone_call_params_video_enabled(remote)) &&
                (!linphone_core_get_video_policy(LC)->automatically_accept ||
                 (([UIApplication sharedApplication].applicationState != UIApplicationStateActive) &&
                  floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_x_Max))) {
                     linphone_core_defer_call_update(LC, call);
                     [self displayAskToEnableVideoCall:call];
                 } else if (linphone_call_params_video_enabled(current) && !linphone_call_params_video_enabled(remote)) {
                     [self displayAudioCall:animated];
                 }
            break;
        }
        case LinphoneCallPausing:
        case LinphoneCallPaused:
            [self displayAudioCall:animated];
            break;
        case LinphoneCallPausedByRemote:
            [self displayAudioCall:animated];
            if (call == linphone_core_get_current_call(LC)) {
//                _pausedByRemoteView.hidden = NO;
            }
            break;
        case LinphoneCallEnd:
        case LinphoneCallError:
        default:
            break;
    }
}
- (void)displayVideoCall:(BOOL)animated {
    [self disableVideoDisplay:FALSE animated:animated];
}

- (void)displayAudioCall:(BOOL)animated {
    [self disableVideoDisplay:TRUE animated:animated];
}
- (void)disableVideoDisplay:(BOOL)disabled animated:(BOOL)animation {
    /*
    if (disabled == videoHidden && animation)
        return;
    videoHidden = disabled;
    
    if (!disabled) {
        [videoZoomHandler resetZoom];
    }
    if (animation) {
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:1.0];
    }
    
    [_videoGroup setAlpha:disabled ? 0 : 1];
    
    [self hideControls:!disabled sender:nil];
    
    if (animation) {
        [UIView commitAnimations];
    }
    
    // only show camera switch button if we have more than 1 camera
    _videoCameraSwitch.hidden = (disabled || !LinphoneManager.instance.frontCamId);
    _videoPreview.hidden = (disabled || !linphone_core_self_view_enabled(LC));
    
    if (hideControlsTimer != nil) {
        [hideControlsTimer invalidate];
        hideControlsTimer = nil;
    }
    
    if(![PhoneMainView.instance isIphoneXDevice]){
        [PhoneMainView.instance fullScreen:!disabled];
    }
    [PhoneMainView.instance hideTabBar:!disabled];
    
    if (!disabled) {
#ifdef TEST_VIDEO_VIEW_CHANGE
        [NSTimer scheduledTimerWithTimeInterval:5.0
                                         target:self
                                       selector:@selector(_debugChangeVideoView)
                                       userInfo:nil
                                        repeats:YES];
#endif
        // [self batteryLevelChanged:nil];
        
        [_videoWaitingForFirstImage setHidden:NO];
        [_videoWaitingForFirstImage startAnimating];
*/
        LinphoneCall *call = linphone_core_get_current_call(LC);
        // linphone_call_params_get_used_video_codec return 0 if no video stream enabled
        if (call != NULL && linphone_call_params_get_used_video_codec(linphone_call_get_current_params(call))) {
            linphone_call_set_next_video_frame_decoded_callback(call, hideSpinner, (__bridge void *)(self));
        }
//    }
}
#pragma mark - ActionSheet Functions

- (void)displayAskToEnableVideoCall:(LinphoneCall *)call {
    if (linphone_call_params_get_local_conference_mode(linphone_call_get_current_params(call))) {
        return;
    }
    if (linphone_core_get_video_policy(LC)->automatically_accept &&
        !([UIApplication sharedApplication].applicationState != UIApplicationStateActive))
        return;
    
    NSString *username = @"";
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@ would like to enable video", nil), username];
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive &&
        floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_x_Max) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = NSLocalizedString(@"Video request", nil);
        content.body = title;
        content.categoryIdentifier = @"video_request";
        content.userInfo = @{
                             @"CallId" : [NSString stringWithUTF8String:linphone_call_log_get_call_id(linphone_call_get_call_log(call))]
                             };
        
        UNNotificationRequest *req =
        [UNNotificationRequest requestWithIdentifier:@"video_request" content:content trigger:NULL];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req
                                                               withCompletionHandler:^(NSError *_Nullable error) {
                                                                   // Enable or disable features based on authorization.
                                                                   if (error) {
                                                                       DLog(@"Error while adding notification request :");
                                                                       DLog(@"%@",error.description);
                                                                   }
                                                               }];
    } else {
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:@"取消" destructiveButtonTitle:@"接受" otherButtonTitles:nil, nil];
        [actionSheet showInView:self.view];
    }
}
- (IBAction)acceptClick:(id)sender {
    [[LinphoneManager instance] acceptCall:self.call evenWithVideo:NO];
}
- (IBAction)declineClick:(id)sender {
    LinphoneCall *currentcall = linphone_core_get_current_call(LC);
    if (linphone_core_is_in_conference(LC) ||                                           // In conference
        (linphone_core_get_conference_size(LC) > 0) // Only one conf
        ) {
        LinphoneManager.instance.conf = TRUE;
        linphone_core_terminate_conference(LC);
    } else if (currentcall != NULL) {
        linphone_call_terminate(currentcall);
    } else {
        const MSList *calls = linphone_core_get_calls(LC);
        if (bctbx_list_size(calls) == 1) { // Only one call
            linphone_call_terminate((LinphoneCall *)(calls->data));
        }
    }
    [self dismissViewControllerAnimated:YES completion:^{
        
    }];
}
#pragma mark ActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex{
    LinphoneCall *call = linphone_core_get_current_call(LC);
    if (buttonIndex == 0) {
        DLog(@"User accept video proposal");
        if (call == linphone_core_get_current_call(LC)) {
            LinphoneCallParams *params = linphone_core_create_call_params(LC, call);
            linphone_call_params_enable_video(params, TRUE);
            linphone_call_accept_update(call, params);
            linphone_call_params_destroy(params);
            [videoDismissTimer invalidate];
            videoDismissTimer = nil;
        }

    }else{
        
        DLog(@"User declined video proposal");
        if (call == linphone_core_get_current_call(LC)) {
            LinphoneCallParams *params = linphone_core_create_call_params(LC, call);
            linphone_call_accept_update(call, params);
            linphone_call_params_destroy(params);
            [videoDismissTimer invalidate];
            videoDismissTimer = nil;
        }
    }
}

@end
