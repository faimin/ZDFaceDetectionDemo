//
//  ZDFaceDetectController.m
//  ZDFaceDetectionDemo
//
//  Created by Zero.D.Saber on 2017/7/11.
//  Copyright © 2017年 Zero.D.Saber. All rights reserved.
//

#import "ZDFaceDetectController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import "UIImage+fixOrientation.h"

@interface ZDFaceDetectController () <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    AVCaptureSession *_session;
    AVCaptureDeviceInput *_captureInput;
    AVCaptureStillImageOutput *_captureOutput;
    AVCaptureVideoPreviewLayer *_preview;
    AVCaptureDevice *_device;
    
    UIView *m_highlitView[100];
    CGAffineTransform m_transform[100];
}

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
    [_session setSessionPreset:AVCaptureSessionPreset640x480];
    
    //2.创建、配置输入设备
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == AVCaptureDevicePositionBack) {
            NSError *__autoreleasing *error = NULL;
            _captureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
            if (*error) NSLog(@"%@", *error);
        }
    }
    
    if (!_captureInput)  return;
    
    [_session addInput:_captureInput];
    
    ///out put
    AVCaptureVideoDataOutput *captureOutput = [[AVCaptureVideoDataOutput alloc] init];
    captureOutput.alwaysDiscardsLateVideoFrames = YES;
    //captureOutput.minFrameDuration = CMTimeMake(1, 10);
    
    dispatch_queue_t queue = dispatch_queue_create("cameraQueue", DISPATCH_QUEUE_SERIAL);
    [captureOutput setSampleBufferDelegate:self queue:queue];
    
#if !__has_feature(objc_arc)
    dispatch_release(queue);
#endif
    NSString *key = (__bridge_transfer NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *value = @(kCVPixelFormatType_32BGRA);
    NSDictionary *videoSettings = @{key : value};
    [captureOutput setVideoSettings:videoSettings];
    [_session addOutput:captureOutput];
    
    ///custom Layer
    [self.view.layer addSublayer:self.customLayer];
    
    //3.创建、配置输出
    _captureOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
    [_captureOutput setOutputSettings:outputSettings];
	[_session addOutput:_captureOutput];
    
    ////////////
    _preview = [AVCaptureVideoPreviewLayer layerWithSession: _session];
    _preview.frame = CGRectMake(0, 0, self.cameraView.frame.size.width, self.cameraView.frame.size.height);
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.cameraView.layer addSublayer:_preview];
    [_session startRunning];
    
   // NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
}

//从摄像头缓冲区获取图像
#pragma mark -
#pragma mark AVCaptureSession delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
#if !__has_feature(objc_arc)
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#else
    @autoreleasepool {
#endif
        
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        
        uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef newContext = CGBitmapContextCreate(baseAddress,
                                                        width,
                                                        height,
                                                        8,
                                                        bytesPerRow,
                                                        colorSpace,
                                                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGImageRef newImage = CGBitmapContextCreateImage(newContext);
        CGContextRelease(newContext);
        CGColorSpaceRelease(colorSpace);
        
        UIImage *image= [UIImage imageWithCGImage:newImage scale:1 orientation:UIImageOrientationLeftMirrored];
        CGImageRelease(newImage);
        image = [image fixOrientation];//图像反转
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self detectForFacesInUIImage:image];
        });
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        
#if __has_feature(objc_arc)
    }
#else
    [pool drain];
#endif
}

/// 人脸识别
- (void)detectForFacesInUIImage:(UIImage *)facePicture {
    CIImage* image = [CIImage imageWithCGImage:facePicture.CGImage];
    
    CIDetector* detector = [CIDetector detectorOfType:CIDetectorTypeFace
                                              context:nil
                                              options:@{CIDetectorAccuracy : CIDetectorAccuracyLow}];
    
    NSArray *features = [detector featuresInImage:image];
    //NSLog(@"%f---%f",facePicture.size.width,facePicture.size.height);
    for(NSUInteger j = 0; m_highlitView[j] != nil; j++) {
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
        m_highlitView[_index]= [[UIView alloc] initWithFrame:frame];
        m_highlitView[_index].layer.borderWidth = 2;
        m_highlitView[_index].layer.borderColor = [[UIColor redColor] CGColor];
        [self.imageView addSubview:m_highlitView[_index]];
        
        UILabel *label = [[UILabel alloc]init];
        label.text = @"found face!!!!!!";
        label.backgroundColor = [UIColor clearColor];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:20];
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
    
    NSArray *inputs = _session.inputs;
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
