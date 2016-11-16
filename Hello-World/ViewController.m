//
//  ViewController.m
//  Hello-World
//
//  Copyright (c) 2013 TokBox, Inc. All rights reserved.
//

#define TIME_WINDOW 3000 // 3 seconds

#import "ViewController.h"
#import <OpenTok/OpenTok.h>
#import <mach/mach.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <signal.h>
#import <VideoToolbox/VideoToolbox.h>
#import "TBExampleSubscriber.h"
#import "TBExamplePublisher.h"
#import "HCSStarRatingView.h"

UITextField *my_pub_dimensions = nil;
UITextField *my_sub_dimensions = nil;

bool startSending = false;

@interface OpenTokObjC : NSObject
+ (void)enableH264Codec;
+ (void)enableWebRTCLogs;
+ (void)setLogBlockQueue:(dispatch_queue_t)queue;
+ (void)setLogBlockArgument:(void*)argument;
+ (void)setLogBlock:(void (^)(NSString* message, void* argument))logBlock;
@end

@interface ViewController ()
<OTSessionDelegate, OTSubscriberKitDelegate,
OTPublisherDelegate, OTSubscriberKitNetworkStatsDelegate>

@end

@implementation ViewController {
    OTSession* _session;
    TBExamplePublisher* _publisher;
    TBExampleSubscriber* _subscriber;
    NSTimer *_sampleTimer;
    double _cpuTotal;
    double _memTotal;
    double _totalCounter;
    float _initialBatteryLvl;
    
    // bandwidth
    double prevVideoTimestamp;
    double prevVideoBytes;
    double prevAudioTimestamp;
    double prevAudioBytes;
    uint64_t prevVideoPacketsLost;
    uint64_t prevVideoPacketsRcvd;
    uint64_t prevAudioPacketsLost;
    uint64_t prevAudioPacketsRcvd;
    long video_bw;
    long audio_bw;
    double video_pl_ratio;
    double audio_pl_ratio;
    
    HCSStarRatingView *starRatingView;
    double currentRating;
    NSString *testName;
    
}
static double widgetHeight = 220 ;//480 ;//240;
static double widgetWidth = 320;//640;

// *** Fill the following variables using your own Project info  ***
// ***          https://dashboard.tokbox.com/projects            ***
// Replace with your OpenTok API key
static NSString* const kApiKey = @"";
// Replace with your generated session ID
static NSString* const kSessionId = @"";
// Replace with your generated token
static NSString* const kToken = @"";


// Change to NO to subscribe to streams other than your own.
static bool subscribeToSelf = NO;
#pragma mark - View lifecycle
- (void)viewDidAppear:(BOOL)animated
{
    [self askTestName];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    
    my_pub_dimensions = self.pubDimensionsTxtFld;
    my_sub_dimensions = self.subDimensionsTxtFld;
    
    [super viewDidLoad];
 
    starRatingView = [HCSStarRatingView new];;
    starRatingView.maximumValue = 5;
    starRatingView.minimumValue = 0;
    starRatingView.value = 0;
    starRatingView.tintColor = [UIColor redColor];
    starRatingView.allowsHalfStars = YES;
    CGRect frame = starRatingView.frame;
    frame.origin.x = 10;
    frame.origin.y = widgetHeight * 2 + 8;
    frame.size.width = 200;
    frame.size.height = 20;
    starRatingView.frame = frame;
    [self.view addSubview:starRatingView];
    
    void (^logBlock)(NSString* message, void* arg);
    logBlock = ^(NSString* message, void* arg){
        NSLog(@"%@",message);
    };
    
    _totalCounter = 0; _memTotal = 0; _cpuTotal = 0;
    
    //    [NSClassFromString(@"OpenTokObjC") performSelector:@selector(setLogBlock:) withObject:logBlock];
    //    [NSClassFromString(@"OpenTokObjC") performSelector:@selector(setLogBlockQueue:) withObject:dispatch_get_main_queue()];
    
    // Step 1: As the view comes into the foreground, initialize a new instance
    // of OTSession and begin the connection process.
    
    //[self sampleCPUUsage:nil];
    //[self doConnect];
}

