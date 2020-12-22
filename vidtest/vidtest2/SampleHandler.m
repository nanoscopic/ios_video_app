// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "SampleHandler.h"
//#include "TurboJPEG/libjpeg-turbo/include/turbojpeg.h"
typedef struct fp_msg_base_s {
    int type;
} fp_msg_base;

typedef struct fp_msg_text_s {
    int type; // 1
    char *text;
} fp_msg_text;

typedef struct fp_msg_buffer_s {
    int type; // 2
    CMSampleBufferRef sampleBuffer;
    long frameNum;
} fp_msg_buffer;

typedef struct fp_msg_port_s {
    int type; // 3
    int port;
    char *ip;
} fp_msg_port;

fp_msg_text *fp_msg__new_text( char *text ) {
    fp_msg_text *msg = (fp_msg_text *) calloc( sizeof( fp_msg_text ), 1 );
    msg->type = 1;
    msg->text = text;
    return msg;
}

fp_msg_port *fp_msg__new_port( int port, char *ip ) {
    fp_msg_port *msg = (fp_msg_port *) calloc( sizeof( fp_msg_port ), 1 );
    msg->type = 3;
    msg->port = port;
    msg->ip = ip;
    return msg;
}

fp_msg_buffer *fp_msg__new_buffer( CMSampleBufferRef sampleBuffer, long frameNum ) {
    fp_msg_buffer *msg = (fp_msg_buffer *) calloc( sizeof( fp_msg_buffer ), 1 );
    msg->type = 2;
    msg->sampleBuffer = sampleBuffer;
    msg->frameNum = frameNum;
    return msg;
}

#define clamp(a) (a > 255 ? 255 : (a < 0 ? 0 : a));

uint8_t * rgbFromYCrCbBiPlanarFullRangeBuffer(uint8_t *inBaseAddress,
                                              uint8_t *cbCrBuffer,
                                              CVPlanarPixelBufferInfo_YCbCrBiPlanar * inBufferInfo,
                                              size_t srcWidth,
                                              size_t srcHeight,
                                              size_t inputBufferBytesPerRow,
                                              size_t destWidth,
                                              size_t destHeight )
{
    int bytesPerPixel = 3;
    NSUInteger yPitch = CFSwapInt32BigToHost( inBufferInfo->componentInfoY.rowBytes ); //EndianU32_BtoN(inBufferInfo->componentInfoY.rowBytes);
    uint8_t *rgbBuffer = (uint8_t *)malloc(destWidth * destHeight * bytesPerPixel);
    NSUInteger cbCrPitch = CFSwapInt32BigToHost( inBufferInfo->componentInfoCbCr.rowBytes ); //EndianU32_BtoN(inBufferInfo->componentInfoCbCr.rowBytes);
    uint8_t *yBuffer = (uint8_t *)inBaseAddress;

    float scale = (float) destHeight / (float) srcHeight;
    
    for(int destY = 0; destY < destHeight; destY++)
    {
        size_t srcY = (int) ( (float) destY / scale );
        
        uint8_t *rgbBufferLine = &rgbBuffer[destY * destWidth * bytesPerPixel];
        uint8_t *yBufferLine = &yBuffer[srcY * yPitch];
        uint8_t *cbCrBufferLine = &cbCrBuffer[(srcY >> 1) * cbCrPitch];
        for(int destX = 0; destX < destWidth; destX++)
        {
            size_t srcX = (int) ( (float) destX / scale );
            int16_t y = yBufferLine[srcX];
            int16_t cb = cbCrBufferLine[srcX & ~1] - 128;
            int16_t cr = cbCrBufferLine[srcX | 1] - 128;

            uint8_t *rgbOutput = &rgbBufferLine[destX*bytesPerPixel];

            int16_t r = (int16_t)roundf( y + cr *  1.4 );
            int16_t g = (int16_t)roundf( y + cb * -0.343 + cr * -0.711 );
            int16_t b = (int16_t)roundf( y + cb *  1.765);

            // ABGR image representation
            //rgbOutput[0] = 0Xff;
            rgbOutput[0] = clamp(b);
            rgbOutput[1] = clamp(g);
            rgbOutput[2] = clamp(r);
        }
    }

    return rgbBuffer;
}

