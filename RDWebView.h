//
//  RDWebView.h
//  RiceDonate
//
//  Created by ozr on 16/1/22.
//  Copyright © 2016年 ricedonate. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RDWebView;
@protocol RDWebViewDelegate <NSObject>
@optional

- (void)webViewDidStartLoad:(RDWebView *)webView;
- (void)webViewDidFinishLoad:(RDWebView *)webView;
- (void)webView:(RDWebView *)webView didFailLoadWithError:(NSError *)error;
- (BOOL)webView:(RDWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType;

@end

typedef BOOL (^RDWebViewJSHandler)(NSURL *requestURL);

//startload的时候要把自己隐藏 因为startload可能会导致位置重设 等待finish把自己展示

//注意 需要加入rac 监听是否能goback 决定interactivePopGestureRecognizer.enable
//例如
//- (void)viewDidAppear:(BOOL)animated
//{
//    [super viewDidAppear:animated];
//    
//    RACSignal *signal = [[RACObserve(self.webView, rd_canGoBack) takeUntil:[self rac_signalForSelector:@selector(viewWillDisappear:)]] map:^id(id value) {
//        return @(![value boolValue]);
//    }];
//    
//    RAC(self.navigationController.interactivePopGestureRecognizer, enabled) = signal;
//}
//
//- (void)viewWillDisappear:(BOOL)animated
//{
//    [super viewWillDisappear:animated];
//    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
//}

@interface RDWebView : UIView

@property (nonatomic, assign) BOOL rd_canGoBack;
//用于objective-C 与 JS交互 返回false则表示匹配成功 拦截改URL
@property (nonatomic, copy)   RDWebViewJSHandler jsHandler;
///是否根据视图大小来缩放页面  默认为YES
@property (nonatomic, assign) BOOL scalesPageToFit;
@property (nonatomic, weak)   id<RDWebViewDelegate> delegate;

@property (nonatomic, readonly) UIScrollView *scrollView;

- (void)goBack;
- (BOOL)canGoBack;
- (id)loadRequest:(NSURLRequest *)request;

@end
