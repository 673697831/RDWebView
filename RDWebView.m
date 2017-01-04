//
//  RDWebView.m
//  RiceDonate
//
//  Created by ozr on 16/1/22.
//  Copyright © 2016年 ricedonate. All rights reserved.
//

#import "RDWebView.h"
#import "RDUICommon.h"
#import "UIColor+RDAlpha.h"
#import <WebKit/WebKit.h>

@interface RDWebView ()<UIGestureRecognizerDelegate, UIWebViewDelegate, WKNavigationDelegate>

@property (nonatomic, weak) UIScreenEdgePanGestureRecognizer *gesture;
@property (nonatomic, weak) UIImageView *previewImageView;
@property (nonatomic, assign) CGPoint webViewOriginCenter;
@property (nonatomic, assign) CGPoint imageViewOriginCenter;
//@property (nonatomic, weak) id<UIWebViewDelegate> originDelegate;
@property (nonatomic, strong) NSMutableArray *historyBackImages;
@property (nonatomic, assign) CGFloat panStartX;
@property (nonatomic, strong) UIProgressView *progressView;

///内部使用的webView
@property (nonatomic, weak, readonly) id realWebView;

///是否正在使用 UIWebView
@property (nonatomic, readonly) BOOL usingUIWebView;

@property (nonatomic, strong) UIImage *gobackBackgroundImage;

@end

@implementation RDWebView

@synthesize scalesPageToFit = _scalesPageToFit;

//@synthesize realWebView = _realWebView;

+ (UIImage *)screenshotOfView:(UIView *)view{
    UIGraphicsBeginImageContextWithOptions(view.frame.size, YES, 0.0);
    
    if ([view respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }
    else{
        [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (void)addShadowToView:(UIView *)view{
    CALayer *layer = view.layer;
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:layer.bounds];
    layer.shadowPath = path.CGPath;
    layer.shadowColor = [UIColor blackColor].CGColor;
    layer.shadowOffset = CGSizeZero;
    layer.shadowOpacity = 0.4f;
    layer.shadowRadius = 8.0f;
}

- (instancetype)init
{
    if (self = [super init]) {
        if (self.usingUIWebView) {
            UIWebView *webView = [UIWebView new];
            webView.delegate = self;
            _realWebView = webView;
            [self addSubview:_realWebView];
            [_realWebView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.edges.equalTo(self);
            }];
        }else
        {
            WKWebView *webView = [WKWebView new];
            webView.navigationDelegate = self;
            _realWebView = webView;
            [self addSubview:_realWebView];
            [_realWebView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.edges.equalTo(self);
            }];
            
            @weakify(self);
            [[RACObserve(webView, estimatedProgress) takeUntil:self.rac_willDeallocSignal] subscribeNext:^(id x)
            {
                @strongify(self);
                CGFloat progress = [x floatValue];
                //加载完成
                [self.progressView setProgress:progress];
                [UIView animateWithDuration:.5
                                 animations:^{
                                     [self.progressView layoutIfNeeded];
                                 } completion:^(BOOL finished) {
                                     if (progress == 1) {
                                         if (finished) {
                                             [UIView animateWithDuration:.2
                                                              animations:^{
                                                                  self.progressView.alpha = 0;
                                                              }
                                                              completion:^(BOOL finished) {
                                                                  [self.progressView setProgress:0 animated:NO];
                                                                  self.progressView.alpha = 1;
                                                              }];
                                         }
                                         
                                     }
                                 }];
            }];
        }
        
        self.scalesPageToFit = YES;
    }
    
    return self;
}

#pragma mark - lazy

- (UIImageView *)previewImageView
{
    if (!_previewImageView) {
        if (self.superview) {
            UIImageView *previewImageView = [[UIImageView alloc] initWithFrame:self.frame];
            [self.superview insertSubview:previewImageView belowSubview:self];
            _previewImageView = previewImageView;
            //_previewImageView.hidden = YES;
            self.imageViewOriginCenter = self.center;
        }
    }
    return _previewImageView;
}

- (UIProgressView *)progressView
{
    if (!_progressView) {
        
        _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 40)];
        
        //甚至进度条的风格颜色值，默认是蓝色的
        _progressView.progressTintColor = kOrangeColor1;
        
        //表示进度条未完成的，剩余的轨迹颜色,默认是灰色
        _progressView.trackTintColor =[UIColor clearColor];
        
        [self addSubview:_progressView];
    }
    
    return _progressView;
}

//#pragma mark - override
//
//- (void)setDelegate:(id<UIWebViewDelegate>)delegate
//{
//    self.originDelegate = delegate;
//}
//
//- (id<UIWebViewDelegate>)delegate{
//    return self.originDelegate;
//}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.webViewOriginCenter = self.center;
    
}

