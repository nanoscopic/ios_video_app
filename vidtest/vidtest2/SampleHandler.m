// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "SampleHandler.h"
//#include "TurboJPEG/libjpeg-turbo/include/turbojpeg.h"

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

uint32_t crc32( uint32_t crc, const char *buf, size_t len ) {
    static uint32_t table[256];
    static int have_table = 0;
    uint32_t rem;
    uint8_t octet;
    int i, j;
    const char *p, *q;
 
    /* This check is not thread safe; there is no mutex. */
    if (have_table == 0) {
        /* Calculate CRC table. */
        for (i = 0; i < 256; i++) {
            rem = i;  /* remainder from polynomial division */
            for (j = 0; j < 8; j++) {
                if (rem & 1) {
                    rem >>= 1;
                    rem ^= 0xedb88320;
                } else
                    rem >>= 1;
            }
            table[i] = rem;
        }
        have_table = 1;
    }
 
    crc = ~crc;
    q = buf + len;
    for (p = buf; p < q; p++) {
        octet = *p;  /* Cast to unsigned octet. */
        crc = (crc >> 8) ^ table[(crc & 0xff) ^ octet];
    }
    return ~crc;
}

@implementation ControlThread

-(ControlThread *) init:(int)controlPort framePasser:(FramePasser *)framePasser {
    self = [super init];
        
    _controlPort = controlPort;
    _framePasser = framePasser;
    
    return self;
}

-(void) dealloc {
}

-(void) entry:(id)param {
    /*int res = */nng_rep_open(&_rep);
    
    char addr2[50];
    sprintf( addr2, "tcp://127.0.0.1:%d", _controlPort );
    nng_setopt_int( _rep, NNG_OPT_SENDBUF, 100000);
    int listen_error = nng_listen( _rep, addr2, NULL, 0);
    if( listen_error != 0 ) {
        NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _controlPort, listen_error );
    }
    
    ujsonin_init();
    while( 1 ) {
        nng_msg *nmsg = NULL;
        nng_recvmsg( _rep, &nmsg, 0 );
        if( nmsg != NULL  ) {
            int msgLen = (int) nng_msg_len( nmsg );
            if( msgLen > 0 ) {
                char *msg = (char *) nng_msg_body( nmsg );
                
                char buffer[20];
                char *action;
                
                if( msg[0] == '{' ) {
                    int err;
                    node_hash *root = parse( msg, msgLen, NULL, &err );
                    jnode *actionJnode = node_hash__get( root, "action", 6 );
                    if( actionJnode && actionJnode->type == 2 ) {
                        node_str *actionStrNode = (node_str *) actionJnode;
                        action = buffer;
                        sprintf(buffer,"%.*s",actionStrNode->len,actionStrNode->str);
                    } else {
                        action = "";
                    }
                    node_hash__delete( root );
                } else {
                    fp_msg_base *base = ( fp_msg_base * ) msg;
                    if( base->type == 1 ) {
                        fp_msg_text *text = ( fp_msg_text * ) base;
                        action = text->text;
                    }
                }
                if( !strncmp( action, "done", 4 ) ) break;
                if( !strncmp( action, "start", 5 ) ) {
                    [_framePasser startSending];
                }
                if( !strncmp( action, "stop", 4 ) ) {
                    [_framePasser stopSending];
                }
                if( !strncmp( action, "oneframe", 8 ) ) {
                    [_framePasser oneFrame];
                }
            }
            else {
                NSLog(@"xxr empty message");
            }
            nng_msg_free( nmsg );
            
            fp_msg_text *resp = fp_msg__new_text( "ok" );
            
            nng_msg *respN;
            nng_msg_alloc(&respN, 0);
            
            nng_msg_append( respN, resp, sizeof( fp_msg_text ) );
            nng_sendmsg( _rep, respN, 0 );
            free( resp );
            nng_msg_free( respN );
        }
    }
    
    nng_close( _rep );
}

@end

@implementation FramePasser

