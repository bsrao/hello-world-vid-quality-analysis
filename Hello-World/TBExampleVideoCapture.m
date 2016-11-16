//
//  TBExampleVideoCapture.m
//  otkit-objc-libs
//
//  Created by Charley Robinson on 10/11/13.
//
//

#import <Availability.h>
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenTok/OpenTok.h>
#import "TBExampleVideoCapture.h"

extern UITextField *my_pub_dimensions ;

#define SYSTEM_VERSION_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

@implementation TBExampleVideoCapture {
    id<OTVideoCaptureConsumer> _videoCaptureConsumer;
    OTVideoFrame* _videoFrame;
    
    uint32_t _captureWidth;
    uint32_t _captureHeight;
    NSString* _capturePreset;
    
    AVCaptureSession *_captureSession;
    AVCaptureDeviceInput *_videoInput;
    AVCaptureVideoDataOutput *_videoOutput;
    
    BOOL _capturing;
    FILE * pFile;
    long file_size;
    long frame_size;
    uint8_t * frame_buffer;

    dispatch_source_t _timer;
    long _picCount;
    int _currentLoopNum;
    bool _markedAsFinished;
    
}

@synthesize captureSession = _captureSession;
@synthesize videoInput = _videoInput, videoOutput = _videoOutput;
@synthesize videoCaptureConsumer = _videoCaptureConsumer;

#define OT_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE 20.0000f

-(id)init {
    self = [super init];
    if (self) {

        NSString *yuvFileName = @"640_480_MED_20FPS.jpeg";
        // 352_288_HIGH.yuv 640_480_HIGH.yuv 1280_720_HIGH.yuv
        _captureWidth = 0;
        _captureHeight = 0;
        [self setCaptureDimesionsFromFileName:yuvFileName
                                        width:&_captureWidth
                                       height:&_captureHeight];
        
        my_pub_dimensions.text = [NSString stringWithFormat:@"%uX%u",_captureWidth,_captureHeight];
        _capture_queue = dispatch_queue_create("com.tokbox.OTVideoCapture",
                                               DISPATCH_QUEUE_SERIAL);

        _videoFrame = [[OTVideoFrame alloc] initWithFormat:
                       [OTVideoFormat videoFormatI420WithWidth:_captureWidth
                                                        height:_captureHeight]];
        
        NSString *yuvFilePath = [[NSBundle mainBundle]
                                 pathForResource:[yuvFileName stringByDeletingPathExtension]
                                 ofType:[yuvFileName pathExtension]];
        
        pFile = fopen ( [yuvFilePath cStringUsingEncoding:NSUTF8StringEncoding] , "rb" );
        //frame_size = (_captureWidth * _captureHeight) + (_captureWidth / 2 * _captureHeight);
        frame_size = (_captureWidth * _captureHeight) +
                     (_captureWidth / 2 * _captureHeight / 2) +
                    (_captureWidth / 2 * _captureHeight / 2);
        frame_buffer = malloc(frame_size);
    }
    return self;
}

- (void)setCaptureDimesionsFromFileName:(NSString *)fileName
                                  width:(uint32_t *)width
                                 height:(uint32_t *)height
{
    NSArray *components = [fileName componentsSeparatedByString:@"_"];
    *width = [[components objectAtIndex:0] integerValue];
    *height = [[components objectAtIndex:1] integerValue];
}
- (int32_t)captureSettings:(OTVideoFormat*)videoFormat {
    videoFormat.pixelFormat = OTPixelFormatNV12;
    videoFormat.imageWidth = _captureWidth;
    videoFormat.imageHeight = _captureHeight;
    return 0;
}

- (void)dealloc {
    [self stopCapture];
    [self releaseCapture];
    
    if (_capture_queue) {
        dispatch_release(_capture_queue);
        _capture_queue = nil;
    }
    
    [_videoFrame release];
    
    [super dealloc];
}

- (void)updateCaptureFormatWithWidth:(int)width height:(int)height
{
    _captureWidth = width;
    _captureHeight = height;
    [_videoFrame setFormat:[OTVideoFormat
                            videoFormatNV12WithWidth:_captureWidth
                            height:_captureHeight]];
    
}

-(void)releaseCapture {
    [self stopCapture];
    fclose(pFile);
    free(frame_buffer);
}

- (void) initCapture {
    
    fseek (pFile , 0 , SEEK_END);
    file_size = ftell (pFile);
    rewind (pFile);
}

- (BOOL) isCaptureStarted {
    return _capturing;
}

