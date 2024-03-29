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

-(ControlThread *) init:(int)controlPort logPort:(int)logPort framePasser:(FramePasser *)framePasser {
    self = [super init];
        
    _controlPort = controlPort;
    _logPort = logPort;
    _framePasser = framePasser;
    _logSetup = false;
    
    return self;
}

-(void) dealloc {
}

-(void) log:(char *)str {
    if( _logSetup ) return;
    nng_msg *msg;
    nng_msg_alloc(&msg, 0);
    nng_msg_append( msg, str, (int) strlen(str) );
    int failed = nng_sendmsg( _log, msg, 0 );
    if( failed ) nng_msg_free( msg );
}

-(void) entry:(id)param {
    nng_rep_open(&_rep);
    
    char addr2[50];
    sprintf( addr2, "tcp://127.0.0.1:%d", _controlPort );
    nng_setopt_int( _rep, NNG_OPT_SENDBUF, 200000);
    //nng_setopt_int( _rep, NNG_OPT_RECVTIMEO, 100);
    int listen_error = nng_listen( _rep, addr2, NULL, 0);
    if( listen_error != 0 ) {
        //NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _controlPort, listen_error );
    }
    
    /*nng_push_open( &_log );
    char addrlog[50];
    sprintf( addrlog, "tcp://127.0.0.1:%d", _logPort );
    int r10 = nng_listen( _log, addrlog, NULL, 0);
    if( r10 != 0 ) {
        //NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _logPort, r10 );
    }
    _logSetup=true;*/
    
    nng_pull_open(&_pull);
    char addr3[50];
    sprintf( addr3, "inproc://control" );
    nng_listen( _pull, addr3, NULL, 0);
    
    ujsonin_init();
    int sending = 0;
    while( 1 ) {
        nng_msg *nmsg = NULL;
        [self log:"control - waiting for message"];
        int err = nng_recvmsg( _rep, &nmsg, 0 );
        if( err ) {
            usleep( 20 );
            continue;
        }
        [self log:"control - got message"];
        if( nmsg != NULL  ) {
            int msgLen = (int) nng_msg_len( nmsg );
            if( msgLen > 0 ) {
                char *msg = (char *) nng_msg_body( nmsg );
                
                //char buffer[20];
                char *action = "";
                
                node_hash *root = NULL;
                if( msg[0] == '{' ) {
                    //NSLog( @"xxr json msg : %.*s", msgLen, msg );
                    //os_log( OS_LOG_DEFAULT, "xxr Got message %.*s", msgLen, msg );
                    char buffer[40];
                    sprintf( buffer, "Got msg %.*s", msgLen, msg );
                    [self log:buffer];
                    
                    int err;
                    root = parse( msg, msgLen, NULL, &err );
                    jnode *actionJnode = node_hash__get( root, "action", 6 );
                    if( actionJnode && actionJnode->type == 2 ) {
                        node_str *actionStrNode = (node_str *) actionJnode;
                        action = buffer;
                        sprintf(buffer,"%.*s",(int) actionStrNode->len,actionStrNode->str);
                    }
                    
                } else {
                    [self log:"unknown to control channel"];
                    /*fp_msg_base *base = ( fp_msg_base * ) msg;
                    if( base->type == 1 ) {
                        fp_msg_text *text = ( fp_msg_text * ) base;
                        action = text->text;
                    }*/
                }
                
                unsigned long len = strlen( action );
                
                if( len == 3 && !strncmp( action, "log", 3 ) ) {
                    jnode *logNode = node_hash__get( root, "log", 3 );
                    if( logNode && logNode->type == 2 ) {
                        node_str *logStrNode = (node_str *) logNode;
                        char buffer[2000];
                        sprintf( buffer, "%.*s",(int) logStrNode->len,logStrNode->str);
                        [self log:buffer];
                    }
                }
                if( len == 4 && !strncmp( action, "done", 4 ) ) {
                    nng_msg_free( nmsg );
                    if( root ) node_hash__delete( root );
                    break;
                }
                if( len == 5 && !strncmp( action, "start",    5 ) ) {
                    if( !sending ) {
                        sending = 1;
                        [_framePasser startSending];
                    } else {
                        [self log:"duplicate start"];
                    }
                }
                if( len == 4 && !strncmp( action, "stop",     4 ) ) {
                    if( sending ) {
                        sending = 0;
                        [_framePasser stopSending];
                    } else {
                        [self log:"duplicate stop"];
                    }
                }
                if( len == 8 && !strncmp( action, "oneframe", 8 ) ) [_framePasser oneFrame];
                
                if( root ) node_hash__delete( root );
            }
            else {
                //NSLog(@"xxr empty message");
                [self log:"empty message"];
            }
            nng_msg_free( nmsg );
            
            fp_msg_text *resp = fp_msg__new_text( "ok" );
            
            nng_msg *respN;
            nng_msg_alloc(&respN, 0);
            
            nng_msg_append( respN, resp, sizeof( fp_msg_text ) );
            int failed = nng_sendmsg( _rep, respN, 0 );
            free( resp );
            if( failed ) nng_msg_free( respN );
        }
    }
    
    nng_close( _rep );
    nng_close( _pull );
}