-(FramePasser *) init:(int)inputPort outputIp:(char*)outputIp outputPort:(int)outputPort {
    self = [super init];
    _outputIp = outputIp;
    _outputPort = outputPort;
    _inputPort = inputPort;
    _sending = false;
    _crc = malloc( sizeof( uint32_t ) );
    *_crc = 0;
    _crc2 = malloc( sizeof( uint32_t ) );
    *_crc2 = 0;
    _forceFrame1 = 0;
    _forceFrame2 = malloc( sizeof( uint16_t ) );
    *_forceFrame2 = 0;
    _w = 0;
    _h = 0;
    return self;
}

-(void) startSending {
    _sending = true;
    *_crc = 0;
    *_crc2 = 0;
}

-(void) stopSending {
    _sending = false;
}

-(void) oneFrame {
    _forceFrame1++;
}

-(void) dealloc {
    if( _outputIp ) {
        free( _outputIp );
    }
    free( _crc );
    free( _forceFrame2 );
}

-(void) setupFrameDest {
    /*int res = */nng_push_open(&_push);
    
    if( _outputPort != 0 ) {
        char addr2[50];
        sprintf( addr2, "tcp://%s:%d", _outputIp, _outputPort );
        nng_setopt_int( _push, NNG_OPT_SENDBUF, 100000);
        int r10 = nng_dial( _push, addr2, NULL, 0);
        if( r10 != 0 ) {
            NSLog( @"xxr error connecting to %s : %d - %d", _outputIp, _outputPort, r10 );
        }
        _sending = true;
    } else {
        char addr2[50];
        sprintf( addr2, "tcp://127.0.0.1:%d", _inputPort );
        nng_setopt_int( _push, NNG_OPT_SENDBUF, 100000);
        int r10 = nng_listen( _push, addr2, NULL, 0);
        if( r10 != 0 ) {
            NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _inputPort, r10 );
        }
    }
}

-(void) handle_buffer: (fp_msg_buffer *) msg wContext:(CIContext *)context {
    CIImage *ciImage;
    
    CVImageBufferRef sourcePixelBuffer = CMSampleBufferGetImageBuffer( msg->sampleBuffer );
    CFTypeID imageType = CFGetTypeID(sourcePixelBuffer);

    if (imageType == CVPixelBufferGetTypeID()) {
        CVPixelBufferRef pixelBuffer;
        @autoreleasepool {
                
            pixelBuffer = ( CVPixelBufferRef ) sourcePixelBuffer;
            CVPixelBufferLockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
            
            //void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
            
            if( !_w ) {
                _w = (int) CVPixelBufferGetWidth( pixelBuffer );
                _h = (int) CVPixelBufferGetHeight( pixelBuffer );
                
                _destH = 1000;
                _scale = (float) _destH / (float) _h;
                _destW = (size_t) ( (float) _scale * (float) _w );
                
                _ciFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
                [_ciFilter setValue:[[NSNumber alloc] initWithFloat:_scale] forKey:@"inputScale"];
                [_ciFilter setValue:@1.0 forKey:@"inputAspectRatio"];
            }
            
            uint32_t newCrc = 0;
            //NSLog( @"xxr test8" );
            size_t planeCount = 1;//CVPixelBufferGetPlaneCount( pixelBuffer );
            //NSLog( @"xxs planes:%d", planeCount );
            for( int i=0;i<planeCount;i++ ) {
                size_t bytes = CVPixelBufferGetBytesPerRowOfPlane( pixelBuffer, i );
                void *planeBase = CVPixelBufferGetBaseAddressOfPlane( pixelBuffer, i );
                size_t planeH = CVPixelBufferGetHeightOfPlane( pixelBuffer, i );
                //size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
                size_t barSize = 50*bytes;
                newCrc = crc32( newCrc, (const char *) planeBase + barSize, bytes*planeH - barSize );
            }
            
            bool force = false;
            
            if( _forceFrame1 != *_forceFrame2 ) {
                *_forceFrame2 = _forceFrame1;
                force = true;
            }
            
            if( force || ( *_crc != newCrc && *_crc2 != newCrc ) ) {
                *_crc2 = *_crc;
                *_crc = newCrc;
                ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer];
                
                //CGColorSpaceRef linearColorSpace = CGColorSpaceCreateWithName( kCGColorSpaceLinearSRGB );
                CGColorSpaceRef deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB();
                                
                [_ciFilter setValue:ciImage forKey:@"inputImage"];
                CIImage *newImage = _ciFilter.outputImage;
                
                //NSData *heifData = [context HEIFRepresentationOfImage:ciImage format:kCIFormatRGBA8 colorSpace:linearColorSpace options:@{} ];
                NSData *jpegData = [context JPEGRepresentationOfImage:newImage colorSpace:deviceRGBColorSpace options:@{}];
                
                mynano__send_jpeg( _push, (unsigned char *) jpegData.bytes, jpegData.length, _w, _h, (int) _destW, (int) _destH );
                
                //filter = nil;
                jpegData = nil;
                ciImage = nil;
                newImage = nil;
            }
        }
        
        CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
        CFRelease( msg->sampleBuffer );
    }
    else  {
        NSLog( @"xxr other");
    }
    
    ciImage = nil;
}

