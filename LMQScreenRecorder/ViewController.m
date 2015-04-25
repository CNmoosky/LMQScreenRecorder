//
//  ViewController.m
//  LMQScreenRecorder
//
//  Created by lizhengheng on 2015/4/25.
//  Copyright © 2015 limengqi. All rights reserved.
//

#import "ViewController.h"
#import "LMQScreenRecorder.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVKit/AVKit.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIView *colorView;
@property (weak, nonatomic) IBOutlet UIButton *recoderBtn;
@property(nonatomic,strong)LMQScreenRecorder *screenRecorder;
@property(nonatomic,weak)NSTimer *timer;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    LMQScreenRecorderOption *option = [[LMQScreenRecorderOption alloc]init];
    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"video.mp4"];
    option.outputURL = path;
    self.screenRecorder = [LMQScreenRecorder recorderWithOption:option];
}

- (IBAction)recod:(UIButton *)sender
{
    if (self.screenRecorder.state == LMQScreenRecorderStateRecording) {
        [self.timer invalidate];
        self.timer = nil;
        [sender setTitle:@"录屏" forState:UIControlStateNormal];
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
    }else{
        [sender setTitle:@"停止" forState:UIControlStateNormal];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(changeColor) userInfo:nil repeats:YES];
        [self.screenRecorder startRecordView:self.colorView];
    }
}

- (void)changeColor
{
    self.colorView.backgroundColor = [UIColor colorWithRed:arc4random_uniform(256)/255.0 green:arc4random_uniform(256)/255.0 blue:arc4random_uniform(256)/255.0 alpha:1];
}

@end
