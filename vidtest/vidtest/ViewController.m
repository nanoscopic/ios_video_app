// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "ViewController.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *blah;

@end

@implementation ViewController

-(ViewController *) init {
    self = [super init];
    ujsonin_init();
    
    return self;
}

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
    
    NSString *confPath = [sourceUrl absoluteString];
    const char *cPath = [confPath UTF8String];
    //NSLog( @"xxr config path %s", cPath );
    FILE *fh = fopen( &cPath[7], "r" );
    
    fseek(fh, 0, SEEK_END);
    long fsize = ftell(fh);
    fseek(fh, 0, SEEK_SET);  /* same as rewind(f); */

    char *string = malloc(fsize + 1);
    fread(string, 1, fsize, fh);
    
    int err2;
    node_hash *root = parse( (char *) string, (int) fsize, NULL, &err2 );
    jnode *port = node_hash__get( root, "port", 4 );
    jnode *ip = node_hash__get( root, "ip", 2 );
    if( port->type == 2 && ip->type == 2 ) {
        node_str *strOb = (node_str *) port;
        node_str *ipOb = ( node_str * ) ip;
        
        char buffer[30];
        sprintf(buffer,"%.*s:%.*s",ipOb->len,ipOb->str,strOb->len,strOb->str);
        
        NSString *str = [NSString stringWithUTF8String:buffer];
        
        _blah.text = str;
    } else {
        _blah.text = @"Config invalid";
    }
    
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

@end