@end

@implementation FramePasser

-(FramePasser *) init:(int)inputPort outputIp:(char*)outputIp outputPort:(int)outputPort logPort:(int)logPort {
    self = [super init];
    _outputIp = outputIp;
    _outputPort = outputPort;
    _inputPort = inputPort;
    _logPort = logPort;
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
    _context = NULL;
    _colorSpace = NULL;
    return self;
}

-(void) log:(char *)str {
    nng_msg *msg;
    nng_msg_alloc(&msg, 0);
    nng_msg_append( msg, str, (int) strlen(str) );
    int failed = nng_sendmsg( _log, msg, 0 );
    if( failed ) nng_msg_free( msg );
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
        nng_setopt_int( _push, NNG_OPT_SENDBUF, 200000);
        //nng_setopt_int( _push, NNG_OPT_SENDTIMEO, 500);
        int r10 = nng_dial( _push, addr2, NULL, 0);
        if( r10 != 0 ) {
            //NSLog( @"xxr error connecting to %s : %d - %d", _outputIp, _outputPort, r10 );
        }
        _sending = true;
    } else {
        char addr2[50];
        sprintf( addr2, "tcp://127.0.0.1:%d", _inputPort );
        nng_setopt_int( _push, NNG_OPT_SENDBUF, 200000);
        //nng_setopt_int( _push, NNG_OPT_SENDTIMEO, 500);
        int r10 = nng_listen( _push, addr2, NULL, 0);
        if( r10 != 0 ) {
            //NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _inputPort, r10 );
        }
    }
}

