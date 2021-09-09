// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "ViewController.h"
#import <ReplayKit/ReplayKit.h>

@interface ViewController ()
@end

@implementation ViewController

-(ViewController *) init {
    self = [super init];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIView *view = [[UIView alloc] initWithFrame: UIScreen.mainScreen.bounds /*CGRectMake(0,0,320,300)*/];
    UIColor *color = [UIColor colorWithRed:246/255.f green:0/255.f blue:0/255.f alpha:1.0];
    view.backgroundColor = color;
    
    UIColor *color2 = [UIColor colorWithRed:0/255.f green:200/255.f blue:0/255.f alpha:1.0];
    
    RPSystemBroadcastPickerView *picker = [[RPSystemBroadcastPickerView alloc] initWithFrame:view.frame];//CGRectMake(0,40,320,200)];
    
    NSString *bi = [[NSBundle mainBundle] bundleIdentifier];
    NSString *ebi = [bi stringByAppendingString:@".extension"];
    
    picker.preferredExtension = ebi;//@"com.dryark.vidstream.extension";
    picker.backgroundColor = color2;
    
    UIButton *btn = picker.subviews[0];
    [btn setTitle:@"  Broadcast Selector" forState:UIControlStateNormal];
    [btn setAccessibilityIdentifier:@"Broadcast Selector"];
    UIImage *playImg = [UIImage systemImageNamed: @"play"];
    [btn setImage: playImg forState:UIControlStateNormal];
    [view addSubview: picker];
    
    //[btn sendActionsForControlEvents:UIControlEventAllTouchEvents];
    [self.view addSubview: view];
    //self.view = view;
}

@end
