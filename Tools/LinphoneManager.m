//
//  LinphoneManager.m
//  CustomLinphone
//
//  Created by yulong on 2018/4/17.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import "LinphoneManager.h"
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/sysctl.h>
#import <UserNotifications/UserNotifications.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "FileTransferDelegate.h"
#import "AudioHelper.h"

#include "linphone/factory.h"
#include "linphone/linphonecore_utils.h"
#include "linphone/lpconfig.h"
#include "mediastreamer2/mscommon.h"

#define FRONT_CAM_NAME                                                                                                 \
"AV Capture: com.apple.avfoundation.avcapturedevice.built-in_video:1" /*"AV Capture: Front Camera"*/
#define BACK_CAM_NAME                                                                                                  \
"AV Capture: com.apple.avfoundation.avcapturedevice.built-in_video:0" /*"AV Capture: Back Camera"*/

#import "LinphoneUtils.h"
static LinphoneCore *theLinphoneCore = nil;
static LinphoneManager *theLinphoneManager = nil;

NSString *const LINPHONERC_APPLICATION_KEY = @"app";

NSString *const kLinphoneCoreUpdate = @"LinphoneCoreUpdate";
NSString *const kLinphoneDisplayStatusUpdate = @"LinphoneDisplayStatusUpdate";
NSString *const kLinphoneMessageReceived = @"LinphoneMessageReceived";
NSString *const kLinphoneTextComposeEvent = @"LinphoneTextComposeStarted";
NSString *const kLinphoneCallUpdate = @"LinphoneCallUpdate";
NSString *const kLinphoneRegistrationUpdate = @"LinphoneRegistrationUpdate";
NSString *const kLinphoneAddressBookUpdate = @"LinphoneAddressBookUpdate";
NSString *const kLinphoneMainViewChange = @"LinphoneMainViewChange";
NSString *const kLinphoneLogsUpdate = @"LinphoneLogsUpdate";
NSString *const kLinphoneSettingsUpdate = @"LinphoneSettingsUpdate";
NSString *const kLinphoneBluetoothAvailabilityUpdate = @"LinphoneBluetoothAvailabilityUpdate";
NSString *const kLinphoneConfiguringStateUpdate = @"LinphoneConfiguringStateUpdate";
NSString *const kLinphoneGlobalStateUpdate = @"LinphoneGlobalStateUpdate";
NSString *const kLinphoneNotifyReceived = @"LinphoneNotifyReceived";
NSString *const kLinphoneNotifyPresenceReceivedForUriOrTel = @"LinphoneNotifyPresenceReceivedForUriOrTel";
NSString *const kLinphoneCallEncryptionChanged = @"LinphoneCallEncryptionChanged";
NSString *const kLinphoneFileTransferSendUpdate = @"LinphoneFileTransferSendUpdate";
NSString *const kLinphoneFileTransferRecvUpdate = @"LinphoneFileTransferRecvUpdate";

NSString *const kLinphoneOldChatDBFilename = @"chat_database.sqlite";
NSString *const kLinphoneInternalChatDBFilename = @"linphone_chats.db";

extern void libmsamr_init(MSFactory *factory);
extern void libmsx264_init(MSFactory *factory);
extern void libmsopenh264_init(MSFactory *factory);
extern void libmssilk_init(MSFactory *factory);
extern void libmswebrtc_init(MSFactory *factory);
extern void libmscodec2_init(MSFactory *factory);

@implementation LinphoneCallAppData
- (id)init {
    if ((self = [super init])) {
        batteryWarningShown = FALSE;
        notification = nil;
        videoRequested = FALSE;
        userInfos = [[NSMutableDictionary alloc] init];
    }
    return self;
}

@end

@interface LinphoneManager ()
@property(strong, nonatomic) AVAudioPlayer *messagePlayer;
@end

@implementation LinphoneManager
+ (LinphoneCore *)getLc {
    if (theLinphoneCore == nil) {
//        @throw([NSException exceptionWithName:@"LinphoneCoreException"
//                                       reason:@"Linphone core not initialized yet"
//                                     userInfo:nil]);
    }
    return theLinphoneCore;
}
+ (LinphoneManager *)instance {
    @synchronized(self) {
        if (theLinphoneManager == nil) {
            theLinphoneManager = [[LinphoneManager alloc] init];
        }
    }
    return theLinphoneManager;
}
+ (void)instanceRelease {
    if (theLinphoneManager != nil) {
        theLinphoneManager = nil;
    }
}
+ (NSString *)getCurrentWifiSSID {
#if TARGET_IPHONE_SIMULATOR
    return @"Sim_err_SSID_NotSupported";
#else
    NSString *data = nil;
    CFDictionaryRef dict = CNCopyCurrentNetworkInfo((CFStringRef) @"en0");
    if (dict) {
        DLog(@"AP Wifi: %@", dict);
        data = [NSString stringWithString:(NSString *)CFDictionaryGetValue(dict, @"SSID")];
        CFRelease(dict);
    }
    return data;
#endif
}
+ (void)kickOffNetworkConnection {
    static BOOL in_progress = FALSE;
    if (in_progress) {
        DLog(@"Connection kickoff already in progress");
        return;
    }
    in_progress = TRUE;
    /* start a new thread to avoid blocking the main ui in case of peer host failure */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static int sleep_us = 10000;
        static int timeout_s = 5;
        BOOL timeout_reached = FALSE;
        int loop = 0;
        CFWriteStreamRef writeStream;
        CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef) @"192.168.0.200" /*"linphone.org"*/, 15000, nil,
                                           &writeStream);
        BOOL res = CFWriteStreamOpen(writeStream);
        const char *buff = "hello";
        time_t start = time(NULL);
        time_t loop_time;
        
        if (res == FALSE) {
            DLog(@"Could not open write stream, backing off");
            CFRelease(writeStream);
            in_progress = FALSE;
            return;
        }
        
        // check stream status and handle timeout
        CFStreamStatus status = CFWriteStreamGetStatus(writeStream);
        while (status != kCFStreamStatusOpen && status != kCFStreamStatusError) {
            usleep(sleep_us);
            status = CFWriteStreamGetStatus(writeStream);
            loop_time = time(NULL);
            if (loop_time - start >= timeout_s) {
                timeout_reached = TRUE;
                break;
            }
            loop++;
        }
        
        if (status == kCFStreamStatusOpen) {
            CFWriteStreamWrite(writeStream, (const UInt8 *)buff, strlen(buff));
        } else if (!timeout_reached) {
            CFErrorRef error = CFWriteStreamCopyError(writeStream);
            DLog(@"CFStreamError: %@", error);
            CFRelease(error);
        } else if (timeout_reached) {
            DLog(@"CFStream timeout reached");
        }
        CFWriteStreamClose(writeStream);
        CFRelease(writeStream);
        in_progress = FALSE;
    });
}
+ (BOOL)runningOnIpad {
    return ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
}
+ (BOOL)isNotIphone3G {
    static BOOL done = FALSE;
    static BOOL result;
    if (!done) {
        size_t size;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        char *machine = malloc(size);
        sysctlbyname("hw.machine", machine, &size, NULL, 0);
        NSString *platform = [[NSString alloc] initWithUTF8String:machine];
        free(machine);
        
        result = ![platform isEqualToString:@"iPhone1,2"];
        
        done = TRUE;
    }
    return result;
}
+ (void)setValueInMessageAppData:(id)value forKey:(NSString *)key inMessage:(LinphoneChatMessage *)msg {
    
    NSMutableDictionary *appDataDict = [NSMutableDictionary dictionary];
    const char *appData = linphone_chat_message_get_appdata(msg);
    if (appData) {
        appDataDict = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:appData length:strlen(appData)]
                                                      options:NSJSONReadingMutableContainers
                                                        error:nil];
    }
    
    [appDataDict setValue:value forKey:key];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:appDataDict options:0 error:nil];
    NSString *appdataJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    linphone_chat_message_set_appdata(msg, [appdataJSON UTF8String]);
}
- (id)init {
    if ((self = [super init])) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(audioRouteChangeListenerCallback:)
                                                   name:AVAudioSessionRouteChangeNotification
                                                 object:nil];
        
        NSString *path = [[NSBundle mainBundle] pathForResource:@"msg" ofType:@"wav"];
        self.messagePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:path] error:nil];
        
        _sounds.vibrate = kSystemSoundID_Vibrate;
        
        _logs = [[NSMutableArray alloc] init];
        _pushDict = [[NSMutableDictionary alloc] init];
        _database = NULL;
        _speakerEnabled = FALSE;
        _speakerBeforePause = FALSE;
        _bluetoothEnabled = FALSE;
        _conf = FALSE;
        _fileTransferDelegates = [[NSMutableArray alloc] init];
//        _linphoneManagerAddressBookMap = [[OrderedDictionary alloc] init];
        pushCallIDs = [[NSMutableArray alloc] init];