#import<Accelerate/Accelerate.h>

void discard_buffer( fp_msg_buffer *msg ) {
    CFRelease( msg->sampleBuffer );
}

void handle_buffer( fp_msg_buffer *msg, nng_socket push, CIContext *context ) {
    CVImageBufferRef sourcePixelBuffer;
    CIImage *ciImage;
    UIImage *img;
    
    sourcePixelBuffer = CMSampleBufferGetImageBuffer( msg->sampleBuffer );
    
    CFTypeID imageType = CFGetTypeID(sourcePixelBuffer);

    if (imageType == CVPixelBufferGetTypeID()) {
        NSLog( @"xxr pix buf");
        
        CVPixelBufferRef pixelBuffer;
        @autoreleasepool {
                
            pixelBuffer = ( CVPixelBufferRef ) sourcePixelBuffer;
            CVPixelBufferLockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
            int w = (int) CVPixelBufferGetWidth( pixelBuffer );
            int h = (int) CVPixelBufferGetHeight( pixelBuffer );
            
            // Resize via vImage
            /*void *data = CVPixelBufferGetBaseAddress( pixelBuffer );
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
            
            CVImageBufferRef cvImage;
            vImage_Buffer inBuff;
            inBuff.height = h;
            inBuff.width = w;
            inbuff.rowBytes = bytesPerRow;
            inbuff.data = data;
            
            size_t destH = 800;
            float scale = (float) 800 / (float) h;
            size_t destW = (size_t) ( (float) scale * (float) w );
            unsigned char *outImg = (unsigned char *) malloc( 4*destW*destH );
            vImage_Buffer outBuff = { outImg, destH, destW, 4*destW };
            
            vImage_Error err = vImageScale_ARGB8888( &inBuff, &outBuff, NULL, 0 );
            
            CVPixelBufferRef sizedBuffer = CVPixelBufferCreateWithBytes( );*/
            
            /*
            void *data = CVPixelBufferGetBaseAddress( pixelBuffer );
            size_t size = CVPixelBufferGetDataSize( pixelBuffer );
            
            
            
            int qual = MIN(100, MAX(1, (int)(75 * 100)));
            unsigned char *jpegBuf = NULL;
            unsigned long jpegSize = 0;
            int bytesPerRow = (int) CVPixelBufferGetBytesPerRow(pixelBuffer);
            
            //unsigned int type = CVPixelBufferGetPixelFormatType( pixelBuffer );
            //NSLog(@"xxr type: %d", type );
            // this spits out 420f
            
            CVPlanarPixelBufferInfo_YCbCrBiPlanar *bufferInfo = (CVPlanarPixelBufferInfo_YCbCrBiPlanar *)data;
            uint8_t* cbrBuff = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
            // This just moved the pointer past the offset
            uint8_t * baseAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            //int bytesPerPixel = 4;
            
            size_t destH = 800;
            float scale = (float) 800 / (float) h;
            size_t destW = (size_t) ( (float) scale * (float) w );
            
            NSLog(@"xxr w: %d, h: %d, num:%ld", destW, destH, msg->frameNum );
            
            uint8_t *rgbData =  rgbFromYCrCbBiPlanarFullRangeBuffer(baseAddress,
                                                                    cbrBuff,
                                                                    bufferInfo,
                                                                    w,
                                                                    h,
                                                                    bytesPerRow,
                                                                    destW,
                                                                    destH );
            
            tjhandle handle = tjInitCompress();
            //int success = tjCompress2(
            //      handle,
            //      data,
            //      (int)w,
            //      0,
            //      (int)h,
            //      TJPF_RGBA,
            //      &jpegBuf,
            //      &jpegSize,
            //      TJSAMP_444,
            //      qual,
            //      TJFLAG_FASTDCT
            //);
            
            int _bufferSize = tjBufSize( destW, destH, TJSAMP_420 );
            jpegBuf = tjAlloc(_bufferSize);
            
            int success = tjCompress2(
                        handle,
                        rgbData,
                        destW,
                        3*destW,//bytesPerRow,
                        destH,
                        TJPF_BGR,
                        &jpegBuf,
                        &jpegSize,
                        TJSAMP_420,
                        qual,
                        TJFLAG_FASTDCT | TJFLAG_NOREALLOC );
            NSLog( @"xxr jpeg success %d", success);
            
            free( rgbData );
            */
            
            ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer];
            //CIContext *context = [CIContext context];
            
            
            //CGColorSpaceRef linearColorSpace = CGColorSpaceCreateWithName( kCGColorSpaceLinearSRGB );
            CGColorSpaceRef deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB();
            
            size_t destH = 1000;
            float scale = (float) destH / (float) h;
            size_t destW = (size_t) ( (float) scale * (float) w );
            
            CIFilter *filter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
            [filter setValue:ciImage forKey:@"inputImage"];
            [filter setValue:[[NSNumber alloc] initWithFloat:scale] forKey:@"inputScale"];
            [filter setValue:@1.0 forKey:@"inputAspectRatio"];
            CIImage *newImage = filter.outputImage;
            
            //NSData *heifData = [context HEIFRepresentationOfImage:ciImage format:kCIFormatRGBA8 colorSpace:linearColorSpace options:@{} ];
            NSData *jpegData = [context JPEGRepresentationOfImage:newImage colorSpace:deviceRGBColorSpace options:@{}];
            
            mynano__send_jpeg( push, (unsigned char *) jpegData.bytes, jpegData.length, w, h, destW, destH );
            
            filter = nil;
            jpegData = nil;
            ciImage = nil;
            newImage = nil;
            
        }
        
        // for turbojpeg method:
        //mynano__send_jpeg( push, (unsigned char *) jpegBuf, jpegSize, w, h, destW, destH );
        //tjFree( jpegBuf );
        //tjDestroy(handle);
        //CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
        
        /*CVPixelBufferRef buf2;
        CVPixelBufferCreateWithBytes(
                                     kCFAllocatorDefault,
                                     1334,
                                     750,
                                     CVPixelBufferGetPixelFormatType( pixelBuffer ),
                                     data,
                                     CVPixelBufferGetBytesPerRow( pixelBuffer ),
                                     NULL, NULL, NULL,
                                     &buf2
                                     );*/
                
        
        //CVPixelBufferRef pixelFormat = CVPixelBufferGetPixelFormatType( sourcePixelBuffer );
        //int ciImage = [CIImage sourcePixelBuffer ];
        
        
        // (id)kCIImageRepresentationPortraitEffectsMatteImage: semanticSegmentationMatteImage
        
        //NSLog( @"xxr ciimage");
        
        //size_t w = CVImageBufferGe(ciImage);
        //size_t h = CGImageGetHeight(ciImage);
        
        /*img = [[UIImage alloc] initWithCIImage: ciImage ];
        NSLog( @"xxr uiimage");
        int w = img.size.width * img.scale;
        int h = img.size.height * img.scale;
        
        NSData *jpegData = [UIImage dataUsingTurboJpegWithImage:img jpegQual:0.75];
        NSLog( @"xxr made jpeg");
        //mynano__send_jpeg( push, (unsigned char *) jpegData.bytes, jpegData.length, w, h, w, h );
        NSLog(@"xxr w: %d, h: %d, num:%ld jlen:%d", w, h, msg->frameNum, (int) jpegData.length );
        CFRelease( msg->sampleBuffer );*/
        
        CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
        CFRelease( msg->sampleBuffer );
    }
    else  {
        NSLog( @"xxr other");
    }
    
    ciImage = nil;
    img = nil;
}