-(void) askTestName
{
UIAlertController * alert=   [UIAlertController
                                  alertControllerWithTitle:@"Test details"
                                  message:@"Enter Test Name"
                                  preferredStyle:UIAlertControllerStyleAlert];
     
    UIAlertAction* ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction * action) {
                                                   //Do Some action here
                                                    testName = [alert.textFields[0].text copy];
                                                    [alert dismissViewControllerAnimated:YES completion:nil];
                                                    [self doConnect];
                                               }];
    UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       [alert dismissViewControllerAnimated:YES completion:nil];
                                                       [self doConnect];
                                                   }];
     
    [alert addAction:ok];
    [alert addAction:cancel];
     
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"";
    }];
    
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:
(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    if (UIUserInterfaceIdiomPhone == [[UIDevice currentDevice]
                                      userInterfaceIdiom])
    {
        return NO;
    } else {
        return YES;
    }
}
#pragma mark - OpenTok methods

/**
 * Asynchronously begins the session connect process. Some time later, we will
 * expect a delegate method to call us back with the results of this action.
 */
- (void)doConnect
{

    prevVideoTimestamp = 0;
    prevVideoBytes = 0;
    prevAudioTimestamp = 0;
    prevAudioBytes = 0;
    prevVideoPacketsLost = 0;
    prevVideoPacketsRcvd = 0;
    prevAudioPacketsLost = 0;
    prevAudioPacketsRcvd = 0;
    video_bw = 0;
    audio_bw = 0;
    video_pl_ratio = -1;
    audio_pl_ratio = -1;
    currentRating = -1;
    
    OTError *error = nil;
    _session = [[OTSession alloc] initWithApiKey:kApiKey
                                       sessionId:kSessionId
                                        delegate:self];

    [_session connectWithToken:kToken error:&error];
    if (error)
    {
        [self showAlert:[error localizedDescription]];
    }
}

/**
 * Sets up an instance of OTPublisher to use with this session. OTPubilsher
 * binds to the device camera and microphone, and will provide A/V streams
 * to the OpenTok session.
 */
- (void)doPublish
{
    _publisher = [[TBExamplePublisher alloc] initWithDelegate:self
                                                         name:nil
                                                   audioTrack:YES
                                                   videoTrack:YES];
    
    OTError *error = nil;
    [_session publish:_publisher error:&error];
    if (error)
    {
        [self showAlert:[error localizedDescription]];
    }
    
    [self.view addSubview:_publisher.view];
    [_publisher.view setFrame:CGRectMake(0, 0, widgetWidth, widgetHeight)];
}

/**
 * Cleans up the publisher and its view. At this point, the publisher should not
 * be attached to the session any more.
 */
- (void)cleanupPublisher {
    [_publisher.view removeFromSuperview];
    _publisher = nil;
    // this is a good place to notify the end-user that publishing has stopped.
}

/**
 * Instantiates a subscriber for the given stream and asynchronously begins the
 * process to begin receiving A/V content for this stream. Unlike doPublish,
 * this method does not add the subscriber to the view hierarchy. Instead, we
 * add the subscriber only after it has connected and begins receiving data.
 */
- (void)doSubscribe:(OTStream*)stream
{
 
    _subscriber = [[TBExampleSubscriber alloc] initWithStream:stream
                                                     delegate:self];
    _subscriber.networkStatsDelegate = self;
    //_subscriber.fileNameToWriteRawData = @"640_480_HIGH_Decoded.yuv";
    OTError *error = nil;
    [_session subscribe:_subscriber error:&error];
    if (error)
    {
        [self showAlert:[error localizedDescription]];
    }
}

/**
 * Cleans the subscriber from the view hierarchy, if any.
 * NB: You do *not* have to call unsubscribe in your controller in response to
 * a streamDestroyed event. Any subscribers (or the publisher) for a stream will
 * be automatically removed from the session during cleanup of the stream.
 */