-(void) handle_buffer: (fp_msg_buffer *) msg {
    CIImage *ciImage;
    
    CVImageBufferRef sourcePixelBuffer = CMSampleBufferGetImageBuffer( msg->sampleBuffer );
    CFTypeID imageType = CFGetTypeID(sourcePixelBuffer);

    bool released = false;
    
    if (imageType == CVPixelBufferGetTypeID()) {
        CVPixelBufferRef pixelBuffer;
        @autoreleasepool {
                
            pixelBuffer = ( CVPixelBufferRef ) sourcePixelBuffer;
            CVPixelBufferLockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
            
            if( !_w ) {
                _w = (int) CVPixelBufferGetWidth( pixelBuffer );
                _h = (int) CVPixelBufferGetHeight( pixelBuffer );
                
                _destH = 848;
                _scale = (float) _destH / (float) _h;
                _destW = (size_t) ( (float) _scale * (float) _w );
                
                _ciFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
                [_ciFilter setValue:[[NSNumber alloc] initWithFloat:_scale] forKey:@"inputScale"];
                [_ciFilter setValue:@1.0 forKey:@"inputAspectRatio"];
                
                _resizeTransform = CGAffineTransformMakeScale(_scale, _scale);
                
                _context = [CIContext contextWithOptions:@{
                    kCIContextWorkingFormat: @(kCIFormatRGBAf),
                    kCIContextUseSoftwareRenderer: @NO
                }];
                OSType type = CVPixelBufferGetPixelFormatType( pixelBuffer );
                switch (type) {
                    case kCVPixelFormatType_32BGRA:
                        [self log:"pixel buffer type: 32BGRA"]; break;
                    case kCVPixelFormatType_32RGBA:
                        [self log:"pixel buffer type: 32RGBA"]; break;
                    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                        [self log:"pixel buffer type: 420"]; break;
                    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: // nv12
                        [self log:"pixel buffer type: 420full"]; break;
                    default:
                        [self log:"pixel buffer type: unknown"]; break;
                }
            }
            
            bool force = false;
            
            char *planeBase = NULL;
            size_t planeSize = 0;
            
            //size_t planeCount = CVPixelBufferGetPlaneCount( pixelBuffer );
            
            uint32_t diff = 0;
            if( _lastPlaneBase ) {
                for( int i=1;i<2;i++ ) { //planeCount;i++ ) {
                    size_t bytes = CVPixelBufferGetBytesPerRowOfPlane( pixelBuffer, i );
                    planeBase = CVPixelBufferGetBaseAddressOfPlane( pixelBuffer, i );
                    size_t planeH = CVPixelBufferGetHeightOfPlane( pixelBuffer, i );
                    //size_t barSize = 50*bytes;
                    planeSize = bytes * planeH;
                    for( int j=0;j<planeSize; j++ ) {
                        int dif = planeBase[j]-_lastPlaneBase[j];
                        if( dif < 0 ) dif = -dif;
                        diff += dif;
                        if( diff > 0x3000 ) break;
                    }
                    if( diff > 0x3000 ) break;
                }
            }
            else {
                //size_t planeCount = 2;//CVPixelBufferGetPlaneCount( pixelBuffer );
                for( int i=1;i<2;i++ ) {
                    size_t bytes = CVPixelBufferGetBytesPerRowOfPlane( pixelBuffer, i );
                    planeBase = CVPixelBufferGetBaseAddressOfPlane( pixelBuffer, i );
                    size_t planeH = CVPixelBufferGetHeightOfPlane( pixelBuffer, i );
                    planeSize = bytes * planeH;
                }
            }
            
            if( diff > 0x3000 ) {
                force = true;
            }

            _frameCount++;
            double frameDif = _frameCount - _lastFrameCount;
            
            if( ( frameDif > 20 ) || force ) {
                if( !_lastPlaneBase ) {
                    _lastPlaneBase = malloc( planeSize );
                    //[self log:"allocated lastplanebase"];
                }
                memcpy( _lastPlaneBase, planeBase, planeSize );
                //[self log:"copied to lastplanebase"];
                
                _lastFrameCount = _frameCount;
                int cause = 0;
                if( frameDif > 20 ) cause = 1;
                if( force ) cause = 2;
                
                // Can add options; doesn't seem to change anything
                //NSDictionary *opt =  @{ (id)kCVPixelBufferPixelFormatTypeKey :
                //                      @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) };
                //ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer options:opt];
                
                ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
                
                // Use this for terrible nearest neighbor resize. Doesn't improve performance much...
                // ciImage = [ciImage imageBySamplingNearest];
                
                ciImage = [ciImage imageByApplyingTransform:_resizeTransform];
                
                // Try to free up some memory before conversion to jpeg
                //CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
                //CFRelease( msg->sampleBuffer );
                //released = true;
                
                // Could be used to encode to useless HEIF format that cannot be decoded anywhere.
                // NSData *heifData = [context HEIFRepresentationOfImage:ciImage format:kCIFormatRGBA8 colorSpace:linearColorSpace options:@{} ];
                
                if( !_colorSpace ) _colorSpace = ciImage.colorSpace;
                
                NSDictionary *options = @{(NSString *)kCGImageDestinationLossyCompressionQuality:[NSNumber numberWithFloat:0.8]};
                NSData *jpegData = [_context
                                    JPEGRepresentationOfImage:ciImage
                                    colorSpace:_colorSpace
                                    options:options];
                ciImage = nil;
                
                mynano__send_jpeg( _push,
                  (unsigned char *) jpegData.bytes, jpegData.length, _w, _h, (int) _destW, (int) _destH, cause, diff );
                jpegData = nil;
            }
        }
        
        if( !released ) {
            CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
            CFRelease( msg->sampleBuffer );
        }
    }
    else  {
        //NSLog( @"xxr other");
    }
    
    ciImage = nil;
}

-(void) noframes {
    mynano__send_text( _push, "noframes" );
}

-(void) entry:(id)param {
    nng_socket pullF;
    
    int r1 = nng_pull_open( &pullF );
    printf( "r1 %d", r1 );
    const char *addr = "inproc://frames";
    nng_setopt_int( pullF, NNG_OPT_RECVBUF, 10000);
    
    // If we don't receive any images for 100ms; then we are in trouble...
    //nng_setopt_int( pullF, NNG_OPT_RECVTIMEO, 100);
    
    nng_dial( pullF, addr, NULL, 0 );
    
    [self setupFrameDest];
    
    /*nng_push_open(&_control);
    char addr2[50];
    sprintf( addr2, "inproc://control" );
    nng_setopt_int(_control, NNG_OPT_SENDBUF, 2000);
    nng_dial( _control, addr2, NULL, 0 );*/
    nng_push_open( &_log );
    char addrlog[50];
    sprintf( addrlog, "tcp://127.0.0.1:%d", _logPort );
    int r10 = nng_listen( _log, addrlog, NULL, 0);
    if( r10 != 0 ) {
        //NSLog( @"xxr error bindind on 127.0.0.1 : %d - %d", _logPort, r10 );
    }
    [self log:"framepasser log attached"];
    
    bool noFrames = false;
    while( 1 ) {
        nng_msg *msg = NULL;
        int recv_err = nng_recvmsg( pullF, &msg, 0 );
        if( recv_err == NNG_ETIMEDOUT ) {
            if( !noFrames ) {
                noFrames = true;
                [self noframes];
            }
            usleep( 20 );
        }
        else if( msg != NULL  ) {
            if( nng_msg_len( msg ) > 0 ) {
                fp_msg_base *base = (fp_msg_base *) nng_msg_body( msg );
                if( base->type == 1 ) {
                    fp_msg_text *text = ( fp_msg_text * ) base;
                    //os_log( OS_LOG_DEFAULT, "xxr Got message %s", text->text );
                    if( !strncmp( text->text, "done", 4 ) ) {
                        nng_msg_free( msg );
                        break;
                    }
                } else if( base->type == 2 ) {
                    fp_msg_buffer *buffer = ( fp_msg_buffer * ) base;
                    if( noFrames ) noFrames = false;
                    if( _sending ) [self handle_buffer:buffer];
                    else discard_buffer( buffer );
                }
            }
            else {
                //NSLog(@"xxr empty message");
            }
            nng_msg_free( msg );
        }
        else {
            usleep( 20 );
        }
    }
    
    nng_close( _push );
}