//        _photoLibrary = [[ALAssetsLibrary alloc] init];
//        _isTesting = [LinphoneManager isRunningTests];
        [self renameDefaultSettings];
        [self copyDefaultSettings];
        [self overrideDefaultSettings];
        
        // set default values for first boot
        if ([self lpConfigStringForKey:@"debugenable_preference"] == nil) {
#ifdef DEBUG
            [self lpConfigSetInt:1 forKey:@"debugenable_preference"];
#else
            [self lpConfigSetInt:0 forKey:@"debugenable_preference"];
#endif
        }
        
        // by default if handle_content_encoding is not set, we use plain text for debug purposes only
        if ([self lpConfigStringForKey:@"handle_content_encoding" inSection:@"misc"] == nil) {
#ifdef DEBUG
            [self lpConfigSetString:@"none" forKey:@"handle_content_encoding" inSection:@"misc"];
#else
            [self lpConfigSetString:@"conflate" forKey:@"handle_content_encoding" inSection:@"misc"];
#endif
        }
        
        [self migrateFromUserPrefs];
    }
    return self;
}
/** Should be called once per linphone_core_new() */
- (void)finishCoreConfiguration {
    
    //Force keep alive to workaround push notif on chat message
    linphone_core_enable_keep_alive(theLinphoneCore, true);
    
    // get default config from bundle
    NSString *zrtpSecretsFileName = [LinphoneManager documentFile:@"zrtp_secrets"];
    NSString *chatDBFileName = [LinphoneManager documentFile:kLinphoneInternalChatDBFilename];
    
    NSString *device = [[NSMutableString alloc]
                        initWithString:[NSString
                                        stringWithFormat:@"%@_%@_iOS%@",
                                        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                                        [LinphoneUtils deviceModelIdentifier],
                                        UIDevice.currentDevice.systemVersion]];
    device = [device stringByReplacingOccurrencesOfString:@"," withString:@"."];
    device = [device stringByReplacingOccurrencesOfString:@" " withString:@"."];
    linphone_core_set_user_agent(theLinphoneCore, device.UTF8String, LINPHONE_IOS_VERSION);
    
    _contactSipField = [self lpConfigStringForKey:@"contact_im_type_value" inSection:@"sip" withDefault:@"SIP"];
    
//    if (_fastAddressBook == nil) {
//        _fastAddressBook = [[FastAddressBook alloc] init];
//    }
    
    linphone_core_set_zrtp_secrets_file(theLinphoneCore, [zrtpSecretsFileName UTF8String]);
    linphone_core_set_chat_database_path(theLinphoneCore, [chatDBFileName UTF8String]);
    linphone_core_set_call_logs_database_path(theLinphoneCore, [chatDBFileName UTF8String]);
    
    [self setupNetworkReachabilityCallback];
    
    NSString *path = [LinphoneManager bundleFile:@"nowebcamCIF.jpg"];
    if (path) {
        const char *imagePath = [path UTF8String];
        DLog(@"Using '%s' as source image for no webcam", imagePath);
        linphone_core_set_static_picture(theLinphoneCore, imagePath);
    }
    
    /*DETECT cameras*/
    _frontCamId = _backCamId = nil;
    char **camlist = (char **)linphone_core_get_video_devices(theLinphoneCore);
    if (camlist) {
        for (char *cam = *camlist; *camlist != NULL; cam = *++camlist) {
            if (strcmp(FRONT_CAM_NAME, cam) == 0) {
                _frontCamId = cam;
                // great set default cam to front
                DLog(@"Setting default camera [%s]", _frontCamId);
                linphone_core_set_video_device(theLinphoneCore, _frontCamId);
            }
            if (strcmp(BACK_CAM_NAME, cam) == 0) {
                _backCamId = cam;
            }
        }
    } else {
        DLog(@"No camera detected!");
    }
    
    if (![LinphoneManager isNotIphone3G]) {
        PayloadType *pt = linphone_core_find_payload_type(theLinphoneCore, "SILK", 24000, -1);
        if (pt) {
            linphone_core_enable_payload_type(theLinphoneCore, pt, FALSE);
            DLog(@"SILK/24000 and video disabled on old iPhone 3G");
        }
        linphone_core_enable_video_display(theLinphoneCore, FALSE);
        linphone_core_enable_video_capture(theLinphoneCore, FALSE);
    }
    
    [self enableProxyPublish:([UIApplication sharedApplication].applicationState == UIApplicationStateActive)];
    
    DLog(@"Linphone [%s]  started on [%s]", linphone_core_get_version(), [[UIDevice currentDevice].model UTF8String]);
    
    // Post event
    NSDictionary *dict = [NSDictionary dictionaryWithObject:[NSValue valueWithPointer:theLinphoneCore] forKey:@"core"];
    
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneCoreUpdate
                                                      object:LinphoneManager.instance
                                                    userInfo:dict];
}

static BOOL libStarted = FALSE;
- (void)startLinphoneCore {
    
    if (libStarted) {
        DLog(@"Liblinphone is already initialized!")
        return;
    }
    
    libStarted = TRUE;
    
    connectivity = none;
    signal(SIGPIPE, SIG_IGN);
    
    
    // create linphone core
    [self destroyLinphoneCore];
    [self createLinphoneCore];
    [self.providerDelegate config];

//    linphone_core_migrate_to_multi_transport(theLinphoneCore);
    
    // init audio session (just getting the instance will init)
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    BOOL bAudioInputAvailable= audioSession.inputAvailable;
    NSError* err;
    
    if( ![audioSession setActive:NO error: &err] && err ){
        //        NSLog(@"audioSession setActive failed: %@", [err description]);
    }
    if(!bAudioInputAvailable){
        UIAlertView* error = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No microphone",nil)
                                                        message:NSLocalizedString(@"You need to plug a microphone to your device to use this application.",nil)
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Ok",nil)
                                              otherButtonTitles:nil ,nil];
        [error show];
    }
    
    if ([UIApplication sharedApplication].applicationState ==  UIApplicationStateBackground) {
        //go directly to bg mode
        [self enterBackgroundMode];
    }
}
- (void)resetLinphoneCore {
    [self destroyLinphoneCore];
    [self createLinphoneCore];
    // reload friends
//    [self.fastAddressBook fetchContactsInBackGroundThread];
    
    // reset network state to trigger a new network connectivity assessment
    linphone_core_set_network_reachable(theLinphoneCore, FALSE);
}

