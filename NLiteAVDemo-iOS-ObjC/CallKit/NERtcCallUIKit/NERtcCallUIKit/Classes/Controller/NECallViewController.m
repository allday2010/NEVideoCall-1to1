// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

#import "NECallViewController.h"
#import <NECommonKit/NECommonKit-Swift.h>
#import <NECommonUIKit/UIView+YXToast.h>
#import <NECoreKit/YXModel.h>
#import <SDWebImage/SDWebImage.h>
#include <mach/mach_time.h>
#import "NECallUIStateController.h"
#import "NECustomButton.h"
#import "NEExpandButton.h"
#import "NERtcCallUIKit.h"
#import "NEVideoOperationView.h"
#import "NetManager.h"

NSString *const kCallKitDismissNoti = @"kCallKitDismissNoti";

NSString *const kCallKitShowNoti = @"kCallKitShowNoti";

@interface NECallViewController () <NERtcLinkEngineDelegate>

@property(nonatomic, strong) UIButton *switchCameraBtn;

@property(strong, nonatomic) NEVideoOperationView *operationView;

@property(strong, nonatomic) UILabel *timerLabel;

@property(strong, nonatomic) NSTimer *timer;

@property(strong, nonatomic) UIImageView *blurImage;

@property(strong, nonatomic) UIToolbar *toolBar;

@property(assign, nonatomic) int timerCount;

@property(nonatomic, strong) UIView *bannerView;

@property(nonatomic, weak) UIAlertController *alert;

@property(nonatomic, strong) UILabel *cnameLabel;

@property(assign, nonatomic) CGFloat factor;

/// 通话状态视图
@property(nonatomic, strong) NEAudioCallingController *audioCallingController;

@property(nonatomic, strong) NEAudioInCallController *audioInCallController;

@property(nonatomic, strong) NEVideoCallingController *videoCallingController;

@property(nonatomic, strong) NEVideoInCallController *videoInCallController;

@property(nonatomic, strong) NECalledViewController *calledController;

@property(nonatomic, weak) NECallUIStateController *stateUIController;

@property(nonatomic, strong) NSBundle *bundle;

/// 上次点击时间
@property(nonatomic, assign) double lastClickTime;

/// 点击限制间隔时间
@property(nonatomic, assign) double clickDuration;

@end

@implementation NECallViewController

- (instancetype)init {
  self = [super init];
  if (self) {
    self.timerCount = 0;
    self.factor = 1.0;
    self.bundle = [NSBundle bundleForClass:NECallViewController.class];
    self.clickDuration = 500;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [[NSNotificationCenter defaultCenter] postNotificationName:kCallKitShowNoti object:nil];
  [[NERtcEngine sharedEngine] setParameters:@{kNERtcKeyVideoStartWithBackCamera : @NO}];
  [self setupCommon];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  [[NECallEngine sharedInstance] setupLocalView:nil];
}

#pragma mark - SDK

- (void)setupCommon {
  [self setupUI];
  [self setupSDK];
  [self updateUIonStatus:self.status];
  if (self.callParam.isCaller == NO &&
      [NECallEngine sharedInstance].callStatus == NERtcCallStatusIdle) {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf destroy];
    });
  }

  [self.view addSubview:self.bannerView];
  [NSLayoutConstraint activateConstraints:@[
    [self.bannerView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:80],
    [self.bannerView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor constant:20],
    [self.bannerView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor constant:-20],
    [self.bannerView.heightAnchor constraintEqualToConstant:40]
  ]];
}

- (void)setupSDK {
  [[NECallEngine sharedInstance] addCallDelegate:self];
  [[NECallEngine sharedInstance] enableLocalVideo:YES];

  __weak typeof(self) weakSelf = self;
  if (self.status == NERtcCallStatusCalling) {
    NECallParam *param = [[NECallParam alloc] initWithAccId:self.callParam.remoteUserAccid
                                               withCallType:self.callParam.callType];
    param.globalExtraCopy = self.callParam.extra;
    param.rtcChannelName = self.callParam.channelName;
    param.extraInfo = self.callParam.attachment;
    param.pushConfig = self.callParam.pushConfig;

    [[NECallEngine sharedInstance]
              call:param
        completion:^(NSError *_Nullable error, NECallInfo *_Nullable callInfo) {
          NSLog(@"callkit call callback ne call info : %@", [callInfo yx_modelToJSONString]);
          if (weakSelf.callParam.callType == NERtcCallTypeVideo) {
            if ([self isGlobalInit] == YES) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [[NECallEngine sharedInstance]
                    setupLocalView:weakSelf.videoCallingController.bigVideoView.videoView];
              });
            }
            weakSelf.videoCallingController.bigVideoView.userID =
                weakSelf.callParam.currentUserAccid;
          }

          if (error) {
            /// 对方离线时 通过APNS推送 UI不弹框提示
            if (error.code == NIMRemoteErrorCodeSignalResPeerPushOffline ||
                error.code == NIMRemoteErrorCodeSignalResPeerNIMOffline) {
              return;
            } else {
              [weakSelf destroy];
            }
            [UIApplication.sharedApplication.keyWindow ne_makeToast:error.localizedDescription];
          }
        }];
  }
}

#pragma mark - UI

