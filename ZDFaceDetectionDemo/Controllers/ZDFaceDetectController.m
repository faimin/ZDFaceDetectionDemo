//
//  ZDFaceDetectController.m
//  ZDFaceDetectionDemo
//
//  Created by Zero.D.Saber on 2017/7/11.
//  Copyright © 2017年 Zero.D.Saber. All rights reserved.
//
// http://developer.apple.com/library/ios/samplecode/SquareCam/SquareCam.zip
// http://www.jianshu.com/p/61ca3a917fe5
// https://github.com/daiweiping/Scanner-AVCapture
// https://github.com/clisuper/CLFaceDetectionImagePicker
// http://www.jianshu.com/p/b5618066dc2c
// https://github.com/June0611/EyeBlickCheck

#import "ZDFaceDetectController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import "UIImage+fixOrientation.h"

@interface ZDFaceDetectController () <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    UIView *m_highlitView[100];
    CGAffineTransform m_transform[100];
}

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *captureInput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureDevice *device;

@property (weak, nonatomic) IBOutlet UIView *cameraView;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) CALayer *customLayer;

@end

@implementation ZDFaceDetectController

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_cameraView release];
    [_imageView release];
    [_customLayer release];
    [super dealloc];
#endif
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    [self initialize];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//初始化
- (void)initialize {
    //1.创建会话层
    _session = [[AVCaptureSession alloc] init];
    
    //2.设置session显示分辨率
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        [_session setSessionPreset:AVCaptureSessionPreset640x480];
    } else {
        [_session setSessionPreset:AVCaptureSessionPresetPhoto];
    }
    
    //3.创建输入设备
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == AVCaptureDevicePositionBack) {
            NSError *__autoreleasing *error = NULL;
            _captureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
            if (*error) NSLog(@"%@", *error);
        }
    }
    if (!_captureInput) return;
    if ([_session canAddInput:_captureInput]) {
        [_session addInput:_captureInput];
    }
    
    // make a video data output
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    // captureOutput.minFrameDuration = CMTimeMake(1, 10);
    NSDictionary *rgbOutputSettings = @{(__bridge_transfer NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    [videoDataOutput setVideoSettings:rgbOutputSettings];
    videoDataOutput.alwaysDiscardsLateVideoFrames = YES; // discard if the data output queue is blocked (as we process the still image)
    
    // create a serial dispatch queue used for the sample buffer delegate
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
    dispatch_queue_t queue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:queue];
#if !__has_feature(objc_arc)
    dispatch_release(queue);
#endif
    
    if ([_session canAddOutput:videoDataOutput]) {
        [_session addOutput:videoDataOutput];
    }
    
    // make stillImageoutput
    AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
    [stillImageOutput setOutputSettings:outputSettings];
    [_session addOutput:stillImageOutput];
    
    // 调整人脸显示方向
    AVCaptureConnection *videoConnection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    videoConnection.enabled = NO;
    if ([videoConnection isVideoOrientationSupported]) {
        videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    //custom Layer
    [self.view.layer addSublayer:self.customLayer];
    
    //添加一个预览图像的层
    // AVCaptureVideoPreviewLayer是摄像头的视频预览层
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    _previewLayer.frame = self.cameraView.bounds;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.cameraView.layer.masksToBounds = YES;
    [self.cameraView.layer addSublayer:_previewLayer];
    
    //启动session,output开始接受samplebuffer回调
    [_session startRunning];
}

//从摄像头缓冲区获取图像
#pragma mark -
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
#if !__has_feature(objc_arc)
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#else
    @autoreleasepool {
#endif
        // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // 锁定pixel buffer的基地址
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        
        // 得到pixel buffer的基地址
        uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
        // 得到pixel buffer的行字节数
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        // 得到pixel buffer的宽和高
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        
        // 创建一个依赖于设备的RGB颜色空间
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        // 用抽样缓存的数据创建一个位图格式的图形上下文（graphics context）对象
        CGContextRef newContext = CGBitmapContextCreate(baseAddress,
                                                        width,
                                                        height,
                                                        8,
                                                        bytesPerRow,
                                                        colorSpace,
                                                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        // 根据这个位图context中的像素数据创建一个Quartz image对象
        CGImageRef newImage = CGBitmapContextCreateImage(newContext);
        CGContextRelease(newContext);
        CGColorSpaceRelease(colorSpace);
        
        UIImage *image = [UIImage imageWithCGImage:newImage scale:1 orientation:UIImageOrientationLeftMirrored];
        CGImageRelease(newImage);
        image = [image fixOrientation];//图像反转
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self detectForFacesInUIImage:image];
        });
        
        // 解锁pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        