- (void)destroyLinphoneCore {
    [mIterateTimer invalidate];
    // just in case
    [self removeCTCallCenterCb];
    
    if (theLinphoneCore != nil) { // just in case application terminate before linphone core initialization
        
        for (FileTransferDelegate *ftd in _fileTransferDelegates) {
            [ftd stopAndDestroy];
        }
        [_fileTransferDelegates removeAllObjects];
        
        linphone_core_destroy(theLinphoneCore);
        DLog(@"Destroy linphonecore %p", theLinphoneCore);
        theLinphoneCore = nil;
        
        // Post event
        NSDictionary *dict =
        [NSDictionary dictionaryWithObject:[NSValue valueWithPointer:theLinphoneCore] forKey:@"core"];
        [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneCoreUpdate
                                                          object:LinphoneManager.instance
                                                        userInfo:dict];
        
        SCNetworkReachabilityUnscheduleFromRunLoop(proxyReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        if (proxyReachability)
            CFRelease(proxyReachability);
        proxyReachability = nil;
    }
    libStarted = FALSE;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/**
 设置登陆信息
 */
- (BOOL)addProxyConfig:(NSString*)username password:(NSString*)password displayName:(NSString *)displayName domain:(NSString*)domain port:(NSString *)port withTransport:(NSString*)transport{
    
    LinphoneCore* lc = [LinphoneManager getLc];
    if (lc == nil) {
        [[LinphoneManager instance] startLinphoneCore];
        lc = [LinphoneManager getLc];
    }
    //清除config
//    linphone_core_clear_proxy_config([LinphoneManager getLc]);
//    linphone_core_clear_all_auth_info([LinphoneManager getLc]);
    
    linphone_core_set_network_reachable(theLinphoneCore, true);
    LinphoneProxyConfig *config = linphone_core_create_proxy_config(LC);
    LinphoneAddress *addr = linphone_address_new(NULL);
    LinphoneAddress *tmpAddr = linphone_address_new([NSString stringWithFormat:@"sip:%@",domain].UTF8String);
    linphone_address_set_username(addr, username.UTF8String);
    linphone_address_set_port(addr, linphone_address_get_port(tmpAddr));
    linphone_address_set_domain(addr, linphone_address_get_domain(tmpAddr));
    if (displayName && ![displayName isEqualToString:@""]) {
        linphone_address_set_display_name(addr, displayName.UTF8String);
    }
    linphone_proxy_config_set_identity_address(config, addr);
    
    // set transport
//    UISegmentedControl *transports = (UISegmentedControl *)[self findView:ViewElement_Transport
//                                                                   inView:self.contentView
//                                                                   ofType:UISegmentedControl.class];
//    if (transports) {
//        NSString *type = [transports titleForSegmentAtIndex:[transports selectedSegmentIndex]];
    NSString *type = @"UDP";
        linphone_proxy_config_set_route(
                                        config,
                                        [NSString stringWithFormat:@"%s;transport=%s", domain.UTF8String, type.lowercaseString.UTF8String]
                                        .UTF8String);
        linphone_proxy_config_set_server_addr(
                                              config,
                                              [NSString stringWithFormat:@"%s;transport=%s", domain.UTF8String, type.lowercaseString.UTF8String]
                                              .UTF8String);
//    }
    
    linphone_proxy_config_enable_publish(config, FALSE);
    linphone_proxy_config_enable_register(config, TRUE);
    
    LinphoneAuthInfo *info =
    linphone_auth_info_new(linphone_address_get_username(addr), // username
                           NULL,                                // user id
                           password.UTF8String,                        // passwd
                           NULL,                                // ha1
                           linphone_address_get_domain(addr),   // realm - assumed to be domain
                           linphone_address_get_domain(addr)    // domain
                           );
    //添加之前先清除
    linphone_core_clear_proxy_config([LinphoneManager getLc]);
    linphone_core_clear_all_auth_info([LinphoneManager getLc]);
    
    linphone_core_add_auth_info(LC, info);
    linphone_address_unref(addr);
    linphone_address_unref(tmpAddr);
    
    if (config) {
        [[LinphoneManager instance] configurePushTokenForProxyConfig:config];
        if (linphone_core_add_proxy_config(LC, config) != -1) {
            linphone_core_set_default_proxy_config(LC, config);
            // reload address book to prepend proxy config domain to contacts' phone number
            // todo: STOP doing that!
            DLog(@"登录成功");
            return YES;
        } else {
            return NO;
        }
    } else {
        return NO;
    }
    return NO;
}


/**
 注销登陆信息
 */
- (void)removeAccount{
    
}


/**
 拨打电话
 */
- (void)call:(NSString *)address displayName:(NSString*)displayName transfer:(BOOL)transfer{
    
}
- (void)renameDefaultSettings {
    // rename .linphonerc to linphonerc to ease debugging: when downloading
    // containers from MacOSX, Finder do not display hidden files leading
    // to useless painful operations to display the .linphonerc file
    NSString *src = [LinphoneManager documentFile:@".linphonerc"];
    NSString *dst = [LinphoneManager documentFile:@"linphonerc"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *fileError = nil;
    if ([fileManager fileExistsAtPath:src]) {
        if ([fileManager fileExistsAtPath:dst]) {
            [fileManager removeItemAtPath:src error:&fileError];
            DLog(@"%@ already exists, simply removing %@ %@", dst, src,
                 fileError ? fileError.localizedDescription : @"successfully");
        } else {
            [fileManager moveItemAtPath:src toPath:dst error:&fileError];
            DLog(@"%@ moving to %@ %@", dst, src, fileError ? fileError.localizedDescription : @"successfully");
        }
    }
}
+ (BOOL)copyFile:(NSString *)src destination:(NSString *)dst override:(BOOL)override {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *error = nil;
    if ([fileManager fileExistsAtPath:src] == NO) {
        DLog(@"Can't find \"%@\": %@", src, [error localizedDescription]);
        return FALSE;
    }
    if ([fileManager fileExistsAtPath:dst] == YES) {
        if (override) {
            [fileManager removeItemAtPath:dst error:&error];
            if (error != nil) {
                DLog(@"Can't remove \"%@\": %@", dst, [error localizedDescription]);
                return FALSE;
            }
        } else {
            DLog(@"\"%@\" already exists", dst);
            return FALSE;
        }
    }
    [fileManager copyItemAtPath:src toPath:dst error:&error];
    if (error != nil) {
        DLog(@"Can't copy \"%@\" to \"%@\": %@", src, dst, [error localizedDescription]);
        return FALSE;
    }
    return TRUE;
}

- (void)copyDefaultSettings {
    NSString *src = [LinphoneManager bundleFile:@"linphonerc"];
    NSString *srcIpad = [LinphoneManager bundleFile:@"linphonerc~ipad"];
    if (IPAD && [[NSFileManager defaultManager] fileExistsAtPath:srcIpad]) {
        src = srcIpad;
    }
    NSString *dst = [LinphoneManager documentFile:@"linphonerc"];
    [LinphoneManager copyFile:src destination:dst override:FALSE];
}
- (void)overrideDefaultSettings {
    NSString *factory = [LinphoneManager bundleFile:@"linphonerc-factory"];
    NSString *factoryIpad = [LinphoneManager bundleFile:@"linphonerc-factory~ipad"];
    if (IPAD && [[NSFileManager defaultManager] fileExistsAtPath:factoryIpad]) {
        factory = factoryIpad;
    }
    NSString *confiFileName = [LinphoneManager documentFile:@"linphonerc"];
    _configDb = lp_config_new_with_factory([confiFileName UTF8String], [factory UTF8String]);
}
- (void)migrateFromUserPrefs {
    static NSString *migration_flag = @"userpref_migration_done";
    
    if (_configDb == nil)
        return;
    
    if ([self lpConfigIntForKey:migration_flag withDefault:0]) {
        return;
    }
    
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSArray *defaults_keys = [defaults allKeys];
    NSDictionary *values =
    @{ @"backgroundmode_preference" : @YES,
       @"debugenable_preference" : @NO,
       @"start_at_boot_preference" : @YES };
    BOOL shouldSync = FALSE;
    
    DLog(@"%lu user prefs", (unsigned long)[defaults_keys count]);
    
    for (NSString *userpref in values) {
        if ([defaults_keys containsObject:userpref]) {
            DLog(@"Migrating %@ from user preferences: %d", userpref, [[defaults objectForKey:userpref] boolValue]);
            [self lpConfigSetBool:[[defaults objectForKey:userpref] boolValue] forKey:userpref];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:userpref];
            shouldSync = TRUE;
        } else if ([self lpConfigStringForKey:userpref] == nil) {
            // no default value found in our linphonerc, we need to add them
            [self lpConfigSetBool:[[values objectForKey:userpref] boolValue] forKey:userpref];
        }
    }
    
    if (shouldSync) {
        DLog(@"Synchronizing...");
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    // don't get back here in the future
    [self lpConfigSetBool:YES forKey:migration_flag];
}
- (SCNetworkReachabilityRef)getProxyReachability {
    return proxyReachability;
}
- (void)beginInterruption {
    LinphoneCall *c = linphone_core_get_current_call(theLinphoneCore);
    DLog(@"Sound interruption detected!");
    if (c && linphone_call_get_state(c) == LinphoneCallStreamsRunning) {
        _speakerBeforePause = _speakerEnabled;
        linphone_call_pause(c);
    }
}

- (void)endInterruption {
    DLog(@"Sound interruption ended!");
}
static int comp_call_state_paused(const LinphoneCall *call, const void *param) {
    return linphone_call_get_state(call) != LinphoneCallPaused;
}
static void showNetworkFlags(SCNetworkReachabilityFlags flags) {
    NSMutableString *log = [[NSMutableString alloc] initWithString:@"Network connection flags: "];
    if (flags == 0)
        [log appendString:@"no flags."];
    if (flags & kSCNetworkReachabilityFlagsTransientConnection)
        [log appendString:@"kSCNetworkReachabilityFlagsTransientConnection, "];
    if (flags & kSCNetworkReachabilityFlagsReachable)
        [log appendString:@"kSCNetworkReachabilityFlagsReachable, "];
    if (flags & kSCNetworkReachabilityFlagsConnectionRequired)
        [log appendString:@"kSCNetworkReachabilityFlagsConnectionRequired, "];
    if (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)
        [log appendString:@"kSCNetworkReachabilityFlagsConnectionOnTraffic, "];
    if (flags & kSCNetworkReachabilityFlagsConnectionOnDemand)
        [log appendString:@"kSCNetworkReachabilityFlagsConnectionOnDemand, "];
    if (flags & kSCNetworkReachabilityFlagsIsLocalAddress)
        [log appendString:@"kSCNetworkReachabilityFlagsIsLocalAddress, "];
    if (flags & kSCNetworkReachabilityFlagsIsDirect)
        [log appendString:@"kSCNetworkReachabilityFlagsIsDirect, "];
    if (flags & kSCNetworkReachabilityFlagsIsWWAN)
        [log appendString:@"kSCNetworkReachabilityFlagsIsWWAN, "];
    DLog(@"%@", log);
}

//This callback keeps tracks of wifi SSID changes.
static void networkReachabilityNotification(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                            const void *object, CFDictionaryRef userInfo) {
    LinphoneManager *mgr = LinphoneManager.instance;
    SCNetworkReachabilityFlags flags;
    
    // for an unknown reason, we are receiving multiple time the notification, so
    // we will skip each time the SSID did not change
    NSString *newSSID = [LinphoneManager getCurrentWifiSSID];
    if ([newSSID compare:mgr.SSID] == NSOrderedSame)
        return;
    
    
    if (newSSID != Nil && newSSID.length > 0 && mgr.SSID != Nil && newSSID.length > 0) {
        if (SCNetworkReachabilityGetFlags([mgr getProxyReachability], &flags)) {
            DLog(@"Wifi SSID changed, resesting transports.");
            mgr.connectivity=none; //this will trigger a connectivity change in networkReachabilityCallback.
            networkReachabilityCallBack([mgr getProxyReachability], flags, nil);
        }
    }
    mgr.SSID = newSSID;
}
static int comp_call_id(const LinphoneCall *call, const char *callid) {
    if (linphone_call_log_get_call_id(linphone_call_get_call_log(call)) == nil) {
        ms_error("no callid for call [%p]", call);
        return 1;
    }
    return strcmp(linphone_call_log_get_call_id(linphone_call_get_call_log(call)), callid);
}
void networkReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *nilCtx) {
    showNetworkFlags(flags);
    LinphoneManager *lm = LinphoneManager.instance;
    SCNetworkReachabilityFlags networkDownFlags = kSCNetworkReachabilityFlagsConnectionRequired |
    kSCNetworkReachabilityFlagsConnectionOnTraffic |
    kSCNetworkReachabilityFlagsConnectionOnDemand;
    
    if (theLinphoneCore != nil) {
        LinphoneProxyConfig *proxy = linphone_core_get_default_proxy_config(theLinphoneCore);
        
        struct NetworkReachabilityContext *ctx = nilCtx ? ((struct NetworkReachabilityContext *)nilCtx) : 0;
        if ((flags == 0) || (flags & networkDownFlags)) {
            linphone_core_set_network_reachable(theLinphoneCore, false);
            lm.connectivity = none;
            [LinphoneManager kickOffNetworkConnection];
        } else {
            Connectivity newConnectivity;
            BOOL isWifiOnly = [lm lpConfigBoolForKey:@"wifi_only_preference" withDefault:FALSE];
            if (!ctx || ctx->testWWan)
                newConnectivity = flags & kSCNetworkReachabilityFlagsIsWWAN ? wwan : wifi;
            else
                newConnectivity = wifi;
            
            if (newConnectivity == wwan && proxy && isWifiOnly &&
                (lm.connectivity == newConnectivity || lm.connectivity == none)) {
                linphone_proxy_config_expires(proxy, 0);
            } else if (proxy) {
                NSInteger defaultExpire = [lm lpConfigIntForKey:@"default_expires"];
                if (defaultExpire >= 0)
                    linphone_proxy_config_expires(proxy, (int)defaultExpire);
                // else keep default value from linphonecore
            }
            
            if (lm.connectivity != newConnectivity) {
                // connectivity has changed
                linphone_core_set_network_reachable(theLinphoneCore, false);
                if (newConnectivity == wwan && proxy && isWifiOnly) {
                    linphone_proxy_config_expires(proxy, 0);
                }
                linphone_core_set_network_reachable(theLinphoneCore, true);
                [LinphoneManager.instance iterate];
                DLog(@"Network connectivity changed to type [%s]", (newConnectivity == wifi ? "wifi" : "wwan"));
                lm.connectivity = newConnectivity;
            }
        }
        if (ctx && ctx->networkStateChanged) {
            (*ctx->networkStateChanged)(lm.connectivity);
        }
    }
}
- (LinphoneCall *)callByCallId:(NSString *)call_id {
    const bctbx_list_t *calls = linphone_core_get_calls(theLinphoneCore);
    if (!calls || !call_id) {
        return NULL;
    }
    bctbx_list_t *call_tmp = bctbx_list_find_custom(calls, (bctbx_compare_func)comp_call_id, [call_id UTF8String]);
    if (!call_tmp) {
        return NULL;
    }
    LinphoneCall *call = (LinphoneCall *)call_tmp->data;
    return call;
}

- (void)enableProxyPublish:(BOOL)enabled {
    if (linphone_core_get_global_state(LC) != LinphoneGlobalOn || !linphone_core_get_default_friend_list(LC)) {
        DLog(@"Not changing presence configuration because linphone core not ready yet");
        return;
    }
    
    if ([self lpConfigBoolForKey:@"publish_presence"]) {
        // set present to "tv", because "available" does not work yet
        if (enabled) {
            linphone_core_set_presence_model(
                                             LC, linphone_core_create_presence_model_with_activity(LC, LinphonePresenceActivityTV, NULL));
        }
        
        const MSList *proxies = linphone_core_get_proxy_config_list(LC);
        while (proxies) {
            LinphoneProxyConfig *cfg = proxies->data;
            linphone_proxy_config_edit(cfg);
            linphone_proxy_config_enable_publish(cfg, enabled);
            linphone_proxy_config_done(cfg);
            proxies = proxies->next;
        }
        // force registration update first, then update friend list subscription
        [self iterate];
    }
    
    const MSList *lists = linphone_core_get_friends_lists(LC);
    while (lists) {
        linphone_friend_list_enable_subscriptions(
                                                  lists->data, enabled && [LinphoneManager.instance lpConfigBoolForKey:@"use_rls_presence"]);
        lists = lists->next;
    }
}
- (void)setupNetworkReachabilityCallback {
    SCNetworkReachabilityContext *ctx = NULL;
    // any internet cnx
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    
    if (proxyReachability) {
        DLog(@"Cancelling old network reachability");
        SCNetworkReachabilityUnscheduleFromRunLoop(proxyReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(proxyReachability);
        proxyReachability = nil;
    }
    
    // This notification is used to detect SSID change (switch of Wifi network). The ReachabilityCallback is
    // not triggered when switching between 2 private Wifi...
    // Since we cannot be sure we were already observer, remove ourself each time... to be improved
    _SSID = [LinphoneManager getCurrentWifiSSID];
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self),
                                       CFSTR("com.apple.system.config.network_change"), NULL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self),
                                    networkReachabilityNotification, CFSTR("com.apple.system.config.network_change"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    
    proxyReachability =
    SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    
    if (!SCNetworkReachabilitySetCallback(proxyReachability, (SCNetworkReachabilityCallBack)networkReachabilityCallBack,
                                          ctx)) {
        DLog(@"Cannot register reachability cb: %s", SCErrorString(SCError()));
        return;
    }
    if (!SCNetworkReachabilityScheduleWithRunLoop(proxyReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)) {
        DLog(@"Cannot register schedule reachability cb: %s", SCErrorString(SCError()));
        return;
    }
    
    // this check is to know network connectivity right now without waiting for a change. Don'nt remove it unless you
    // have good reason. Jehan
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(proxyReachability, &flags)) {
        networkReachabilityCallBack(proxyReachability, flags, nil);
    }
}
- (void)refreshRegisters {
    if (connectivity == none) {
        // don't trust ios when he says there is no network. Create a new reachability context, the previous one might
        // be mis-functionning.
        DLog(@"None connectivity");
        [self setupNetworkReachabilityCallback];
    }
    DLog(@"Network reachability callback setup");
    linphone_core_refresh_registers(theLinphoneCore); // just to make sure REGISTRATION is up to date
}

- (BOOL)enterBackgroundMode {
    LinphoneProxyConfig *proxyCfg = linphone_core_get_default_proxy_config(theLinphoneCore);
    BOOL shouldEnterBgMode = FALSE;
    
    // disable presence
    [self enableProxyPublish:NO];
    
    // handle proxy config if any
    if (proxyCfg) {
        const char *refkey = proxyCfg ? linphone_proxy_config_get_ref_key(proxyCfg) : NULL;
        BOOL pushNotifEnabled = (refkey && strcmp(refkey, "push_notification") == 0);
        if ([LinphoneManager.instance lpConfigBoolForKey:@"backgroundmode_preference"] || pushNotifEnabled) {
            if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
                // For registration register
                [self refreshRegisters];
            }
        }
        
        if ([LinphoneManager.instance lpConfigBoolForKey:@"backgroundmode_preference"]) {
            shouldEnterBgMode = TRUE;
        }
    }
    
    LinphoneCall *currentCall = linphone_core_get_current_call(theLinphoneCore);
    const bctbx_list_t *callList = linphone_core_get_calls(theLinphoneCore);
    if (!currentCall // no active call
        && callList  // at least one call in a non active state
        && bctbx_list_find_custom(callList, (bctbx_compare_func)comp_call_state_paused, NULL)) {
        [self startCallPausedLongRunningTask];
    }
    if (callList) {
        /*if at least one call exist, enter normal bg mode */
        shouldEnterBgMode = TRUE;
    }
    /*stop the video preview*/
    if (theLinphoneCore) {
        linphone_core_enable_video_preview(theLinphoneCore, FALSE);
        [self iterate];
    }
    linphone_core_stop_dtmf_stream(theLinphoneCore);
    
    DLog(@"Entering [%s] bg mode", shouldEnterBgMode ? "normal" : "lite");
    
    if (!shouldEnterBgMode && floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        const char *refkey = proxyCfg ? linphone_proxy_config_get_ref_key(proxyCfg) : NULL;
        BOOL pushNotifEnabled = (refkey && strcmp(refkey, "push_notification") == 0);
        if (pushNotifEnabled) {
            DLog(@"Keeping lc core to handle push");
            /*destroy voip socket if any and reset connectivity mode*/
            connectivity = none;
            linphone_core_set_network_reachable(theLinphoneCore, FALSE);
            return YES;
        }
        return NO;
        
    } else
        return YES;
}
- (void)startCallPausedLongRunningTask {
    pausedCallBgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        DLog(@"Call cannot be paused any more, too late");
        [[UIApplication sharedApplication] endBackgroundTask:pausedCallBgTask];
    }];
    DLog(@"Long running task started, remaining [%g s] because at least one call is paused",
         [[UIApplication sharedApplication] backgroundTimeRemaining]);
}
- (void)globalStateChangedNotificationHandler:(NSNotification *)notif {
    if ((LinphoneGlobalState)[[[notif userInfo] valueForKey:@"state"] integerValue] == LinphoneGlobalOn) {
        [self finishCoreConfiguration];
    }
}
- (void)configuringStateChangedNotificationHandler:(NSNotification *)notif {
    _wasRemoteProvisioned = ((LinphoneConfiguringState)[[[notif userInfo] valueForKey:@"state"] integerValue] ==
                             LinphoneConfiguringSuccessful);
    if (_wasRemoteProvisioned) {
        LinphoneProxyConfig *cfg = linphone_core_get_default_proxy_config(LC);
        if (cfg) {
            [self configurePushTokenForProxyConfig:cfg];
        }
    }
}
- (void)audioSessionInterrupted:(NSNotification *)notification {
    int interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue];
    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        [self beginInterruption];
    } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        [self endInterruption];
    }
}
static void linphone_iphone_call_state(LinphoneCore *lc, LinphoneCall *call, LinphoneCallState state,
                                       const char *message) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onCall:call StateChanged:state withMessage:message];
}
static void linphone_iphone_registration_state(LinphoneCore *lc, LinphoneProxyConfig *cfg,
                                               LinphoneRegistrationState state, const char *message) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onRegister:lc cfg:cfg state:state message:message];
}
static void linphone_iphone_notify_presence_received_for_uri_or_tel(LinphoneCore *lc, LinphoneFriend *lf,
                                                                    const char *uri_or_tel,
                                                                    const LinphonePresenceModel *presence_model) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onNotifyPresenceReceivedForUriOrTel:lc
                                                                                                                                       friend:lf
                                                                                                                                          uri:uri_or_tel
                                                                                                                                presenceModel:presence_model];
}
static void linphone_iphone_popup_password_request(LinphoneCore *lc, LinphoneAuthInfo *auth_info, LinphoneAuthMethod method) {
//    DLog(@"%@",auth_info);
}
static void linphone_iphone_message_received(LinphoneCore *lc, LinphoneChatRoom *room, LinphoneChatMessage *message) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onMessageReceived:lc room:room message:message];
}
static void linphone_iphone_message_received_unable_decrypt(LinphoneCore *lc, LinphoneChatRoom *room,
                                                            LinphoneChatMessage *message) {
    DLog(@"%@",message);
}
static void linphone_iphone_transfer_state_changed(LinphoneCore *lc, LinphoneCall *call, LinphoneCallState state) {
    DLog(@"%d",state);
}
static void linphone_iphone_is_composing_received(LinphoneCore *lc, LinphoneChatRoom *room) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onMessageComposeReceived:lc forRoom:room];
}
static void linphone_iphone_configuring_status_changed(LinphoneCore *lc, LinphoneConfiguringState status,
                                                       const char *message) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onConfiguringStatusChanged:status withMessage:message];
}
static void linphone_iphone_global_state_changed(LinphoneCore *lc, LinphoneGlobalState gstate, const char *message) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onGlobalStateChanged:gstate withMessage:message];
}
static void linphone_iphone_notify_received(LinphoneCore *lc, LinphoneEvent *lev, const char *notified_event,
                                            const LinphoneContent *body) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onNotifyReceived:lc
                                                                                                                     event:lev
                                                                                                               notifyEvent:notified_event
                                                                                                                   content:body];
}
static void linphone_iphone_call_encryption_changed(LinphoneCore *lc, LinphoneCall *call, bool_t on,
                                                    const char *authentication_token) {
    [(__bridge LinphoneManager *)linphone_core_cbs_get_user_data(linphone_core_get_current_callbacks(lc)) onCallEncryptionChanged:lc
                                                                                                                             call:call
                                                                                                                               on:on
                                                                                                                            token:authentication_token];
}
- (void)onCall:(LinphoneCall *)call StateChanged:(LinphoneCallState)state withMessage:(const char *)message {
    // Handling wrapper
    DLog(@"%s",message);
    // Handling wrapper
    LinphoneCallAppData *data = (__bridge LinphoneCallAppData *)linphone_call_get_user_data(call);
    if (!data) {
        data = [[LinphoneCallAppData alloc] init];
        linphone_call_set_user_data(call, (void *)CFBridgingRetain(data));
    }
    
#pragma deploymate push "ignored-api-availability"
    if (_silentPushCompletion) {
        // we were woken up by a silent push. Call the completion handler with NEWDATA
        // so that the push is notified to the user
        DLog(@"onCall - handler %p", _silentPushCompletion);
        _silentPushCompletion(UIBackgroundFetchResultNewData);
        _silentPushCompletion = nil;
    }
#pragma deploymate pop
    
    const LinphoneAddress *addr = linphone_call_get_remote_address(call);
//    NSString *address = [FastAddressBook displayNameForAddress:addr];
    NSString *address = @"XXXX";
    if (state == LinphoneCallIncomingReceived) {
        LinphoneCallLog *callLog = linphone_call_get_call_log(call);
        NSString *callId = [NSString stringWithUTF8String:linphone_call_log_get_call_id(callLog)];
        int index = [(NSNumber *)[_pushDict objectForKey:callId] intValue] - 1;
        DLog(@"Decrementing index of long running task for call id : %@ with index : %d", callId, index);
        [_pushDict setValue:[NSNumber numberWithInt:index] forKey:callId];
        BOOL need_bg_task = FALSE;
        for (NSString *key in [_pushDict allKeys]) {
            int value = [(NSNumber *)[_pushDict objectForKey:key] intValue];
            if (value > 0) {
                need_bg_task = TRUE;
                break;
            }
        }
        if (pushBgTaskCall && !need_bg_task) {
            DLog(@"Call received, stopping call background task for call-id [%@]", callId);
            [[UIApplication sharedApplication] endBackgroundTask:pushBgTaskCall];
            pushBgTaskCall = 0;
        }
        /*first step is to re-enable ctcall center*/
        CTCallCenter *lCTCallCenter = [[CTCallCenter alloc] init];
        
        /*should we reject this call ?*/
        if ([lCTCallCenter currentCalls] != nil &&
            floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
            char *tmp = linphone_call_get_remote_address_as_string(call);
            if (tmp) {
                DLog(@"Mobile call ongoing... rejecting call from [%s]", tmp);
                ms_free(tmp);
            }
            linphone_call_decline(call, LinphoneReasonBusy);
            return;
        }
            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
                // if (![LinphoneManager.instance popPushCallID:callId]) {
                // case where a remote notification is not already received
                // Create a new local notification
                if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
                    UIMutableUserNotificationAction *answer = [[UIMutableUserNotificationAction alloc] init];
                    answer.identifier = @"answer";
                    answer.title = NSLocalizedString(@"Answer", nil);
                    answer.activationMode = UIUserNotificationActivationModeForeground;
                    answer.destructive = NO;
                    answer.authenticationRequired = YES;
                    
                    UIMutableUserNotificationAction *decline = [[UIMutableUserNotificationAction alloc] init];
                    decline.identifier = @"decline";
                    decline.title = NSLocalizedString(@"Decline", nil);
                    decline.activationMode = UIUserNotificationActivationModeBackground;
                    decline.destructive = YES;
                    decline.authenticationRequired = NO;
                    
                    NSArray *callactions = @[ decline, answer ];
                    
                    UIMutableUserNotificationCategory *callcat = [[UIMutableUserNotificationCategory alloc] init];
                    callcat.identifier = @"incoming_call";
                    [callcat setActions:callactions forContext:UIUserNotificationActionContextDefault];
                    [callcat setActions:callactions forContext:UIUserNotificationActionContextMinimal];
                    
                    NSSet *categories = [NSSet setWithObjects:callcat, nil];
                    
                    UIUserNotificationSettings *set = [UIUserNotificationSettings
                                                       settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeBadge |
                                                                         UIUserNotificationTypeSound)
                                                       categories:categories];
                    [[UIApplication sharedApplication] registerUserNotificationSettings:set];
                    data->notification = [[UILocalNotification alloc] init];
                    if (data->notification) {
                        // iOS8 doesn't need the timer trick for the local notification.
                        data->notification.category = @"incoming_call";
                        if ([[UIDevice currentDevice].systemVersion floatValue] >= 8 &&
                            [self lpConfigBoolForKey:@"repeat_call_notification"] == NO) {
                            NSString *ring = ([LinphoneManager bundleFile:[self lpConfigStringForKey:@"local_ring"
                                                                                           inSection:@"sound"]
                                               .lastPathComponent]
                                              ?: [LinphoneManager bundleFile:@"notes_of_the_optimistic.caf"])
                            .lastPathComponent;
                            data->notification.soundName = ring;
                        } else {
                            data->notification.soundName = @"shortring.caf";
                            data->timer = [NSTimer scheduledTimerWithTimeInterval:5
                                                                           target:self
                                                                         selector:@selector(localNotifContinue:)
                                                                         userInfo:data->notification
                                                                          repeats:TRUE];
                        }
                        
                        data->notification.repeatInterval = 0;
                        
                        data->notification.alertBody =
                        [NSString stringWithFormat:NSLocalizedString(@"IC_MSG", nil), address];
                        // data->notification.alertAction = NSLocalizedString(@"Answer", nil);
                        data->notification.userInfo = @{ @"callId" : callId, @"timer" : [NSNumber numberWithInt:1] };
                        data->notification.applicationIconBadgeNumber = 1;
                        UIApplication *app = [UIApplication sharedApplication];
                        DLog(@"%@",[app currentUserNotificationSettings].description);
                        [app presentLocalNotificationNow:data->notification];
                        
                        if (!incallBgTask) {
                            incallBgTask =
                            [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                                DLog(@"Call cannot ring any more, too late");
                                [[UIApplication sharedApplication] endBackgroundTask:incallBgTask];
                                incallBgTask = 0;
                            }];
                            
                            if (data->timer) {
                                [[NSRunLoop currentRunLoop] addTimer:data->timer forMode:NSRunLoopCommonModes];
                            }
                        }
                    }
                }
            }
        }
    
    // we keep the speaker auto-enabled state in this static so that we don't
    // force-enable it on ICE re-invite if the user disabled it.
    static BOOL speaker_already_enabled = FALSE;
    
    // Disable speaker when no more call
    if ((state == LinphoneCallEnd || state == LinphoneCallError)) {
        [[UIDevice currentDevice] setProximityMonitoringEnabled:FALSE];
        speaker_already_enabled = FALSE;
        if (linphone_core_get_calls_nb(theLinphoneCore) == 0) {
            [self setSpeakerEnabled:FALSE];
            [self removeCTCallCenterCb];
            // disable this because I don't find anygood reason for it: _bluetoothAvailable = FALSE;
            // furthermore it introduces a bug when calling multiple times since route may not be
            // reconfigured between cause leading to bluetooth being disabled while it should not
            _bluetoothEnabled = FALSE;
        }
        
        if (incallBgTask) {
            [[UIApplication sharedApplication] endBackgroundTask:incallBgTask];
            incallBgTask = 0;
        }
        
        
            if (data != nil && data->notification != nil) {
                LinphoneCallLog *log = linphone_call_get_call_log(call);
                // cancel local notif if needed
                if (data->timer) {
                    [data->timer invalidate];
                    data->timer = nil;
                }
                [[UIApplication sharedApplication] cancelLocalNotification:data->notification];
                data->notification = nil;
                
                if (log == NULL || linphone_call_log_get_status(log) == LinphoneCallMissed) {
                    UILocalNotification *notification = [[UILocalNotification alloc] init];
                    notification.repeatInterval = 0;
                    notification.alertBody = [NSString stringWithFormat:
                                              NSLocalizedString(@"You missed a call from %@",nil), address];
                    notification.alertAction = NSLocalizedString(@"Show", nil);
                    notification.userInfo = [NSDictionary dictionaryWithObject: [NSString stringWithUTF8String:linphone_call_log_get_call_id(log)]
                                                                        forKey:@"callLog"];
                    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
                }
            }
        
        if (state == LinphoneCallError){
            //            [PhoneMainView.instance popCurrentView];
        }
    }
    if (state == LinphoneCallReleased) {
        if (data != NULL) {
            linphone_call_set_user_data(call, NULL);
            CFBridgingRelease((__bridge CFTypeRef)(data));
        }
    }
    // Enable speaker when video
    if (state == LinphoneCallIncomingReceived || state == LinphoneCallOutgoingInit ||
        state == LinphoneCallConnected || state == LinphoneCallStreamsRunning) {
        if (linphone_call_params_video_enabled( linphone_call_get_current_params(call)) && !speaker_already_enabled && !_bluetoothEnabled) {
            [self setSpeakerEnabled:TRUE];
            speaker_already_enabled = TRUE;
        }
    }
    if (state == LinphoneCallStreamsRunning) {
        if (_speakerBeforePause) {
            _speakerBeforePause = FALSE;
            [self setSpeakerEnabled:TRUE];
            speaker_already_enabled = TRUE;
        }
    }
    if (state == LinphoneCallConnected && !mCallCenter) {
        /*only register CT call center CB for connected call*/
        [self setupGSMInteraction];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:!(_speakerEnabled || _bluetoothEnabled)];
    }
    
    // Post event
    NSDictionary *dict = @{@"call" : [NSValue valueWithPointer:call],
                           @"state" : [NSNumber numberWithInt:state],
                           @"message" : [NSString stringWithUTF8String:message]};
    
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneCallUpdate
                                                      object:self
                                                    userInfo:dict];
    
    // 回调message参数
    NSDictionary *msgDic = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:message], @"message", address, @"remote_address", nil];
    
    if (self.delegate) {
        
        // 通话状态更新回调
        switch (state) {
            case LinphoneCallOutgoingInit:{
                DLog(@"通话已呼出->state:%d,\nmessage:%@",state,msgDic);
                if ([[LinphoneManager instance].delegate respondsToSelector:@selector(onOutgoingCall:withState:withMessage:)]) {
                    [[LinphoneManager instance].delegate onOutgoingCall:call withState:state withMessage:msgDic];
                }
                break;
            }
                
            case LinphoneCallIncomingReceived: {
                msgDic = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:message], @"message", address, @"remote_address", [NSString stringWithUTF8String:linphone_core_get_identity([LinphoneManager getLc])], @"called_address", nil];
                DLog(@"收到来电->state:%d,\nmessage:%@",state,msgDic);
                if ([self.delegate respondsToSelector:@selector(onIncomingCall:withState:withMessage:)]) {
                    [self.delegate onIncomingCall:call withState:state withMessage:msgDic];
                }
                break;
            }
                
            case LinphoneCallConnected: {
                DLog(@"电话已建立->state:%d,\nmessage:%@",state,msgDic);
                if ([self.delegate respondsToSelector:@selector(onAnswer:withState:withMessage:)]) {
                    [self.delegate onAnswer:call withState:state withMessage:msgDic];
                }
                break;
            }
                
            case LinphoneCallReleased:
            case LinphoneCallEnd: {
                DLog(@"通话结束->state:%d,\nmessage:%@",state,msgDic);
                if ([self.delegate respondsToSelector:@selector(onHangUp:withState:withMessage:)]) {
                    [self.delegate onHangUp:call withState:state withMessage:msgDic];
                }
                break;
            }
                
            default:
                DLog(@"通话状态更新->state:%d,\nmessage:%@",state,msgDic);
                break;
                
        }
        
    }
}
- (void)onMessageReceived:(LinphoneCore *)lc room:(LinphoneChatRoom *)room message:(LinphoneChatMessage *)msg {
    DLog(@"%@",msg);
}
- (void)onMessageComposeReceived:(LinphoneCore *)core forRoom:(LinphoneChatRoom *)room {
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneTextComposeEvent
                                                      object:self
                                                    userInfo:@{
                                                               @"room" : [NSValue valueWithPointer:room]
                                                               }];
}
- (void)onRegister:(LinphoneCore *)lc
               cfg:(LinphoneProxyConfig *)cfg
             state:(LinphoneRegistrationState)state
           message:(const char *)cmessage {
    DLog(@"New registration state: %s (message: %s)", linphone_registration_state_to_string(state), cmessage);
    
    LinphoneReason reason = linphone_proxy_config_get_error(cfg);
    NSString *message = nil;
    switch (reason) {
        case LinphoneReasonBadCredentials:
            message = NSLocalizedString(@"Bad credentials, check your account settings", nil);
            break;
        case LinphoneReasonNoResponse:
            message = NSLocalizedString(@"No response received from remote", nil);
            break;
        case LinphoneReasonUnsupportedContent:
            message = NSLocalizedString(@"Unsupported content", nil);
            break;
        case LinphoneReasonIOError:
            message = NSLocalizedString(
                                        @"Cannot reach the server: either it is an invalid address or it may be temporary down.", nil);
            break;
            
        case LinphoneReasonUnauthorized:
            message = NSLocalizedString(@"Operation is unauthorized because missing credential", nil);
            break;
        case LinphoneReasonNoMatch:
            message = NSLocalizedString(@"Operation could not be executed by server or remote client because it "
                                        @"didn't have any context for it",
                                        nil);
            break;
        case LinphoneReasonMovedPermanently:
            message = NSLocalizedString(@"Resource moved permanently", nil);
            break;
        case LinphoneReasonGone:
            message = NSLocalizedString(@"Resource no longer exists", nil);
            break;
        case LinphoneReasonTemporarilyUnavailable:
            message = NSLocalizedString(@"Temporarily unavailable", nil);
            break;
        case LinphoneReasonAddressIncomplete:
            message = NSLocalizedString(@"Address incomplete", nil);
            break;
        case LinphoneReasonNotImplemented:
            message = NSLocalizedString(@"Not implemented", nil);
            break;
        case LinphoneReasonBadGateway:
            message = NSLocalizedString(@"Bad gateway", nil);
            break;
        case LinphoneReasonServerTimeout:
            message = NSLocalizedString(@"Server timeout", nil);
            break;
        case LinphoneReasonNotAcceptable:
        case LinphoneReasonDoNotDisturb:
        case LinphoneReasonDeclined:
        case LinphoneReasonNotFound:
        case LinphoneReasonNotAnswered:
        case LinphoneReasonBusy:
        case LinphoneReasonNone:
        case LinphoneReasonUnknown:
            message = NSLocalizedString(@"Unknown error", nil);
            break;
    }
    
    // Post event
    NSDictionary *dict =
    [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:state], @"state",
     [NSValue valueWithPointer:cfg], @"cfg", message, @"message", nil];
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneRegistrationUpdate object:self userInfo:dict];
}
- (void)onGlobalStateChanged:(LinphoneGlobalState)state withMessage:(const char *)message {
    DLog(@"onGlobalStateChanged: %d (message: %s)", state, message);
    
    NSDictionary *dict = [NSDictionary
                          dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:state], @"state",
                          [NSString stringWithUTF8String:message ? message : ""], @"message", nil];
    
    // dispatch the notification asynchronously
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneGlobalStateUpdate object:self userInfo:dict];
    });
}
- (void)onNotifyReceived:(LinphoneCore *)lc
                   event:(LinphoneEvent *)lev
             notifyEvent:(const char *)notified_event
                 content:(const LinphoneContent *)body {
    // Post event
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[NSValue valueWithPointer:lev] forKey:@"event"];
    [dict setObject:[NSString stringWithUTF8String:notified_event] forKey:@"notified_event"];
    if (body != NULL) {
        [dict setObject:[NSValue valueWithPointer:body] forKey:@"content"];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneNotifyReceived object:self userInfo:dict];
}
- (void)onNotifyPresenceReceivedForUriOrTel:(LinphoneCore *)lc
                                     friend:(LinphoneFriend *)lf
                                        uri:(const char *)uri
                              presenceModel:(const LinphonePresenceModel *)model {
    // Post event
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[NSValue valueWithPointer:lf] forKey:@"friend"];
    [dict setObject:[NSValue valueWithPointer:uri] forKey:@"uri"];
    [dict setObject:[NSValue valueWithPointer:model] forKey:@"presence_model"];
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneNotifyPresenceReceivedForUriOrTel
                                                      object:self
                                                    userInfo:dict];
}
- (void)onConfiguringStatusChanged:(LinphoneConfiguringState)status withMessage:(const char *)message {
    DLog(@"onConfiguringStatusChanged: %s %@", linphone_configuring_state_to_string(status),
         message ? [NSString stringWithFormat:@"(message: %s)", message] : @"");
    
    NSDictionary *dict = [NSDictionary
                          dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:status], @"state",
                          [NSString stringWithUTF8String:message ? message : ""], @"message", nil];
    
    // dispatch the notification asynchronously
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneConfiguringStateUpdate
                                                          object:self
                                                        userInfo:dict];
    });
}
- (void)onCallEncryptionChanged:(LinphoneCore *)lc
                           call:(LinphoneCall *)call
                             on:(BOOL)on
                          token:(const char *)authentication_token {
    // Post event
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[NSValue valueWithPointer:call] forKey:@"call"];
    [dict setObject:[NSNumber numberWithBool:on] forKey:@"on"];
    if (authentication_token) {
        [dict setObject:[NSString stringWithUTF8String:authentication_token] forKey:@"token"];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:kLinphoneCallEncryptionChanged object:self userInfo:dict];
}
- (void)createLinphoneCore {
//    [self migrationAllPre];
    if (theLinphoneCore != nil) {
        DLog(@"linphonecore is already created");
        return;
    }
    connectivity = none;
    
    // Set audio assets
    NSString *ring =
    ([LinphoneManager bundleFile:[self lpConfigStringForKey:@"local_ring" inSection:@"sound"].lastPathComponent]
     ?: [LinphoneManager bundleFile:@"notes_of_the_optimistic.caf"])
    .lastPathComponent;
    NSString *ringback =
    ([LinphoneManager bundleFile:[self lpConfigStringForKey:@"remote_ring" inSection:@"sound"].lastPathComponent]
     ?: [LinphoneManager bundleFile:@"ringback.wav"])
    .lastPathComponent;
    NSString *hold =
    ([LinphoneManager bundleFile:[self lpConfigStringForKey:@"hold_music" inSection:@"sound"].lastPathComponent]
     ?: [LinphoneManager bundleFile:@"hold.mkv"])
    .lastPathComponent;
    [self lpConfigSetString:[LinphoneManager bundleFile:ring] forKey:@"local_ring" inSection:@"sound"];
    [self lpConfigSetString:[LinphoneManager bundleFile:ringback] forKey:@"remote_ring" inSection:@"sound"];
    [self lpConfigSetString:[LinphoneManager bundleFile:hold] forKey:@"hold_music" inSection:@"sound"];
    
    LinphoneFactory *factory = linphone_factory_get();
    LinphoneCoreCbs *cbs = linphone_factory_create_core_cbs(factory);
    linphone_core_cbs_set_call_state_changed(cbs, linphone_iphone_call_state);
    linphone_core_cbs_set_registration_state_changed(cbs,linphone_iphone_registration_state);
    linphone_core_cbs_set_notify_presence_received_for_uri_or_tel(cbs, linphone_iphone_notify_presence_received_for_uri_or_tel);
    linphone_core_cbs_set_authentication_requested(cbs, linphone_iphone_popup_password_request);
    linphone_core_cbs_set_message_received(cbs, linphone_iphone_message_received);
    linphone_core_cbs_set_message_received_unable_decrypt(cbs, linphone_iphone_message_received_unable_decrypt);
    linphone_core_cbs_set_transfer_state_changed(cbs, linphone_iphone_transfer_state_changed);
    linphone_core_cbs_set_is_composing_received(cbs, linphone_iphone_is_composing_received);
    linphone_core_cbs_set_configuring_status(cbs, linphone_iphone_configuring_status_changed);
    linphone_core_cbs_set_global_state_changed(cbs, linphone_iphone_global_state_changed);
    linphone_core_cbs_set_notify_received(cbs, linphone_iphone_notify_received);
    linphone_core_cbs_set_call_encryption_changed(cbs, linphone_iphone_call_encryption_changed);
    linphone_core_cbs_set_user_data(cbs, (__bridge void *)(self));
    
    theLinphoneCore = linphone_factory_create_core_with_config(factory, cbs, _configDb);
    // Let the core handle cbs
    linphone_core_cbs_unref(cbs);
    
    DLog(@"Create linphonecore %p", theLinphoneCore);
    
    // Load plugins if available in the linphone SDK - otherwise these calls will do nothing
    MSFactory *f = linphone_core_get_ms_factory(theLinphoneCore);
    libmssilk_init(f);
    libmsamr_init(f);
    libmsx264_init(f);
    libmsopenh264_init(f);
    libmswebrtc_init(f);
    libmscodec2_init(f);
    
    linphone_core_reload_ms_plugins(theLinphoneCore, NULL);
//    [self migrationAllPost];
    
    /* set the CA file no matter what, since the remote provisioning could be hitting an HTTPS server */
    linphone_core_set_root_ca(theLinphoneCore, [LinphoneManager bundleFile:@"rootca.pem"].UTF8String);
    linphone_core_set_user_certificates_path(theLinphoneCore, [LinphoneManager cacheDirectory].UTF8String);
    
    /* The core will call the linphone_iphone_configuring_status_changed callback when the remote provisioning is loaded
     (or skipped).
     Wait for this to finish the code configuration */
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(audioSessionInterrupted:)
                                               name:AVAudioSessionInterruptionNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(globalStateChangedNotificationHandler:)
                                               name:kLinphoneGlobalStateUpdate
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(configuringStateChangedNotificationHandler:)
                                               name:kLinphoneConfiguringStateUpdate
                                             object:nil];
