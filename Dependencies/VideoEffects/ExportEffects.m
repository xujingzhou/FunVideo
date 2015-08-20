//
//  ExportEffects
//  VideoTheme
//
//  Created by Johnny Xu(徐景周) on 5/30/15.
//  Copyright (c) 2015 Future Studio. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "ExportEffects.h"
#import "GifAnimationLayer.h"
#import "StickerView.h"

#define DefaultOutputVideoName @"outputMovie.mp4"
#define DefaultOutputAudioName @"outputAudio.caf"

@interface ExportEffects ()
{
}

@property (strong, nonatomic) NSTimer *timerEffect;
@property (strong, nonatomic) AVAssetExportSession *exportSession;

@end

@implementation ExportEffects
{

}

+ (ExportEffects *)sharedInstance
{
    static ExportEffects *sharedInstance = nil;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedInstance = [[ExportEffects alloc] init];
    });
    
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    
    if (self)
    {
        _timerEffect = nil;
        _exportSession = nil;
        
        _filenameBlock = nil;
        _gifArray = nil;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_exportSession)
    {
        _exportSession = nil;
    }
    
    if (_timerEffect)
    {
        [_timerEffect invalidate];
        _timerEffect = nil;
    }
}

#pragma mark Utility methods
- (NSString*)getOutputFilePath
{
    NSString* mp4OutputFile = [NSTemporaryDirectory() stringByAppendingPathComponent:DefaultOutputVideoName];
    return mp4OutputFile;
}

- (NSString*)getTempOutputFilePath
{
    NSString *path = NSTemporaryDirectory();
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    formatter.dateFormat = @"yyyyMMddHHmmssSSS";
    NSString *nowTimeStr = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:0]];
    
    NSString *fileName = [[path stringByAppendingPathComponent:nowTimeStr] stringByAppendingString:@".mov"];
    return fileName;
}

#pragma mark - writeExportedVideoToAssetsLibrary
- (void)writeExportedVideoToAssetsLibrary:(NSString *)outputPath
{
    __unsafe_unretained typeof(self) weakSelf = self;
    NSURL *exportURL = [NSURL fileURLWithPath:outputPath];
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:exportURL])
    {
        [library writeVideoAtPathToSavedPhotosAlbum:exportURL completionBlock:^(NSURL *assetURL, NSError *error)
         {
             NSString *message;
             if (!error)
             {
                 message = GBLocalizedString(@"MsgSuccess");
             }
             else
             {
                 message = [error description];
             }
             
             NSLog(@"%@", message);
             
             // Output path
             self.filenameBlock = ^(void) {
                 return outputPath;
             };
             
             if (weakSelf.finishVideoBlock)
             {
                 weakSelf.finishVideoBlock(YES, message);
             }
         }];
    }
    else
    {
        NSString *message = GBLocalizedString(@"MsgFailed");;
        NSLog(@"%@", message);
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (_finishVideoBlock)
        {
            _finishVideoBlock(NO, message);
        }
    }
    
    library = nil;
}

#pragma mark - addAudioMixToComposition
- (void)addAudioMixToComposition:(AVMutableComposition *)composition withAudioMix:(AVMutableAudioMix *)audioMix withAsset:(AVURLAsset*)commentary withAniBeginTime:(CFTimeInterval)beginTime
{
    // 1. Clip commentary duration to composition duration.
    CMTimeRange commentaryTimeRange = CMTimeRangeMake(kCMTimeZero, commentary.duration);
    if (CMTIME_COMPARE_INLINE(CMTimeRangeGetEnd(commentaryTimeRange), >, [composition duration]))
        commentaryTimeRange.duration = CMTimeSubtract([composition duration], commentaryTimeRange.start);
    
    // 2. Add the commentary track.
    AVMutableCompositionTrack *compositionCommentaryTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:TrackIDCustom];
    AVAssetTrack * commentaryTrack = [[commentary tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    [compositionCommentaryTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, commentaryTimeRange.duration) ofTrack:commentaryTrack atTime:CMTimeMake(beginTime, 1) error:nil];
    
    // 3. Fade in
    CMTimeRange startRange = CMTimeRangeMake(kCMTimeZero, commentary.duration);
    NSMutableArray *trackMixArray = [NSMutableArray array];
    AVMutableAudioMixInputParameters *trackMixComentray = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:commentaryTrack];
    [trackMixComentray setVolumeRampFromStartVolume:0.9f toEndVolume:1.0f timeRange:startRange];
    AVMutableAudioMixInputParameters *trackMixComposition = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:compositionCommentaryTrack];
    [trackMixComposition setVolumeRampFromStartVolume:0.0f toEndVolume:0.5f timeRange:CMTimeRangeMake(kCMTimeZero, composition.duration)];
    [trackMixArray addObject:trackMixComposition];
    [trackMixArray addObject:trackMixComentray];
    
    audioMix.inputParameters = trackMixArray;
}