@interface FramePasser : NSObject

-(FramePasser *)init;
-(void)dealloc;
-(void)myThread:(id)param;
@property CIContext *context;
@property int frameDestPort;
@property char *frameDestIp;
@property bool destSocketSetup;
@property nng_socket push;
@end

@implementation FramePasser

-(FramePasser *) init {
    self = [super init];
    _destSocketSetup = false;
    _frameDestIp = nil;
    _frameDestPort = 0;
    
    return self;
}

-(void) dealloc {
    if( _frameDestIp ) {
        free( _frameDestIp );
    }
}

-(void) setupFrameDest {
    //nng_socket push;
    int res = nng_push_open(&_push);
    char addr2[50];
    sprintf( addr2, "tcp://%s:%d", _frameDestIp, _frameDestPort );
    nng_setopt_int( _push, NNG_OPT_SENDBUF, 100000);
    int r10 = nng_dial( _push, addr2, NULL, 0);
    if( r10 != 0 ) {
        NSLog( @"xxr error connecting to %s : %d - %d", _frameDestIp, _frameDestPort, r10 );
    }
    _destSocketSetup = true;
}

- (void) handleData:(const char*)dataBytes withLength:(long)dataSize
{
    //const char* dataBytes = [data bytes];
    //size_t dataSize = [data length];
    ujsonin_init();
    int err;
    node_hash *root = parse( (char *) dataBytes, (int) dataSize, NULL, &err );
    jnode *port = node_hash__get( root, "port", 4 );
    jnode *ip = node_hash__get( root, "ip", 2 );
    if( port->type == 2 && ip->type == 2 ) {
        node_str *strOb = (node_str *) port;
        char buffer[20];
        sprintf(buffer,"%.*s",strOb->len,strOb->str);
        int portNum = atoi( buffer );
        
        node_str *ipOb = ( node_str * ) ip;
        sprintf(buffer,"%.*s",ipOb->len,ipOb->str);
        char *ipDup = strdup( buffer );
        
        /*fp_msg_port *msgt = fp_msg__new_port( portNum, ipDup );
        
        nng_msg *msg;
        nng_msg_alloc(&msg, 0);
        
        nng_msg_append( msg, msgt, sizeof( fp_msg_text ) );
        int r5 = nng_sendmsg( _pushF, msg, 0 );
        nng_msg_free( msg );*/
        _frameDestIp = ipDup;
        _frameDestPort = portNum;
        NSLog( @"xxr sending to %s : %d", _frameDestIp, _frameDestPort );
        [self setupFrameDest];
    }
    //jnode__dump( (jnode *) root, 0 );
    node_hash__delete( root );
    
}