- (void)setupUI {
  if (self.view.frame.size.height < 600) {
    self.factor = 0.5;
  }

  CGSize buttonSize = CGSizeMake(75, 103);
  CGFloat statusHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;

  self.blurImage = [[UIImageView alloc] init];
  self.blurImage.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.blurImage];
  [NSLayoutConstraint activateConstraints:@[
    [self.blurImage.leftAnchor constraintEqualToAnchor:self.view.leftAnchor],
    [self.blurImage.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
    [self.blurImage.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.blurImage.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];

  if (self.callParam.remoteAvatar.length <= 0) {
    UIView *cover = [self getDefaultHeaderView:self.callParam.remoteUserAccid
                                          font:[UIFont systemFontOfSize:200]
                                      showName:self.callParam.remoteShowName];
    [self.blurImage addSubview:cover];
    [NSLayoutConstraint activateConstraints:@[
      [cover.leftAnchor constraintEqualToAnchor:self.blurImage.leftAnchor],
      [cover.rightAnchor constraintEqualToAnchor:self.blurImage.rightAnchor],
      [cover.topAnchor constraintEqualToAnchor:self.blurImage.topAnchor],
      [cover.bottomAnchor constraintEqualToAnchor:self.blurImage.bottomAnchor]
    ]];
  }

  self.toolBar = [[UIToolbar alloc] initWithFrame:self.view.bounds];
  self.toolBar.barStyle = UIBarStyleBlackOpaque;
  [self.blurImage addSubview:self.toolBar];

  [self setupChildController];

  [self.view addSubview:self.switchCameraBtn];
  [NSLayoutConstraint activateConstraints:@[
    [self.switchCameraBtn.topAnchor constraintEqualToAnchor:self.view.topAnchor
                                                   constant:statusHeight + 20],
    [self.switchCameraBtn.leftAnchor constraintEqualToAnchor:self.view.leftAnchor constant:20],
    [self.switchCameraBtn.heightAnchor constraintEqualToConstant:30],
    [self.switchCameraBtn.widthAnchor constraintEqualToConstant:30]
  ]];

  [self.view addSubview:self.operationView];
  [NSLayoutConstraint activateConstraints:@[
    [self.operationView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.operationView.heightAnchor constraintEqualToConstant:60],
    [self.operationView.widthAnchor constraintEqualToConstant:self.view.frame.size.width * 0.8],
    [self.operationView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
                                                    constant:-50.0 * self.factor]
  ]];

  /// 未接通状态下的音视频切换按钮
  self.mediaSwitchBtn = [[NECustomButton alloc] init];
  self.mediaSwitchBtn.maskBtn.accessibilityIdentifier = @"inCallSwitch";

  [self.view addSubview:self.mediaSwitchBtn];
  [NSLayoutConstraint activateConstraints:@[
    [self.mediaSwitchBtn.centerXAnchor constraintEqualToAnchor:self.operationView.centerXAnchor],
    [self.mediaSwitchBtn.bottomAnchor constraintEqualToAnchor:self.operationView.topAnchor
                                                     constant:-150 * self.factor],
    [self.mediaSwitchBtn.heightAnchor constraintEqualToConstant:buttonSize.height],
    [self.mediaSwitchBtn.widthAnchor constraintEqualToConstant:buttonSize.width]
  ]];

  self.mediaSwitchBtn.hidden = YES;

  [self.mediaSwitchBtn.maskBtn addTarget:self
                                  action:@selector(mediaClick:)
                        forControlEvents:UIControlEventTouchUpInside];

  [self.view addSubview:self.timerLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.timerLabel.centerYAnchor constraintEqualToAnchor:self.switchCameraBtn.centerYAnchor],
    [self.timerLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
  ]];
}

#pragma mark - inner function

- (void)setCallingTypeSwith:(BOOL)show {
  if (show == YES && self.config.showCallingSwitchCallType == YES) {
    if ([self isSupportAutoJoinWhenCalled] == YES) {
      self.mediaSwitchBtn.hidden = NO;
    } else {
      self.mediaSwitchBtn.hidden = YES;
    }
  } else {
    self.mediaSwitchBtn.hidden = YES;
  }
}

- (void)setupChildController {
  if (self.callParam.isCaller == YES) {
    [self addChildViewController:self.videoCallingController];
    [self.view addSubview:self.videoCallingController.view];
    [self addChildViewController:self.audioCallingController];
    [self.view addSubview:self.audioCallingController.view];
  } else {
    [self addChildViewController:self.calledController];
    [self.view addSubview:self.calledController.view];
  }

  [self addChildViewController:self.audioInCallController];
  [self.view addSubview:self.audioInCallController.view];
  [self addChildViewController:self.videoInCallController];
  [self.view addSubview:self.videoInCallController.view];
}

- (void)setSwitchAudioStyle {
  self.mediaSwitchBtn.imageView.image = [UIImage imageNamed:@"switch_audio"
                                                   inBundle:self.bundle
                              compatibleWithTraitCollection:nil];
  self.mediaSwitchBtn.titleLabel.text = [self localizableWithKey:@"switch_to_audio"];
  self.mediaSwitchBtn.tag = NERtcCallTypeAudio;
  [self showVideoView];
  [self setUrl:self.callParam.remoteAvatar withPlaceholder:@"avator"];
  [self.stateUIController refreshUI];
}

- (void)setSwitchVideoStyle {
  self.mediaSwitchBtn.imageView.image = [UIImage imageNamed:@"switch_video"
                                                   inBundle:self.bundle
                              compatibleWithTraitCollection:nil];
  self.mediaSwitchBtn.titleLabel.text = [self localizableWithKey:@"switch_to_video"];
  self.mediaSwitchBtn.tag = NERtcCallTypeVideo;
  [self hideVideoView];
  [self setUrl:self.callParam.remoteAvatar withPlaceholder:@"avator"];
  [self.stateUIController refreshUI];
}

- (void)updateUIonStatus:(NERtcCallStatus)status {
  switch (status) {
    case NERtcCallStatusCalling: {
      [self setCallingTypeSwith:YES];
      self.operationView.hidden = YES;
      self.stateUIController.view.hidden = YES;
      if (self.callParam.callType == NECallTypeVideo) {
        self.stateUIController = self.videoCallingController;
        [self.videoCallingController refreshUI];
        [self setSwitchAudioStyle];

      } else {
        self.stateUIController = self.audioCallingController;
        [self setSwitchVideoStyle];
      }
      self.stateUIController.view.hidden = NO;

    } break;
    case NERtcCallStatusCalled: {
      [self setCallingTypeSwith:YES];
      self.operationView.hidden = YES;
      self.stateUIController.view.hidden = YES;
      self.stateUIController = self.calledController;
      self.stateUIController.view.hidden = NO;
      [self.calledController refreshUI];
      if (self.callParam.callType == NECallTypeVideo) {
        self.mediaSwitchBtn.imageView.image = [UIImage imageNamed:@"switch_audio"
                                                         inBundle:self.bundle
                                    compatibleWithTraitCollection:nil];
        self.mediaSwitchBtn.titleLabel.text = [self localizableWithKey:@"switch_to_audio"];
        [self setSwitchAudioStyle];
      } else {
        self.mediaSwitchBtn.imageView.image = [UIImage imageNamed:@"switch_video"
                                                         inBundle:self.bundle
                                    compatibleWithTraitCollection:nil];
        self.mediaSwitchBtn.titleLabel.text = [self localizableWithKey:@"switch_to_video"];
        [self setSwitchVideoStyle];
      }
      __weak typeof(self) weakSelf = self;
      [self.calledController.remoteBigAvatorView
          sd_setImageWithURL:[NSURL URLWithString:self.callParam.remoteAvatar]
                   completed:^(UIImage *_Nullable image, NSError *_Nullable error,
                               SDImageCacheType cacheType, NSURL *_Nullable imageURL) {
                     if (image == nil) {
                       image = [UIImage imageNamed:@"avator"
                                                inBundle:weakSelf.bundle
                           compatibleWithTraitCollection:nil];
                     }
                     if (weakSelf.callParam.isCaller == false &&
                         weakSelf.callParam.callType == NECallTypeVideo) {
                       [weakSelf.blurImage setHidden:NO];
                     }
                     weakSelf.blurImage.image = image;
                   }];

    } break;
    case NERtcCallStatusInCall: {
      [self setCallingTypeSwith:NO];
      self.operationView.hidden = NO;
      self.stateUIController.view.hidden = YES;
      if (self.callParam.callType == NECallTypeVideo) {
        self.stateUIController = self.videoInCallController;
        self.switchCameraBtn.hidden = NO;
        self.isRemoteMute = NO;
        self.videoInCallController.operationView.cameraBtn.selected = NO;
        self.videoInCallController.smallVideoView.imageView.hidden = YES;
        self.videoInCallController.bigVideoView.imageView.hidden = YES;
        [self.videoInCallController refreshUI];
        if (self.callParam.enableVideoToAudio == NO) {
          [self.operationView removeMediaBtn];
        }
      } else {
        [self.operationView changeAudioStyle];
        self.stateUIController = self.audioInCallController;
        self.switchCameraBtn.hidden = YES;
        if (self.callParam.enableAudioToVideo == NO) {
          [self.operationView removeMediaBtn];
        }
      }
      self.stateUIController.view.hidden = NO;

    } break;
    default:
      break;
  }
  self.status = status;
}

- (void)showVideoView {
  if (self.status == NERtcCallStatusCalling) {
    [[NECallEngine sharedInstance]
        setupLocalView:self.videoCallingController.bigVideoView.videoView];
  }
  if (self.status == NERtcCallStatusInCall) {
    [[NECallEngine sharedInstance]
        setupLocalView:self.videoInCallController.smallVideoView.videoView];
    [[NECallEngine sharedInstance]
        setupRemoteView:self.videoInCallController.bigVideoView.videoView];
  }

  [[NECallEngine sharedInstance] muteLocalVideo:NO];
  [[NECallEngine sharedInstance] muteLocalAudio:NO];
  self.operationView.microPhone.selected = NO;
  self.operationView.cameraBtn.selected = NO;

  self.operationView.speakerBtn.selected = NO;
  self.operationView.microPhone.selected = NO;
  [[NERtcEngine sharedEngine] setLoudspeakerMode:YES];
  [[NERtcEngine sharedEngine] muteLocalAudio:NO];
}

- (void)hideVideoView {
  [[NECallEngine sharedInstance] setupLocalView:nil];
  [[NECallEngine sharedInstance] setupRemoteView:nil];
  self.operationView.speakerBtn.selected = YES;
  self.operationView.microPhone.selected = NO;
  [[NERtcEngine sharedEngine] setLoudspeakerMode:NO];
  [[NERtcEngine sharedEngine] muteLocalAudio:NO];
}

#pragma mark - event

//- (void)closeEvent:(UIButton *)button {
//    __weak typeof(self) weakSelf = self;
//
//  NEHangupParam *param = [[NEHangupParam alloc] init];
//  [[NECallEngine sharedInstance] hangup:param
//                             completion:^(NSError *_Nullable error){
//                                if (error != nil && error.code == CurrentStatusNotSupport) {
//                                    [weakSelf destroy];
//                                }
//                             }];
//}

- (void)cancelEvent:(UIButton *)button {
  __weak typeof(self) weakSelf = self;
  NSLog(@"cancel rtc");
  if ([[NetManager shareInstance] isClose] == YES) {
    [self destroy];
  }
  NEHangupParam *param = [[NEHangupParam alloc] init];
  [[NECallEngine sharedInstance] hangup:param
                             completion:^(NSError *_Nullable error) {
                               NSLog(@"cancel error %@", error);
                               button.enabled = YES;
                               [weakSelf destroy];
                             }];
}

- (void)rejectEvent:(UIButton *)button {
  if ([[NetManager shareInstance] isClose] == YES) {
    [self destroy];
  }
  self.calledController.acceptBtn.userInteractionEnabled = NO;
  __weak typeof(self) weakSelf = self;

  NEHangupParam *param = [[NEHangupParam alloc] init];
  [[NECallEngine sharedInstance] hangup:param
                             completion:^(NSError *_Nullable error) {
                               weakSelf.calledController.acceptBtn.userInteractionEnabled = YES;
                               [weakSelf destroy];
                             }];
}

- (void)acceptEvent:(UIButton *)button {
  if ([[NetManager shareInstance] isClose] == YES) {
    [self.view ne_makeToast:[self localizableWithKey:@"network_error"]];
    return;
  }

  self.calledController.rejectBtn.userInteractionEnabled = NO;
  self.calledController.acceptBtn.userInteractionEnabled = NO;
  __weak typeof(self) weakSelf = self;

  [[NECallEngine sharedInstance] accept:^(NSError *_Nullable error,
                                          NECallInfo *_Nullable callInfo) {
    weakSelf.calledController.rejectBtn.userInteractionEnabled = YES;
    weakSelf.calledController.acceptBtn.userInteractionEnabled = YES;
    if (error) {
      if (error.code != 10420) {
        [UIApplication.sharedApplication.keyWindow
            ne_makeToast:[NSString stringWithFormat:@"%@ %@",
                                                    [weakSelf localizableWithKey:@"accept_failed"],
                                                    error.localizedDescription]];
      }
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       [weakSelf destroy];
                     });
    } else {
      [weakSelf updateUIonStatus:NERtcCallStatusInCall];
      [weakSelf startTimer];
    }
  }];
}

