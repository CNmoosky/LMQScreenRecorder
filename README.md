# LMQScreenRecorder
> A screen recorder for iOS before iOS 9

## How to use

```Objc
//初始化
NSString *outputUrl = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"video.mp4"];
NSString *inputAudioUrl = [[NSBundle ****mainBundle]pathForResource:@"baby" ofType:@"m4a"];

LMQScreenRecorderOption *option = [[LMQScreenRecorderOption alloc]init];
option.outputURL = outputUrl;
option.inputAudioURL = inputAudioUrl;

self.screenRecorder = [LMQScreenRecorder recorderWithOption:option];
```

```Objc
//开始录制
[self.screenRecorder startRecordView:self.colorView];
```
```Objc
//停止录制
@weakify(self);
[self.screenRecorder stopRecordingWithCompletion:^(BOOL success, NSURL *videoURL, NSError *error) {
@strongify(self);
    if (success) {
        if ([UIDevice currentDevice].systemVersion.doubleValue >= 8.0) {
            AVPlayer *player = [AVPlayer playerWithURL:videoURL];
            AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc]init];
                playerViewController.player = player;
            [self presentViewController:playerViewController animated:YES completion:nil];
        }else{
            MPMoviePlayerViewController *playerVc = [[MPMoviePlayerViewController alloc]initWithContentURL:videoURL];
                UINavigationController *na = [[UINavigationController alloc]initWithRootViewController:playerVc];
            [self presentViewController:na animated:YES completion:nil];
            }
    }else
        NSLog(@"%@",error);
     self.screenRecorder = nil;
}];
```

