//
//  ViewController.m
//  player
//
//  Created by Anders Borum on 11/11/14.
//  Copyright (c) 2014 NOTA. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "ViewController.h"
#import "SoundChunk.h"
#import "Book.h"
#import "BookPart.h"

@interface ViewController () {
    NSArray* chunks;
    AVAudioPlayer* player;
    AVQueuePlayer* queuePlayer;
    
    Book* book;
}
@property (strong, nonatomic) IBOutlet UIWebView *webView;

@end

@implementation ViewController

#pragma mark UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType {
    NSLog(@"shouldStartLoadWithRequest: %@, type: %d", request, (int)navigationType);
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    NSLog(@"webViewDidFinishLoad: %@", webView.request.URL);
    
    if([webView.request.URL.fragment isEqualToString:@"login"]) {
        /*dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self loadBookshelf];
        });*/
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    NSLog(@"webView: %@ didFailLoadWithError: %@", webView.request.URL, error);
}

#pragma mark -

-(void)loadTestBook {
    NSString* path = [[NSBundle mainBundle] pathForResource:@"37027.json" ofType:nil];
    NSData* data = [NSData dataWithContentsOfFile:path];
    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    
    NSURL* baseURL = [NSURL URLWithString:@"http://m.e17.dk/DodpFiles/20014/37027/"];
    book = [Book bookFromDictionary:json baseURL:baseURL];
    [book joinParts];
}

-(void)testPlay {
    queuePlayer = [book makeQueuePlayer];
    [queuePlayer play];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"play error: %@", queuePlayer.error);
    });
}

-(void)testDownload {
    [book deleteCache];
    book.bufferingPoint = 100;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [book play];
        //[queuePlayer play];

        //BookPart* part = book.parts.firstObject;
        //NSURL* url = [NSURL fileURLWithPath: part.cachePath];
        //AVPlayerItem* item = [AVPlayerItem playerItemWithURL: url];
        
        //queuePlayer = [AVQueuePlayer queuePlayerWithItems:@[item]];
        //[queuePlayer play];
        //AVAudioPlayer* audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
        //[audioPlayer play];
        
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            //[audioPlayer stop];
            
            //[queuePlayer pause];
            //AVPlayerItem* firstItem = queuePlayer.items.firstObject;
            //NSLog(@"play error: %@", audioPlayer.error);
        });
    });
}

-(void)loadBookshelf {
    NSURL* url = [NSURL URLWithString:@"http://m.e17.dk/#bookshelf?guest=true"];
    NSURLRequest* request = [NSURLRequest requestWithURL:url];
    
    [self.webView loadRequest:request];
}

- (void)viewDidLoad {
    
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self loadTestBook];
    //[self testPlay];
    [self testDownload];
    
    //NSURL* url = [NSURL URLWithString:@"http://m.e17.dk/#login"];
    //NSURLRequest* request = [NSURLRequest requestWithURL:url];
    //[self.webView loadRequest:request];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