- (void)switchCameraBtn:(UIButton *)button {
  [[NECallEngine sharedInstance] switchCamera];
  button.selected = !button.selected;
  if (button.isSelected == YES) {
    [[NERtcEngine sharedEngine] setParameters:@{kNERtcKeyVideoStartWithBackCamera : @YES}];
  } else {
    [[NERtcEngine sharedEngine] setParameters:@{kNERtcKeyVideoStartWithBackCamera : @NO}];
  }
}

- (void)microPhoneClick:(UIButton *)button {
  button.selected = !button.selected;
  [[NECallEngine sharedInstance] muteLocalAudio:button.selected];
}

- (void)cameraBtnClick:(UIButton *)button {
  button.selected = !button.selected;
  NSLog(@"mute video select : %d", button.selected);
  if (self.callParam.useEnableLocalMute == YES) {
    NSLog(@"enableLocalVideo: %d", !button.selected);
    [[NECallEngine sharedInstance] enableLocalVideo:!button.selected];
  } else {
    [[NECallEngine sharedInstance] muteLocalVideo:button.selected];
  }
  [self changeDefaultImage:button.selected];
  [self cameraAvailble:!button.selected userId:self.callParam.currentUserAccid];
}

- (void)hangupBtnClick:(UIButton *)button {
  NEHangupParam *param = [[NEHangupParam alloc] init];
  [[NECallEngine sharedInstance] hangup:param
                             completion:^(NSError *_Nullable error) {
                               [self destroy];
                             }];
}

