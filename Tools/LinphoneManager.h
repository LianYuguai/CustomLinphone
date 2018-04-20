//
//  LinphoneManager.h
//  CustomLinphone
//
//  Created by yulong on 2018/4/17.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <CoreTelephony/CTCallCenter.h>
#import <sqlite3.h>
#import "ProviderDelegate.h"
#import "LinphoneDelegate.h"
#include "linphone/linphonecore.h"
extern NSString *const kLinphoneCoreUpdate;
extern NSString *const kLinphoneDisplayStatusUpdate;
extern NSString *const kLinphoneMessageReceived;
extern NSString *const kLinphoneTextComposeEvent;
extern NSString *const kLinphoneCallUpdate;
extern NSString *const kLinphoneRegistrationUpdate;
extern NSString *const kLinphoneMainViewChange;
extern NSString *const kLinphoneAddressBookUpdate;
extern NSString *const kLinphoneLogsUpdate;
extern NSString *const kLinphoneSettingsUpdate;
extern NSString *const kLinphoneBluetoothAvailabilityUpdate;
extern NSString *const kLinphoneConfiguringStateUpdate;
extern NSString *const kLinphoneGlobalStateUpdate;
extern NSString *const kLinphoneNotifyReceived;
extern NSString *const kLinphoneNotifyPresenceReceivedForUriOrTel;
extern NSString *const kLinphoneCallEncryptionChanged;
extern NSString *const kLinphoneFileTransferSendUpdate;
extern NSString *const kLinphoneFileTransferRecvUpdate;
typedef enum _Connectivity {
    wifi,
    wwan,
    none
} Connectivity;

struct NetworkReachabilityContext {
    bool_t testWifi, testWWan;
    void (*networkStateChanged) (Connectivity newConnectivity);
};
typedef struct _LinphoneManagerSounds {
    SystemSoundID vibrate;
} LinphoneManagerSounds;
typedef enum _NetworkType {
    network_none = 0,
    network_2g,
    network_3g,
    network_4g,
    network_lte,
    network_wifi
} NetworkType;
@interface LinphoneCallAppData :NSObject {
@public
    bool_t batteryWarningShown;
    UILocalNotification *notification;
    NSMutableDictionary *userInfos;
    bool_t videoRequested; /*set when user has requested for video*/
    NSTimer* timer;
};
@end
@interface LinphoneManager : NSObject{
@protected
    SCNetworkReachabilityRef proxyReachability;
@private
    NSTimer* mIterateTimer;
    NSMutableArray*  pushCallIDs;
    Connectivity connectivity;
    UIBackgroundTaskIdentifier pausedCallBgTask;
    UIBackgroundTaskIdentifier pushBgTaskCall;
    UIBackgroundTaskIdentifier incallBgTask;
    CTCallCenter* mCallCenter;
    NSDate *mLastKeepAliveDate;
}
@property ProviderDelegate *providerDelegate;
@property (nonatomic, readwrite, assign) id<LinphoneDelegate> delegate;
@property (readonly) NetworkType network;
@property (readonly) LpConfig *configDb;
@property(strong, nonatomic) NSString *SSID;
@property Connectivity connectivity;
@property(nonatomic, strong) NSData *pushNotificationToken;
@property (readonly) LinphoneManagerSounds sounds;
@property (readonly) NSMutableArray *logs;
@property NSDictionary *pushDict;
@property (readonly) sqlite3* database;
@property (nonatomic, assign) BOOL speakerEnabled;
@property (nonatomic, assign) BOOL speakerBeforePause;
@property (nonatomic, assign) BOOL bluetoothEnabled;
@property BOOL conf;
@property(strong, nonatomic) NSMutableArray *fileTransferDelegates;
@property (readonly) NSString* contactSipField;
@property (readonly) const char*  frontCamId;
@property (readonly) const char*  backCamId;
@property (readonly) BOOL wasRemoteProvisioned;
@property (copy) void (^silentPushCompletion)(UIBackgroundFetchResult);
@property BOOL nextCallIsTransfer;
@property (readonly) ALAssetsLibrary *photoLibrary;

+ (LinphoneCore*) getLc;
+ (LinphoneManager *)instance;
+ (BOOL)runningOnIpad;
+ (void)setValueInMessageAppData:(id)value forKey:(NSString *)key inMessage:(LinphoneChatMessage *)msg;
+ (void)instanceRelease;
- (void)startLinphoneCore;
- (LinphoneCall *)callByCallId:(NSString *)call_id;
- (void)acceptCall:(LinphoneCall *)call evenWithVideo:(BOOL)video;
- (BOOL)doCall:(const LinphoneAddress *)iaddr;
- (void)destroyLinphoneCore;
/**
 设置登陆信息
 */
- (BOOL)addProxyConfig:(NSString*)username password:(NSString*)password displayName:(NSString *)displayName domain:(NSString*)domain port:(NSString *)port withTransport:(NSString*)transport;


/**
 注销登陆信息
 */
- (void)removeAccount;


/**
 拨打电话
 */
- (void)call:(NSString *)address displayName:(NSString*)displayName transfer:(BOOL)transfer;
- (BOOL)lpConfigBoolForKey:(NSString *)key;
+ (NSString *)documentFile:(NSString *)file;
@end
