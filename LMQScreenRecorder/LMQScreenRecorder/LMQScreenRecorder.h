//
//  LMQScreenRecorder.h
//  LMQScreenRecorder
//
//  Created by lizhengheng on 2015/4/25.
//  Copyright © 2015 limengqi. All rights reserved.
//

#import <Foundation/Foundation.h>


@class LMQScreenRecorderOption,UIView;

typedef void (^LMQLMQScreenRecordCompletionBlock)(BOOL success,NSURL *videoURL,NSError *error);

typedef enum : NSUInteger {
    LMQScreenRecorderStateDefault,
    LMQScreenRecorderStateRecording,
    LMQScreenRecorderStateWriting,
    LMQScreenRecorderStateCompleted,
} LMQScreenRecorderState;

@interface LMQScreenRecorder : NSObject


@property(nonatomic,assign,readonly)LMQScreenRecorderState state;

+ (instancetype)recorderWithOption:(LMQScreenRecorderOption *)option;

- (void)startRecordView:(UIView *)view;

- (void)stopRecordingWithCompletion:(LMQLMQScreenRecordCompletionBlock)completionBlock;

@end

@interface LMQScreenRecorderOption : NSObject

/**
 视频输出地址
 */
@property(nonatomic,copy)NSString *outputURL;

/**
 导入的音频地址
 */
@property(nonatomic,copy)NSString *inputAudioURL;

/**
 最大帧数
 */
@property(nonatomic,assign)NSUInteger maxFrame;

@end


#ifndef weakify
#if __has_feature(objc_arc)

#define weakify( x ) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wshadow\"") \
autoreleasepool{} __weak __typeof__(x) __weak_##x##__ = x; \
_Pragma("clang diagnostic pop")

#else

#define weakify( x ) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wshadow\"") \
autoreleasepool{} __block __typeof__(x) __block_##x##__ = x; \
_Pragma("clang diagnostic pop")

#endif
#endif

#ifndef strongify
#if __has_feature(objc_arc)

#define strongify( x ) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wshadow\"") \
try{} @finally{} __typeof__(x) x = __weak_##x##__; \
_Pragma("clang diagnostic pop")

#else

#define strongify( x ) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wshadow\"") \
try{} @finally{} __typeof__(x) x = __block_##x##__; \
_Pragma("clang diagnostic pop")

#endif
#endif