//        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inappReady:) name:kIAPReady object:nil];
    
    /*call iterate once immediately in order to initiate background connections with sip server or remote provisioning
     * grab, if any */
    [self iterate];
    // start scheduler
    mIterateTimer =
    [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(iterate) userInfo:nil repeats:YES];
}
- (NetworkType)network {
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 7) {
        UIApplication *app = [UIApplication sharedApplication];
        NSArray *subviews = [[[app valueForKey:@"statusBar"] valueForKey:@"foregroundView"] subviews];
        NSNumber *dataNetworkItemView = nil;
        
        for (id subview in subviews) {
            if ([subview isKindOfClass:[NSClassFromString(@"UIStatusBarDataNetworkItemView") class]]) {
                dataNetworkItemView = subview;
                break;
            }
        }
        
        NSNumber *number = (NSNumber *)[dataNetworkItemView valueForKey:@"dataNetworkType"];
        return [number intValue];
    } else {
#pragma deploymate push "ignored-api-availability"
        CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
        NSString *currentRadio = info.currentRadioAccessTechnology;
        if ([currentRadio isEqualToString:CTRadioAccessTechnologyEdge]) {
            return network_2g;
        } else if ([currentRadio isEqualToString:CTRadioAccessTechnologyLTE]) {
            return network_4g;
        }
#pragma deploymate pop
        return network_3g;
    }
}
// scheduling loop
- (void)iterate {
    UIBackgroundTaskIdentifier coreIterateTaskId = 0;
    coreIterateTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        DLog(@"Background task for core iteration launching expired.");
        [[UIApplication sharedApplication] endBackgroundTask:coreIterateTaskId];
    }];
    linphone_core_iterate(theLinphoneCore);
    if (coreIterateTaskId != UIBackgroundTaskInvalid)
        [[UIApplication sharedApplication] endBackgroundTask:coreIterateTaskId];
}
- (void)setSpeakerEnabled:(BOOL)enable {
    _speakerEnabled = enable;
    NSError *err = nil;
    
    if (enable && [self allowSpeaker]) {
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&err];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:FALSE];
        _bluetoothEnabled = FALSE;
    } else {
        AVAudioSessionPortDescription *builtinPort = [AudioHelper builtinAudioDevice];
        [[AVAudioSession sharedInstance] setPreferredInput:builtinPort error:&err];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:(linphone_core_get_calls_nb(LC) > 0)];
    }
    
    if (err) {
        DLog(@"Failed to change audio route: err %@", err.localizedDescription);
        err = nil;
    }
}
#pragma mark - Audio route Functions

