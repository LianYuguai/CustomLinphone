//
//  ViewController.m
//  CustomLinphone
//
//  Created by yulong on 2018/4/16.
//  Copyright © 2018年 yulong. All rights reserved.
//

#import "ViewController.h"
#import "LoginVC.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)goLogin:(id)sender {
    LoginVC *loginVC = [LoginVC new];
    [self.navigationController pushViewController:loginVC animated:YES];
}


@end
