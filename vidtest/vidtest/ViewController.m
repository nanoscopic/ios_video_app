// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "ViewController.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *blah;

@end

@implementation ViewController

- (void)viewDidLoad {
    NSFileManager *fileMan = [NSFileManager defaultManager];
    NSURL *sharedUrl = [fileMan containerURLForSecurityApplicationGroupIdentifier:@"group.com.dryark.vidtest"];
    
    NSURL *docDir = [[fileMan URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *sourceUrl = [docDir URLByAppendingPathComponent:@"config.json"];
    
    NSError *err;
    
    //NSArray <NSURL *> *fileurls = [fileMan contentsOfDirectoryAtURL:docDir includingPropertiesForKeys:nil options:nil error:nil];
    
    NSURL *destUrl = [sharedUrl URLByAppendingPathComponent:@"config.json"];
    
    [fileMan removeItemAtURL:destUrl error:&err];
    [fileMan copyItemAtURL:sourceUrl toURL: destUrl error:&err];
    
    _blah.text = @"Hello World";
    
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

@end