- (bool)allowSpeaker {
    if (IPAD)
        return true;
    
    bool allow = true;
    AVAudioSessionRouteDescription *newRoute = [AVAudioSession sharedInstance].currentRoute;
    if (newRoute) {
        NSString *route = newRoute.outputs[0].portType;
        allow = !([route isEqualToString:AVAudioSessionPortLineOut] ||
                  [route isEqualToString:AVAudioSessionPortHeadphones] ||
                  [[AudioHelper bluetoothRoutes] containsObject:route]);
    }
    return allow;
}

#pragma mark - Call Functions

- (void)acceptCall:(LinphoneCall *)call evenWithVideo:(BOOL)video {
    LinphoneCallParams *lcallParams = linphone_core_create_call_params(theLinphoneCore, call);
    if (!lcallParams) {
        DLog(@"Could not create call parameters for %p, call has probably already ended.", call);
        return;
    }
    
    if ([self lpConfigBoolForKey:@"edge_opt_preference"]) {
        bool low_bandwidth = self.network == network_2g;
        if (low_bandwidth) {
            DLog(@"Low bandwidth mode");
        }
        linphone_call_params_enable_low_bandwidth(lcallParams, low_bandwidth);
    }
    linphone_call_params_enable_video(lcallParams, video);
    
    linphone_call_accept_with_params(call, lcallParams);
    
//    [self setSpeakerEnabled:YES];
}
- (BOOL)doCall:(const LinphoneAddress *)iaddr {
    LinphoneAddress *addr = linphone_address_clone(iaddr);
//    NSString *displayName = [FastAddressBook displayNameForAddress:addr];
    NSString *displayName = @"####";

    // Finally we can make the call
    LinphoneCallParams *lcallParams = linphone_core_create_call_params(theLinphoneCore, NULL);
    if ([self lpConfigBoolForKey:@"edge_opt_preference"] && (self.network == network_2g)) {
        DLog(@"Enabling low bandwidth mode");
        linphone_call_params_enable_low_bandwidth(lcallParams, YES);
    }
    
    if (displayName != nil) {
        linphone_address_set_display_name(addr, displayName.UTF8String);
    }
    if ([LinphoneManager.instance lpConfigBoolForKey:@"override_domain_with_default_one"]) {
        linphone_address_set_domain(
                                    addr, [[LinphoneManager.instance lpConfigStringForKey:@"domain" inSection:@"assistant"] UTF8String]);
    }
    
    LinphoneCall *call;
    if (LinphoneManager.instance.nextCallIsTransfer) {
        char *caddr = linphone_address_as_string(addr);
        call = linphone_core_get_current_call(theLinphoneCore);
        linphone_call_transfer(call, caddr);
        LinphoneManager.instance.nextCallIsTransfer = NO;
        ms_free(caddr);
    } else {
        call = linphone_core_invite_address_with_params(theLinphoneCore, addr, lcallParams);
        if (call) {
            // The LinphoneCallAppData object should be set on call creation with callback
            // - (void)onCall:StateChanged:withMessage:. If not, we are in big trouble and expect it to crash
            // We are NOT responsible for creating the AppData.
            LinphoneCallAppData *data = (__bridge LinphoneCallAppData *)linphone_call_get_user_data(call);
            if (data == nil) {
                DLog(@"New call instanciated but app data was not set. Expect it to crash.");
                /* will be used later to notify user if video was not activated because of the linphone core*/
            } else {
                data->videoRequested = linphone_call_params_video_enabled(lcallParams);
            }
        }
    }
    linphone_address_destroy(addr);
    linphone_call_params_destroy(lcallParams);
    
    return TRUE;
}

