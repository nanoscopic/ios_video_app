// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "ViewController.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *blah;
@property (weak, nonatomic) IBOutlet UILabel *inputPort;
@property (weak, nonatomic) IBOutlet UILabel *controlPort;

@end

@implementation ViewController

-(ViewController *) init {
    self = [super init];
    return self;
}

- (void)viewDidLoad {
    _inputPort.text = @"Input port 8352";
    _controlPort.text = @"Control port 8351";
    _blah.text = @"";
    
    [super viewDidLoad];
}

@end
