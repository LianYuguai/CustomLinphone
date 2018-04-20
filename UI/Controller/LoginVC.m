//
//  LoginVC.m
//  CustomLinphone
//
//  Created by yulong on 2018/4/16.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import "LoginVC.h"
#import "LinphoneManager.h"
@interface LoginVC ()<UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UITextField *nameField;
@property (weak, nonatomic) IBOutlet UITextField *passwordField;
@property (weak, nonatomic) IBOutlet UITextField *domainField;

@end

@implementation LoginVC

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)loginAction:(id)sender {
    [[LinphoneManager instance] addProxyConfig:self.nameField.text password:self.passwordField.text displayName:@"" domain:self.domainField.text port:nil withTransport:@"UDP"];
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    return  YES;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [_nameField resignFirstResponder];
    [_passwordField resignFirstResponder];
    [_domainField resignFirstResponder];

}
- (IBAction)loginOut:(id)sender {
//    [[LinphoneManager instance] destroyLinphoneCore];
    linphone_core_clear_proxy_config([LinphoneManager getLc]);
    linphone_core_clear_all_auth_info([LinphoneManager getLc]);
    @try {
        [LinphoneManager.instance destroyLinphoneCore];
    } @catch (NSException *e) {
        DLog(@"Exception while destroying linphone core: %@", e);
    } @finally {
        if ([NSFileManager.defaultManager
             isDeletableFileAtPath:[LinphoneManager documentFile:@"linphonerc"]] == YES) {
            [NSFileManager.defaultManager
             removeItemAtPath:[LinphoneManager documentFile:@"linphonerc"]
             error:nil];
        }
#ifdef DEBUG
//        [LinphoneManager instanceRelease];
#endif
    }
//    [UIApplication sharedApplication].keyWindow.rootViewController = nil;
    // make the application crash to be sure that user restart it properly
    DLog(@"Self-destructing in 3..2..1..0!");
}
@end