- (void)cleanupSubscriber
{
    [_subscriber.view removeFromSuperview];
    //NSLog(@"Subscriber frames rcvd %ld",[_subscriber totalRcvdFrames]);
    _subscriber = nil;
}

# pragma mark - OTSession delegate callbacks

- (void)sessionDidConnect:(OTSession*)session
{
    NSLog(@"sessionDidConnect (%@)", session.sessionId);
    
    [self doPublish];
}

- (void)sessionDidDisconnect:(OTSession*)session
{
    [_sampleTimer invalidate];
    
    NSString* alertMessage =
    [NSString stringWithFormat:@"Session disconnected: (%@)",
     session.sessionId];
    NSLog(@"sessionDidDisconnect (%@)", alertMessage);
    
//    double cpuVal = _cpuTotal / _totalCounter;
//    double memVal = _memTotal / _totalCounter;
//    [self updateBatteryLevel];
//    NSLog(@"Final Avg. CPU Usage %.2f, Memory used %.2f",cpuVal,memVal);
    
}

- (void)session:(OTSession*)mySession
  streamCreated:(OTStream *)stream
{
    NSLog(@"session streamCreated (%@)", stream.streamId);
    
    // Step 3a: (if NO == subscribeToSelf): Begin subscribing to a stream we
    // have seen on the OpenTok session.
    //if (nil == _subscriber && !subscribeToSelf)
    //if (![_publisher.stream.streamId isEqualToString:stream.streamId])
    {
        [self doSubscribe:stream];
    }
}

- (void)session:(OTSession*)session
streamDestroyed:(OTStream *)stream
{
    NSLog(@"session streamDestroyed (%@)", stream.streamId);
    
    if ([_subscriber.stream.streamId isEqualToString:stream.streamId])
    {
        [self cleanupSubscriber];
    }
}

- (void)  session:(OTSession *)session
connectionCreated:(OTConnection *)connection
{
    NSLog(@"session connectionCreated (%@)", connection.connectionId);
}

- (void)    session:(OTSession *)session
connectionDestroyed:(OTConnection *)connection
{
    NSLog(@"session connectionDestroyed (%@)", connection.connectionId);
    if ([_subscriber.stream.connection.connectionId
         isEqualToString:connection.connectionId])
    {
        [self cleanupSubscriber];
    }
}

- (void) session:(OTSession*)session
didFailWithError:(OTError*)error
{
    NSLog(@"didFailWithError: (%@)", error);
}

# pragma mark - OTSubscriber delegate callbacks

- (void)subscriberDidConnectToStream:(OTSubscriberKit*)subscriber
{
    
//    _initialBatteryLvl = [UIDevice currentDevice].batteryLevel;
//    NSLog(@"Initial Battery Level %f",_initialBatteryLvl);
    
    NSLog(@"subscriberDidConnectToStream (%@)",
          subscriber.stream.connection.connectionId);
    
    
    [_subscriber.view setFrame:CGRectMake( 0 ,
                                          widgetHeight,
                                          widgetWidth,
                                          widgetHeight)];
    
    [self.view addSubview:_subscriber.view];
    [self startTimer];
    
    [self  performSelector:@selector(disconnectSession)
                withObject:nil
                afterDelay: (5 * 60)];
    
    printf("Test Name : %s\n",[testName UTF8String]);
    printf("video_bw(kbps),audio_bw(kbps),video_pl,audio_pl,user_rating\n");
}

- (void)subscriber:(OTSubscriberKit*)subscriber
  didFailWithError:(OTError*)error
{
    NSLog(@"subscriber %@ didFailWithError %@",
          subscriber.stream.streamId,
          error);
}

# pragma mark - OTPublisher delegate callbacks

