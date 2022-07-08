// MIT License
//
// Copyright (c) 2016-present, Critical Blue Ltd.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
// THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "ApproovNSURLSession.h"
#import "ApproovPinningURLSessionDelegate.h"
#import <CommonCrypto/CommonCrypto.h>

// properties for each ApproovNSURLSession instance
@interface ApproovNSURLSession()

// pinned session that is delegated to
@property NSURLSession *pinnedURLSession;

// URL session configuration retained to obtain session wide headers without duplicating each time
@property NSURLSessionConfiguration *config;

@end

// provides an Approov capable implementation of NSURLSession. A pinned delegate is used, which may further delegare to any user
// supplied one. An internal NSURLSession is created which is used to perform the actual network requests once Approov tokens
// or substiutions have been applied.
@implementation ApproovNSURLSession

/**
 *  URLSession initializer
 *  see ApproovNSURLSession.h
 */
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                      delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    ApproovNSURLSession *session = [[ApproovNSURLSession alloc] init];
    session.config = configuration;
    ApproovPinningURLSessionDelegate *pinnedDelegate = [[ApproovPinningURLSessionDelegate alloc] initWithDelegate:delegate];
    session.pinnedURLSession = [NSURLSession sessionWithConfiguration:configuration delegate:pinnedDelegate delegateQueue:queue];
    return session;
}

/**
 *  URLSession initializer
 *  see ApproovNSURLSession.h
 */
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    return [ApproovNSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];
}
/**
 * Allow private  construction only.
 */
- (instancetype)init {
    if ([super init]) {
        return self;
    }
    return nil;
}

/**
 * see ApproovNSURLSession.h
 */
- (NSURLSessionConfiguration *)configuration {
    return self.pinnedURLSession.configuration;
}

/**
 * see ApproovNSURLSession.h
 */
- (id<NSURLSessionDelegate>)delegate {
    return self.pinnedURLSession.delegate;
}

/**
 * see ApproovNSURLSession.h
 */
- (NSOperationQueue *)delegateQueue {
    return self.pinnedURLSession.delegateQueue;
}

/**
 * see ApproovNSURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    return [self dataTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler
{
    return [self dataTaskWithRequest:[[NSURLRequest alloc] initWithURL:url] completionHandler:completionHandler];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *sessionDataTask = [self.pinnedURLSession dataTaskWithRequest:request];
    [ApproovService interceptSessionTask:sessionDataTask sessionConfig:self.config completionHandler:nil];
    return sessionDataTask;

}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDataTask *sessionDataTask = [self.pinnedURLSession dataTaskWithRequest:request completionHandler:completionHandler];
    [ApproovService interceptSessionTask:sessionDataTask sessionConfig:self.config completionHandler:completionHandler];
    return sessionDataTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url {
    return [self downloadTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return [self downloadTaskWithRequest:[[NSURLRequest alloc] initWithURL:url] completionHandler:completionHandler];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDownloadTask *sessionDownloadTask = [self.pinnedURLSession downloadTaskWithRequest:request];
    [ApproovService interceptSessionTask:sessionDownloadTask sessionConfig:self.config completionHandler:nil];
    return sessionDownloadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDownloadTask *sessionDownloadTask = [self.pinnedURLSession downloadTaskWithRequest:request
        completionHandler:completionHandler];
    [ApproovService interceptSessionTask:sessionDownloadTask sessionConfig:self.config
        completionHandler:(CompletionHandlerType)completionHandler];
    return sessionDownloadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData {
    // Approov protection is not provided for this
    return [self.pinnedURLSession downloadTaskWithResumeData:resumeData];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
                                       completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    // Approov protection is not provided for this
    return [self.pinnedURLSession downloadTaskWithResumeData:resumeData completionHandler:completionHandler];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL {
    NSURLSessionUploadTask *sessionUploadTask = [self.pinnedURLSession uploadTaskWithRequest:request fromFile:fileURL];
    [ApproovService interceptSessionTask:sessionUploadTask sessionConfig:self.config completionHandler:nil];
    return sessionUploadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
        fromFile:(NSURL *)fileURL
        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionUploadTask *sessionUploadTask = [self.pinnedURLSession uploadTaskWithRequest:request
            fromFile:fileURL completionHandler:completionHandler];
    [ApproovService interceptSessionTask:sessionUploadTask sessionConfig:self.config
            completionHandler:completionHandler];
    return sessionUploadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    NSURLSessionUploadTask *sessionUploadTask = [self.pinnedURLSession uploadTaskWithStreamedRequest:request];
    [ApproovService interceptSessionTask:sessionUploadTask sessionConfig:self.config completionHandler:nil];
    return sessionUploadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData {
    NSURLSessionUploadTask *sessionUploadTask = [self.pinnedURLSession uploadTaskWithRequest:request fromData:bodyData];
    [ApproovService interceptSessionTask:sessionUploadTask sessionConfig:self.config completionHandler:nil];
    return sessionUploadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromData:(NSData *)bodyData
         completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionUploadTask *sessionUploadTask = [self.pinnedURLSession uploadTaskWithRequest:request
        fromData:bodyData completionHandler:completionHandler];
    [ApproovService interceptSessionTask:sessionUploadTask sessionConfig:self.config completionHandler:completionHandler];
    return sessionUploadTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionStreamTask *)streamTaskWithHostName:(NSString *)hostname port:(NSInteger)port {
    // Approov protection is not provided for this
    return [self streamTaskWithHostName:hostname port:port];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url API_AVAILABLE(ios(13.0)) {
    return [self webSocketTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}

/**
 *  see ApproovNSURLSession.h
 */
- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request API_AVAILABLE(ios(13.0)){
    NSURLSessionWebSocketTask *sessionWebSocketTask = [self.pinnedURLSession webSocketTaskWithRequest:request];
    [ApproovService interceptSessionTask:sessionWebSocketTask sessionConfig:self.config completionHandler:nil];
    return sessionWebSocketTask;
}

/**
 *  see ApproovNSURLSession.h
 */
- (void)finishTasksAndInvalidate {
    [self.pinnedURLSession finishTasksAndInvalidate];
}

/**
 *  see ApproovNSURLSession.h
 */
- (void)flushWithCompletionHandler:(void (^)(void))completionHandler {
    [self.pinnedURLSession flushWithCompletionHandler:completionHandler];
}

/**
 *  see ApproovNSURLSession.h
 */
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *dataTasks, NSArray<NSURLSessionUploadTask *> *uploadTasks, NSArray<NSURLSessionDownloadTask *> *downloadTasks))completionHandler {
    [self.pinnedURLSession getTasksWithCompletionHandler:completionHandler];
}

/**
 *  see ApproovNSURLSession.h
 */
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler {
    [self.pinnedURLSession getAllTasksWithCompletionHandler:completionHandler];
}

/**
 *  see ApproovNSURLSession.h
 */
- (void)invalidateAndCancel {
    [self.pinnedURLSession invalidateAndCancel];
}

/**
 *  see ApproovNSURLSession.h
 */
- (void)resetWithCompletionHandler:(void (^)(void))completionHandler {
    [self.pinnedURLSession resetWithCompletionHandler:completionHandler];
}

@end