#if __has_feature(objc_arc)
    }
#else
    [pool drain];
#endif
}

/// 人脸识别
- (void)detectForFacesInUIImage:(UIImage *)facePicture {
    CIImage *image = [CIImage imageWithCGImage:facePicture.CGImage];
    
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeFace
                                              context:nil
                                              options:@{CIDetectorAccuracy : CIDetectorAccuracyLow}];
    
    NSArray *features = [detector featuresInImage:image];
    //NSLog(@"%f---%f",facePicture.size.width,facePicture.size.height);
    for (NSUInteger j = 0; m_highlitView[j] != nil; j++) {
        m_highlitView[j].hidden = YES;
    }

    NSUInteger i = 0;
    for (CIFaceFeature *faceObject in features) {
        NSLog(@"found face");
        CGRect modifiedFaceBounds = faceObject.bounds;
        modifiedFaceBounds.origin.y = facePicture.size.height - faceObject.bounds.size.height - faceObject.bounds.origin.y;
        
        [self addSubViewWithFrame:modifiedFaceBounds index:i];
        i++;
    }
#if !__has_feature(objc_arc)
    [facePicture release];
#endif
}

/// 自画图像
- (void)addSubViewWithFrame:(CGRect)frame index:(NSUInteger)_index {
    if (m_highlitView[_index] == nil) {
        m_highlitView[_index] = [[UIView alloc] initWithFrame:frame];
        m_highlitView[_index].layer.borderWidth = 2;
        m_highlitView[_index].layer.borderColor = [[UIColor redColor] CGColor];
        [self.imageView addSubview:m_highlitView[_index]];
        
        UILabel *label = [[UILabel alloc] init];
        label.text = @"found face!!!!!!";
        label.backgroundColor = [UIColor clearColor];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:20.0];
        label.frame = CGRectMake(0, 0, frame.size.width, 20);
        [m_highlitView[_index] addSubview:label];
#if !__has_feature(objc_arc)
        [label release];
#endif
        
        UIImageView *bqImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"bq.png"]];
        bqImage.frame = CGRectMake(0, -30, 30, 30);
        [m_highlitView[_index] addSubview:bqImage];
#if !__has_feature(objc_arc)
        [bqImage release];
#endif
        
        m_transform[_index] = m_highlitView[_index].transform;
    }
    frame.origin.x = frame.origin.x/1.5;
    frame.origin.y = frame.origin.y/1.5;
    frame.size.width = frame.size.width/1.5;
    frame.size.height = frame.size.height/1.5;
    m_highlitView[_index].frame = frame;
    
    ///根据头像大小缩放自画View
    CGFloat scale = frame.size.width/220;
    CGAffineTransform transform = CGAffineTransformScale(m_transform[_index], scale, scale);
    m_highlitView[_index].transform = transform;
    m_highlitView[_index].hidden = NO;
}

#pragma amrk -

/// 摄像头反转
- (IBAction)turnCamera:(UIButton *)sender {
    NSArray *inputs = self.session.inputs;
    for (AVCaptureDeviceInput *input in inputs) {
        AVCaptureDevice *device = input.device;
        if ([device hasMediaType:AVMediaTypeVideo]) {
            AVCaptureDevicePosition position = device.position;
            AVCaptureDevice *newCamera = nil;
            AVCaptureDeviceInput *newInput = nil;
            
            if (position == AVCaptureDevicePositionFront) {
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
            }
            else {
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
            }
            _device = newCamera;
            NSError *__autoreleasing *error = NULL;
            newInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:error];
            if (*error) NSLog(@"%@", *error);
            
            // beginConfiguration ensures that pending changes are not applied immediately
            [_session beginConfiguration];
            
            [_session removeInput:input];
            [_session addInput:newInput];
            
            // Changes take effect once the outermost commitConfiguration is invoked.
            [_session commitConfiguration];
            break;
        }
    }
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

#pragma mark - Property

- (AVCaptureVideoPreviewLayer *)previewLayer {
    if (!_previewLayer) {
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
        _previewLayer.frame = self.cameraView.bounds;
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    }
    return _previewLayer;
}

- (CALayer *)customLayer {
    if (!_customLayer) {
        _customLayer = ({
            CALayer *layer = [CALayer layer];
            layer.frame = self.view.bounds;
            layer.transform = CATransform3DRotate(CATransform3DIdentity, M_PI/2.0f, 0, 0, 1);
            layer.contentsGravity = kCAGravityResizeAspectFill;
            layer;
        });
    }
    return _customLayer;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