#pragma mark - LPConfig Functions

- (void)lpConfigSetString:(NSString *)value forKey:(NSString *)key {
    [self lpConfigSetString:value forKey:key inSection:LINPHONERC_APPLICATION_KEY];
}
- (void)lpConfigSetString:(NSString *)value forKey:(NSString *)key inSection:(NSString *)section {
    if (!key)
        return;
    lp_config_set_string(_configDb, [section UTF8String], [key UTF8String], value ? [value UTF8String] : NULL);
}
- (NSString *)lpConfigStringForKey:(NSString *)key {
    return [self lpConfigStringForKey:key withDefault:nil];
}
- (NSString *)lpConfigStringForKey:(NSString *)key withDefault:(NSString *)defaultValue {
    return [self lpConfigStringForKey:key inSection:LINPHONERC_APPLICATION_KEY withDefault:defaultValue];
}
- (NSString *)lpConfigStringForKey:(NSString *)key inSection:(NSString *)section {
    return [self lpConfigStringForKey:key inSection:section withDefault:nil];
}
- (NSString *)lpConfigStringForKey:(NSString *)key inSection:(NSString *)section withDefault:(NSString *)defaultValue {
    if (!key)
        return defaultValue;
    const char *value = lp_config_get_string(_configDb, [section UTF8String], [key UTF8String], NULL);
    return value ? [NSString stringWithUTF8String:value] : defaultValue;
}