/*- (void) readCompletionNotification:(NSNotification*)notification
{
    NSLog( @"xxr read handler" );
    NSFileHandle* handle = [notification object];
    NSDictionary* userInfo = [notification userInfo];

    NSData* readData = [userInfo valueForKey:NSFileHandleNotificationDataItem];
    NSNumber* error = [userInfo valueForKey:@"NSFileHandleError"];
    int errorCode = [error intValue];
    size_t cbRead = [readData length];
    NSLog( @"xxr config %s", readData.bytes );
    //LogMsg("readCompletionNotification: %li bytes, error: %u", cbRead, errorCode);
    
    if (errorCode == 0 && cbRead != 0) {
        [self handleData:readData];
        //[handle readInBackgroundAndNotify];
    } else {
        //LogMsg("readCompletionNotification: closing tty!");
        NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self name:NSFileHandleReadCompletionNotification object:handle];
        //LogMsg("readCompletionNotification: handle retain count is %u",
    }
}*/

-(void) myThread:(id)param {
    nng_socket pullF;
    
    CIContext *context = [CIContext contextWithOptions:@{ kCIContextWorkingFormat: @(kCIFormatRGBAh) }];
        
    int r1 = nng_pull_open( &pullF );
    printf( "r1 %d", r1 );
    const char *addr = "inproc://frames";
    nng_setopt_int( pullF, NNG_OPT_RECVBUF, 100000);
    nng_dial( pullF, addr, NULL, 0 );
    
    if( _frameDestPort != 0 ) {
        [self setupFrameDest];
    }
    
    // Read configuration if it exists
    /*NSString *documentsDirectory = [
        NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0
    ];*/
    NSFileManager *fileMan = [NSFileManager defaultManager];
    
    //NSURL *docDir = [[fileMan URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    //NSURL *confFile = [docDir URLByAppendingPathComponent:@"config.json"];
    NSURL *sharedUrl = [fileMan containerURLForSecurityApplicationGroupIdentifier:@"group.com.dryark.vidtest"];
    NSURL *confFile = [sharedUrl URLByAppendingPathComponent:@"config.json"];
    
    //NSString *fileName = [documentsDirectory stringByAppendingPathComponent:@"config.json"];

    char addr2[100];
    NSError *err;
    //if( [[NSFileManager defaultManager] fileExistsAtPath:fileName] ) {
    if ([confFile checkResourceIsReachableAndReturnError:&err] != NO) {
        NSLog( @"xxr config reachable" );
        //NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:fileName];
        //NSFileHandle *file = [NSFileHandle fileHandleForWritingToURL:confFile error:&err];
        
        /*NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:confFile error:&err];
        if( err != nil ) {
            NSLog( @"xxr config read err", err );
        }
        NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
        [nc
            addObserver:self
            selector:@selector(readCompletionNotification:)
            name:NSFileHandleReadCompletionNotification
            object:file
        ];
        
        [file readInBackgroundAndNotify];*/
        NSString *confPath = [confFile absoluteString];
        const char *cPath = [confPath UTF8String];
        NSLog( @"xxr config path %s", cPath );
        FILE *fh = fopen( &cPath[7], "r" );
        
        fseek(fh, 0, SEEK_END);
        long fsize = ftell(fh);
        fseek(fh, 0, SEEK_SET);  /* same as rewind(f); */

        char *string = malloc(fsize + 1);
        fread(string, 1, fsize, fh);
        
        NSLog( @"xxr config %s", string);
        [self handleData:string withLength:fsize];
        
        fclose( fh );
        
        string[fsize] = 0;
    } else {
        NSString *devName = [[UIDevice currentDevice] name];
        NSDictionary *devToPort = @{
            @"A":@7879,
            @"B":@7880,
            @"C":@7881,
            @"D":@7883
        };
        sprintf( addr2, "tcp://10.0.0.6:%ld", [devToPort[ devName ] integerValue] );
    }
    
    //NSLog( @"xxr sending to %s", addr2 );
    
    
    while( 1 ) {
        nng_msg *msg;
        int r2 = nng_recvmsg( pullF, &msg, 0 );
        NSLog( @"xxr r2 %d", r2 );
        if( msg != NULL  ) {
            if( nng_msg_len( msg ) > 0 ) {
                fp_msg_base *base = (fp_msg_base *) nng_msg_body( msg );
                if( base->type == 1 ) {
                    fp_msg_text *text = ( fp_msg_text * ) base;
                    NSLog(@"xxr Got message %s", text->text );
                    if( !strncmp( text->text, "done", 4 ) ) break;
                } else if( base->type == 2 ) {
                    fp_msg_buffer *buffer = ( fp_msg_buffer * ) base;
                    NSLog(@"xxr Received buffer" );
                    if( _destSocketSetup == true ) {
                        handle_buffer( buffer, _push, context );
                    } else {
                        discard_buffer( buffer );
                    }
                } else if( base->type == 3 ) {
                    fp_msg_port *port = ( fp_msg_port * ) base;
                    _frameDestIp = port->ip;
                    _frameDestPort = port->port;
                    NSLog( @"xxr sending to %s : %d", _frameDestIp, _frameDestPort );
                    [self setupFrameDest];
                }
                //free( base );
            }
            else {
                NSLog(@"xxr empty message");
            }
            nng_msg_free( msg );
        }
    }
    
    nng_close( _push );
    context = nil;
}