- (void)dealloc
{
    if (self.previewImageView) {
        [self.previewImageView removeFromSuperview];
    }
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        
        UIScreenEdgePanGestureRecognizer *swipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self
                                                                                                    action:@selector(swipe:)];
        swipe.edges = UIRectEdgeLeft;
        swipe.delegate = self;
        _gesture = swipe;
        [self addGestureRecognizer:swipe];
        
        _historyBackImages = [NSMutableArray new];
        
        [RDWebView addShadowToView:self];
        
        //[super setDelegate:self];
        
    }
    
    return self;
}

#pragma mark -

- (void)swipe:(UIScreenEdgePanGestureRecognizer *)sender
{
    
    if (!self.canGoBack) {
        self.center = self.webViewOriginCenter;
        self.previewImageView.center = self.imageViewOriginCenter;
        return;
    }
    
    CGPoint translation = [sender translationInView:self];
    CGFloat deltaX = translation.x - self.panStartX;
    
    if (UIGestureRecognizerStateBegan == sender.state) {
        self.panStartX = translation.x;
    }
    
    if (UIGestureRecognizerStateChanged == sender.state) {
        CGPoint center = CGPointMake(self.webViewOriginCenter.x+deltaX, self.center.y);
        self.center = center;
        
        center.x = -self.bounds.size.width/2.0f + deltaX/2.0f+self.imageViewOriginCenter.x;
        self.previewImageView.center = center;
    }

    CGFloat duration = .5f;
    if (UIGestureRecognizerStateEnded == sender.state) {
        if (deltaX > self.bounds.size.width/4.0f) {
            [UIView animateWithDuration:(1.0f - deltaX/self.bounds.size.width)*duration animations:^{
                CGPoint center = CGPointMake(self.webViewOriginCenter.x+self.bounds.size.width, self.center.y);
                self.center = center;
                self.previewImageView.center = self.imageViewOriginCenter;
            } completion:^(BOOL finished) {
                if (finished) {
                    self.hidden = YES;
                    [self goBack];
                }
                
            }];
        }
        else{
            [UIView animateWithDuration:(deltaX/self.bounds.size.width)*duration animations:^{
                self.center = self.webViewOriginCenter;
                CGPoint center = CGPointMake(-self.bounds.size.width/2.0f + self.imageViewOriginCenter.x, self.imageViewOriginCenter.y);
                self.previewImageView.center = center;
            }];
        }
    }

    if (UIGestureRecognizerStateCancelled == sender.state || UIGestureRecognizerStateFailed == sender.state) {
        self.center = self.webViewOriginCenter;
        self.previewImageView.center = self.imageViewOriginCenter;
    }
    
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    BOOL result = NO;
    
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        result = YES;
    }
    
    return YES;
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    return [self rd_webViewShouldStartLoadWithRequest:request navigationType:navigationType];
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [self rd_webViewDidStartLoad];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self rd_webViewDidFinishLoad];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [self rd_webViewDidFailLoadWithError:error];
}

#pragma mark- WKNavigationDelegate
-(void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    BOOL resultBOOL = [self rd_webViewShouldStartLoadWithRequest:navigationAction.request navigationType:navigationAction.navigationType];
    if(resultBOOL)
    {
        if(navigationAction.targetFrame == nil)
        {
            [webView loadRequest:navigationAction.request];
        }
        decisionHandler(WKNavigationActionPolicyAllow);
    }
    else
    {
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}
-(void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    [self rd_webViewDidStartLoad];
}
-(void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [self rd_webViewDidFinishLoad];
}
- (void)webView:(WKWebView *) webView didFailProvisionalNavigation: (WKNavigation *) navigation withError: (NSError *) error
{
    [self rd_webViewDidFailLoadWithError:error];
}
- (void)webView: (WKWebView *)webView didFailNavigation:(WKNavigation *) navigation withError: (NSError *) error
{
    [self rd_webViewDidFailLoadWithError:error];
}

#pragma mark - 统一回调处理

- (void)rd_webViewDidStartLoad
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.delegate webViewDidStartLoad:self];
    }
//    self.hidden = YES;
}

- (void)rd_webViewDidFinishLoad
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.delegate webViewDidFinishLoad:self];
    }
    
    self.center = self.webViewOriginCenter;
    self.gesture.enabled = self.canGoBack?YES:NO;
    self.rd_canGoBack = self.canGoBack;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.hidden = NO;
        self.previewImageView.image = self.gobackBackgroundImage;
    });

}

- (void)rd_webViewDidFailLoadWithError:(NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
    
    self.center = self.webViewOriginCenter;
    self.gesture.enabled = self.canGoBack?YES:NO;
    self.rd_canGoBack = self.canGoBack;
    self.hidden = NO;
}