#pragma mark - Asset
- (void)addAsset:(AVAsset *)asset toComposition:(AVMutableComposition *)composition withTrackID:(CMPersistentTrackID)trackID withRecordAudio:(BOOL)recordAudio withAssetFilePath:(NSString *)identifier
{
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:trackID];
    AVAssetTrack *assetVideoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    CMTimeRange timeRange = CMTimeRangeFromTimeToTime(kCMTimeZero, assetVideoTrack.timeRange.duration);
    [videoTrack insertTimeRange:timeRange ofTrack:assetVideoTrack atTime:kCMTimeZero error:nil];
    [videoTrack setPreferredTransform:assetVideoTrack.preferredTransform];
    
    UIInterfaceOrientation videoOrientation = orientationForTrack(asset);
    NSLog(@"videoOrientation: %ld", (long)videoOrientation);
    if (videoOrientation == UIInterfaceOrientationPortrait)
    {
        // Right rotation 90 degree
        [self setShouldRightRotate90:YES withTrackID:trackID];
    }
    else
    {
        if ([self shouldRightRotate90ByCustom:identifier])
        {
            NSLog(@"shouldRightRotate90ByCustom: %@", identifier);
            [self setShouldRightRotate90:YES withTrackID:trackID];
        }
        else
        {
            [self setShouldRightRotate90:NO withTrackID:trackID];
        }
    }

    
    if (recordAudio)
    {
        AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:trackID];
        if ([[asset tracksWithMediaType:AVMediaTypeAudio] count] > 0)
        {
            AVAssetTrack *assetAudioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
            [audioTrack insertTimeRange:timeRange ofTrack:assetAudioTrack atTime:kCMTimeZero error:nil];
        }
        else
        {
            NSLog(@"Reminder: video hasn't audio!");
        }
    }
}