@end

@implementation SampleHandler

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *,NSObject *> *)setupInfo {
    // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
    int r4 = nng_push_open(&_pushF);
    NSLog( @"xxr r4 %d", r4 );
    const char *addr = "inproc://frames";
    nng_setopt_int(_pushF, NNG_OPT_SENDBUF, 100000);
    int r3 = nng_listen( _pushF, addr, NULL, 0 );
    NSLog( @"xxr r1 %d", r3 );
    
    _framePasserInst = [[FramePasser alloc] init];
    
    [NSThread detachNewThreadSelector:@selector(myThread:) toTarget:_framePasserInst withObject:nil];
}

- (void)broadcastPaused {
    // User has requested to pause the broadcast. Samples will stop being delivered.
}

- (void)broadcastResumed {
    // User has requested to resume the broadcast. Samples delivery will resume.
}

- (void)broadcastFinished {
    // User has requested to finish the broadcast.
    _started = 0;
    
    fp_msg_text *msgt = fp_msg__new_text( "done" );
    
    nng_msg *msg;
    nng_msg_alloc(&msg, 0);
    
    nng_msg_append( msg, msgt, sizeof( fp_msg_text ) );
    int r5 = nng_sendmsg( _pushF, msg, 0 );
    NSLog( @"xxr r5 %d", r5 );
    nng_msg_free( msg );
    
    nng_close( _pushF );
    
    _framePasserInst = nil;
        
    //nng_close(_push);
}

