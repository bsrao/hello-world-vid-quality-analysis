//
//  TBSubscriber.m
//  Lets-Build-OTPublisher
//
//  Copyright (c) 2013 TokBox, Inc. All rights reserved.
//

#import "TBExampleSubscriber.h"
#import "TBExampleVideoRender.h"

// Internally forward-declare that we can receive renderer delegate callbacks
@interface TBExampleSubscriber () <TBRendererDelegate>
@end

@implementation TBExampleSubscriber {
    TBExampleVideoRender* _myVideoRender;

    FILE * pFile;
    long frame_size;
    uint8_t * frame_buffer;
}

@synthesize view = _myVideoRender;

- (id)initWithStream:(OTStream *)stream
            delegate:(id<OTSubscriberKitDelegate>)delegate
{
    self = [super initWithStream:stream delegate:delegate];
    if (self) {
        _myVideoRender =
        [[TBExampleVideoRender alloc] initWithFrame:CGRectMake(0,0,1,1)];
        _myVideoRender.delegate = self;
        [self setVideoRender:_myVideoRender];
        
        // Observe important stream attributes to properly react to changes
        [self.stream addObserver:self
                      forKeyPath:@"hasVideo"
                         options:NSKeyValueObservingOptionNew
                         context:nil];
        [self.stream addObserver:self
                      forKeyPath:@"hasAudio"
                         options:NSKeyValueObservingOptionNew
                         context:nil];
        pFile = NULL;
    }
    return self;
}

- (void)dealloc {
    fclose(pFile);
    [self.fileNameToWriteRawData release];
    [self.stream removeObserver:self forKeyPath:@"hasVideo" context:nil];
    [self.stream removeObserver:self forKeyPath:@"hasAudio" context:nil];
    [_myVideoRender release];
    NSLog(@"Total Rcvd Frames %ld",rcvd_count);
    [super dealloc];
}

#pragma mark - KVO listeners for UI updates

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^() {
        if ([@"hasVideo" isEqualToString:keyPath]) {
            // If the video track has gone away, we can clear the screen.
            BOOL value = [[change valueForKey:@"new"] boolValue];
            if (value) {
                [_myVideoRender setRenderingEnabled:YES];
            } else {
                [_myVideoRender setRenderingEnabled:NO];
                [_myVideoRender clearRenderBuffer];
            }
        } else if ([@"hasAudio" isEqualToString:keyPath]) {
            // nop?
        }
    });
}

#pragma mark - Overrides for UI

- (void)setSubscribeToVideo:(BOOL)subscribeToVideo {
    [super setSubscribeToVideo:subscribeToVideo];
    [_myVideoRender setRenderingEnabled:subscribeToVideo];
    if (!subscribeToVideo) {
        [_myVideoRender clearRenderBuffer];
    }
}
long rcvd_count = 0;
- (long)totalRcvdFrames
{
    return rcvd_count;
}
#pragma mark - TBRendererDelegate

CMTimeValue	prev_value = 0;
- (void)renderer:(TBExampleVideoRender *)renderer
 didReceiveFrame:(OTVideoFrame *)frame
{
    rcvd_count ++;
    //NSLog(@"Rcvd frames %ld",rcvd_count);
    //if (prev_value > 0)
     //   NSLog(@"rcvd time stamp %lld", ( frame.timestamp.value - prev_value));
    prev_value = frame.timestamp.value;
    if (pFile == NULL)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                             NSUserDomainMask,
                                                             YES);
        NSString *fullPath = [[paths lastObject] stringByAppendingPathComponent:self.fileNameToWriteRawData];
        [[NSFileManager defaultManager] removeItemAtPath:fullPath
                                                   error:nil];
        pFile = fopen ( [fullPath cStringUsingEncoding:NSUTF8StringEncoding] , "w" );
        frame_size = (frame.format.imageWidth * frame.format.imageHeight) +
        (frame.format.imageWidth / 2 * frame.format.imageHeight);
    }
    //fwrite([frame.planes pointerAtIndex:0], 1, (frame.format.imageWidth * frame.format.imageHeight), pFile);
    //fwrite([frame.planes pointerAtIndex:1], 1, (frame.format.imageWidth / 2 * frame.format.imageHeight), pFile);
    
    dispatch_async(dispatch_get_main_queue(), ^() {
        // post a notification to the controller that video has arrived for this
        // subscriber. Useful for transitioning a "loading" UI.
        if ([self.delegate
             respondsToSelector:@selector(subscriberVideoDataReceived:)])
        {
            [self.delegate subscriberVideoDataReceived:self];
        }
    });
}


@end
