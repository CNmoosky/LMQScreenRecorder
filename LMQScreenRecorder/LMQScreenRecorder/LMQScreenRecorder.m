//
//  LMQScreenRecorder.m
//  LMQScreenRecorder
//
//  Created by lizhengheng on 2015/4/25.
//  Copyright © 2015 limengqi. All rights reserved.
//

#import "LMQScreenRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#ifdef DEBUG
#define LMQLog(...) NSLog(__VA_ARGS__)
#else
#define LMQLog(...)
#endif

@interface LMQScreenRecorder ()

@property(nonatomic,strong)LMQScreenRecorderOption *option;
@property(nonatomic,copy)LMQLMQScreenRecordCompletionBlock completionBlock;
@property(nonatomic,weak)UIView *recordView;
@property(nonatomic,assign,readwrite)LMQScreenRecorderState state;
@property(nonatomic,assign)CGSize recodViewSize;
@property(nonatomic,assign)CGFloat scale;

@property(nonatomic,strong)NSDate *startDate;

@property(nonatomic,strong)dispatch_queue_t render_queue;
@property(nonatomic,strong)dispatch_queue_t append_pixelBuffer_queue;
@property(nonatomic,strong)dispatch_semaphore_t semaphore;

@property(nonatomic,strong)AVAssetWriter *videoWriter;
@property(nonatomic,strong)AVAssetReader *audioReader;
@property(nonatomic,strong)AVAssetWriterInput *videoWriterInput;
@property(nonatomic,strong)AVAssetWriterInput *audioWriterInput;
@property(nonatomic,strong)AVAssetWriterInputPixelBufferAdaptor *avAdaptor;

@end

@implementation LMQScreenRecorder

+ (instancetype)recorderWithOption:(LMQScreenRecorderOption *)option
{
    LMQScreenRecorder *recorder = [[LMQScreenRecorder alloc]init];
    recorder.option = option;
    return recorder;
}

- (void)startRecordView:(UIView *)recordView
{
    self.recordView = recordView;
    self.recordView.layer.drawsAsynchronously = YES;
    self.recodViewSize = self.recordView.frame.size;
    self.scale = [UIScreen mainScreen].scale;
    
    [self startRecord];
}

- (void)stopRecordingWithCompletion:(LMQLMQScreenRecordCompletionBlock)completionBlock
{
    self.completionBlock = completionBlock;
    [self stopRecord];
}

#pragma mark - actions

- (void)startRecord
{
    if (self.recordView == nil) {
        [self errorWithError:[NSError errorWithDomain:@"RecordView can not be nil!" code:400 userInfo:nil]];
        return;
    }
    
    if (self.state == LMQScreenRecorderStateRecording) {
        [self errorWithError:[NSError errorWithDomain:@"Recorder is recording now!" code:400 userInfo:nil]];
        return;
    }
    
    [self setUpWriter];
    if (self.videoWriter) {
        [self addVideoInput];
        [self addAudioInput];
        [self.videoWriter startWriting];
        [self.videoWriter startSessionAtSourceTime:CMTimeMake(0, 1000)];
        self.state = LMQScreenRecorderStateRecording;
        [self readVideoFrame];
    }
    
}

- (void)stopRecord
{
    @weakify(self);
    dispatch_async(self.render_queue, ^{
        @strongify(self);
        self.state = LMQScreenRecorderStateWriting;
        @weakify(self);
        dispatch_async(self.append_pixelBuffer_queue, ^{
            @strongify(self);
            CFTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.startDate];
            CMTime time = CMTimeMakeWithSeconds(elapsed, 1000);
            [self.videoWriterInput markAsFinished];
            @weakify(self);
            [self addAudioreaderWith:elapsed and:^{
                @strongify(self);
                [self.audioReader cancelReading];
                [self.videoWriter endSessionAtSourceTime:time];
                @weakify(self);
                [self.videoWriter finishWritingWithCompletionHandler:^{
                    @strongify(self);
                    @weakify(self);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @strongify(self);
                        self.state = LMQScreenRecorderStateCompleted;
                        NSURL *videoURL = self.videoWriter.outputURL;
                        if (self.completionBlock) {
                            self.completionBlock(YES,videoURL,nil);
                        }
                        self.state = LMQScreenRecorderStateDefault;
                        [self clean];
                    });
                }];
            }];
        });
    });
}

#pragma mark - setUp
- (void)setUpWriter
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:self.option.outputURL]) {
        [fileManager removeItemAtPath:self.option.outputURL error:nil];
    }
    
    NSError* error = nil;
    self.videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:self.option.outputURL] ?: [self tempFileURL]
                                             fileType:AVFileTypeMPEG4
                                                error:&error];
    if (error) {
        [self errorWithError:error];
        self.videoWriter = nil;
    }
}