-(void) noframes {
    mynano__send_text( _push, "noframes" );
}

-(void) entry:(id)param {
    nng_socket pullF;
    
    CIContext *context = [CIContext contextWithOptions:@{ kCIContextWorkingFormat: @(kCIFormatRGBAh) }];
        
    int r1 = nng_pull_open( &pullF );
    printf( "r1 %d", r1 );
    const char *addr = "inproc://frames";
    nng_setopt_int( pullF, NNG_OPT_RECVBUF, 100000);
    
    // If we don't receive any images for 100ms; it is likely that a system
    // dialog box is being shown.
    nng_setopt_int( pullF, NNG_OPT_RECVTIMEO, 100);
    
    nng_dial( pullF, addr, NULL, 0 );
    
    [self setupFrameDest];
    
    bool noFrames = false;
    while( 1 ) {
        nng_msg *msg = NULL;
        int recv_err = nng_recvmsg( pullF, &msg, 0 );
        if( recv_err == NNG_ETIMEDOUT ) {
            if( !noFrames ) {
                noFrames = true;
                [self noframes];
            }
        }
        else if( msg != NULL  ) {
            if( nng_msg_len( msg ) > 0 ) {
                fp_msg_base *base = (fp_msg_base *) nng_msg_body( msg );
                if( base->type == 1 ) {
                    fp_msg_text *text = ( fp_msg_text * ) base;
                    NSLog(@"xxr Got message %s", text->text );
                    if( !strncmp( text->text, "done", 4 ) ) break;
                } else if( base->type == 2 ) {
                    fp_msg_buffer *buffer = ( fp_msg_buffer * ) base;
                    if( noFrames ) noFrames = false;
                    if( _sending ) [self handle_buffer:buffer wContext:context];
                    else discard_buffer( buffer );
                } else if( base->type == 3 ) {
                    //fp_msg_port *port = ( fp_msg_port * ) base;
                    //_frameDestIp = port->ip;
                    //_frameDestPort = port->port;
                    //NSLog( @"xxr sending to %s : %d", _frameDestIp, _frameDestPort );
                    [self setupFrameDest];
                }
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
    nng_push_open(&_pushF);
    const char *addr = "inproc://frames";
    nng_setopt_int(_pushF, NNG_OPT_SENDBUF, 100000);
    nng_listen( _pushF, addr, NULL, 0 );
    
    [self readConfig];
    
    _framePasserInst = [[FramePasser alloc] init:_inputPort outputIp:_outputIp outputPort:_outputPort];
    
    [NSThread detachNewThreadSelector:@selector(entry:) toTarget:_framePasserInst withObject:nil];
    
    if( _controlPort ) {
        _controlThreadInst = [[ControlThread alloc] init:_controlPort framePasser:_framePasserInst];
        [NSThread detachNewThreadSelector:@selector(entry:) toTarget:_controlThreadInst withObject:nil];
    }
    
    _msgBuffer.type = 2;
}

- (void)readConfig {
    // Read configuration if it exists
    /*NSFileManager *fileMan = [NSFileManager defaultManager];
    
    NSURL *sharedUrl = [fileMan containerURLForSecurityApplicationGroupIdentifier:@"group.com.dryark.vidtest"];
    NSURL *confFile = [sharedUrl URLByAppendingPathComponent:@"config.json"];
    
    NSError *err;
    if ([confFile checkResourceIsReachableAndReturnError:&err] != NO) {
        NSLog( @"xxr config reachable" );
        
        NSString *confPath = [confFile absoluteString];
        const char *cPath = [confPath UTF8String];
        NSLog( @"xxr config path %s", cPath );
        FILE *fh = fopen( &cPath[7], "r" );
        
        fseek(fh, 0, SEEK_END);
        long fsize = ftell(fh);
        fseek(fh, 0, SEEK_SET);  // same as rewind(f);

        char *string = malloc(fsize + 1);
        fread(string, 1, fsize, fh);
        string[fsize] = 0;
        
        NSLog( @"xxr config %s", string);
        [self handleConfig:string withLength:fsize];
        
        fclose( fh );
    } else {*/
        _outputPort = 0;
        _outputIp = nil;
        _controlPort = 8351;
        _inputPort = 8352;
    //}
}

- (void) handleConfig:(const char*)dataBytes withLength:(long)dataSize
{
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
        
        _outputIp = ipDup;
        _outputPort = portNum;
        NSLog( @"xxr sending to %s : %d", _outputIp, _outputPort );
    }
    node_hash__delete( root );
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
    free( msgt );
    nng_sendmsg( _pushF, msg, 0 );
    nng_msg_free( msg );
    
    nng_close( _pushF );
    
    _framePasserInst = nil;
    
    // stop the control thread
    
    nng_socket reqC;
    
    // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
    nng_req_open(&reqC);
    
    char addr2[50];
    sprintf( addr2, "tcp://127.0.0.1:%d", _controlPort );
    
    nng_setopt_int(reqC, NNG_OPT_SENDBUF, 1000);
    nng_dial( reqC, addr2, NULL, 0 );
    
    fp_msg_text *msgt2 = fp_msg__new_text( "done" );
    
    nng_msg *msg2;
    nng_msg_alloc(&msg2, 0);
    
    nng_msg_append( msg2, msgt2, sizeof( fp_msg_text ) );
    nng_sendmsg( reqC, msg2, 0 );
    free( msgt2 );
    nng_msg_free( msg2 );
    
    nng_close( reqC );
    
    _controlThreadInst = nil;
}

void mynano__send_text( nng_socket push, const char *text ) {
    char buffer[50];
    sprintf( buffer, "{msg:\"%s\"}\n", text );
    nng_send( push, (void *) buffer, strlen( buffer ), 0 );
}

void mynano__send_jpeg( nng_socket push, unsigned char *data, unsigned long dataLen, int ow, int oh, int dw, int dh ) {
    char buffer[200];
    
    int jlen = snprintf( buffer, 200, "{\"ow\":%i,\"oh\":%i,\"dw\":%i,\"dh\":%i}", ow, oh, dw, dh );
    long unsigned int totlen = dataLen + jlen;
    char *both = malloc( totlen );
    memcpy( both, buffer, jlen );
    memcpy( &both[jlen], data, dataLen );
    int res = nng_send( push, both, totlen, 0 );
    if( res != 0 ) {
        NSLog(@"xxr Send failed; res=%d", res );
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
                    
                    //fp_msg_buffer *bmsg = fp_msg__new_buffer( sampleBuffer, _frameNum );
                    _msgBuffer.sampleBuffer = sampleBuffer;
                    _msgBuffer.frameNum = _frameNum;
                    nng_msg *msg;
                    nng_msg_alloc(&msg, 0);
                    nng_msg_append( msg, &_msgBuffer, sizeof( fp_msg_buffer ) );
                    nng_sendmsg( _pushF, msg, 0 );
                    //free( bmsg );
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