void mynano__send_jpeg( nng_socket push, unsigned char *data, unsigned long dataLen, int ow, int oh, int dw, int dh ) {
    
    char buffer[200];
    
    int jlen = snprintf( buffer, 200, "{\"ow\":%i,\"oh\":%i,\"dw\":%i,\"dh\":%i}", ow, oh, dw, dh );
    long unsigned int totlen = dataLen + jlen;
    char *both = malloc( totlen );
    memcpy( both, buffer, jlen );
    memcpy( &both[jlen], data, dataLen );
    //mynano__send( n, both, totlen );
    int res = nng_send( push, both, totlen, 0 );
    if( res != 0 ) {
        NSLog(@"xxr Send failed; res=%d", res );
    }
    else {
        NSLog(@"xxr Sent" );
    }
    
    free( both );
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    switch (sampleBufferType) {
        case RPSampleBufferTypeVideo:
            _frameNum++;
            if( ( _frameNum % 3 ) == 0 ) {
                @autoreleasepool {
                    CFRetain( sampleBuffer);
                    // Handle video sample buffer
                    
                    fp_msg_buffer *bmsg = fp_msg__new_buffer( sampleBuffer, _frameNum );
                    
                    nng_msg *msg;
                    nng_msg_alloc(&msg, 0);
                    int r8 = nng_msg_append( msg, bmsg, sizeof( fp_msg_buffer ) );
                    NSLog( @"xxr r8 %d", r8 );
                    int r6 = nng_sendmsg( _pushF, msg, 0 );
                    NSLog( @"xxr r6 %d", r6 );
                    //nng_msg_free( msg );
                  
                }
            }
            break;
        case RPSampleBufferTypeAudioApp:
            // Handle audio sample buffer for app audio
            break;
        case RPSampleBufferTypeAudioMic:
            // Handle audio sample buffer for mic audio
            break;
            
        default:
            break;
    }
}

@end