- (void)microphoneBtnClick:(UIButton *)button {
  NSLog(@"micro phone btn click : %d", button.imageView.highlighted);
  self.audioCallingController.microphoneBtn.imageView.highlighted =
      !self.audioCallingController.microphoneBtn.imageView.highlighted;
  [[NECallEngine sharedInstance]
      muteLocalAudio:self.audioCallingController.microphoneBtn.imageView.highlighted];
  _operationView.microPhone.selected =
      self.audioCallingController.microphoneBtn.imageView.highlighted;
}

- (void)speakerBtnClick:(UIButton *)button {
  NSLog(@"speaker btn click : %d", self.audioCallingController.speakerBtn.imageView.highlighted);
  int ret = [[NERtcEngine sharedEngine]
      setLoudspeakerMode:!self.audioCallingController.speakerBtn.imageView.highlighted];
  if (ret == 0) {
    self.audioCallingController.speakerBtn.imageView.highlighted =
        !self.audioCallingController.speakerBtn.imageView.highlighted;
    _operationView.speakerBtn.selected =
        !self.audioCallingController.speakerBtn.imageView.highlighted;
  } else {
    [self.view ne_makeToast:[self localizableWithKey:@"operation_failed"]];
  }
}

- (void)operationSwitchClick:(UIButton *)btn {
  double currentTime = [self uptimeMillis];
  if (currentTime - self.lastClickTime < 500) {
    NSLog(@"click too fast");
    return;
  }
  self.lastClickTime = currentTime;

  if ([[NetManager shareInstance] isClose] == YES) {
    [self.view ne_makeToast:[self localizableWithKey:@"network_error"]];
    return;
  }
  __weak typeof(self) weakSelf = self;
  btn.enabled = NO;
  NECallType type = self.callParam.callType == NECallTypeVideo ? NECallTypeAudio : NECallTypeVideo;

  NESwitchParam *param = [[NESwitchParam alloc] init];
  param.state = NECallSwitchStateInvite;
  param.callType = type;

  [[NECallEngine sharedInstance]
      switchCallType:param
          completion:^(NSError *_Nullable error) {
            btn.enabled = YES;
            if (error == nil) {
              NSLog(@"切换成功 : %lu", type);
              NSLog(@"switch : %d", btn.selected);
              if (type == NECallTypeVideo &&
                  [[NECallEngine sharedInstance] getCallConfig].enableSwitchVideoConfirm) {
                [weakSelf showBannerView];
              } else if (type == NECallTypeAudio &&
                         [[NECallEngine sharedInstance] getCallConfig].enableSwitchAudioConfirm) {
                [weakSelf showBannerView];
              }
            } else {
              [weakSelf.view
                  ne_makeToast:[NSString
                                   stringWithFormat:@"%@: %@",
                                                    [weakSelf localizableWithKey:@"switch_error"],
                                                    error]];
            }
          }];
}

