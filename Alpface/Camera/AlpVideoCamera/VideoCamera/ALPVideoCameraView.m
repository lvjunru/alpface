//
//  ALPVideoCameraView.m
//  AlpVideoCamera
//
//  Created by swae on 2018/9/12.
//  Copyright © 2018 xiaoyuan. All rights reserved.
//

#import "ALPVideoCameraView.h"
#import "GPUImageBeautifyFilter.h"
#import "LFGPUImageEmptyFilter.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "AlpEditVideoViewController.h"
#import "SDAVAssetExportSession.h"
#import "TZImagePickerController.h"
#import "TZImageManager.h"
#import <Photos/Photos.h>
#import "GPUImage.h"
#import "AlpVideoCameraDefine.h"
#import "AlpVideoCameraUtils.h"
#import "AlpEditVideoParameter.h"
#import "XYCutVideoController.h"
#import "MBProgressHUD+XYHUD.h"
#import "UIImage+AlpExtensions.h"

/**
 @note GPUImageVideoCamera录制视频 有时第一帧是黑屏 待解决
 */

// 记录分段录制-每录制的视频的数据
@interface AlpSegmentedVideo : NSObject

@property (nonatomic, copy) NSURL *videoURL;
@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, assign) float time;
@property (nonatomic, strong) UIView *thumbView;

@end

typedef NS_ENUM(NSInteger, AlpCameraDevicePosition) {
    AlpCameraDevicePositionBack,
    AlpCameraDevicePositionFront,
};
///闪光灯状态
typedef NS_ENUM(NSInteger, AlpCameraFlashMode) {
    
    //    AlpCameraFlashModeAuto, /**<自动*/
    
    AlpCameraFlashModeOff, /**<关闭*/
    
    AlpCameraFlashModeOn /**<打开*/
};

@interface ALPVideoCameraView () <TZImagePickerControllerDelegate> {
    
    NSString *_pathToMovie;
    CALayer *_focusLayer;
    // 允许录制视频的最大长度 默认20秒
    float _totalTime;
    // 当前视频长度
    float _currentTime;
    NSTimer *_myTimer;
}

@property (nonatomic, strong) GPUImageView *filteredVideoView;
@property (nonatomic, strong) AlpVideoCameraOptionsView *optionsView;
/// 相机
@property (nonatomic, strong) GPUImageVideoCamera *videoCamera;
@property (nonatomic, strong) GPUImageOutput<GPUImageInput> *filter;
// 录制器
@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;
// 是否开启美颜，默认打开
@property (nonatomic, assign) BOOL isOpenBeautifyFilter;
// 闪光灯状态，默认是关闭的，当切换到前置摄像头时关闭闪光灯
@property (nonatomic , assign) AlpCameraFlashMode flashMode;
// 是否在录制中
@property (nonatomic, assign) BOOL isRecoding;
// 前后摄像头状态
@property (nonatomic, assign) AlpCameraDevicePosition cameraPosition;
/// 分段录制时保存录制视频的url，合并时使用
@property (nonatomic, strong) NSMutableArray *segmentedVideos;

@end

@implementation ALPVideoCameraView

- (instancetype) initWithFrame:(CGRect)frame{
    if (self = [super initWithFrame:frame]) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    if (_totalTime ==0 ) {
        _totalTime =AlpVideoRecordingMaxTime;
        
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(closeVideoCameraNotification) name:AlpVideoCameraCloseNotification object:nil];
    
    [AlpVideoCameraUtils createVideoFolderIfNotExist];
    /// 检查相机权限
    AVAuthorizationStatus cameraStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (cameraStatus == AVAuthorizationStatusAuthorized) {
        // 当用户开启相机权限时再创建相机
        // 此时会显示权限视图
        [self createVideoCamera];
    }
    
    [self setupUI];
    
    [AlpVideoCameraUtils getLatestAssetFromAlbum:^(UIImage * _Nonnull image) {
        if (!image) {
            return;
        }
        [self.optionsView.inputLocalVieoBtn setImage:image forState:UIControlStateNormal];
    }];
}

