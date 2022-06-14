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

#import "ApproovURLSession.h"
#import <CommonCrypto/CommonCrypto.h>

/* The custom delegate */
@interface PinningURLSessionDelegate : NSObject <NSURLSessionDelegate,NSURLSessionTaskDelegate,NSURLSessionDataDelegate,NSURLSessionDownloadDelegate>
- (instancetype)initWithDelegate: (id<NSURLSessionDelegate>)delegate;
@end




/* The ApproovSessionTask observer */
@interface ApproovSessionTaskObserver : NSObject
typedef void (^completionHandlerData)(id, id, NSError*);
-(void)addCompletionHandlerTask:(NSUInteger)taskId dataHandler:(completionHandlerData)handler;
@end

@implementation ApproovURLSession


NSURLSession* pinnedURLSession;
NSURLSessionConfiguration* urlSessionConfiguration;
PinningURLSessionDelegate* pinnedURLSessionDelegate;
NSOperationQueue* delegateQueue;
// The observer object
ApproovSessionTaskObserver* taskObserver;
/*
 *  URLSession initializer
 *   see ApproovURLSession.h
 */
+ (ApproovURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                      delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    urlSessionConfiguration = configuration;
    pinnedURLSessionDelegate = [[PinningURLSessionDelegate alloc] initWithDelegate:delegate];
    delegateQueue = queue;
    // Set as URLSession delegate our implementation
    pinnedURLSession = [NSURLSession sessionWithConfiguration:urlSessionConfiguration delegate:pinnedURLSessionDelegate delegateQueue:delegateQueue];
    taskObserver = [[ApproovSessionTaskObserver alloc] init];
    return [[ApproovURLSession alloc] init];
}

/*
 *  URLSession initializer
 *   see ApproovURLSession.h
 */
+ (ApproovURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    return [ApproovURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];
}