- (void)operationSpeakerClick:(UIButton *)btn {
  int ret = [NERtcEngine.sharedEngine setLoudspeakerMode:btn.selected];
  if (ret == 0) {
    btn.selected = !btn.selected;
  } else {
    [self.view ne_makeToast:[self localizableWithKey:@"operation_failed"]];
  }
}

- (void)mediaClick:(UIButton *)btn {
  double currentTime = [self uptimeMillis];
  if (currentTime - self.lastClickTime < 500) {
    NSLog(@"click too fast");
    return;
  }
  self.lastClickTime = currentTime;
  if ([[NetManager shareInstance] isClose] == YES) {
    [self.view ne_makeToast:[self localizableWithKey:@"network_error"]];
    return;
  }
  __weak typeof(self) weakSelf = self;
  self.mediaSwitchBtn.maskBtn.enabled = NO;

  NECallType type =
      weakSelf.callParam.callType == NECallTypeVideo ? NECallTypeAudio : NECallTypeVideo;

  NESwitchParam *param = [[NESwitchParam alloc] init];
  param.state = NECallSwitchStateInvite;
  param.callType = type;

  [[NECallEngine sharedInstance]
      switchCallType:param
          completion:^(NSError *_Nullable error) {
            weakSelf.mediaSwitchBtn.maskBtn.enabled = YES;
            if (error == nil) {
              if (type == NECallTypeVideo &&
                  [[NECallEngine sharedInstance] getCallConfig].enableSwitchVideoConfirm) {
                [weakSelf showBannerView];
              } else if (type == NECallTypeAudio &&
                         [[NECallEngine sharedInstance] getCallConfig].enableSwitchAudioConfirm) {
                [weakSelf showBannerView];
              }
            } else {
              [weakSelf.view
                  ne_makeToast:[NSString
                                   stringWithFormat:@"%@ : %@",
                                                    [weakSelf localizableWithKey:@"switch_error"],
                                                    error]];
            }
          }];
}

- (void)onCallTypeChangeWithType:(NECallType)callType {
  NSLog(@"onCallTypeChange:");
  if (self.callParam.callType == callType) {
    return;
  }
  self.callParam.callType = callType;
  [self updateUIonStatus:self.status];

  if (self.status == NERtcCallStatusInCall) {
    switch (callType) {
      case NECallTypeAudio:
        NSLog(@"NERtcCallTypeAudio");
        [self.operationView changeAudioStyle];
        [self hideVideoView];
        break;
      case NECallTypeVideo:
        NSLog(@"NERtcCallTypeVideo");
        [self.operationView changeVideoStyle];
        [self showVideoView];
        break;
      default:
        break;
    }
    return;
  }

  switch (callType) {
    case NECallTypeAudio:
      [self.operationView changeAudioStyle];
      [self setSwitchVideoStyle];
      break;
    case NECallTypeVideo:
      [self.operationView changeVideoStyle];
      [self setSwitchAudioStyle];
      break;
    default:
      break;
  }
}

#pragma mark -  call engine delegate

- (void)onVideoMuted:(BOOL)muted userID:(NSString *)userId {
  self.isRemoteMute = muted;
  [self cameraAvailble:!muted userId:userId];
}

- (void)onVideoAvailable:(BOOL)available userID:(NSString *)userId {
  self.isRemoteMute = !available;
  [self cameraAvailble:available userId:userId];
}

- (void)onCallConnected:(NECallInfo *)info {
  [self updateUIonStatus:NERtcCallStatusInCall];
  [self startTimer];
}

- (void)onCallEnd:(NECallEndInfo *)info {
  switch (info.reasonCode) {
    case TerminalCodeTimeOut:
      if ([[NetManager shareInstance] isClose] == YES) {
        [self destroy];
        return;
      }
      if (self.callParam.isCaller == YES) {
        [self showToastWithContent:[self localizableWithKey:@"remote_timeout"]];
      }
      break;
    case TerminalCodeBusy:
      [self showToastWithContent:[self localizableWithKey:@"remote_busy"]];
      break;

    case TerminalCalleeCancel:
      [self showToastWithContent:[self localizableWithKey:@"remote_cancel"]];
      break;

    case TerminalCallerRejcted:
      [self showToastWithContent:[self localizableWithKey:@"remote_reject"]];
      break;

    case TerminalOtherRejected:
      [UIApplication.sharedApplication.keyWindow
          ne_makeToast:[self localizableWithKey:@"other_client_reject"]];
      break;

    case TerminalOtherAccepted:
      [UIApplication.sharedApplication.keyWindow
          ne_makeToast:[self localizableWithKey:@"other_client_accept"]];
      break;

    case TerminalCallerCancel:

      return;

    default:
      break;
  }
  [self destroy];
}