@end

@implementation SampleHandler

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *,NSObject *> *)setupInfo {
    nng_push_open(&_pushF);
    const char *addr = "inproc://frames";
    nng_setopt_int(_pushF, NNG_OPT_SENDBUF, 10000);
    nng_listen( _pushF, addr, NULL, 0 );
    
    [self readConfig];
    
    _framePasserInst = [[FramePasser alloc] init:_inputPort outputIp:_outputIp outputPort:_outputPort logPort:_logPort];
    
    //_frameThread = [[NSThread alloc] initWithTarget:_framePasserInst selector:@selector(entry:) object:nil];
    [NSThread detachNewThreadSelector:@selector(entry:) toTarget:_framePasserInst withObject:nil];
    
    if( _controlPort ) {
        _controlThreadInst = [[ControlThread alloc] init:_controlPort logPort:_logPort framePasser:_framePasserInst];
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
    _logPort = 8353;
}

- (void)broadcastPaused {
}

- (void)broadcastResumed {
}

- (void)broadcastFinished {
    _started = 0;
    
    //[_frameThread cancel];
    //[_controlThread cancel];
    
    //mynano__send_text( _pushF, "done" );
        
    _framePasserInst = nil;
    
    mynano__send_text( _push, "done" ); // stop the control thread
        
    usleep(100);
    
    nng_close( _pushF );
    nng_close( _push );
    
    _controlThreadInst = nil;
}

void mynano__send_text( nng_socket push, const char *text ) {
    char buffer[50];
    sprintf( buffer, "{msg:\"%s\"}\n", text );
    
    nng_msg *msg;
    nng_msg_alloc( &msg, 0 );
    nng_msg_append( msg, buffer, strlen( buffer ) );
    int failed = nng_sendmsg( push, msg, 0 );
    if( failed ) nng_msg_free( msg );
}

void mynano__send_jpeg( nng_socket push, unsigned char *data, unsigned long dataLen, int ow, int oh, int dw, int dh, int cause, uint32_t crc ) {
    char buffer[300];
    
    int jlen = snprintf( buffer, 300, "{\"ow\":%i,\"oh\":%i,\"dw\":%i,\"dh\":%i,\"c\":%i,\"crc\":\"%x\"}", ow, oh, dw, dh, cause, crc );
    
    nng_msg *msg;
    nng_msg_alloc( &msg, 0 );
    nng_msg_append( msg, buffer, jlen );
    nng_msg_append( msg, data, dataLen );
    
    int failed = nng_sendmsg( push, msg, 0 );
    //if( res != 0 ) NSLog(@"xxr Send failed; res=%d", res );
    
    if( failed ) nng_msg_free( msg );
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    switch (sampleBufferType) {
        case RPSampleBufferTypeVideo:
            _frameNum++;
            if( ( _frameNum % 4 ) == 0 ) {
                CFRetain( sampleBuffer);
                    
                _msgBuffer.sampleBuffer = sampleBuffer;
                _msgBuffer.frameNum = _frameNum;
                nng_msg *msg;
                nng_msg_alloc(&msg, 0);
                nng_msg_append( msg, &_msgBuffer, sizeof( fp_msg_buffer ) );
                int failed = nng_sendmsg( _pushF, msg, 0 );
                if( failed ) nng_msg_free( msg );
            }
            break;
        case RPSampleBufferTypeAudioApp: break;
        case RPSampleBufferTypeAudioMic: break;
        default:                         break;
    }
}

@end
