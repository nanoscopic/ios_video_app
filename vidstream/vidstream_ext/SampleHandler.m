// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import "SampleHandler.h"

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
 
    if( have_table == 0 ) {
        for (i = 0; i < 256; i++) {
            rem = i;  /* remainder from polynomial division */
            for (j = 0; j < 8; j++) {
                if (rem & 1) {
                    rem >>= 1;
                    rem ^= 0xedb88320;
                }
                else rem >>= 1;
            }
            table[i] = rem;
        }
        have_table = 1;
    }
 
    crc = ~crc;
    q = buf + len;
    for (p = buf; p < q; p++) {
        octet = *p; /* Cast to unsigned octet. */
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
    nng_rep_open(&_rep);
    
    char addr2[50];
    sprintf( addr2, "tcp://127.0.0.1:%d", _controlPort );
    nng_setopt_int( _rep, NNG_OPT_SENDBUF, 100000);
    nng_setopt_int( _rep, NNG_OPT_RECVTIMEO, 100);
    int listen_error = nng_listen( _rep, addr2, NULL, 0);
    if( listen_error != 0 ) {
        NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _controlPort, listen_error );
    }
    
    nng_pull_open(&_pull);
    char addr3[50];
    sprintf( addr3, "inproc://control" );
    nng_listen( _pull, addr3, NULL, 0);
    
    ujsonin_init();
    while( 1 ) {
        nng_msg *nmsg = NULL;
        int err = nng_recvmsg( _rep, &nmsg, 0 );
        if( err ) {
            int err2 = nng_recvmsg( _pull, &nmsg, NNG_FLAG_NONBLOCK );
            if( !err2 ) break;
            continue;
        }
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
                    }
                    else {
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
                if( !strncmp( action, "done", 4 ) ) {
                    nng_msg_free( nmsg );
                    break;
                }
                if( !strncmp( action, "start", 5 ) ) [_framePasser startSending];
                if( !strncmp( action, "stop", 4 ) ) [_framePasser stopSending];
                if( !strncmp( action, "oneframe", 8 ) ) [_framePasser oneFrame];
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
    nng_close( _pull );
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
    _frameCount = 0;
    _lastFrameCount = 0;
    _lastPlaneBase = NULL;
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
    nng_push_open(&_push);
    
    if( _outputPort != 0 ) {
        char addr2[50];
        sprintf( addr2, "tcp://%s:%d", _outputIp, _outputPort );
        nng_setopt_int( _push, NNG_OPT_SENDBUF, 100000);
        nng_setopt_int( _push, NNG_OPT_SENDTIMEO, 500);
        int r10 = nng_dial( _push, addr2, NULL, 0);
        if( r10 != 0 ) {
            NSLog( @"xxr error connecting to %s : %d - %d", _outputIp, _outputPort, r10 );
        }
        _sending = true;
    } else {
        char addr2[50];
        sprintf( addr2, "tcp://127.0.0.1:%d", _inputPort );
        nng_setopt_int( _push, NNG_OPT_SENDBUF, 100000);
        nng_setopt_int( _push, NNG_OPT_SENDTIMEO, 500);
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
            
            bool force = false;
            
            
            /*uint32_t newCrc = 0;
            size_t planeCount = 1;//CVPixelBufferGetPlaneCount( pixelBuffer );
            for( int i=0;i<planeCount;i++ ) {
                size_t bytes = CVPixelBufferGetBytesPerRowOfPlane( pixelBuffer, i );
                void *planeBase = CVPixelBufferGetBaseAddressOfPlane( pixelBuffer, i );
                size_t planeH = CVPixelBufferGetHeightOfPlane( pixelBuffer, i );
                size_t barSize = 50*bytes;
                newCrc = crc32( newCrc, (const char *) planeBase + barSize, bytes*planeH - barSize );
            }
            
            if( _forceFrame1 != *_forceFrame2 ) {
                *_forceFrame2 = _forceFrame1;
                force = true;
            }*/
            char *planeBase = NULL;
            size_t planeSize = 0;
            
            uint32_t diff = 0;
            if( _lastPlaneBase ) {
                size_t planeCount = 1;//CVPixelBufferGetPlaneCount( pixelBuffer );
                for( int i=0;i<planeCount;i++ ) {
                    size_t bytes = CVPixelBufferGetBytesPerRowOfPlane( pixelBuffer, i );
                    planeBase = CVPixelBufferGetBaseAddressOfPlane( pixelBuffer, i );
                    //char *lastPlaneBase = CVPixelBufferGetBaseAddressOfPlane( _lastPixelBuffer, i );
                    size_t planeH = CVPixelBufferGetHeightOfPlane( pixelBuffer, i );
                    size_t barSize = 50*bytes;
                    //newCrc = crc32( newCrc, (const char *) planeBase + barSize, bytes*planeH - barSize );
                    planeSize = bytes * planeH;
                    for( int i=0;i<planeSize; i++ ) {
                        int dif = planeBase[i]-_lastPlaneBase[i];
                        if( dif < 0 ) dif = -dif;
                        diff += dif;
                    }
                }
            }
            else {
                size_t planeCount = 1;//CVPixelBufferGetPlaneCount( pixelBuffer );
                for( int i=0;i<planeCount;i++ ) {
                    size_t bytes = CVPixelBufferGetBytesPerRowOfPlane( pixelBuffer, i );
                    planeBase = CVPixelBufferGetBaseAddressOfPlane( pixelBuffer, i );
                    size_t planeH = CVPixelBufferGetHeightOfPlane( pixelBuffer, i );
                    planeSize = bytes * planeH;
                }
            }
            
            if( diff > 0x9000 ) {
                //*_forceFrame2 = _forceFrame1;
                force = true;
            }

            _frameCount++;
            double frameDif = _frameCount - _lastFrameCount;
            
            if( ( frameDif > 20 ) || force ) { //}|| ( *_crc != newCrc && *_crc2 != newCrc ) ) {
                //if( _lastPlaneBase ) {
                    //CVPixelBufferUnlockBaseAddress( _lastPixelBuffer, kCVPixelBufferLock_ReadOnly );
                    //CFRelease( _lastMsg->sampleBuffer );
                //}
                //_lastMsg = msg;
                //_lastPixelBuffer = pixelBuffer;
                if( !_lastPlaneBase ) _lastPlaneBase = malloc( planeSize );
                memcpy( _lastPlaneBase, planeBase, planeSize );
                
                _lastFrameCount = _frameCount;
                int cause = 0;
                if( frameDif > 20 ) cause = 1;
                if( force ) cause = 2;
                
                //*_crc2 = *_crc;
                //*_crc = newCrc;
                ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer];
                
                //CGColorSpaceRef linearColorSpace = CGColorSpaceCreateWithName( kCGColorSpaceLinearSRGB );
                CGColorSpaceRef deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB();
                                
                [_ciFilter setValue:ciImage forKey:@"inputImage"];
                CIImage *newImage = _ciFilter.outputImage;
                
                //NSData *heifData = [context HEIFRepresentationOfImage:ciImage format:kCIFormatRGBA8 colorSpace:linearColorSpace options:@{} ];
                NSData *jpegData = [context JPEGRepresentationOfImage:newImage colorSpace:deviceRGBColorSpace options:@{}];
                
                mynano__send_jpeg( _push,
                  (unsigned char *) jpegData.bytes, jpegData.length, _w, _h, (int) _destW, (int) _destH, cause, diff );
                jpegData = nil;
                ciImage = nil;
                newImage = nil;
            } else {
                //CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
                //CFRelease( msg->sampleBuffer );
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
    
    // If we don't receive any images for 100ms; then we are in trouble...
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
                    if( !strncmp( text->text, "done", 4 ) ) {
                        nng_msg_free( msg );
                        break;
                    }
                } else if( base->type == 2 ) {
                    fp_msg_buffer *buffer = ( fp_msg_buffer * ) base;
                    if( noFrames ) noFrames = false;
                    if( _sending ) [self handle_buffer:buffer wContext:context];
                    else discard_buffer( buffer );
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
    nng_push_open(&_pushF);
    const char *addr = "inproc://frames";
    nng_setopt_int(_pushF, NNG_OPT_SENDBUF, 100000);
    nng_listen( _pushF, addr, NULL, 0 );
    
    [self readConfig];
    
    _framePasserInst = [[FramePasser alloc] init:_inputPort outputIp:_outputIp outputPort:_outputPort];
    
    //_frameThread = [[NSThread alloc] initWithTarget:_framePasserInst selector:@selector(entry:) object:nil];
    [NSThread detachNewThreadSelector:@selector(entry:) toTarget:_framePasserInst withObject:nil];
    
    if( _controlPort ) {
        _controlThreadInst = [[ControlThread alloc] init:_controlPort framePasser:_framePasserInst];
        [NSThread detachNewThreadSelector:@selector(entry:) toTarget:_controlThreadInst withObject:nil];
        //_controlThread = [[NSThread alloc] initWithTarget:_controlThreadInst selector:@selector(entry:) object:nil];
    }
    
    _msgBuffer.type = 2;
    
    
    nng_push_open(&_push);
    char addr2[50];
    sprintf( addr2, "inproc://control" );
    nng_setopt_int(_push, NNG_OPT_SENDBUF, 1000);
    nng_dial( _push, addr2, NULL, 0 );
}

- (void)readConfig {
    _outputPort = 0;
    _outputIp = nil;
    _controlPort = 8351;
    _inputPort = 8352;
}

- (void)broadcastPaused {
}

- (void)broadcastResumed {
}

- (void)broadcastFinished {
    _started = 0;
    
    //[_frameThread cancel];
    //[_controlThread cancel];
    fp_msg_text *msgt = fp_msg__new_text( "done" );
    
    nng_msg *msg;
    nng_msg_alloc(&msg, 0);
    nng_msg_append( msg, msgt, sizeof( fp_msg_text ) );
    free( msgt );
    nng_sendmsg( _pushF, msg, 0 );
    //nng_msg_free( msg );
    
    _framePasserInst = nil;
    
    // stop the control thread
    
    fp_msg_text *msgt2 = fp_msg__new_text( "done" );
    
    nng_msg *msg2;
    nng_msg_alloc(&msg2, 0);
    
    nng_msg_append( msg2, msgt2, sizeof( fp_msg_text ) );
    nng_sendmsg( _push, msg2, 0 );
    free( msgt2 );
    //nng_msg_free( msg2 );
    
    usleep(100);
    
    nng_close( _pushF );
    nng_close( _push );
    
    _controlThreadInst = nil;
}

void mynano__send_text( nng_socket push, const char *text ) {
    char buffer[50];
    sprintf( buffer, "{msg:\"%s\"}\n", text );
    nng_send( push, (void *) buffer, strlen( buffer ), 0 );
}

void mynano__send_jpeg( nng_socket push, unsigned char *data, unsigned long dataLen, int ow, int oh, int dw, int dh, int cause, uint32_t crc ) {
    char buffer[300];
    
    int jlen = snprintf( buffer, 300, "{\"ow\":%i,\"oh\":%i,\"dw\":%i,\"dh\":%i,\"c\":%i,\"crc\":\"%x\"}", ow, oh, dw, dh, cause, crc );
    
    nng_msg *msg;
    nng_msg_alloc( &msg, 0 );
    nng_msg_append( msg, buffer, jlen );
    nng_msg_append( msg, data, dataLen );
    
    int res = nng_sendmsg( push, msg, 0 );
    if( res != 0 ) NSLog(@"xxr Send failed; res=%d", res );
    
    //nng_msg_free( msg );
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    switch (sampleBufferType) {
        case RPSampleBufferTypeVideo:
            _frameNum++;
            if( ( _frameNum % 3 ) == 0 ) {
                @autoreleasepool {
                    CFRetain( sampleBuffer);
                    
                    _msgBuffer.sampleBuffer = sampleBuffer;
                    _msgBuffer.frameNum = _frameNum;
                    nng_msg *msg;
                    nng_msg_alloc(&msg, 0);
                    nng_msg_append( msg, &_msgBuffer, sizeof( fp_msg_buffer ) );
                    nng_sendmsg( _pushF, msg, 0 );
                }
            }
            break;
        case RPSampleBufferTypeAudioApp: break;
        case RPSampleBufferTypeAudioMic: break;
        default:                         break;
    }
}

@end