- (void)onCallTypeChange:(NECallTypeChangeInfo *)info {
  NSLog(@"V2 onCallTypeChange : %@", [info yx_modelToJSONString]);
  switch (info.state) {
    case NECallSwitchStateAgree:
      [self hideBannerView];
      [self onCallTypeChangeWithType:info.callType];
      break;
    case NECallSwitchStateInvite: {
      if (self.alert != nil) {
        NSLog(@"alert is showing");
        return;
      }
      UIAlertController *alert = [UIAlertController
          alertControllerWithTitle:[self localizableWithKey:@"permission"]
                           message:info.callType == NECallTypeVideo
                                       ? [self localizableWithKey:@"audio_to_video"]
                                       : [self localizableWithKey:@"video_to_audio"]
                    preferredStyle:UIAlertControllerStyleAlert];
      self.alert = alert;
      UIAlertAction *rejectAction =
          [UIAlertAction actionWithTitle:[self localizableWithKey:@"reject"]
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   NESwitchParam *param = [[NESwitchParam alloc] init];
                                   param.callType = info.callType;
                                   param.state = NECallSwitchStateReject;
                                   [[NECallEngine sharedInstance]
                                       switchCallType:param
                                           completion:^(NSError *_Nullable error) {
                                             if (error) {
                                               [UIApplication.sharedApplication.keyWindow
                                                   ne_makeToast:error.localizedDescription];
                                             }
                                           }];
                                 }];
      __weak typeof(self) weakSelf = self;
      UIAlertAction *agreeAction =
          [UIAlertAction actionWithTitle:[self localizableWithKey:@"agree"]
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   NESwitchParam *param = [[NESwitchParam alloc] init];
                                   param.callType = info.callType;
                                   param.state = NECallSwitchStateAgree;
                                   [[NECallEngine sharedInstance]
                                       switchCallType:param
                                           completion:^(NSError *_Nullable error) {
                                             [weakSelf onCallTypeChangeWithType:info.callType];
                                             if (error) {
                                               [UIApplication.sharedApplication.keyWindow
                                                   ne_makeToast:error.localizedDescription];
                                             }
                                           }];
                                 }];

      [alert addAction:rejectAction];
      [alert addAction:agreeAction];
      [self presentViewController:alert animated:YES completion:nil];

      NSLog(@"NERtcSwitchStateInvite : %ld", info.callType);

    }

    break;
    case NECallSwitchStateReject:
      [self hideBannerView];
      [UIApplication.sharedApplication.keyWindow
          ne_makeToast:[self localizableWithKey:@"reject_tip"]];
      break;
    default:
      break;
  }
}

#pragma mark - private mothed

- (void)cameraAvailble:(BOOL)available userId:(NSString *)userId {
  if ([self.videoInCallController.bigVideoView.userID isEqualToString:userId]) {
    self.videoInCallController.bigVideoView.maskView.hidden = available;
  }
  if ([self.videoInCallController.smallVideoView.userID isEqualToString:userId]) {
    self.videoInCallController.smallVideoView.maskView.hidden = available;
  }

  if (self.showMyBigView) {
    [self changeRemoteMute:self.isRemoteMute videoView:self.stateUIController.smallVideoView];
  } else {
    [self changeRemoteMute:self.isRemoteMute videoView:self.stateUIController.bigVideoView];
  }
}

- (void)setUrl:(NSString *)url withPlaceholder:(NSString *)holder {
  __weak typeof(self) weakSelf = self;
  UIImageView *remoteAvatorView = nil;
  if (self.callParam.callType == NECallTypeVideo) {
    remoteAvatorView = self.videoCallingController.remoteAvatorView;
  } else {
    remoteAvatorView = self.calledController.remoteBigAvatorView;
  }
  [remoteAvatorView sd_setImageWithURL:[NSURL URLWithString:url]
                             completed:^(UIImage *_Nullable image, NSError *_Nullable error,
                                         SDImageCacheType cacheType, NSURL *_Nullable imageURL) {
                               if (image == nil) {
                                 image = [UIImage imageNamed:holder
                                                          inBundle:weakSelf.bundle
                                     compatibleWithTraitCollection:nil];
                               }
                               if (weakSelf.callParam.isCaller == false &&
                                   weakSelf.callParam.callType == NECallTypeVideo) {
                                 [weakSelf.blurImage setHidden:NO];
                               }
                               weakSelf.blurImage.image = image;
                             }];
}

- (void)startTimer {
  if (self.timer != nil) {
    return;
  }
  if (self.timerLabel.hidden == YES) {
    self.timerLabel.hidden = NO;
  }
  self.timer = [NSTimer scheduledTimerWithTimeInterval:1
                                                target:self
                                              selector:@selector(figureTimer)
                                              userInfo:nil
                                               repeats:YES];
}

- (void)figureTimer {
  self.timerCount++;
  self.timerLabel.text = [self timeFormatted:self.timerCount];
}

