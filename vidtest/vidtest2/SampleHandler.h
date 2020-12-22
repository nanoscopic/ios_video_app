// Copyright (C) 2020 David Helkowski
// Anti-Corruption License

#import <ReplayKit/ReplayKit.h>
//#import "TurboJPEG/TurboJPEG.h"
#include "nng/nng.h"
#include "nng/protocol/pipeline0/push.h"
#include "nng/protocol/pipeline0/pull.h"
#include "ujsonin/ujsonin.h"

void mynano__send_jpeg( nng_socket push, unsigned char *data, unsigned long dataLen, int ow, int oh, int dw, int dh );

@interface SampleHandler : RPBroadcastSampleHandler

@property long frameNum;
@property nng_socket pushF;
@property int pushOk;
@property int started;
@property id framePasserInst;

- (void) readCompletionNotification:(NSNotification*)notification;

@end