#pragma mark - Export Video
- (void)addEffectToVideo:(NSString *)videoFilePath withAudioFilePath:(NSString *)audioFilePath withAniBeginTime:(CFTimeInterval)beginTime
{
    if (isStringEmpty(videoFilePath))
    {
        NSLog(@"videoFilePath is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }
    
    CGFloat duration = 0;
    NSURL *videoURL = getFileURL(videoFilePath);
    AVAsset *videoAsset = [AVAsset assetWithURL:videoURL];
    AVMutableComposition *composition = [AVMutableComposition composition];
    
    BOOL useAudio = YES;
    if (!isStringEmpty(audioFilePath))
    {
        useAudio = NO;
    }
    
    if (videoAsset)
    {
        // Max duration
        duration = CMTimeGetSeconds(videoAsset.duration);
        
        [self addAsset:videoAsset toComposition:composition withTrackID:TrackIDCustom withRecordAudio:useAudio withAssetFilePath:videoFilePath];
    }
    else
    {
        NSLog(@"videoAsset is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }

    AVAssetTrack *firstVideoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    CGSize videoSize = CGSizeMake(firstVideoTrack.naturalSize.width, firstVideoTrack.naturalSize.height);
    if (videoSize.width < 10 || videoSize.height < 10)
    {
        NSLog(@"videoSize is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }
    
    BOOL shouldRotate = [self shouldRightRotate90ByTrackID:TrackIDCustom];
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    if (shouldRotate)
    {
        videoComposition.renderSize = CGSizeMake(videoSize.height, videoSize.width);
    }
    else
    {
        videoComposition.renderSize = CGSizeMake(videoSize.width, videoSize.height);
    }
    
    videoComposition.frameDuration = CMTimeMakeWithSeconds(1.0 / firstVideoTrack.nominalFrameRate, firstVideoTrack.naturalTimeScale);
    instruction.timeRange = [composition.tracks.firstObject timeRange];
    
    NSMutableArray *layerInstructionArray = [[NSMutableArray alloc] initWithCapacity:1];
    AVMutableVideoCompositionLayerInstruction *video1LayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstruction];
    
    // Rotation if need
    if (shouldRotate)
    {
        CGAffineTransform t1 = CGAffineTransformIdentity;
        CGAffineTransform t2 = CGAffineTransformIdentity;
        t1 = CGAffineTransformMakeTranslation(videoSize.height, 0);
        t2 = CGAffineTransformRotate(t1, M_PI_2);
        CGAffineTransform finalTransform = t2;
        [video1LayerInstruction setTransform:finalTransform atTime:kCMTimeZero];
    }
    
    video1LayerInstruction.trackID = TrackIDCustom;
    [layerInstructionArray addObject:video1LayerInstruction];
    
    instruction.layerInstructions = layerInstructionArray;
    videoComposition.instructions = @[ instruction ];
    
    NSInteger videoWidth = videoSize.width;
    NSInteger videoHeight = videoSize.height;
    if (shouldRotate)
    {
        videoWidth = videoSize.height;
        videoHeight = videoSize.width;
    }
    
    // Animation Effects
    CALayer *parentLayer = [CALayer layer];
    CALayer *videoLayer = [CALayer layer];
    parentLayer.bounds = CGRectMake(0, 0, videoWidth, videoHeight);
    parentLayer.anchorPoint = CGPointMake(0, 0);
    parentLayer.position = CGPointMake(0, 0);
    
    videoLayer.bounds = parentLayer.bounds;
    videoLayer.anchorPoint =  CGPointMake(0.5, 0.5);
    videoLayer.position = CGPointMake(CGRectGetMidX(parentLayer.bounds), CGRectGetMidY(parentLayer.bounds));
    
    parentLayer.geometryFlipped = YES;
    [parentLayer addSublayer:videoLayer];
    
    // Animation effects
    NSMutableArray *animatedLayers = [[NSMutableArray alloc] init];
    CALayer *animatedLayer = nil;

    if (_gifArray && [_gifArray count] > 0)
    {
        for (StickerView *view in _gifArray)
        {
            NSString *gifPath = view.getFilePath;
            CGFloat widthFactor  = CGRectGetWidth(view.getVideoContentRect) / CGRectGetWidth(view.getInnerFrame);
            CGFloat heightFactor = CGRectGetHeight(view.getVideoContentRect) / CGRectGetHeight(view.getInnerFrame);
            
            CGPoint origin = CGPointMake((view.getInnerFrame.origin.x / CGRectGetWidth(view.getVideoContentRect)) * videoWidth,  (view.getInnerFrame.origin.y / CGRectGetHeight(view.getVideoContentRect)) * videoHeight);
            CGRect gifFrame = CGRectMake(origin.x, origin.y, videoWidth/widthFactor, videoHeight/heightFactor);
            NSLog(@"view.getWidthRatio: %f, view.getHeightRatio: %f", widthFactor, heightFactor);
            
            animatedLayer = [GifAnimationLayer layerWithGifFilePath:gifPath withFrame:gifFrame withAniBeginTime:beginTime];
            if (animatedLayer && [animatedLayer isKindOfClass:[GifAnimationLayer class]])
            {
                animatedLayer.opacity = 0.0f;
                
                CAKeyframeAnimation *animation = [[CAKeyframeAnimation alloc] init];
                [animation setKeyPath:@"contents"];
                animation.calculationMode = kCAAnimationDiscrete;
                animation.autoreverses = NO;
                animation.repeatCount = 1;
                animation.beginTime = beginTime;
            
                NSDictionary *gifDic = [(GifAnimationLayer*)animatedLayer getValuesAndKeyTimes];
                NSMutableArray *keyTimes = [gifDic objectForKey:@"keyTimes"];
                NSMutableArray *imageArray = [NSMutableArray arrayWithCapacity:[keyTimes count]];
                for (int i = 0; i < [keyTimes count]; ++i)
                {
                    CGImageRef image = [(GifAnimationLayer*)animatedLayer copyImageAtFrameIndex:i];
                    if (image)
                    {
                        [imageArray addObject:(__bridge id)image];
                    }
                }
                
                animation.values   = imageArray;
                animation.keyTimes = keyTimes;
                animation.duration = [(GifAnimationLayer*)animatedLayer getTotalDuration];
                animation.removedOnCompletion = YES;
                animation.delegate = self;
                [animation setValue:@"stop" forKey:@"TAG"];
                
                [animatedLayer addAnimation:animation forKey:@"contents"];
                
                CABasicAnimation *fadeOutAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
                fadeOutAnimation.fromValue = @1.0f;
                fadeOutAnimation.toValue = @0.9f;
                fadeOutAnimation.additive = YES;
                fadeOutAnimation.removedOnCompletion = YES;
                fadeOutAnimation.beginTime = beginTime;
                fadeOutAnimation.duration = animation.beginTime + animation.duration + 2;
                fadeOutAnimation.fillMode = kCAFillModeBoth;
                [animatedLayer addAnimation:fadeOutAnimation forKey:@"opacityOut"];
                
                [animatedLayers addObject:(id)animatedLayer];
            }
        }
    }
    
    if (animatedLayers && [animatedLayers count] > 0)
    {
        for (CALayer *animatedLayer in animatedLayers)
        {
            [parentLayer addSublayer:animatedLayer];
        }
    }
    
    videoComposition.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parentLayer];

    NSString *exportPath = [self getOutputFilePath];
    NSURL *exportURL = [NSURL fileURLWithPath:[self returnFormatString:exportPath]];
    // Delete old file
    unlink([exportPath UTF8String]);

    _exportSession = [AVAssetExportSession exportSessionWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
    _exportSession.outputURL = exportURL;
    _exportSession.outputFileType = AVFileTypeMPEG4;
    _exportSession.shouldOptimizeForNetworkUse = YES;
    
    if (videoComposition)
    {
         _exportSession.videoComposition = videoComposition;
    }
    
    // Music effect
    AVMutableAudioMix *audioMix = nil;
    if (!isStringEmpty(audioFilePath))
    {
        NSURL *bgMusicURL = getFileURL(audioFilePath);
        AVURLAsset *assetMusic = [[AVURLAsset alloc] initWithURL:bgMusicURL options:nil];
        
        audioMix = [AVMutableAudioMix audioMix];
        [self addAudioMixToComposition:composition withAudioMix:audioMix withAsset:assetMusic withAniBeginTime:beginTime];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // Progress monitor
        _timerEffect = [NSTimer scheduledTimerWithTimeInterval:0.3f
                                                        target:self
                                                      selector:@selector(retrievingExportProgress)
                                                      userInfo:nil
                                                       repeats:YES];
    });
    
    __block typeof(self) blockSelf = self;
    [_exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
        switch ([_exportSession status])
        {
            case AVAssetExportSessionStatusCompleted:
            {
                // Close timer
                [blockSelf.timerEffect invalidate];
                blockSelf.timerEffect = nil;

                NSLog(@"Export Successful: %@", exportPath);
                
                // Save video to Album
                [self writeExportedVideoToAssetsLibrary:exportPath];
                
                break;
            }
            case AVAssetExportSessionStatusFailed:
            {
                // Close timer
                [blockSelf.timerEffect invalidate];
                blockSelf.timerEffect = nil;

                // Output path
                self.filenameBlock = ^(void) {
                    return @"";
                };
                
                if (self.finishVideoBlock)
                {
                    self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
                }

                NSLog(@"Export failed: %@, %@", [[blockSelf.exportSession error] localizedDescription], [blockSelf.exportSession error]);
                break;
            }
            case AVAssetExportSessionStatusCancelled:
            {
                NSLog(@"Canceled: %@", blockSelf.exportSession.error);
                break;
            }
            default:
                break;
        }
    }];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    NSString *tag = [anim valueForKey:@"TAG"];
    if ([tag isEqualToString:@"stop"])
    {
//        anim.contents = nil;
        
        NSLog(@"animationDidStop");
    }
}

- (UIImageOrientation)getVideoOrientationFromAsset:(AVAsset *)asset
{
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    CGSize size = [videoTrack naturalSize];
    CGAffineTransform txf = [videoTrack preferredTransform];
    
    if (size.width == txf.tx && size.height == txf.ty)
        return UIImageOrientationLeft; //return UIInterfaceOrientationLandscapeLeft;
    else if (txf.tx == 0 && txf.ty == 0)
        return UIImageOrientationRight; //return UIInterfaceOrientationLandscapeRight;
    else if (txf.tx == 0 && txf.ty == size.width)
        return UIImageOrientationDown; //return UIInterfaceOrientationPortraitUpsideDown;
    else
        return UIImageOrientationUp;  //return UIInterfaceOrientationPortrait;
}

// Convert 'space' char
- (NSString *)returnFormatString:(NSString *)str
{
    return [str stringByReplacingOccurrencesOfString:@" " withString:@""];
}

#pragma mark - Export Progress Callback
- (void)retrievingExportProgress
{
    if (_exportSession && _exportProgressBlock)
    {
        self.exportProgressBlock([NSNumber numberWithFloat:_exportSession.progress]);
    }
}

#pragma mark - scaleRespectAspectFromRect
- (CGRect)scaleRespectAspectFromRect1:(CGRect)rect1 toRect2:(CGRect)rect2
{
    CGSize scaledSize = rect2.size;
    float scaleFactor = 1.0;
    
    CGFloat widthFactor  = rect2.size.width / rect1.size.width;
    CGFloat heightFactor = rect2.size.height / rect1.size.height;
    
    if (widthFactor < heightFactor)
        scaleFactor = widthFactor;
    else
        scaleFactor = heightFactor;
    
    scaledSize.height = rect1.size.height * scaleFactor;
    scaledSize.width  = rect1.size.width  * scaleFactor;
    float y = (rect2.size.height - scaledSize.height)/2;
    float x = (rect2.size.width - scaledSize.width)/2;
    
    return CGRectMake(x, y, scaledSize.width, scaledSize.height);
}

#pragma mark - convertCGPoint
- (CGPoint)convertCGPoint:(CGPoint)point1 fromRect1:(CGSize)rect1 toRect2:(CGSize)rect2
{
    point1.y = rect1.height - point1.y;
    CGPoint result = CGPointMake((point1.x*rect2.width)/rect1.width, (point1.y*rect2.height)/rect1.height);
    return result;
}

- (CGPoint)convertPoint:(CGPoint)point1 fromRect1:(CGSize)rect1 toRect2:(CGSize)rect2
{
    CGPoint result = CGPointMake((point1.x*rect2.width)/rect1.width, (point1.y*rect2.height)/rect1.height);
    return result;
}

#pragma mark - NSUserDefaults
#pragma mark - setShouldRightRotate90
- (void)setShouldRightRotate90:(BOOL)shouldRotate withTrackID:(NSInteger)trackID
{
    NSString *identifier = [NSString stringWithFormat:@"TrackID_%ld", (long)trackID];
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    if (shouldRotate)
    {
        [userDefaultes setBool:YES forKey:identifier];
    }
    else
    {
        [userDefaultes setBool:NO forKey:identifier];
    }
    
    [userDefaultes synchronize];
}

- (BOOL)shouldRightRotate90ByTrackID:(NSInteger)trackID
{
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [NSString stringWithFormat:@"TrackID_%ld", (long)trackID];
    BOOL result = [[userDefaultes objectForKey:identifier] boolValue];
    NSLog(@"shouldRightRotate90ByTrackID %@ : %@", identifier, result?@"Yes":@"No");
    
    if (result)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

#pragma mark - ShouldRightRotate90ByCustom
- (BOOL)shouldRightRotate90ByCustom:(NSString *)identifier
{
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    BOOL result = [[userDefaultes objectForKey:identifier] boolValue];
    NSLog(@"shouldRightRotate90ByCustom %@ : %@", identifier, result?@"Yes":@"No");
    
    if (result)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

@end