- (void)addVideoInput
{
    CGSize size = self.recodViewSize;
    CGFloat scale = self.scale;
    
    
    NSInteger pixelNumber = size.width * size.height * scale;
    NSDictionary* videoCompression = @{AVVideoAverageBitRateKey:@(pixelNumber * 11.4)};
    NSDictionary* videoSettings = @{AVVideoCodecKey:AVVideoCodecH264,
                                    AVVideoWidthKey:[NSNumber numberWithInt:size.width * scale],
                                    AVVideoHeightKey:[NSNumber numberWithInt:size.height * scale],
                                    AVVideoCompressionPropertiesKey:videoCompression};
    
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    
    _avAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput sourcePixelBufferAttributes:nil];
    
    [_videoWriter addInput:_videoWriterInput];
}

- (void)addAudioInput
{
    if (self.option.inputAudioURL == nil) {
        return;
    }
    
    AVAssetWriterInput* audioWriterInput = nil;
    CMFormatDescriptionRef audio_fmt_desc_ = nil;
    AudioStreamBasicDescription audioFormat;
    bzero(&audioFormat, sizeof(audioFormat));
    audioFormat.mSampleRate = 44100;
    audioFormat.mFormatID   = kAudioFormatMPEG4AAC;
    audioFormat.mFramesPerPacket = 1024;
    audioFormat.mChannelsPerFrame = 2;
    int bytes_per_sample = sizeof(float);
    audioFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    
    audioFormat.mBitsPerChannel = bytes_per_sample * 8;
    audioFormat.mBytesPerPacket = bytes_per_sample * 2;
    audioFormat.mBytesPerFrame = bytes_per_sample * 2;
    
    CMAudioFormatDescriptionCreate(kCFAllocatorDefault,&audioFormat,0,NULL,0,NULL,NULL,&audio_fmt_desc_);
    audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil sourceFormatHint:audio_fmt_desc_];
    audioWriterInput.expectsMediaDataInRealTime = YES;
    
    self.audioWriterInput = audioWriterInput;
    [_videoWriter addInput:audioWriterInput];
    
}


#pragma mark - read & write
- (void)readVideoFrame
{
    CGSize size = self.recodViewSize;
    @weakify(self);
    dispatch_async(self.render_queue, ^{
        @strongify(self);
        NSTimeInterval lastTime = 0;
        NSDate *startDate = [NSDate date];
        self.startDate = startDate;
        while (self.state == LMQScreenRecorderStateRecording) {
            @autoreleasepool {
                NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:startDate];;
                if (timeInterval - lastTime >= 1.0/self.option.maxFrame || lastTime == 0) {
                    lastTime = timeInterval ;
                    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
                    
                    CVPixelBufferRef pixelBuffer = NULL;
                    CGContextRef bitmapContext = [self createPixelBufferAndBitmapContext:&pixelBuffer];
                    @weakify(self);
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        @strongify(self);
                        UIGraphicsPushContext(bitmapContext);
                        {
                            [self.recordView drawViewHierarchyInRect:CGRectMake(0, 0, size.width, size.height) afterScreenUpdates:NO];
                        }
                        UIGraphicsPopContext();
                        @weakify(self);
                        dispatch_async(self.append_pixelBuffer_queue, ^{
                            @strongify(self);
                            LMQLog(@"录制");
                            if (![self.videoWriterInput isReadyForMoreMediaData]){
                                LMQLog(@"掉帧2");
                            }else{
                                CMTime time = CMTimeMakeWithSeconds(timeInterval, 1000);
                                BOOL success = [self.avAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
                                if (!success) {
                                    LMQLog(@"出错");
                                }
                            }
                            CGContextRelease(bitmapContext);
                            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                            CVPixelBufferRelease(pixelBuffer);
                            
                            dispatch_semaphore_signal(self.semaphore);
                        });
                    });
                }
            }
        }
    });
}