- (void)publisher:(OTPublisherKit *)publisher
    streamCreated:(OTStream *)stream
{
    // Step 3b: (if YES == subscribeToSelf): Our own publisher is now visible to
    // all participants in the OpenTok session. We will attempt to subscribe to
    // our own stream. Expect to see a slight delay in the subscriber video and
    // an echo of the audio coming from the device microphone.
    if (nil == _subscriber && subscribeToSelf)
    {
        [self doSubscribe:stream];
    }
}

- (void)publisher:(OTPublisherKit*)publisher
  streamDestroyed:(OTStream *)stream
{
    if ([_subscriber.stream.streamId isEqualToString:stream.streamId])
    {
        [self cleanupSubscriber];
    }
    
    [self cleanupPublisher];
}

- (void)publisher:(OTPublisherKit*)publisher
 didFailWithError:(OTError*) error
{
    NSLog(@"publisher didFailWithError %@", error);
    [self cleanupPublisher];
}

- (void)showAlert:(NSString *)string
{
    // show alertview on main UI
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"OTError"
                                                        message:string
                                                       delegate:self
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil] ;
        [alert show];
    });
}

- (IBAction)sampleCPUUsage:(id)sender {
    [self doConnect];
}

float cpu_usage1()
{
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t      basic_info;
    thread_array_t         thread_list;
    mach_msg_type_number_t thread_count;
    
    thread_info_data_t     thinfo;
    mach_msg_type_number_t thread_info_count;
    
    thread_basic_info_t basic_info_th;
    uint32_t stat_thread = 0; // Mach threads
    
    basic_info = (task_basic_info_t)tinfo;
    
    // get threads in the task
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    if (thread_count > 0)
        stat_thread += thread_count;
    
    long tot_sec = 0;
    long tot_usec = 0;
    float tot_cpu = 0;
    int j;
    
    for (j = 0; j < thread_count; j++)
    {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO,
                         (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
        
        basic_info_th = (thread_basic_info_t)thinfo;
        
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_sec = tot_sec + basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
            tot_usec = tot_usec + basic_info_th->system_time.microseconds + basic_info_th->system_time.microseconds;
            tot_cpu = tot_cpu + basic_info_th->cpu_usage / (float)TH_USAGE_SCALE * 100.0;
        }
        
    } // for each thread
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    assert(kr == KERN_SUCCESS);
    
    return tot_cpu;
}


static float getMemoryUsage1() {
    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(),
                                   TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    
    if( kerr == KERN_SUCCESS ) return ((float)info.resident_size/1048576.0f);
    else return 0;
}

- (void)timerIntervalForCPUandMemorySamples
{
    if (startSending == NO && _totalCounter == 1)
        startSending = YES;
    float memVal = getMemoryUsage1();
    float cpuVal = cpu_usage1();
    self.cpuUsageTxtFld.text = [NSString stringWithFormat:@"%.2f",cpuVal];
    self.memUsageTxtFld.text = [NSString stringWithFormat:@"%.2f",memVal];
    _totalCounter++;
    _memTotal += memVal;
    _cpuTotal += cpuVal;
    NSLog(@"CPU Usage %.2f, Memory used %.2f",cpuVal,memVal);
}

- (void)disconnectSession
{
    [_session disconnect:nil];
}

- (void)startTimer
{
    return;
    _sampleTimer = [NSTimer timerWithTimeInterval:3
                                           target:self
                                         selector:@selector(timerIntervalForCPUandMemorySamples)
                                         userInfo:nil
                                          repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_sampleTimer
                                 forMode:NSDefaultRunLoopMode];
    
}

- (void)updateBatteryLevel
{
    float batteryLevel = [UIDevice currentDevice].batteryLevel;
    NSLog(@"Finished battery level %f",batteryLevel);
    if (batteryLevel < 0.0) {
        // -1.0 means battery state is UIDeviceBatteryStateUnknown
        self.batteryLevel.text = NSLocalizedString(@"Unknown", @"");
    }
    else {
        batteryLevel =  _initialBatteryLvl - batteryLevel;
        static NSNumberFormatter *numberFormatter = nil;
        if (numberFormatter == nil) {
            numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
            [numberFormatter setMaximumFractionDigits:1];
        }
        
        NSNumber *levelObj = [NSNumber numberWithFloat:batteryLevel];
        self.batteryLevel.text = [numberFormatter stringFromNumber:levelObj];
        NSLog(@"Consumed Battery Level %@",levelObj);
    }
}