- (void)lpConfigSetInt:(int)value forKey:(NSString *)key {
    [self lpConfigSetInt:value forKey:key inSection:LINPHONERC_APPLICATION_KEY];
}
- (void)lpConfigSetInt:(int)value forKey:(NSString *)key inSection:(NSString *)section {
    if (!key)
        return;
    lp_config_set_int(_configDb, [section UTF8String], [key UTF8String], (int)value);
}
- (int)lpConfigIntForKey:(NSString *)key {
    return [self lpConfigIntForKey:key withDefault:-1];
}
- (int)lpConfigIntForKey:(NSString *)key withDefault:(int)defaultValue {
    return [self lpConfigIntForKey:key inSection:LINPHONERC_APPLICATION_KEY withDefault:defaultValue];
}
- (int)lpConfigIntForKey:(NSString *)key inSection:(NSString *)section {
    return [self lpConfigIntForKey:key inSection:section withDefault:-1];
}
- (int)lpConfigIntForKey:(NSString *)key inSection:(NSString *)section withDefault:(int)defaultValue {
    if (!key)
        return defaultValue;
    return lp_config_get_int(_configDb, [section UTF8String], [key UTF8String], (int)defaultValue);
}

- (void)lpConfigSetBool:(BOOL)value forKey:(NSString *)key {
    [self lpConfigSetBool:value forKey:key inSection:LINPHONERC_APPLICATION_KEY];
}
- (void)lpConfigSetBool:(BOOL)value forKey:(NSString *)key inSection:(NSString *)section {
    [self lpConfigSetInt:(int)(value == TRUE) forKey:key inSection:section];
}
- (BOOL)lpConfigBoolForKey:(NSString *)key {
    return [self lpConfigBoolForKey:key withDefault:FALSE];
}
- (BOOL)lpConfigBoolForKey:(NSString *)key withDefault:(BOOL)defaultValue {
    return [self lpConfigBoolForKey:key inSection:LINPHONERC_APPLICATION_KEY withDefault:defaultValue];
}
- (BOOL)lpConfigBoolForKey:(NSString *)key inSection:(NSString *)section {
    return [self lpConfigBoolForKey:key inSection:section withDefault:FALSE];
}
- (BOOL)lpConfigBoolForKey:(NSString *)key inSection:(NSString *)section withDefault:(BOOL)defaultValue {
    if (!key)
        return defaultValue;
    int val = [self lpConfigIntForKey:key inSection:section withDefault:-1];
    return (val != -1) ? (val == 1) : defaultValue;
}
- (void)configurePushTokenForProxyConfig:(LinphoneProxyConfig *)proxyCfg {
    linphone_proxy_config_edit(proxyCfg);
    
    NSData *tokenData = _pushNotificationToken;
    const char *refkey = linphone_proxy_config_get_ref_key(proxyCfg);
    BOOL pushNotifEnabled = (refkey && strcmp(refkey, "push_notification") == 0);
    if (tokenData != nil && pushNotifEnabled) {
        const unsigned char *tokenBuffer = [tokenData bytes];
        NSMutableString *tokenString = [NSMutableString stringWithCapacity:[tokenData length] * 2];
        for (int i = 0; i < [tokenData length]; ++i) {
            [tokenString appendFormat:@"%02X", (unsigned int)tokenBuffer[i]];
        }
        // NSLocalizedString(@"IC_MSG", nil); // Fake for genstrings
        // NSLocalizedString(@"IM_MSG", nil); // Fake for genstrings
        // NSLocalizedString(@"IM_FULLMSG", nil); // Fake for genstrings
#ifdef DEBUG
#define APPMODE_SUFFIX @"dev"
#else
#define APPMODE_SUFFIX @"prod"
#endif
        NSString *ring =
        ([LinphoneManager bundleFile:[self lpConfigStringForKey:@"local_ring" inSection:@"sound"].lastPathComponent]
         ?: [LinphoneManager bundleFile:@"notes_of_the_optimistic.caf"])
        .lastPathComponent;
        
        NSString *timeout;
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_x_Max) {
            timeout = @";pn-timeout=0";
        } else {
            timeout = @"";
        }
        
        NSString *params = [NSString
                            stringWithFormat:@"app-id=%@.voip.%@;pn-type=apple;pn-tok=%@;pn-msg-str=IM_MSG;pn-call-str=IC_MSG;pn-"
                            @"call-snd=%@;pn-msg-snd=msg.caf%@;pn-silent=1",
                            [[NSBundle mainBundle] bundleIdentifier], APPMODE_SUFFIX, tokenString, ring, timeout];
        
        DLog(@"Proxy config %s configured for push notifications with contact: %@",
             linphone_proxy_config_get_identity(proxyCfg), params);
        linphone_proxy_config_set_contact_uri_parameters(proxyCfg, [params UTF8String]);
        linphone_proxy_config_set_contact_parameters(proxyCfg, NULL);
    } else {
        DLog(@"Proxy config %s NOT configured for push notifications", linphone_proxy_config_get_identity(proxyCfg));
        // no push token:
        linphone_proxy_config_set_contact_uri_parameters(proxyCfg, NULL);
        linphone_proxy_config_set_contact_parameters(proxyCfg, NULL);
    }
    
    linphone_proxy_config_done(proxyCfg);
}
#pragma mark - GSM management