- (void)addAudioreaderWith:(CFTimeInterval)elapsed and:(void(^)(void))completionBlock
{
    if (self.option.inputAudioURL == nil) {
        if (completionBlock) {
            completionBlock();
        }
        return;
    }
    
    CFTimeInterval audioTime = 0;
    AVAsset *audioAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:self.option.inputAudioURL]];
    AVAssetTrack *audioAssetTrack = [audioAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    CFTimeInterval audioAssetTime = 0.0;
    if (audioAsset.duration.timescale != 0) {
        audioAssetTime = audioAsset.duration.value/audioAsset.duration.timescale;
    }
    
    audioTime = audioAssetTime;
    
    NSInteger outputCount = 1;
    if (audioTime > 0) {
        outputCount = ceil(elapsed / (CGFloat)audioTime);
    }
    
    NSError *error = nil;
    AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:audioAsset error:&error];
    self.audioReader = assetReader;
    
    if (error) {
        
        if (completionBlock) {
            completionBlock();
        }
        
        return;
    }
    
    AVAssetReaderTrackOutput *audioAssetTrackOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioAssetTrack outputSettings:nil];
    
    if([assetReader canAddOutput:audioAssetTrackOutput])
    {
        [assetReader addOutput:audioAssetTrackOutput];
        
        if (outputCount - 1 > 0) {
            for (NSInteger i = 0; i < (outputCount - 1); i ++) {
                AVAssetReaderTrackOutput *assetTrackOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioAssetTrack outputSettings:nil];
                [assetReader addOutput:assetTrackOutput];
            }
        }
        
        [assetReader startReading];
        
        dispatch_group_t encodingGroup = dispatch_group_create();
        
        dispatch_group_enter(encodingGroup);
        __block  NSInteger assetTrackOutputIndex = 0;
        @weakify(self);
        [self.audioWriterInput requestMediaDataWhenReadyOnQueue:self.render_queue usingBlock:^{
            @strongify(self);
            while ([self.audioWriterInput isReadyForMoreMediaData])
            {
                AVAssetReaderTrackOutput *trackOutput = (AVAssetReaderTrackOutput *)assetReader.outputs[assetTrackOutputIndex];
                
                CMSampleBufferRef nextSampleBuffer = [trackOutput copyNextSampleBuffer];
                
                if (nextSampleBuffer)
                {
                    [self.audioWriterInput appendSampleBuffer:nextSampleBuffer];
                    CFRelease(nextSampleBuffer);
                }
                else if (assetTrackOutputIndex < outputCount -1)
                {
                    assetTrackOutputIndex ++;
                }
                else
                {
                    [self.audioWriterInput markAsFinished];
                    dispatch_group_leave(encodingGroup);
                    if (completionBlock) {
                        completionBlock();
                    }
                    break;
                }
            }
        }];
    }
}

#pragma mark - tools
- (CGContextRef)createPixelBufferAndBitmapContext:(CVPixelBufferRef *)pixelBuffer
{
    CGSize size = self.recodViewSize;
    CGFloat scale = self.scale;
    
    NSDictionary *bufferAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                       (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                                       (id)kCVPixelBufferWidthKey : @(size.width * scale),
                                       (id)kCVPixelBufferHeightKey : @(size.height * scale),
                                       (id)kCVPixelBufferBytesPerRowAlignmentKey : @(size.width * scale * scale)
                                       };
    
    CVPixelBufferPoolRef outputBufferPool = NULL;
    CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)(bufferAttributes), &outputBufferPool);
    
    CVPixelBufferPoolCreatePixelBuffer(NULL, outputBufferPool, pixelBuffer);
    CVPixelBufferLockBaseAddress(*pixelBuffer, 0);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef bitmapContext = NULL;
    bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(*pixelBuffer),
                                          CVPixelBufferGetWidth(*pixelBuffer),
                                          CVPixelBufferGetHeight(*pixelBuffer),
                                          8, CVPixelBufferGetBytesPerRow(*pixelBuffer), rgbColorSpace,
                                          kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                          );
    CGContextScaleCTM(bitmapContext, scale, scale);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, size.height);
    CGContextConcatCTM(bitmapContext, flipVertical);
    
    CVPixelBufferPoolRelease(outputBufferPool);
    CGColorSpaceRelease(rgbColorSpace);
    
    return bitmapContext;
}



- (void)errorWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.state = LMQScreenRecorderStateDefault;
        if (self.completionBlock) {
            self.completionBlock (NO,nil,error);
        }
    });
}

- (NSURL*)tempFileURL
{
    NSString *outputPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/screenCapture.mp4"];
    [self removeTempFilePath:outputPath];
    return [NSURL fileURLWithPath:outputPath];
}

- (void)removeTempFilePath:(NSString*)filePath
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        [fileManager removeItemAtPath:filePath error:nil];
    }
}

#pragma mark - getter & setter

- (dispatch_queue_t)render_queue
{
    if (!_render_queue) {
        _render_queue = dispatch_queue_create("LMQScreenRecorder.render_queue", DISPATCH_QUEUE_CONCURRENT);
//        dispatch_set_target_queue(_render_queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0));

    }
    return _render_queue;
}

- (dispatch_queue_t)append_pixelBuffer_queue
{
    if (!_append_pixelBuffer_queue) {
        _append_pixelBuffer_queue = dispatch_queue_create("LMQScreenRecorder.append_queue", DISPATCH_QUEUE_SERIAL);
    }
    return _append_pixelBuffer_queue;
}

- (dispatch_semaphore_t)semaphore
{
    if (!_semaphore) {
        _semaphore = dispatch_semaphore_create(1);
    }
    return _semaphore;
}


- (void)clean
{
  
}

- (void)dealloc
{
    self.recordView = nil;
    self.completionBlock = nil;
    _semaphore = nil;
    _render_queue = nil;
    _append_pixelBuffer_queue = nil;
}

@end

@implementation LMQScreenRecorderOption

- (NSUInteger)maxFrame
{
    if (_maxFrame == 0) {
        _maxFrame = 30;
    }
    return _maxFrame;
}

@end
