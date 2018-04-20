//
//  LinphoneDelegate.h
//  CustomLinphone
//
//  Created by yulong on 2018/4/19.
//  Copyright © 2018年 yulong. All rights reserved.
//
#include "linphone/linphonecore.h"
#ifndef LinphoneDelegate_h
#define LinphoneDelegate_h
@protocol LinphoneDelegate <NSObject>
@optional


//  登陆状态变化回调
- (void)onRegisterStateChange:(LinphoneCallState) state message:(const char*) message;

// 发起来电回调
- (void)onOutgoingCall:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message;

// 收到来电回调
- (void)onIncomingCall:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message;

// 接听回调
-(void)onAnswer:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message;

// 释放通话回调
- (void)onHangUp:(LinphoneCall *)call withState:(LinphoneCallState)state withMessage:(NSDictionary *) message;

// 呼叫失败回调
- (void)onDialFailed:(LinphoneCallState)state withMessage:(NSDictionary *) message;


@end
#endif /* LinphoneDelegate_h */