- (void)removeCTCallCenterCb {
    if (mCallCenter != nil) {
        DLog(@"Removing CT call center listener [%p]", mCallCenter);
        mCallCenter.callEventHandler = NULL;
    }
    mCallCenter = nil;
}
- (void)setupGSMInteraction {
    
    [self removeCTCallCenterCb];
    mCallCenter = [[CTCallCenter alloc] init];
    DLog(@"Adding CT call center listener [%p]", mCallCenter);
    __block __weak LinphoneManager *weakSelf = self;
    __block __weak CTCallCenter *weakCCenter = mCallCenter;
    mCallCenter.callEventHandler = ^(CTCall *call) {
        // post on main thread
        [weakSelf performSelectorOnMainThread:@selector(handleGSMCallInteration:)
                                   withObject:weakCCenter
                                waitUntilDone:YES];
    };
}

- (void)handleGSMCallInteration:(id)cCenter {
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        CTCallCenter *ct = (CTCallCenter *)cCenter;
        // pause current call, if any
        LinphoneCall *call = linphone_core_get_current_call(theLinphoneCore);
        if ([ct currentCalls] != nil) {
            if (call) {
                DLog(@"Pausing SIP call because GSM call");
                _speakerBeforePause = _speakerEnabled;
                linphone_call_pause(call);
                [self startCallPausedLongRunningTask];
            } else if (linphone_core_is_in_conference(theLinphoneCore)) {
                DLog(@"Leaving conference call because GSM call");
                linphone_core_leave_conference(theLinphoneCore);
                [self startCallPausedLongRunningTask];
            }
        } // else nop, keep call in paused state
    }
}

#pragma mark - Misc Functions

+ (NSString *)bundleFile:(NSString *)file {
    return [[NSBundle mainBundle] pathForResource:[file stringByDeletingPathExtension] ofType:[file pathExtension]];
}
+ (NSString *)cacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath = [paths objectAtIndex:0];
    BOOL isDir = NO;
    NSError *error;
    // cache directory must be created if not existing
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath isDirectory:&isDir] && isDir == NO) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cachePath
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:&error];
    }
    return cachePath;
}
+ (NSString *)documentFile:(NSString *)file {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = [paths objectAtIndex:0];
    return [documentsPath stringByAppendingPathComponent:file];
}
@end