- (instancetype)init {
    if([super init]){
        return self;
    }
    return nil;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    return [self dataTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler
{
    return [self dataTaskWithRequest:[[NSURLRequest alloc] initWithURL:url] completionHandler:completionHandler];
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // Create the return object
    NSURLSessionDataTask* sessionDataTask = [pinnedURLSession dataTaskWithRequest:requestWithHeaders];
    // Add observer
    [sessionDataTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionDataTask;

}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionDataTask* sessionDataTask;
    // Check if completionHandler is nil and if so provide a delegate version
    if (completionHandler != nil) {
        // Create the return object
        sessionDataTask = [pinnedURLSession dataTaskWithRequest:requestWithHeaders completionHandler:completionHandler];
        // Add completionHandler
        [taskObserver addCompletionHandlerTask:sessionDataTask.taskIdentifier dataHandler:completionHandler];
    } else {
        sessionDataTask = [pinnedURLSession dataTaskWithRequest:requestWithHeaders];
    }
    // Add observer
    [sessionDataTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionDataTask;
}

// MARK: Download Tasks
/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url {
    return [self downloadTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return [self downloadTaskWithRequest:[[NSURLRequest alloc] initWithURL:url] completionHandler:completionHandler];
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionDownloadTask* sessionDownloadTask = [pinnedURLSession downloadTaskWithRequest:requestWithHeaders];
    // Add observer
    [sessionDownloadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionDownloadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionDownloadTask* sessionDownloadTask;
    // Check if completionHandler is nil and if so provide a delegate version
    if (completionHandler != nil){
        sessionDownloadTask = [pinnedURLSession downloadTaskWithRequest:requestWithHeaders completionHandler:completionHandler];
        // Add completionHandler
        [taskObserver addCompletionHandlerTask:sessionDownloadTask.taskIdentifier dataHandler:completionHandler];
    } else {
        sessionDownloadTask = [pinnedURLSession downloadTaskWithRequest:requestWithHeaders];
    }
    // Add observer
    [sessionDownloadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionDownloadTask;
}

/*  NOTE: this call is not protected by Approov
 *   see ApproovURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData {
    return [pinnedURLSession downloadTaskWithResumeData:resumeData];
}

/*  NOTE: this call is not protected by Approov
 *   see ApproovURLSession.h
 */
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
                                       completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return [pinnedURLSession downloadTaskWithResumeData:resumeData completionHandler:completionHandler];
}

// MARK: Upload Tasks
/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask = [pinnedURLSession uploadTaskWithRequest: requestWithHeaders fromFile:fileURL];
    // Add observer
    [sessionUploadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromFile:(NSURL *)fileURL
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask;
    // Check if completionHandler is nil and if so provide a delegate version
    if(completionHandler != nil){
        sessionUploadTask = [pinnedURLSession uploadTaskWithRequest:requestWithHeaders fromFile:fileURL completionHandler:completionHandler];
        // Add completionHandler
        [taskObserver addCompletionHandlerTask:sessionUploadTask.taskIdentifier dataHandler:completionHandler];
    } else {
        sessionUploadTask = [pinnedURLSession uploadTaskWithRequest:requestWithHeaders fromFile:fileURL];
    }
    // Add observer
    [sessionUploadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask = [pinnedURLSession uploadTaskWithStreamedRequest:requestWithHeaders];
    // Add observer
    [sessionUploadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask = [pinnedURLSession uploadTaskWithRequest:requestWithHeaders fromData:bodyData];
    // Add observer
    [sessionUploadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask;
    // Check if completionHandler is nil and if so provide a delegate version
    if (completionHandler != nil){
        sessionUploadTask = [pinnedURLSession uploadTaskWithRequest:requestWithHeaders fromData:bodyData completionHandler:completionHandler];
        // Add completionHandler
        [taskObserver addCompletionHandlerTask:sessionUploadTask.taskIdentifier dataHandler:completionHandler];
    } else {
        sessionUploadTask = [pinnedURLSession uploadTaskWithRequest:requestWithHeaders fromData:bodyData];
    }
    
    // Add observer
    [sessionUploadTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionUploadTask;
}

// MARK: Websocket task
/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url API_AVAILABLE(ios(13.0)) {
    return [self webSocketTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}

/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request  API_AVAILABLE(ios(13.0)){
    // Add the session headers to the task
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // The return object
    NSURLSessionWebSocketTask* sessionWebSocketTask = [pinnedURLSession webSocketTaskWithRequest:requestWithHeaders];
    // Add observer
    [sessionWebSocketTask addObserver:taskObserver forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    return sessionWebSocketTask;
}


/*
 *   see ApproovURLSession.h
 */
- (void)finishTasksAndInvalidate {
    [pinnedURLSession finishTasksAndInvalidate];
}
/*
 *   see ApproovURLSession.h
 */
- (void)flushWithCompletionHandler:(void (^)(void))completionHandler {
    [pinnedURLSession flushWithCompletionHandler:completionHandler];
}
/*
 *   see ApproovURLSession.h
 */
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *dataTasks, NSArray<NSURLSessionUploadTask *> *uploadTasks, NSArray<NSURLSessionDownloadTask *> *downloadTasks))completionHandler {
    [pinnedURLSession getTasksWithCompletionHandler:completionHandler];
}
/*
 *   see ApproovURLSession.h
 */
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler {
    [pinnedURLSession getAllTasksWithCompletionHandler:completionHandler];
}
/*
 *   see ApproovURLSession.h
 */
- (void)invalidateAndCancel {
    [pinnedURLSession invalidateAndCancel];
}
/*
 *   see ApproovURLSession.h
 */
- (void)resetWithCompletionHandler:(void (^)(void))completionHandler {
    [pinnedURLSession resetWithCompletionHandler:completionHandler];
}

/*  Add any additional session defined headers to a NSURLRequest object
 *  @param  request URLRequest
 *  @return copy of original request with additional session headers
 */
- (NSURLRequest*)addUserHeadersToRequest:(NSURLRequest*)userRequest {
    // Make a mutable copy
    NSMutableURLRequest *newRequest = [userRequest mutableCopy];
    NSDictionary* allHeaders = urlSessionConfiguration.HTTPAdditionalHeaders;
    for (NSString* key in allHeaders){
        [newRequest addValue:[allHeaders valueForKey:key] forHTTPHeaderField:key];
    }
    return [newRequest copy];
}


@end




@implementation PinningURLSessionDelegate
id<NSURLSessionDelegate,NSURLSessionTaskDelegate,NSURLSessionDataDelegate,NSURLSessionDownloadDelegate> optionalURLDelegate;
BOOL mPKIInitialized;
/* Subject public key info (SPKI) headers for public keys' type and size. Only RSA-2048, RSA-4096, EC-256 and EC-384 are supported.
 */
static NSDictionary<NSString *, NSDictionary<NSNumber *, NSData *> *> *sSPKIHeaders;
- (void)initializePKI {
    const unsigned char rsa2048SPKIHeader[] = {
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
        0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    };
    const unsigned char rsa4096SPKIHeader[] = {
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
        0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    };
    const unsigned char ecdsaSecp256r1SPKIHeader[] = {
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48,
        0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    };
    const unsigned char ecdsaSecp384r1SPKIHeader[] = {
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04,
        0x00, 0x22, 0x03, 0x62, 0x00
    };
    sSPKIHeaders = @{
        (NSString *)kSecAttrKeyTypeRSA : @{
              @2048 : [NSData dataWithBytes:rsa2048SPKIHeader length:sizeof(rsa2048SPKIHeader)],
              @4096 : [NSData dataWithBytes:rsa4096SPKIHeader length:sizeof(rsa4096SPKIHeader)]
        },
        (NSString *)kSecAttrKeyTypeECSECPrimeRandom : @{
              @256 : [NSData dataWithBytes:ecdsaSecp256r1SPKIHeader length:sizeof(ecdsaSecp256r1SPKIHeader)],
              @384 : [NSData dataWithBytes:ecdsaSecp384r1SPKIHeader length:sizeof(ecdsaSecp384r1SPKIHeader)]
        }
    };
    mPKIInitialized = YES;
}

- (instancetype)initWithDelegate: (id<NSURLSessionDelegate,NSURLSessionTaskDelegate,NSURLSessionDataDelegate,NSURLSessionDownloadDelegate>)delegate {
    if([super init]){
        if (!mPKIInitialized){
            [self initializePKI];
        }
        optionalURLDelegate = delegate;
        return self;
    }
    return nil;
}

/*  NSURLSessionDelegate
 *  A protocol that defines methods that URL session instances call on their delegates to handle session-level events,
 *  like session life cycle changes
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate
 */

/*  Tells the URL session that the session has been invalidated
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1407776-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    [optionalURLDelegate URLSession:session didBecomeInvalidWithError:error];
}

/*  Tells the delegate that all messages enqueued for a session have been delivered
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1617185-urlsessiondidfinisheventsforback?language=objc
 */
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    [optionalURLDelegate URLSessionDidFinishEventsForBackgroundURLSession:session];
}

/*  Requests credentials from the delegate in response to a session-level authentication request from the remote server
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1409308-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    BOOL respondsToSelector = [optionalURLDelegate respondsToSelector:@selector(URLSession:didReceiveChallenge:completionHandler:)];
    // we are only interested in server trust requests
    if(![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]){
        if (respondsToSelector) {
            [optionalURLDelegate URLSession:session didReceiveChallenge:challenge completionHandler: completionHandler];
        } else if (completionHandler != nil) {
            NSLog(@"approov-service: Challenge authentication other than ServerTrust must be handled by a user delegate");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
        return;
    }
    NSError* error;
    SecTrustRef serverTrust = [self shouldAcceptAuthenticationChallenge:challenge error:&error];
    if ((error == nil) && (serverTrust != nil)) {
        if (respondsToSelector) {
            [optionalURLDelegate URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
        } else if (completionHandler != nil){
            completionHandler(NSURLSessionAuthChallengeUseCredential, [[NSURLCredential alloc]initWithTrust:serverTrust]);
        }
        return;
    }
    if(error != nil){
        // Log error message
        NSLog(@"approov-service: Pinning: %@", error.localizedDescription);
    } else {
        // serverTrust == nil
        NSLog(@"approov-service: Pinning: No pins match for host %@", challenge.protectionSpace.host);
    }
    // Cancel connection
    completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}

/*  URLSessionTaskDelegate
 *  A protocol that defines methods that URL session instances call on their delegates to handle task-level events
 *  https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate?language=objc
 */

/*  Requests credentials from the delegate in response to an authentication request from the remote server
 *  https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411595-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    BOOL respondsToSelector = [optionalURLDelegate respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)];
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    // we are only interested in server trust requests
    if (respondsToSelector) {
        [optionalURLDelegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
    } else if (completionHandler != nil){
        completionHandler(NSURLSessionAuthChallengeUseCredential,[[NSURLCredential alloc]initWithTrust:serverTrust]);
    }
}

/*  Tells the delegate that the task finished transferring data
 *   https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411610-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]){
        [optionalURLDelegate URLSession:session task:task didCompleteWithError:error];
    }
}

/*  Tells the delegate that the remote server requested an HTTP redirect
 *  https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411626-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]){
        [optionalURLDelegate URLSession:session task:task willPerformHTTPRedirection:response newRequest:request completionHandler:completionHandler];
    }
}

/*  Tells the delegate when a task requires a new request body stream to send to the remote server
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1410001-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
             task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:task:needNewBodyStream:)]){
        [optionalURLDelegate URLSession:session task:task needNewBodyStream:completionHandler];
    }
}

/*  Periodically informs the delegate of the progress of sending body content to the server
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1408299-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)]){
        [optionalURLDelegate URLSession:session task:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
    }
}

/*  Tells the delegate that a delayed URL session task will now begin loading
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2873415-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willBeginDelayedRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLSessionDelayedRequestDisposition disposition, NSURLRequest *newRequest))completionHandler  API_AVAILABLE(ios(11.0)){
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:task:willBeginDelayedRequest:completionHandler:)]){
        [optionalURLDelegate URLSession:session task:task willBeginDelayedRequest:request completionHandler:completionHandler];
    }
}

/*  Tells the delegate that the session finished collecting metrics for the task
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1643148-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:task:didFinishCollectingMetrics:)]){
        [optionalURLDelegate URLSession:session task:task didFinishCollectingMetrics:metrics];
    }
}

/*  Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2908819-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
taskIsWaitingForConnectivity:(NSURLSessionTask *)task API_AVAILABLE(ios(11.0)) {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:taskIsWaitingForConnectivity:)]){
        [optionalURLDelegate URLSession:session taskIsWaitingForConnectivity:task];
    }
}


/*  URLSessionDataDelegate
 *  A protocol that defines methods that URL session instances call on their delegates to handle task-level events
 *  specific to data and upload tasks
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondatadelegate?language=objc
 */

/*  Tells the delegate that the data task received the initial reply (headers) from the server
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1410027-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]){
        [optionalURLDelegate URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
    }
}

/*  Tells the delegate that the data task was changed to a download task
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1409936-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didBecomeDownloadTask:)]){
        [optionalURLDelegate URLSession:session dataTask:dataTask didBecomeDownloadTask:downloadTask];
    }
}

/*  Tells the delegate that the data task was changed to a stream task
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411648-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeStreamTask:(NSURLSessionStreamTask *)streamTask {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didBecomeStreamTask:)]){
        [optionalURLDelegate URLSession:session dataTask:dataTask didBecomeStreamTask:streamTask];
    }
}

/*  Tells the delegate that the data task has received some of the expected data
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]){
        [optionalURLDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

/*  Asks the delegate whether the data (or upload) task should store the response in the cache
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411612-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
         dataTask:(NSURLSessionDataTask *)dataTask
willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:willCacheResponse:completionHandler:)]){
        [optionalURLDelegate URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
    }
}

/*  A protocol that defines methods that URL session instances call on their delegates to handle
 *  task-level events specific to download tasks
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate?language=objc
 */

/*  Tells the delegate that a download task has finished downloading
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1411575-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)]){
        [optionalURLDelegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    }
}

/*  Tells the delegate that the download task has resumed downloading
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1408142-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes:)]){
        [optionalURLDelegate URLSession:session downloadTask:downloadTask didResumeAtOffset:fileOffset expectedTotalBytes:expectedTotalBytes];
    }
}

/*  Periodically informs the delegate about the download’s progress
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1409408-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if([optionalURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)]){
        [optionalURLDelegate URLSession:session downloadTask:downloadTask didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}


/* Error codes related to TLS certificate processing */
typedef NS_ENUM(NSUInteger, SecCertificateRefError)
{
    NOT_SERVER_TRUST = 1100,
    SERVER_CERTIFICATE_FAILED_VALIDATION,
    SERVER_TRUST_EVALUATION_FAILURE,
    CERTIFICATE_CHAIN_READ_ERROR,
    PUBLIC_KEY_INFORMATION_READ_FAILURE
};

/*  Evaluates a URLAuthenticationChallenge deciding if to proceed further/
 *
 *  @param  challenge: NSURLAuthenticationChallenge
 *  @return SecTrustRef: valid SecTrust if authentication should proceed, nil otherwise
 */
- (SecTrustRef)shouldAcceptAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge error:(NSError **)error {
    // check we have a server trust
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    if(!serverTrust) {
        // Set error message and return
        *error = [ApproovService createErrorWithCode:NOT_SERVER_TRUST userMessage:@"ApproovURLSession not a server trust"
            ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    }
    // check the validity of the server cert
    SecTrustResultType result;
    OSStatus status = SecTrustEvaluate(serverTrust, &result);
    if(status != errSecSuccess){
        // Set error message and return
        *error = [ApproovService createErrorWithCode:SERVER_CERTIFICATE_FAILED_VALIDATION
            userMessage:@"ApproovURLSession: server certificate validation failed"
            ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    } else if((result != kSecTrustResultUnspecified) && (result != kSecTrustResultProceed)){
        // Set error message and return
        *error = [ApproovService createErrorWithCode:SERVER_TRUST_EVALUATION_FAILURE
            userMessage:@"ApproovURLSession: server trust evaluation failed"
            ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    }
    NSDictionary* pins = [ApproovService getPins:@"public-key-sha256"];
    // if no pins are defined then we trust the connection
    if (pins == nil) {
        return serverTrust;
    }
    
    // get the certificate chain count
    int certCountInChain = (int)SecTrustGetCertificateCount(serverTrust);
    int indexCurrentCert = 0;
    while(indexCurrentCert < certCountInChain) {
        SecCertificateRef serverCert = SecTrustGetCertificateAtIndex(serverTrust, indexCurrentCert);
        if(serverCert == nil) {
            // Set error message and return
            *error = [ApproovService createErrorWithCode:CERTIFICATE_CHAIN_READ_ERROR
                userMessage:@"ApproovURLSession: failed to read certificate from chain"
                ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return nil;
        }
        // get the subject public key info from the certificate
        NSData* publicKeyInfo = [self publicKeyInfoOfCertificate:serverCert];
        if(publicKeyInfo == nil){
            // Set error message and return
            *error = [ApproovService createErrorWithCode:PUBLIC_KEY_INFORMATION_READ_FAILURE
                userMessage:@"ApproovURLSession: failed reading public key information"
                ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return nil;
        }
        
        // compute the SHA-256 hash of the public key info and base64 encode the result
        CC_SHA256_CTX shaCtx;
        CC_SHA256_Init(&shaCtx);
        CC_SHA256_Update(&shaCtx,(void*)[publicKeyInfo bytes],(unsigned)publicKeyInfo.length);
        unsigned char publicKeyHash[CC_SHA256_DIGEST_LENGTH] = {'\0',};
        CC_SHA256_Final(publicKeyHash, &shaCtx);
        // Base64 encode the sha256 hash
        NSString *publicKeyHashBase64 = [[NSData dataWithBytes:publicKeyHash length:CC_SHA256_DIGEST_LENGTH] base64EncodedStringWithOptions:0];
        
        // match pins on the receivers host
        NSString* host = challenge.protectionSpace.host;
        if([pins objectForKey:host] != nil){
            // We have on or more cert hashes matching the receivers host, compare them
            NSArray<NSString*>* certHashList = [pins objectForKey:host];
            if (certHashList.count == 0) { // the host is in but no pins defined
                // if there are no pins and no managed trust allow connection
                if ([pins objectForKey:@"*"] == nil) {
                    return serverTrust;  // We do not pin connection explicitly setting no pins for the host
                } else {
                    // there are no pins for current host, then we try and use any managed trust roots since @"*" is available
                    certHashList = [pins objectForKey:@"*"];
                }
            }
            for (NSString* certHash in certHashList){
                if([certHash isEqualToString:publicKeyHashBase64]) {
                    return serverTrust;
                }
            }
        } else {
            // Host is not pinned
            return serverTrust;
        }
        indexCurrentCert += 1;
    }
    // we return nil if no match in current set of pins and certificate chain seen during TLS handshake
    return nil;
}

/*
 * Gets a certificate's subject public key info (SPKI).
 */
- (NSData*)publicKeyInfoOfCertificate:(SecCertificateRef)certificate {
    SecKeyRef publicKey = nil;
    
    if (@available(iOS 12.0, *)) {
        publicKey = SecCertificateCopyKey(certificate);
    } else {
        // Fallback on earlier versions
        // from TrustKit https://github.com/datatheorem/TrustKit/blob/master/TrustKit/Pinning/TSKSPKIHashCache.m lines
        // 221-234:
        // Create an X509 trust using the using the certificate
        SecTrustRef trust;
        SecPolicyRef policy = SecPolicyCreateBasicX509();
        SecTrustCreateWithCertificates(certificate, policy, &trust);
        
        // Get a public key reference for the certificate from the trust
        SecTrustResultType result;
        SecTrustEvaluate(trust, &result);
        publicKey = SecTrustCopyPublicKey(trust);
        CFRelease(policy);
        CFRelease(trust);
    }
    if(publicKey == nil) return nil;
    
    // get the SPKI header depending on the public key's type and size
    NSData* spkiHeader = [self publicKeyInfoHeaderForKey:publicKey];
    if(spkiHeader == nil) return nil;
    
    // combine the public key header and the public key data to form the public key info
    CFDataRef publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil);
    if(publicKeyData == nil) return nil;
    NSMutableData* returnData = [NSMutableData dataWithData:spkiHeader];
    [returnData appendData:(__bridge NSData * _Nonnull)(publicKeyData)];
    CFRelease(publicKeyData);
    return [NSData dataWithData:returnData];
}

/*
 * Gets the subject public key info (SPKI) header depending on a public key's type and size.
 */
- (NSData *)publicKeyInfoHeaderForKey:(SecKeyRef)publicKey {
    // get the SPKI header depending on the key's type and size
    CFDictionaryRef publicKeyAttributes = SecKeyCopyAttributes(publicKey);
    NSString *keyType = CFDictionaryGetValue(publicKeyAttributes, kSecAttrKeyType);
    NSNumber *keyLength = CFDictionaryGetValue(publicKeyAttributes, kSecAttrKeySizeInBits);
    NSData *aSPKIHeader = sSPKIHeaders[keyType][keyLength];
    CFRelease(publicKeyAttributes);
    return aSPKIHeader;
}

@end


@implementation ApproovSessionTaskObserver
static NSString* stateKeyPath = @"state";
NSMutableDictionary<NSString*,id>* completionHandlers;

-(instancetype)init {
    if([super init]) {
        completionHandlers = [[NSMutableDictionary alloc]init];
        return self;
    }
    return nil;
}

/*  Adds a task UUID mapped to a function to be invoked as a callback in case of error
 *  after cancelling the task
 */


-(void)addCompletionHandlerTask:(NSUInteger)taskId dataHandler:(completionHandlerData)handler {
    NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)taskId];
    @synchronized (completionHandlers) {
        [completionHandlers setValue:handler forKey:key];
    }
}
/*
 * It is necessary to use KVO and observe the task returned to the user in order to modify the original request
 * Since we do not want to block the task in order to contact the Approov servers, we have to perform the Approov
 * network connection asynchronously and depending on the result, modify the header and resume the request or
 * cancel the task after informing the caller of the error
 */
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    /*
        NSURLSessionTaskStateRunning = 0,
        NSURLSessionTaskStateSuspended = 1,
        NSURLSessionTaskStateCanceling = 2,
        NSURLSessionTaskStateCompleted = 3,
     */
    if([keyPath isEqualToString:stateKeyPath])
    {
        
        id newC = [change objectForKey:NSKeyValueChangeNewKey];
        long newValue = [newC longValue];
        // The task at hand; we simply cast to superclass from which specific Data/Download ... etc classes inherit
        NSURLSessionTask* task = (NSURLSessionTask*)object;
        // Find out the current task id
        NSString* taskIdString = [NSString stringWithFormat:@"%lu", (unsigned long)task.taskIdentifier];
        /*  If the new state is Cancelling or Completed we must remove ourselves as observers and return
         *  because the user is either cancelling or the connection has simply terminated
         */
        if ((newValue == NSURLSessionTaskStateCompleted) || (newValue == NSURLSessionTaskStateCanceling)) {
            NSLog(@"task id %lu is cancelling or has completed; removing observer", (unsigned long)task.taskIdentifier);
            [task removeObserver:self forKeyPath:stateKeyPath];
            // If the completionHandler is in dictionary, remove it since it will not be needed
            @synchronized (completionHandlers) {
                if ([completionHandlers objectForKey:taskIdString] != nil) {
                    [completionHandlers removeObjectForKey:taskIdString];
                }
            }
            return;
        }
        /*  We detect the initial switch from when the task is created in Suspended state to when the user
         *  triggers the Resume state. We immediately pause the task by suspending it again and doing the background
         *  Approov network connection before considering if the actual connection should be resumed or terminated.
         *  Note that this is meant to only happen during the initial resume call since we remove ourselves as observers
         *  at the first ever resume call
         */
        if (newValue == NSURLSessionTaskStateRunning) {
            // We do not need any information about further changes; we are done since we only need the furst ever resume call
            // Remove observer
            [task removeObserver:self forKeyPath:stateKeyPath];
            // Suspend immediately the task: Note this is optional since the current callback is executed before another one being invoked
            [task suspend];
            // Contact Approov service
            ApproovData* dataResult = [ApproovService updateRequestWithApproov:task.currentRequest];
            // Should we proceed?
            if([dataResult getDecision] == ShouldProceed) {
                // Modify the original request
                SEL selector = NSSelectorFromString(@"updateCurrentRequest:");
                if ([task respondsToSelector:selector]) {
                    IMP imp = [task methodForSelector:selector];
                    void (*func)(id, SEL, NSURLRequest*) = (void *)imp;
                    func(task, selector, [dataResult getRequest]);
                } else {
                    // This means that NSURLRequest has removed the `updateCurrentRequest` method or we are observing an object that
                    // is not an instance of NSURLRequest. Both are fatal errors.
                    NSString* errorMessageSting = [NSString stringWithFormat:@"%@ %@", @"Fatal ApproovSession error: Unable to modify NSURLRequest headers; object instance is of type", NSStringFromClass([task class])];
                    NSLog(@"approov-service: %@", errorMessageSting);
                } // else
                // If the completionHandler is in dictionary, remove it since it will not be needed
                @synchronized (completionHandlers) {
                    if ([completionHandlers objectForKey:taskIdString] != nil) {
                        [completionHandlers removeObjectForKey:taskIdString];
                    }
                }
                // Resume the original task
                [task resume];
                return;
            } else if ([dataResult getDecision] == ShouldIgnore) {
                // We should ignore the request and not modify the headers in any way
                [task resume];
                return;
            } else {
                // Error handling
                @synchronized (completionHandlers) {
                    [pinnedURLSessionDelegate URLSession:pinnedURLSession didBecomeInvalidWithError:[dataResult error]];
                    if ([completionHandlers objectForKey:taskIdString] != nil) {
                        completionHandlerData handler = [completionHandlers objectForKey:taskIdString];
                        handler(nil, nil, [dataResult error]);
                        // We have invoked the original handler with error message; remove it from dictionary
                        [completionHandlers removeObjectForKey:taskIdString];
                    }
                }
                // We should cancel the request since we are finished with error
                [task cancel];
            }
        }
        
    }
}

@end