// 创建摄像头
- (void)createVideoCamera {
    if (_videoCamera) {
        return;
    }
    _videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionBack];
    if ([_videoCamera.inputCamera lockForConfiguration:nil]) {
        //自动对焦
        if ([_videoCamera.inputCamera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [_videoCamera.inputCamera setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        //自动曝光
        if ([_videoCamera.inputCamera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [_videoCamera.inputCamera setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        //自动白平衡
        if ([_videoCamera.inputCamera isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
            [_videoCamera.inputCamera setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        }
        
        [_videoCamera.inputCamera unlockForConfiguration];
    }
    
    self.cameraPosition = AlpCameraDevicePositionBack;
    //    videoCamera.frameRate = 10;
    // 输出图像旋转方式
    _videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    _videoCamera.horizontallyMirrorFrontFacingCamera = YES;
    _videoCamera.horizontallyMirrorRearFacingCamera = NO;

    _filter = [[LFGPUImageEmptyFilter alloc] init];
    [_videoCamera addTarget:_filter];
    [_filter addTarget:self.filteredVideoView];
    AVAuthorizationStatus audioStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (audioStatus == AVAuthorizationStatusAuthorized) {
        // 音频状态允许时，才添加视频的输入和输出
        [_videoCamera addAudioInputsAndOutputs];
    }
    self.isOpenBeautifyFilter = YES;
}

- (void)stopCameraCapture {
    [_videoCamera stopCameraCapture];
}
- (void)startCameraCapture {
    [_videoCamera startCameraCapture];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UI
////////////////////////////////////////////////////////////////////////
- (void)setupUI {
    UITapGestureRecognizer *singleFingerOne = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cameraViewTapAction:)];
    singleFingerOne.numberOfTouchesRequired = 1; //手指数
    singleFingerOne.numberOfTapsRequired = 1; //tap次数
    [self.filteredVideoView addGestureRecognizer:singleFingerOne];
    [self addSubview:self.filteredVideoView];
    self.filteredVideoView.translatesAutoresizingMaskIntoConstraints = false;
    [NSLayoutConstraint constraintWithItem:self.filteredVideoView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self.filteredVideoView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0].active = YES;
    
    [NSLayoutConstraint constraintWithItem:self.filteredVideoView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self.filteredVideoView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0].active = YES;
    
    //    253 91 73
    [self.filteredVideoView addSubview:self.optionsView];
    self.optionsView.translatesAutoresizingMaskIntoConstraints = false;
    [NSLayoutConstraint constraintWithItem:self.optionsView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.filteredVideoView attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self.optionsView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.filteredVideoView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self.optionsView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.filteredVideoView attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self.optionsView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.filteredVideoView attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0].active = YES;
    
    [self.optionsView.photoCaptureButton addTarget:self action:@selector(startRecording:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.backBtn addTarget:self action:@selector(clickBack:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.cameraPositionChangeButton addTarget:self action:@selector(changeCameraPositionBtn:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.camerafilterChangeButton addTarget:self action:@selector(changebeautifyFilterBtn:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.cameraChangeButton addTarget:self action:@selector(stopRecording:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.deleteButton addTarget:self action:@selector(clickDleBtn:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.inputLocalVieoBtn addTarget:self action:@selector(clickInputBtn:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.shootingLightingButton addTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    [self.optionsView.permissionView updateHidden];
    __weak typeof(self) weakSelf = self;
    // 请求相机权限的回调，只有摄像头权限允许访问时，才创建相机
    self.optionsView.permissionView.requestCameraAccessBlock = ^(BOOL granted) {
        if (granted) {
            [weakSelf createVideoCamera];
        }
    };
    // 请求麦克风权限的回调，只有麦克风权限允许时才添加音频的输入和输出
    self.optionsView.permissionView.requestAudioAccessBlock = ^(BOOL granted) {
        if (granted) {
            // 该句可防止允许声音通过的情况下，避免录制第一帧黑屏闪屏(====)
            [weakSelf.videoCamera addAudioInputsAndOutputs];
        }
    };
    
    // 初始化闪光灯模式为Auto
    [self setFlashMode:AlpCameraFlashModeOff];
    [self.optionsView.shootingLightingButton setImage:[UIImage alp_videoCameraBundleImageNamed:@"icShootingLightingOff_31x31_"] forState:UIControlStateNormal];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Actions
////////////////////////////////////////////////////////////////////////

/// 开始录制视频
- (void)startRecording:(UIButton*)sender {
    if (!sender.selected) {
        self.optionsView.recordState = AlpVideoCameraRecordStateStart;
        _pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp/Movie%lu.mov",(unsigned long)self.segmentedVideos.count]];
        unlink([_pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
        // 配置录制器
        NSURL *movieURL = [NSURL fileURLWithPath:_pathToMovie];
        _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:movieURL size:CGSizeMake(720.0, 1280.0)];
        //        _movieWriter.isNeedBreakAudioWhiter = YES;
        _movieWriter.encodingLiveVideo = YES;
        _movieWriter.shouldPassthroughAudio = YES;
        
        // 设置录制视频滤镜
        [_filter addTarget:_movieWriter];
        _videoCamera.audioEncodingTarget = _movieWriter;
        // 开始录制
        [_movieWriter startRecording];
        _isRecoding = YES;
        [_myTimer invalidate];
        _myTimer = [NSTimer scheduledTimerWithTimeInterval:TIMER_INTERVAL
                                                    target:self
                                                  selector:@selector(updateTimer:)
                                                  userInfo:nil
                                                   repeats:YES];
        
    }
    else {
        self.optionsView.recordState = AlpVideoCameraRecordStatePause;
        _videoCamera.audioEncodingTarget = nil;
        NSLog(@"Path %@",_pathToMovie);
        if (_pathToMovie == nil) {
            return;
        }
        if (_isRecoding) {
            [_movieWriter finishRecording];
            [_filter removeTarget:_movieWriter];
            // 添加分段录制的url
            NSURL *movieURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@",_pathToMovie]];
            [self addVideoURL:movieURL];
            _isRecoding = NO;
        }
        [_myTimer invalidate];
        _myTimer = nil;
        if (self.segmentedVideos.count) {
            self.optionsView.deleteButton.hidden = NO;
        }
    }
    sender.selected = !sender.isSelected;
}

// 添加分段录制的url
// 防止重复添加分段录制的url，当photoCaptureButton.isSelected==NO时为暂停录制，此时已经将暂停的那一段添加到url了
- (void)addVideoURL:(NSURL *)url {
    NSAssert(url != nil, @"视频路径不能为nil");
    NSUInteger foundIdxInURLArray = [self.segmentedVideos indexOfObjectPassingTest:^BOOL(AlpSegmentedVideo *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        BOOL flag = [obj.videoURL.absoluteString isEqualToString:url.absoluteString];
        if (flag) {
            *stop = YES;
        }
        return flag;
    }];
    if (foundIdxInURLArray == NSNotFound) {
        AlpSegmentedVideo *video = [AlpSegmentedVideo new];
        video.time = _currentTime;
        video.progress = self.optionsView.progressPreView.progress;
        video.videoURL = url;
        [self.segmentedVideos addObject:video];
        
        // 在进度跳上创建一个标识，作为当前这段视频的结尾
        UIView *view = [UIView new];
        view.backgroundColor = [UIColor redColor];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.optionsView.progressPreView addSubview:view];
        video.thumbView = view;
        [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.optionsView.progressPreView attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0].active = YES;
        [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.optionsView.progressPreView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0].active = YES;
        CGFloat viewWidth = 2.0;
        [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:viewWidth].active = YES;
        CGFloat progressWidth = self.optionsView.progressPreView.bounds.size.width * video.progress;
        [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.optionsView.progressPreView attribute:NSLayoutAttributeLeading multiplier:1.0 constant:progressWidth-viewWidth].active = YES;
        
    }
}

/// 停止录制视频
- (void)stopRecording:(id)sender {
    _videoCamera.audioEncodingTarget = nil;
    self.optionsView.recordState = AlpVideoCameraRecordStateDone;
    NSLog(@"Path %@",_pathToMovie);
    if (_pathToMovie == nil) {
        return;
    }
    //    UISaveVideoAtPathToSavedPhotosAlbum(_pathToMovie, nil, nil, nil);
    if (_isRecoding) {
        [_movieWriter finishRecording];
        [_filter removeTarget:_movieWriter];
        _isRecoding = NO;
    }
    
    [self.optionsView.timeButton setTitle:@"录制 00:00" forState:UIControlStateNormal];
    [_myTimer invalidate];
    _myTimer = nil;
    [MBProgressHUD xy_hideHUD];
    [MBProgressHUD xy_showActivityMessage:@"视频生成中..."];
    
    
    // 添加分段录制的视频url
    NSURL *movieURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@",_pathToMovie]];
    [self addVideoURL:movieURL];
    
    NSString *outPath = [AlpVideoCameraUtils getVideoMergeFilePathString];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __weak typeof(self) weakSelf = self;
        __weak typeof(self->_videoCamera) weakVideoCamera = self->_videoCamera;
        NSMutableArray *urls = @[].mutableCopy;
        for (AlpSegmentedVideo *video in self.segmentedVideos) {
            [urls addObject:video.videoURL];
        }
        
        
        [AlpVideoCameraUtils mergeVideos:urls exportPath:outPath watermarkImg: nil/*[UIImage alp_videoCameraBundleImageNamed:@"icon_watermark"]*/ completion:^(NSURL * _Nonnull outLocalURL) {
            [weakVideoCamera stopCameraCapture];
            
            AlpEditVideoViewController* vc = [[AlpEditVideoViewController alloc]init];
            vc.videoOptions = weakSelf.videoOptions;
            vc.videoURL = outLocalURL;
            [[NSNotificationCenter defaultCenter] removeObserver:weakSelf];
            [MBProgressHUD xy_hideHUD];
            if (weakSelf.delegate&&[weakSelf.delegate respondsToSelector:@selector(videoCamerView:pushViewCotroller:)]) {
                [weakSelf.delegate videoCamerView:weakSelf pushViewCotroller:vc];
            }
            [weakSelf removeFromSuperview];
            [self removeAllSegmentedVideos];
        }];
        
        self.optionsView.recordState = AlpVideoCameraRecordStateDone;
    });
    
    
    
    
    //    http://blog.csdn.net/ismilesky/article/details/51920113  视频与音乐合成
    //    http://www.jianshu.com/p/0f9789a6d99a 视频与音乐合成
    
    //[_movieWriter cancelRecording];
}


- (void)clickDleBtn:(UIButton*)sender {
    [self removeLastSegementedVideo];
}

/// 删除最后一段录制的内容
- (void)removeLastSegementedVideo {
    AlpSegmentedVideo *video = [self.segmentedVideos lastObject];
    if (!video) {
        self.optionsView.deleteButton.hidden = YES;
        self.optionsView.cameraChangeButton.hidden = YES;
        _currentTime = 0.0;
        [self.optionsView.progressPreView cancelProgress];
        self.optionsView.recordState = AlpVideoCameraRecordStateNotStart;
    }
    else {
        [video.thumbView removeFromSuperview];
        [self.optionsView.progressPreView removeConstraints:video.thumbView.constraints];
        [self.segmentedVideos removeObject:video];
        
        // 更新当前时间
        AlpSegmentedVideo *lastVideo = [self.segmentedVideos lastObject];
        _currentTime = lastVideo.time;
        [self.optionsView.progressPreView setProgress:lastVideo.progress animated:YES];
        if (_currentTime < 3) {
            self.optionsView.cameraChangeButton.hidden = YES;
        }
        
        if (!lastVideo) {
            self.optionsView.recordState = AlpVideoCameraRecordStateNotStart;
        }
    }
    [self.optionsView.timeButton setTitle:[NSString stringWithFormat:@"录制 00:0%.0f",_currentTime] forState:UIControlStateNormal];
}

- (void)removeAllSegmentedVideos {
    for (NSInteger i = 0; i < self.segmentedVideos.count; i++) {
        [self removeLastSegementedVideo];
    }
}

/// 从相册中导入视频
- (void)clickInputBtn:(UIButton*)sender {
    TZImagePickerController* imagePickerVc = [[TZImagePickerController alloc] initWithMaxImagesCount:1 delegate:self];
    imagePickerVc.isSelectOriginalPhoto = NO;
    imagePickerVc.allowTakePicture = NO;
    imagePickerVc.allowTakeVideo = NO;
    imagePickerVc.allowPickingImage = NO;
    imagePickerVc.allowPickingGif = NO;
    imagePickerVc.sortAscendingByModificationDate = YES;
//    imagePickerVc.autoDismiss = NO;
    __weak typeof(self) weakSelf = self;
    imagePickerVc.pickerDelegate = self;
    [imagePickerVc setDidFinishPickingVideoHandle:^(UIImage *coverImage,id asset) {
        [MBProgressHUD xy_hideHUD];
        [MBProgressHUD xy_showActivityMessage:@"视频导出中..."];
        if ([UIDevice currentDevice].systemVersion.floatValue >= 8.0f) {
            PHAsset* myasset = asset;
            PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
            //            options.version = PHImageRequestOptionsVersionCurrent;
            options.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
            options.version = PHImageRequestOptionsVersionCurrent;
            options.networkAccessAllowed = true; // iCloud的相册需要网络许可，否则icloud中的取出为nil
            PHImageManager *manager = [PHImageManager defaultManager];
            [manager requestAVAssetForVideo:myasset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
                if(![asset isKindOfClass:[AVURLAsset class]]){
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    AVURLAsset *urlAsset = (AVURLAsset *)asset;
                    NSURL *url = urlAsset.URL;
                    NSData* videoData = [NSData dataWithContentsOfFile:[[url absoluteString ] stringByReplacingOccurrencesOfString:@"file://" withString:@""]];
                    if (videoData.length/1024/1024>AlpVideoCameraMaxVideoSize) {
                        [MBProgressHUD xy_hideHUD];
                        [MBProgressHUD xy_showMessage:[NSString stringWithFormat:@"所选视频大于%1.fM,请重新选择", AlpVideoCameraMaxVideoSize] delayTime:1.5];
                    }
                    else {
                        [MBProgressHUD xy_hideHUD];
                        XYCutVideoController *vc = [XYCutVideoController  new];
                        vc.videoURL = url;
                        vc.videoOptions = weakSelf.videoOptions;
                        [[NSNotificationCenter defaultCenter] removeObserver:self];
                        [_videoCamera stopCameraCapture];
                        if (weakSelf.delegate&&[weakSelf.delegate respondsToSelector:@selector(videoCamerView:pushViewCotroller:)]) {
                            [weakSelf.delegate videoCamerView:weakSelf pushViewCotroller:vc];
                        }
                        [weakSelf removeFromSuperview];
                        
                    }
                });
                
            }];
        }
        else  {
            dispatch_async(dispatch_get_main_queue(), ^{
                ALAsset* myasset = asset;
                NSURL *videoURL =[myasset valueForProperty:ALAssetPropertyAssetURL];
                NSURL *url = videoURL;
                NSData* videoData = [NSData dataWithContentsOfFile:[[url absoluteString ] stringByReplacingOccurrencesOfString:@"file://" withString:@""]];
                if (videoData.length/1024/1024>AlpVideoCameraMaxVideoSize) {
                    [MBProgressHUD xy_hideHUD];
                    [MBProgressHUD xy_showMessage:[NSString stringWithFormat:@"所选视频大于%1.fM,请重新选择", AlpVideoCameraMaxVideoSize] delayTime:1.5];
                }
                else {
                    [MBProgressHUD xy_hideHUD];
                    XYCutVideoController *vc = [XYCutVideoController  new];
                    vc.videoURL = url;
                    vc.videoOptions = weakSelf.videoOptions;
                    [[NSNotificationCenter defaultCenter] removeObserver:self];
                    [_videoCamera stopCameraCapture];
                    if (weakSelf.delegate&&[weakSelf.delegate respondsToSelector:@selector(videoCamerView:pushViewCotroller:)]) {
                        [weakSelf.delegate videoCamerView:weakSelf pushViewCotroller:vc];
                    }
                    [weakSelf removeFromSuperview];
                }
                
            });
        }
        
    }];
    
    
    [[UIApplication sharedApplication] setStatusBarHidden:NO];
    [MBProgressHUD xy_hideHUD];
    if (self.delegate&&[self.delegate respondsToSelector:@selector(videoCamerView:presentViewCotroller:)]) {
        [self.delegate videoCamerView:self presentViewCotroller:imagePickerVc];
    }
    
}

/// 退出
- (void)clickBack:(UIButton *)btn {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_videoCamera stopCameraCapture];
    if (_isRecoding) {
        [_movieWriter cancelRecording];
        [_filter removeTarget:_movieWriter];
        _isRecoding = NO;
    }
    [_myTimer invalidate];
    _myTimer = nil;
    if (self.delegate && [self.delegate respondsToSelector:@selector(videoCamerView:didClickBackButton:)]) {
        [self.delegate videoCamerView:self didClickBackButton:btn];
        [self removeFromSuperview];
    }
}

/// 切换前后摄像头
- (void)changeCameraPositionBtn:(UIButton*)sender {
    switch (self.cameraPosition) {
        case AlpCameraDevicePositionBack: {
            if (_videoCamera.cameraPosition == AVCaptureDevicePositionBack) {
                [_videoCamera pauseCameraCapture];
                self.cameraPosition = AlpCameraDevicePositionFront;
                [_videoCamera rotateCamera];
                [_videoCamera resumeCameraCapture];
            }
        }
            break;
        case AlpCameraDevicePositionFront: {
            if (_videoCamera.cameraPosition == AVCaptureDevicePositionFront) {
                [_videoCamera pauseCameraCapture];
                self.cameraPosition = AlpCameraDevicePositionBack;
                [_videoCamera rotateCamera];
                [_videoCamera resumeCameraCapture];
            }
        }
            break;
        default:
            break;
    }
    
    if ([_videoCamera.inputCamera lockForConfiguration:nil] && [_videoCamera.inputCamera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        [_videoCamera.inputCamera setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        [_videoCamera.inputCamera unlockForConfiguration];
    }
    
    // 重置下美颜
    self.isOpenBeautifyFilter = self.isOpenBeautifyFilter;
    sender.selected = !sender.isSelected;
}

/// 打开或关闭美颜功能
- (void)changebeautifyFilterBtn:(UIButton*)sender {
    sender.selected = !sender.isSelected;
    self.isOpenBeautifyFilter = !sender.isSelected;
}

- (void)setIsOpenBeautifyFilter:(BOOL)isOpenBeautifyFilter {
    _isOpenBeautifyFilter = isOpenBeautifyFilter;
    if (isOpenBeautifyFilter) {
        [_videoCamera removeAllTargets];
        _filter = [[GPUImageBeautifyFilter alloc] init];
        [_videoCamera addTarget:_filter];
        [_filter addTarget:_filteredVideoView];
    }
    else {
        [_videoCamera removeAllTargets];
        _filter = [[LFGPUImageEmptyFilter alloc] init];
        [_videoCamera addTarget:_filter];
        [_filter addTarget:_filteredVideoView];
    }
}

//设置闪光灯模式

- (void)setFlashMode:(AlpCameraFlashMode)flashMode {
    _flashMode = flashMode;
    
    switch (flashMode) {
            //        case AlpCameraFlashModeAuto: {
            //            NSError *error = nil;
            //            if ([_videoCamera.inputCamera hasTorch]) {
            //                BOOL locked = [_videoCamera.inputCamera lockForConfiguration:&error];
            //                if (locked) {
            //                    _videoCamera.inputCamera.torchMode = AVCaptureTorchModeAuto;
            //                    [_videoCamera.inputCamera unlockForConfiguration];
            //                }
            //            }
            //            [_videoCamera.inputCamera unlockForConfiguration];
            //        }
            //            break;
        case AlpCameraFlashModeOff: {
            [self.optionsView.shootingLightingButton setImage:[UIImage alp_videoCameraBundleImageNamed:@"icShootingLightingOff_31x31_"] forState:UIControlStateNormal];
            AVCaptureDevice *device = _videoCamera.inputCamera;
            if ([device hasTorch]) {
                [device lockForConfiguration:nil];
                [device setTorchMode:AVCaptureTorchModeOff];
                [device unlockForConfiguration];
            }
        }
            
            break;
        case AlpCameraFlashModeOn: {
            [self.optionsView.shootingLightingButton setImage:[UIImage alp_videoCameraBundleImageNamed:@"icShootingLightingOn_31x31_"] forState:UIControlStateNormal];
            NSError *error = nil;
            if ([_videoCamera.inputCamera hasTorch]) {
                BOOL locked = [_videoCamera.inputCamera lockForConfiguration:&error];
                if (locked) {
                    _videoCamera.inputCamera.torchMode = AVCaptureTorchModeOn;
                    [_videoCamera.inputCamera unlockForConfiguration];
                }
                
            }
            
        }
            break;
            
        default:
            break;
    }
}

/// 改变闪光灯状态
- (void)changeFlashMode:(UIButton *)button {
    switch (self.flashMode) {
            //        case AlpCameraFlashModeAuto:
            //            self.flashMode = AlpCameraFlashModeOn;
            //            [button setImage:[UIImage alp_videoCameraBundleImageNamed:@"icShootingLightingOn_31x31_"] forState:UIControlStateNormal];
            //            break;
        case AlpCameraFlashModeOff:
            //            self.flashMode = AlpCameraFlashModeAuto;
            self.flashMode = AlpCameraFlashModeOn;
            break;
        case AlpCameraFlashModeOn:
            self.flashMode = AlpCameraFlashModeOff;
            break;
            
        default:
            break;
    }
}

/// 录制时timer更新UI
- (void)updateTimer:(NSTimer *)sender{
    
    _currentTime += TIMER_INTERVAL;
    
    if (_currentTime>=10) {
        [self.optionsView.timeButton setTitle:[NSString stringWithFormat:@"录制 00:%d",(int)_currentTime] forState:UIControlStateNormal];     }
    else {
        [self.optionsView.timeButton setTitle:[NSString stringWithFormat:@"录制 00:0%.0f",_currentTime] forState:UIControlStateNormal];
    }
    
    [self.optionsView.progressPreView setProgress:_currentTime/_totalTime animated:YES];
    if (_currentTime>3) {
        self.optionsView.cameraChangeButton.hidden = NO;
    }
    
    // 时间到了停止录制视频
    if (_currentTime>=_totalTime) {
        
        self.optionsView.photoCaptureButton.enabled = NO;
        
        [self stopRecording:nil];
    }
}

/// 设置相机对焦的layer
- (void)setfocusImage {
    UIImage *focusImage = [UIImage alp_videoCameraBundleImageNamed:@"96"];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, focusImage.size.width, focusImage.size.height)];
    imageView.image = focusImage;
    CALayer *layer = imageView.layer;
    layer.hidden = YES;
    [_filteredVideoView.layer addSublayer:layer];
    _focusLayer = layer;
    
}

- (void)setCameraPosition:(AlpCameraDevicePosition)cameraPosition {
    _cameraPosition = cameraPosition;
    self.flashMode = AlpCameraFlashModeOff;
    if (cameraPosition == AlpCameraDevicePositionFront) {
        self.optionsView.shootingLightingButton.hidden = YES;
    }
    else {
        self.optionsView.shootingLightingButton.hidden = NO;
    }
}

- (void)layerAnimationWithPoint:(CGPoint)point {
    if (_focusLayer) {
        CALayer *focusLayer = _focusLayer;
        focusLayer.hidden = NO;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [focusLayer setPosition:point];
        focusLayer.transform = CATransform3DMakeScale(2.0f,2.0f,1.0f);
        [CATransaction commit];
        
        
        CABasicAnimation *animation = [ CABasicAnimation animationWithKeyPath: @"transform" ];
        animation.toValue = [ NSValue valueWithCATransform3D: CATransform3DMakeScale(1.0f,1.0f,1.0f)];
        //        animation.delegate = self;
        animation.duration = 0.3f;
        animation.repeatCount = 1;
        animation.removedOnCompletion = NO;
        animation.fillMode = kCAFillModeForwards;
        [focusLayer addAnimation: animation forKey:@"animation"];
        
        // 0.5秒钟延时
        [self performSelector:@selector(focusLayerNormal) withObject:self afterDelay:0.5f];
    }
}
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
    
}


- (void)focusLayerNormal {
    _filteredVideoView.userInteractionEnabled = YES;
    _focusLayer.hidden = YES;
}

/// 点击相机对焦
- (void)cameraViewTapAction:(UITapGestureRecognizer *)tgr {
    if (tgr.state == UIGestureRecognizerStateRecognized && (_focusLayer == nil || _focusLayer.hidden)) {
        CGPoint location = [tgr locationInView:_filteredVideoView];
        [self setfocusImage];
        [self layerAnimationWithPoint:location];
        AVCaptureDevice *device = _videoCamera.inputCamera;
        //        CGPoint pointOfInterest = CGPointMake(0.5f, 0.5f);
        //        NSLog(@"taplocation x = %f y = %f", location.x, location.y);
        //        CGSize frameSize = [_filteredVideoView frame].size;
        //
        //        if ([videoCamera cameraPosition] == AVCaptureDevicePositionFront) {
        //            location.x = frameSize.width - location.x;
        //        }
        //
        //        pointOfInterest = CGPointMake(location.y / frameSize.height, 1.f - (location.x / frameSize.width));
        CGPoint pointOfInterest = [AlpVideoCameraUtils convertToPointOfInterestFromViewCoordinates:location frameSize:_filteredVideoView.frame.size];
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            
            if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                [device setFocusPointOfInterest:pointOfInterest];
                [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                
            }
            
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            {
                [device setExposurePointOfInterest:pointOfInterest];
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            }
            
            [device unlockForConfiguration];
            
            NSLog(@"FOCUS OK");
        } else {
            NSLog(@"ERROR = %@", error);
        }
    }
}
- (void)closeVideoCameraNotification {
    [self clickBack:nil];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - TZImagePickerControllerDelegate
////////////////////////////////////////////////////////////////////////
- (void)tz_imagePickerControllerDidCancel:(TZImagePickerController *)picker {
    [picker dismissViewControllerAnimated:NO completion:nil];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Getter
////////////////////////////////////////////////////////////////////////

- (AlpVideoCameraOptionsView *)optionsView {
    if (!_optionsView) {
        _optionsView = [AlpVideoCameraOptionsView new];
    }
    return _optionsView;
}

- (GPUImageView *)filteredVideoView {
    if (!_filteredVideoView) {
        // 创建摄像头显示视图
        _filteredVideoView = [[GPUImageView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        // 显示模式充满整个边框
        _filteredVideoView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
        _filteredVideoView.clipsToBounds = YES;
        [_filteredVideoView.layer setMasksToBounds:YES];
    }
    return _filteredVideoView;
}

- (NSMutableArray *)segmentedVideos {
    if (!_segmentedVideos) {
        _segmentedVideos = @[].mutableCopy;
    }
    return _segmentedVideos;
}

- (void)dealloc {
    NSLog(@"%@释放了",self.class);
    [_videoCamera stopCameraCapture];
    _videoCamera = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end


@implementation AlpSegmentedVideo
@end