- (BOOL)rd_webViewShouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType
{
    if ([request.URL.absoluteString isEqualToString:@"about:blank"]) {
        return NO;
    }
    
    BOOL ret = YES;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)])
    {
        if(navigationType == -1) {
            navigationType = UIWebViewNavigationTypeOther;
        }
        ret = [self.delegate webView:self shouldStartLoadWithRequest:request navigationType:navigationType];
    }
    
    BOOL isFragmentJump = NO;
    if (request.URL.fragment) {
        NSString *nonFragmentURL = [request.URL.absoluteString stringByReplacingOccurrencesOfString:[@"#" stringByAppendingString:request.URL.fragment] withString:@""];
        isFragmentJump = [nonFragmentURL isEqualToString:request.URL.absoluteString];
    }
    
    BOOL isTopLevelNavigation = [request.mainDocumentURL isEqual:request.URL];
    
    BOOL isHTTPOrFile = [request.URL.scheme isEqualToString:@"http"] || [request.URL.scheme isEqualToString:@"https"] || [request.URL.scheme isEqualToString:@"file"];
    if (ret && !isFragmentJump && isHTTPOrFile && isTopLevelNavigation) {
        if ((navigationType != UIWebViewNavigationTypeOther && navigationType != UIWebViewNavigationTypeBackForward) && [[request.URL description] length]) {
            //if (![[[self.historyBackImages lastObject] objectForKey:@"url"] isEqualToString:[self.request.URL description]]) {
            //    UIImage *curPreview = [RDWebView screenshotOfView:self];
            UIImage *image = [RDWebView screenshotOfView:self.realWebView];
            NSDictionary *dic = @{
                                  @"url":request.URL.description,
                                  @"image":image
                                      };
            [self.historyBackImages addObject:dic];
            self.gobackBackgroundImage = image;
            //}
        }else if (navigationType == UIWebViewNavigationTypeBackForward)
        {
            if (self.historyBackImages.count > 0) {
                [self.historyBackImages removeLastObject];
                if (self.historyBackImages.count > 0 && [self.historyBackImages.lastObject[@"url"] isEqualToString:request.URL.description]) {
                    NSLog(@"image= %@", self.historyBackImages.lastObject[@"image"]);
                    self.gobackBackgroundImage = self.historyBackImages.lastObject[@"image"];
                }else
                {
                    self.gobackBackgroundImage = nil;
                }
            }
        }else
        {
            self.gobackBackgroundImage = nil;
        }
    }else
    {
        //拦截特殊URL 用于js与oc交互
        if (self.jsHandler) {
            BOOL b = self.jsHandler([request URL]);
            if (!b) {
                return NO;
            }
        }
    }
    
    return ret;
}

#pragma mark -

- (BOOL)usingUIWebView
{
    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_8_4) {
        return NO;
    }else
    {
        return YES;
    }
}

-(BOOL)canGoBack
{
    return [self.realWebView canGoBack];
}

- (void)goBack
{
    @weakify(self);
    if (self.usingUIWebView) {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [(UIWebView *)self.realWebView goBack];
    }else
    {
        NSSet *websiteDataTypes = [NSSet setWithArray:@[WKWebsiteDataTypeMemoryCache]];
        NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{
            @strongify(self);
            [(WKWebView *)self.realWebView goBack];
        }];
    }
//    [self.historyBackImages removeLastObject];
}

- (id)loadRequest:(NSURLRequest *)request
{
//    self.originRequest = request;
//    self.currentRequest = request;
    
    if(self.usingUIWebView)
    {
        [(UIWebView*)self.realWebView loadRequest:request];
        return nil;
    }
    else
    {
        return [(WKWebView*)self.realWebView loadRequest:request];
    }
}

- (void)setScalesPageToFit:(BOOL)scalesPageToFit
{
    if(self.usingUIWebView)
    {
        UIWebView* webView = _realWebView;
        webView.scalesPageToFit = scalesPageToFit;
    }
    else
    {
        if(_scalesPageToFit == scalesPageToFit)
        {
            return;
        }
        
        WKWebView* webView = _realWebView;
        
        NSString *jScript = @"var meta = document.createElement('meta'); \
        meta.name = 'viewport'; \
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'; \
        var head = document.getElementsByTagName('head')[0];\
        head.appendChild(meta);";
        
        if(scalesPageToFit)
        {
            WKUserScript *wkUScript = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:jScript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
            [webView.configuration.userContentController addUserScript:wkUScript];
        }
        else
        {
            NSMutableArray* array = [NSMutableArray arrayWithArray:webView.configuration.userContentController.userScripts];
            for (WKUserScript *wkUScript in array)
            {
                if([wkUScript.source isEqual:jScript])
                {
                    [array removeObject:wkUScript];
                    break;
                }
            }
            for (WKUserScript *wkUScript in array)
            {
                [webView.configuration.userContentController addUserScript:wkUScript];
            }
        }
    }
    
    _scalesPageToFit = scalesPageToFit;
}
- (BOOL)scalesPageToFit
{
    if(self.scalesPageToFit)
    {
        return [_realWebView scalesPageToFit];
    }
    else
    {
        return _scalesPageToFit;
    }
}

- (UIScrollView *)scrollView
{
    if (self.usingUIWebView) {
        return [(UIWebView *)self.realWebView scrollView];
    }else
    {
        return [(WKWebView *)self.realWebView scrollView];
    }
}

@end