- (int32_t) startCapture {
    _capturing = YES;
    _picCount = 0;
    _currentLoopNum = 1;
    self.loopCount = 5;
    _markedAsFinished = false;
    double secondsToFire = 1.000f / OT_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE; // 1.000f;
    
    _timer = CreateDispatchTimer(secondsToFire, _capture_queue, ^{
        // Do something
       // NSLog(@"Firing consumeFrame");
        [self consumeFrame];
    });
    return 0;
}

- (int32_t) stopCapture {
    _capturing = NO;
    
    if (_timer) {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }
    return 0;
}
extern bool startSending ;
-(void)consumeFrame
{
    if (_markedAsFinished /*|| !startSending */)
        return;

    _picCount ++;
    CMTime time = CMTimeMake(_picCount, OT_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE);
    
    _videoFrame.timestamp = time;
    size_t height = _captureHeight;
    size_t width = _captureWidth;

    _videoFrame.format.imageWidth = width;
    _videoFrame.format.imageHeight = height;

    _videoFrame.format.estimatedFramesPerSecond =
    OT_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE;
    
    // TODO: how do we measure this from AVFoundation?
    _videoFrame.format.estimatedCaptureDelay = 0;
    _videoFrame.orientation = OTVideoOrientationUp;
    
    [_videoFrame clearPlanes];
    
    //NSLog(@"started fread");
    int result = fread (frame_buffer,1,frame_size,pFile);
    //NSLog(@"_picCount %ld",_picCount);
    if /*(_picCount == 932)*/ (result != frame_size)
    {
        //(_picCount == 100)
        _currentLoopNum ++;
        if (_currentLoopNum > self.loopCount )
        {
            _markedAsFinished = true;
            [self stopSession];
            return;
        }
        rewind (pFile);
        fread (frame_buffer,1,frame_size,pFile);
    }
    [_videoFrame.planes addPointer:frame_buffer];
    [_videoFrame.planes addPointer:frame_buffer + (width * height)];
    [_videoFrame.planes addPointer:frame_buffer + (width * height) +
     (width / 2 * height / 2)];
    
    [_videoCaptureConsumer consumeFrame:_videoFrame];
}

- (void)stopSession
{
    // Delay execution of my block for 10 seconds.
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self.session disconnect:nil];
        NSLog(@"Session stopped");
  //  });

}

dispatch_source_t CreateDispatchTimer(double interval, dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (timer)
    {
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }
    return timer;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    if (!(_capturing && _videoCaptureConsumer)) {
        return;
    }
    
    CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    _videoFrame.timestamp = time;
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    height = 480;
    width = 640;
    if (width != _captureWidth || height != _captureHeight) {
        [self updateCaptureFormatWithWidth:width height:height];
        my_pub_dimensions.text = [NSString stringWithFormat:@"%zuX%zu",width,height];
    }
    _videoFrame.format.imageWidth = width;
    _videoFrame.format.imageHeight = height;
    CMTime minFrameDuration;
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        minFrameDuration = _videoInput.device.activeVideoMinFrameDuration;
    } else {
        AVCaptureConnection *conn =
        [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
        minFrameDuration = conn.videoMinFrameDuration;
    }
    _videoFrame.format.estimatedFramesPerSecond =
    minFrameDuration.timescale / minFrameDuration.value;
    // TODO: how do we measure this from AVFoundation?
    _videoFrame.format.estimatedCaptureDelay = 100;
    _videoFrame.orientation = OTVideoOrientationUp;
    
    [_videoFrame clearPlanes];
    uint8_t* sanitizedImageBuffer = NULL;
    
    if (!CVPixelBufferIsPlanar(imageBuffer))
    {
        [_videoFrame.planes
         addPointer:CVPixelBufferGetBaseAddress(imageBuffer)];
    } else if ([self imageBufferIsSanitary:imageBuffer]) {
        for (int i = 0; i < CVPixelBufferGetPlaneCount(imageBuffer); i++) {
            [_videoFrame.planes addPointer:
             CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i)];
        }
    } else {
//        NSLog(@"started fread");
        int result = fread (frame_buffer,1,frame_size,pFile);
  //              NSLog(@"ended fread");
        if (result != frame_size)
        {
            rewind (pFile);
            fread (frame_buffer,1,frame_size,pFile);
        }
        // sanitizedImageBuffer =
        //        [self sanitizeImageBuffer:imageBuffer
        //                             data:&sanitizedImageBuffer
        //                           planes:_videoFrame.planes];
        [_videoFrame.planes addPointer:frame_buffer];
        [_videoFrame.planes addPointer:frame_buffer + (640 * 480)];
    }
    
    [_videoCaptureConsumer consumeFrame:_videoFrame];
    
    //free(sanitizedImageBuffer);
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
}

@end