- (void)subscriber:(OTSubscriberKit*)subscriber
videoNetworkStatsUpdated:(OTSubscriberKitVideoNetworkStats*)stats
{
    if (prevVideoTimestamp == 0)
    {
        prevVideoTimestamp = stats.timestamp;
        prevVideoBytes = stats.videoBytesReceived;
    }
    
    if (stats.timestamp - prevVideoTimestamp >= TIME_WINDOW)
    {
        video_bw = (8 * (stats.videoBytesReceived - prevVideoBytes)) / ((stats.timestamp - prevVideoTimestamp) / 1000ull);

        [self processStats:stats];
        prevVideoTimestamp = stats.timestamp;
        prevVideoBytes = stats.videoBytesReceived;
        printf("%ld,%ld,%.2f,%.2f,%.2f\n",
        (video_bw / 1000), (audio_bw / 1000),
        video_pl_ratio, audio_pl_ratio,
        currentRating);
//        NSLog(@"kbps %ld, packetsLost %.2f", (video_bw / 1000),
//        video_pl_ratio);
    }
}

- (void)subscriber:(OTSubscriberKit*)subscriber
audioNetworkStatsUpdated:(OTSubscriberKitAudioNetworkStats*)stats
{
    if (prevAudioTimestamp == 0)
    {
        prevAudioTimestamp = stats.timestamp;
        prevAudioBytes = stats.audioBytesReceived;
    }
    
    if (stats.timestamp - prevAudioTimestamp >= TIME_WINDOW)
    {
        audio_bw = (8 * (stats.audioBytesReceived - prevAudioBytes)) / ((stats.timestamp - prevAudioTimestamp) / 1000ull);

        [self processStats:stats];
        prevAudioTimestamp = stats.timestamp;
        prevAudioBytes = stats.audioBytesReceived;
        //NSLog(@"kbps %ld, packetsLost %.2f", (audio_bw / 1000),
        //audio_pl_ratio);
    }
}

- (void)processStats:(id)stats
{
    if ([stats isKindOfClass:[OTSubscriberKitVideoNetworkStats class]])
    {
        video_pl_ratio = -1;
        OTSubscriberKitVideoNetworkStats *videoStats =
        (OTSubscriberKitVideoNetworkStats *) stats;
        if (prevVideoPacketsRcvd != 0) {
            uint64_t pl = videoStats.videoPacketsLost - prevVideoPacketsLost;
            uint64_t pr = videoStats.videoPacketsReceived - prevVideoPacketsRcvd;
            uint64_t pt = pl + pr;
            if (pt > 0)
                video_pl_ratio = (double) pl / (double) pt;
        }
        prevVideoPacketsLost = videoStats.videoPacketsLost;
        prevVideoPacketsRcvd = videoStats.videoPacketsReceived;
    }
    if ([stats isKindOfClass:[OTSubscriberKitAudioNetworkStats class]])
    {
        audio_pl_ratio = -1;
        OTSubscriberKitAudioNetworkStats *audioStats =
        (OTSubscriberKitAudioNetworkStats *) stats;
        if (prevAudioPacketsRcvd != 0) {
            uint64_t pl = audioStats.audioPacketsLost - prevAudioPacketsLost;
            uint64_t pr = audioStats.audioPacketsReceived - prevAudioPacketsRcvd;
            uint64_t pt = pl + pr;
            if (pt > 0)
                audio_pl_ratio = (double) pl / (double) pt;
        }
        prevAudioPacketsLost = audioStats.audioPacketsLost;
        prevAudioPacketsRcvd = audioStats.audioPacketsReceived;
    }
    if (!(currentRating == -1 && starRatingView.value == 0))
        currentRating = starRatingView.value;
}

@end