- (NSString *)timeFormatted:(int)totalSeconds {
  if (totalSeconds < 3600) {
    int seconds = totalSeconds % 60;
    int minutes = (totalSeconds / 60) % 60;
    return [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
  }
  int seconds = totalSeconds % 60;
  int minutes = (totalSeconds / 60) % 60;
  int hours = totalSeconds / 3600;
  return [NSString stringWithFormat:@"%02d:%02d:%02d", hours, minutes, seconds];
}

- (NSString *)getInviteText {
  return (self.callParam.callType == NECallTypeAudio
              ? [self localizableWithKey:@"invite_audio_call"]
              : [self localizableWithKey:@"invite_video_call"]);
}

- (void)hideBannerView {
  self.bannerView.hidden = YES;
}

- (void)showBannerView {
  self.bannerView.hidden = NO;
}

#pragma mark - destroy
- (void)destroy {
  if (self.alert != nil) {
    [self.alert dismissViewControllerAnimated:NO completion:nil];
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:kCallKitDismissNoti object:nil];
  [[NECallEngine sharedInstance] removeCallDelegate:self];

  if (self.timer != nil) {
    [self.timer invalidate];
    self.timer = nil;
  }
}

#pragma mark - property

- (UIView *)bannerView {
  if (!_bannerView) {
    _bannerView = [[UIView alloc] init];
    _bannerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    _bannerView.clipsToBounds = YES;
    _bannerView.layer.cornerRadius = 4.0;
    _bannerView.hidden = YES;
    _bannerView.translatesAutoresizingMaskIntoConstraints = NO;

    NEExpandButton *closeBtn = [NEExpandButton buttonWithType:UIButtonTypeCustom];
    [_bannerView addSubview:closeBtn];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.backgroundColor = [UIColor clearColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    [closeBtn addTarget:self
                  action:@selector(hideBannerView)
        forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
      [closeBtn.topAnchor constraintEqualToAnchor:_bannerView.topAnchor],
      [closeBtn.bottomAnchor constraintEqualToAnchor:_bannerView.bottomAnchor],
      [closeBtn.rightAnchor constraintEqualToAnchor:_bannerView.rightAnchor],
      [closeBtn.widthAnchor constraintEqualToConstant:40]
    ]];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [_bannerView addSubview:label];
    label.textColor = [UIColor whiteColor];
    [NSLayoutConstraint activateConstraints:@[
      [label.leftAnchor constraintEqualToAnchor:self.bannerView.leftAnchor constant:10],
      [label.topAnchor constraintEqualToAnchor:self.bannerView.topAnchor],
      [label.rightAnchor constraintEqualToAnchor:closeBtn.leftAnchor constant:-10]
    ]];

    label.adjustsFontSizeToFitWidth = YES;
    label.text = [self localizableWithKey:@"waitting_remote_response"];
  }
  return _bannerView;
}

- (UIButton *)switchCameraBtn {
  if (!_switchCameraBtn) {
    _switchCameraBtn = [[UIButton alloc] init];
    [_switchCameraBtn setImage:[UIImage imageNamed:@"call_switch_camera"
                                                        inBundle:self.bundle
                                   compatibleWithTraitCollection:nil]
                      forState:UIControlStateNormal];
    [_switchCameraBtn addTarget:self
                         action:@selector(switchCameraBtn:)
               forControlEvents:UIControlEventTouchUpInside];
    _switchCameraBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _switchCameraBtn.hidden = YES;
  }
  return _switchCameraBtn;
}

- (NEVideoOperationView *)operationView {
  if (!_operationView) {
    _operationView = [[NEVideoOperationView alloc] init];
    _operationView.translatesAutoresizingMaskIntoConstraints = NO;
    _operationView.layer.cornerRadius = 30;
    [_operationView.microPhone addTarget:self
                                  action:@selector(microPhoneClick:)
                        forControlEvents:UIControlEventTouchUpInside];
    [_operationView.cameraBtn addTarget:self
                                 action:@selector(cameraBtnClick:)
                       forControlEvents:UIControlEventTouchUpInside];
    [_operationView.hangupBtn addTarget:self
                                 action:@selector(hangupBtnClick:)
                       forControlEvents:UIControlEventTouchUpInside];
    [_operationView.mediaBtn addTarget:self
                                action:@selector(operationSwitchClick:)
                      forControlEvents:UIControlEventTouchUpInside];
    [_operationView.speakerBtn addTarget:self
                                  action:@selector(operationSpeakerClick:)
                        forControlEvents:UIControlEventTouchUpInside];
  }
  return _operationView;
}

- (UILabel *)timerLabel {
  if (nil == _timerLabel) {
    _timerLabel = [[UILabel alloc] init];
    _timerLabel.textColor = [UIColor whiteColor];
    _timerLabel.font = [UIFont systemFontOfSize:14.0];
    _timerLabel.textAlignment = NSTextAlignmentCenter;
    _timerLabel.translatesAutoresizingMaskIntoConstraints = NO;
  }
  return _timerLabel;
}

- (void)dealloc {
  [[NECallEngine sharedInstance] removeCallDelegate:self];
}

- (void)hideViews:(NSArray<UIView *> *)views {
  for (UIView *view in views) {
    [view setHidden:YES];
  }
}

- (void)showViews:(NSArray<UIView *> *)views {
  for (UIView *view in views) {
    [view setHidden:NO];
  }
}

- (void)changeDefaultImage:(BOOL)mute {
  NSLog(@"changeDefaultImage mute : %d", mute);
  NSLog(@"showMyBigView : %d", self.showMyBigView);

  UIImage *image = self.callParam.muteDefaultImage;
  if (image != nil) {
    if (mute == YES) {
      if (self.showMyBigView) {
        self.stateUIController.bigVideoView.imageView.image = image;
        self.stateUIController.bigVideoView.imageView.hidden = NO;
      } else {
        self.stateUIController.smallVideoView.imageView.image = image;
        self.stateUIController.smallVideoView.imageView.hidden = NO;
      }
    } else {
      if (self.showMyBigView) {
        self.stateUIController.bigVideoView.imageView.image = nil;
        self.stateUIController.bigVideoView.imageView.hidden = YES;
        self.stateUIController.smallVideoView.imageView.hidden = YES;
      } else {
        self.stateUIController.smallVideoView.imageView.image = nil;
        self.stateUIController.smallVideoView.imageView.hidden = YES;
      }
    }
  }
}

- (void)changeRemoteMute:(BOOL)mute videoView:(NEVideoView *)remoteVideo {
  UIImage *defaultImage = self.callParam.remoteDefaultImage;
  if (mute == true && defaultImage != nil) {
    remoteVideo.imageView.hidden = NO;
    remoteVideo.imageView.image = defaultImage;
  } else {
    remoteVideo.imageView.hidden = YES;
  }
}

- (NEAudioCallingController *)audioCallingController {
  if (nil == _audioCallingController) {
    _audioCallingController =
        (NEAudioCallingController *)[self getCallStateInstanceWithClassKey:kAudioCalling];
  }
  if (nil == _audioCallingController) {
    _audioCallingController = [[NEAudioCallingController alloc] init];
    _audioCallingController.callParam = self.callParam;
    _audioCallingController.mainController = self;
    _audioCallingController.view.hidden = YES;
    _audioCallingController.operationView = self.operationView;
  }

  return _audioCallingController;
}

- (NEAudioInCallController *)audioInCallController {
  if (nil == _audioInCallController) {
    _audioInCallController =
        (NEAudioInCallController *)[self getCallStateInstanceWithClassKey:kAudioInCall];
  }
  if (nil == _audioInCallController) {
    _audioInCallController = [[NEAudioInCallController alloc] init];
    _audioInCallController.callParam = self.callParam;
    _audioInCallController.mainController = self;
    _audioInCallController.view.hidden = YES;
    _audioInCallController.operationView = self.operationView;
  }
  return _audioInCallController;
}

- (NEVideoCallingController *)videoCallingController {
  if (nil == _videoCallingController) {
    _videoCallingController =
        (NEVideoCallingController *)[self getCallStateInstanceWithClassKey:kVideoCalling];
  }
  if (nil == _videoCallingController) {
    _videoCallingController = [[NEVideoCallingController alloc] init];
    _videoCallingController.callParam = self.callParam;
    _videoCallingController.mainController = self;
    _videoCallingController.view.hidden = YES;
    _videoCallingController.operationView = self.operationView;
  }
  return _videoCallingController;
}

- (NEVideoInCallController *)videoInCallController {
  if (nil == _videoInCallController) {
    _videoInCallController =
        (NEVideoInCallController *)[self getCallStateInstanceWithClassKey:kVideoInCall];
  }
  if (nil == _videoInCallController) {
    _videoInCallController = [[NEVideoInCallController alloc] init];
    _videoInCallController.callParam = self.callParam;
    _videoInCallController.mainController = self;
    _videoInCallController.view.hidden = YES;
  }
  return _videoInCallController;
}

- (NECalledViewController *)calledController {
  if (nil == _calledController) {
    _calledController =
        (NECalledViewController *)[self getCallStateInstanceWithClassKey:kCalledState];
  }
  if (nil == _calledController) {
    _calledController = [[NECalledViewController alloc] init];
    _calledController.callParam = self.callParam;
    _calledController.mainController = self;
    _calledController.view.hidden = YES;
  }
  return _calledController;
}

#pragma mark - common fuction

- (NECallUIStateController *)getCallStateInstanceWithClassKey:(NSString *)key {
  Class cls = [self.uiConfigDic objectForKey:key];
  if (nil != cls) {
    NECallUIStateController *controller = [[cls alloc] init];
    controller.callParam = self.callParam;
    controller.mainController = self;
    controller.operationView = self.operationView;
    controller.view.hidden = YES;
    return controller;
  }
  return nil;
}

- (UIView *)getDefaultHeaderView:(NSString *)accid
                            font:(UIFont *)font
                        showName:(NSString *)showName {
  UIView *headerView = [[UIView alloc] init];
  headerView.backgroundColor = [UIColor colorWithStringWithString:accid];
  headerView.translatesAutoresizingMaskIntoConstraints = NO;
  NSString *show = showName.length > 0 ? showName : accid;
  if (show.length >= 2) {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:label];
    label.textColor = [UIColor whiteColor];
    label.font = font;
    label.text = [show substringWithRange:NSMakeRange(show.length - 2, 2)];
    [NSLayoutConstraint activateConstraints:@[
      [label.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
      [label.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor]
    ]];
  }
  return headerView;
}

- (NSString *)localizableWithKey:(NSString *)key {
  return [self.bundle localizedStringForKey:key value:nil table:@"Localizable"];
}

#pragma mark CallEngine Key Value

- (BOOL)isGlobalInit {
  return !([[[NECallEngine sharedInstance] valueForKeyPath:@"context.initRtcMode"] intValue] == 1);
}

- (BOOL)isSupportAutoJoinWhenCalled {
  return [[[NECallEngine sharedInstance] valueForKeyPath:@"context.supportAutoJoinWhenCalled"]
      boolValue];
}

- (uint64_t)uptimeMillis {
  static mach_timebase_info_data_t timebaseInfo;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    (void)mach_timebase_info(&timebaseInfo);
  });
  uint64_t uptime = mach_absolute_time() * timebaseInfo.numer / timebaseInfo.denom;
  return uptime / NSEC_PER_MSEC;
}

@end
