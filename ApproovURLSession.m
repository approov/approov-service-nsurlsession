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
#import "Approov/Approov.h"

/* Token fetch decision code */
typedef NS_ENUM(NSUInteger, ApproovTokenNetworkFetchDecision) {
    ShouldProceed,
    ShouldRetry,
    ShouldFail,
};

/* ApproovSDk token fetch return object */
@interface ApproovData : NSObject
@property (getter=getRequest)NSURLRequest* request;
@property (getter=getDecision)ApproovTokenNetworkFetchDecision decision;
@property (getter=getSdkMessage)NSString* sdkMessage;
@property NSError* error;
@end

/* The ApproovSDK interface wrapper */
@interface ApproovService:NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedInstance:(NSString*)configString;
+ (void)setBindHeader:(NSString*)newHeader;
+ (NSString*)getBindHeader;
+ (void)prefetch;
/* The ApproovSDK error enum status codes mapped to a NSString */
+ (NSString*)stringFromApproovTokenFetchStatus:(NSUInteger)status;
- (NSString*)getApproovTokenHeader;
- (void)setApproovTokenHeader:(NSString*)newHeader;
- (NSString*)getApproovTokenPrefix;
- (void)setApproovTokenPrefix:(NSString*)newHeader;
- (void)addSubstitutionHeader:(NSString*)header requiredPrefix:(NSString*)prefix;
- (void)removeSubstitutionHeader:(NSString*)header;
- (ApproovData*)fetchApproovToken:(NSURLRequest*)request;
- (NSString*)fetchSecureString:(NSString*)key newDefinition:(NSString*)newDef error:(NSError**)error;
- (NSString*)fetchCustomJWT:(NSString*)payload error:(NSError**)error;
@end

/* The custom delegate */
@interface ApproovURLSessionDelegate : NSObject <NSURLSessionDelegate,NSURLSessionTaskDelegate,NSURLSessionDataDelegate,NSURLSessionDownloadDelegate>
- (instancetype)initWithDelegate: (id<NSURLSessionDelegate>)delegate;
@end

/*
 *  Encapsulates Approov SDk errors, decisions to proceed or not and any user defined headers
 */
@implementation ApproovData

- (instancetype)init {
    if([super init]){
        [self setDecision:ShouldFail];
        return self;
    }
    return nil;
}

@end


@implementation ApproovURLSession


NSURLSession* urlSession;
NSURLSessionConfiguration* urlSessionConfiguration;
ApproovURLSessionDelegate* urlSessionDelegate;
NSOperationQueue* delegateQueue;
ApproovService* approovSDK;

/*
 *  URLSession initializer
 *   see ApproovURLSession.h
 */
+ (ApproovURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                      delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue configString:(NSString *)config {
    urlSessionConfiguration = configuration;
    urlSessionDelegate = [[ApproovURLSessionDelegate alloc] initWithDelegate:delegate];
    delegateQueue = queue;
    // Set as URLSession delegate our implementation
    urlSession = [NSURLSession sessionWithConfiguration:urlSessionConfiguration delegate:urlSessionDelegate delegateQueue:delegateQueue];
    approovSDK = [ApproovService sharedInstance:config];
    return [[ApproovURLSession alloc] init];
}

/*
 *  URLSession initializer
 *   see ApproovURLSession.h
 */

+ (ApproovURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration                                                   configString:(NSString *)config {
    return [ApproovURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:nil configString:config];
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
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionDataTask* sessionDataTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest]];
        return sessionDataTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed:
            // Go ahead and make the API call with the provided request object
            sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest]];
            break;
        case ShouldRetry:
            // We create a task and cancel it immediately
            sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest]];
            [sessionDataTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
        default:
            // We create a task and cancel it immediately
            sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest]];
            [sessionDataTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
    }
    return sessionDataTask;
}

/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionDataTask* sessionDataTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionDataTask = [urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
            // Invoke completition handler
            completionHandler(data,response,error);
        }];
        return sessionDataTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed: {
            // Go ahead and make the API call with the provided request object
            sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
                // Invoke completition handler
                completionHandler(data,response,error);
            }];
            break;
        }
        case ShouldRetry: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
            }];
            // We cancel the connection and return the task object at end of function
            [sessionDataTask cancel];
            break;
        }
        default: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionDataTask = [urlSession dataTaskWithRequest:[approovData getRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
            }];
            // We cancel the connection and return the task object at end of function
            [sessionDataTask cancel];
            break;
        }
    }
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
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionDownloadTask* sessionDownloadTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest]];
        return sessionDownloadTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed:
            // Go ahead and make the API call with the provided request object
            sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest]];
            break;
        case ShouldRetry:
            // We create a task and cancel it immediately
            sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest]];
            [sessionDownloadTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
        default:
            // We create a task and cancel it immediately
            sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest]];
            [sessionDownloadTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
    }
    return sessionDownloadTask;
}

/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionDownloadTask* sessionDownloadTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error){
            // Invoke completition handler
            completionHandler(location,response,error);
        }];
        return sessionDownloadTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed: {
            // Go ahead and make the API call with the provided request object
            sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error){
                // Invoke completition handler
                completionHandler(location,response,error);
            }];
            break;
        }
        case ShouldRetry: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error){
            }];
            // We cancel the connection and return the task object at end of function
            [sessionDownloadTask cancel];
            break;
        }
        default: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionDownloadTask = [urlSession downloadTaskWithRequest:[approovData getRequest] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error){
            }];
            // We cancel the connection and return the task object at end of function
            [sessionDownloadTask cancel];
            break;
        }
    }
    return sessionDownloadTask;
}

/*  NOTE: this call is not protected by Approov
 *   see ApproovURLSession.h
 */

- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData {
    return [urlSession downloadTaskWithResumeData:resumeData];
}

/*  NOTE: this call is not protected by Approov
 *   see ApproovURLSession.h
 */

- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
                                       completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return [urlSession downloadTaskWithResumeData:resumeData completionHandler:completionHandler];
}

// MARK: Upload Tasks
/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL {
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL];
        return sessionUploadTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed:
            // Go ahead and make the API call with the provided request object
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL];
            break;
        case ShouldRetry:
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL];
            [sessionUploadTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
        default:
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL];
            [sessionUploadTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
    }
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromFile:(NSURL *)fileURL
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Invoke completition handler
            completionHandler(data,response,error);
        }];
        return sessionUploadTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed: {
            // Go ahead and make the API call with the provided request object
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                // Invoke completition handler
                completionHandler(data,response,error);
            }];
            break;
        }
        case ShouldRetry: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            }];
            // We cancel the connection and return the task object at end of function
            [sessionUploadTask cancel];
            break;
        }
        default: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            }];
            // We cancel the connection and return the task object at end of function
            [sessionUploadTask cancel];
            break;
        }
    }
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionUploadTask = [urlSession uploadTaskWithStreamedRequest:[approovData getRequest]];
        return sessionUploadTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed:
            // Go ahead and make the API call with the provided request object
            sessionUploadTask = [urlSession uploadTaskWithStreamedRequest:[approovData getRequest]];
            break;
        case ShouldRetry:
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithStreamedRequest:[approovData getRequest]];
            [sessionUploadTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
        default:
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithStreamedRequest:[approovData getRequest]];
            [sessionUploadTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
    }
    return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData {
        NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
        ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
        // The return object
        NSURLSessionUploadTask* sessionUploadTask;
        if (approovData == nil){
            // Approov SDK call failed, go ahead and make the API call with the original request object
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData];
            return sessionUploadTask;
        }
        switch ([approovData getDecision]) {
            case ShouldProceed:
                // Go ahead and make the API call with the provided request object
                sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData];
                break;
            case ShouldRetry:
                // We create a task and cancel it immediately
                sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData];
                [sessionUploadTask cancel];
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
                break;
            default:
                // We create a task and cancel it immediately
                sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData];
                [sessionUploadTask cancel];
                // We should retry doing a fetch after a user driven event
                // Tell the delagate we are marking the session as invalid
                [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
                break;
        }
        return sessionUploadTask;
}

/*
 *   see ApproovURLSession.h
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionUploadTask* sessionUploadTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Invoke completition handler
            completionHandler(data,response,error);
        }];
        return sessionUploadTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed: {
            // Go ahead and make the API call with the provided request object
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                // Invoke completition handler
                completionHandler(data,response,error);
            }];
            break;
        }
        case ShouldRetry: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            }];
            // We cancel the connection and return the task object at end of function
            [sessionUploadTask cancel];
            break;
        }
        default: {
            // Invoke completition handler
            completionHandler(nil,nil,[approovData error]);
            // We create a task and cancel it immediately
            sessionUploadTask = [urlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            }];
            // We cancel the connection and return the task object at end of function
            [sessionUploadTask cancel];
            break;
        }
    }
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
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    ApproovData* approovData = [approovSDK fetchApproovToken:requestWithHeaders];
    // The return object
    NSURLSessionWebSocketTask* sessionWebSocketTask;
    if (approovData == nil){
        // Approov SDK call failed, go ahead and make the API call with the original request object
        sessionWebSocketTask = [urlSession webSocketTaskWithRequest:[approovData getRequest]];
        return sessionWebSocketTask;
    }
    switch ([approovData getDecision]) {
        case ShouldProceed:
            // Go ahead and make the API call with the provided request object
            sessionWebSocketTask = [urlSession webSocketTaskWithRequest:[approovData getRequest]];
            break;
        case ShouldRetry:
            // We create a task and cancel it immediately
            sessionWebSocketTask = [urlSession webSocketTaskWithRequest:[approovData getRequest]];
            [sessionWebSocketTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
        default:
            // We create a task and cancel it immediately
            sessionWebSocketTask = [urlSession webSocketTaskWithRequest:[approovData getRequest]];
            [sessionWebSocketTask cancel];
            // We should retry doing a fetch after a user driven event
            // Tell the delagate we are marking the session as invalid
            [urlSessionDelegate URLSession:urlSession didBecomeInvalidWithError:[approovData error]];
            break;
    }
    return sessionWebSocketTask;
}


/*
 *   see ApproovURLSession.h
 */
- (void)finishTasksAndInvalidate {
    [urlSession finishTasksAndInvalidate];
}
/*
 *   see ApproovURLSession.h
 */
- (void)flushWithCompletionHandler:(void (^)(void))completionHandler {
    [urlSession flushWithCompletionHandler:completionHandler];
}
/*
 *   see ApproovURLSession.h
 */
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *dataTasks, NSArray<NSURLSessionUploadTask *> *uploadTasks, NSArray<NSURLSessionDownloadTask *> *downloadTasks))completionHandler {
    [urlSession getTasksWithCompletionHandler:completionHandler];
}
/*
 *   see ApproovURLSession.h
 */
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler {
    [urlSession getAllTasksWithCompletionHandler:completionHandler];
}
/*
 *   see ApproovURLSession.h
 */
- (void)invalidateAndCancel {
    [urlSession invalidateAndCancel];
}
/*
 *   see ApproovURLSession.h
 */
- (void)resetWithCompletionHandler:(void (^)(void))completionHandler {
    [urlSession resetWithCompletionHandler:completionHandler];
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

#pragma mark ApproovService interface
/* Set and gets bindHeader content for the ApproovService
 * Those are static variables and do not depend on Approov SDK being initialized
 */
+ (void)setBindHeader:(NSString*)newHeader {
    [ApproovService setBindHeader:newHeader];
}

+ (NSString*)getBindHeader {
    return [ApproovService getBindHeader];
}
/* Enables the ApproovService prefetch operation
 *
 */
+ (void)prefetch {
    [ApproovService prefetch];
}

/* ApproovService token header set/get
 *
 */
- (NSString*)getApproovTokenHeader {
    if (approovSDK != nil) return [approovSDK getApproovTokenHeader];
    return nil;
}
- (void)setApproovTokenHeader:(NSString*)newHeader {
    if (approovSDK != nil)  [approovSDK setApproovTokenHeader:newHeader];
}

/* ApproovService token header prefix set/get
 *
 */
- (NSString*)getApproovTokenPrefix {
    if (approovSDK != nil)  return [approovSDK getApproovTokenPrefix];
    return nil;
}
- (void)setApproovTokenPrefix:(NSString*)newHeader {
    if (approovSDK != nil) [approovSDK setApproovTokenPrefix:newHeader];
}

/* ApproovService header substitution
 *
 */
- (void)addSubstitutionHeader:(NSString*)header requiredPrefix:(NSString*)prefix {
    if (approovSDK != nil) [approovSDK addSubstitutionHeader:header requiredPrefix:prefix];
}
- (void)removeSubstitutionHeader:(NSString*)header {
    if (approovSDK != nil) [approovSDK removeSubstitutionHeader:header];
}

/*  ApproovService fetchSecureString feature
 *  Note: we return a valid error if the Approov SDK has not been initialized
 */
- (NSString*)fetchSecureString:(NSString*)key newDefinition:(NSString*)newDef error:(NSError**)error {
    return [approovSDK fetchSecureString:key newDefinition:newDef error:error];
}

/*  ApproovService fetchCustomJWT feature
 *  Note: we return a valid error if the Approov SDK has not been initialized
 */
- (NSString*)fetchCustomJWT:(NSString*)payload error:(NSError**)error{
    return [approovSDK fetchCustomJWT:payload error:error];
}

@end


@implementation ApproovService
/* Dynamic configuration string key in user default database */
static NSString* kApproovDynamicKey = @"approov-dynamic";
/* Initial configuration string/filename for Approov SDK */
static NSString* kApproovInitialKey = @"approov-initial";
/* Initial configuration file extention for Approov SDK */
static NSString* kConfigFileExtension = @"config";
/* Approov token default header */
static NSString* approovTokenHeader = @"Approov-Token";
/* Approov token custom prefix: any prefix to be added such as "Bearer " */
static NSString* approovTokenPrefix = @"";
/* Bind header string */
static NSString* bindHeader = @"";
/* map of headers that should have their values substituted for secure strings, mapped to their
 required prefixes
 */
static NSMutableDictionary<NSString*, NSString*>* substitutionHeaders;
/* NSError dictionary keys to hold Approov SDK Errors and additional status messages */
static NSString* ApproovSDKErrorKey = @"ApproovServiceError";
static NSString* ApproovSDKRejectionReasonsKey = @"RejectionReasons";
static NSString* ApproovSDKARCKey = @"ARC";
static NSString* RetryLastOperationKey = @"RetryLastOperation";

// Shared instance
+ (instancetype)sharedInstance: (NSString*)configString {
    static ApproovService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
        NSError* error = nil;
        [Approov initialize:configString updateConfig:@"auto" comment:nil error:&error];
        if (error != nil) {
            NSLog(@"ApproovURLSession FATAL: Error initilizing Approov SDK: %@", error.localizedDescription);
            /* NOTE: We do not want to return nil, since if there is a failure during Approov SDK creation, we
             * we really want to allow the actual SDK to report the error by populating the NSError variable
             * and inform the user. In the current context, this is impossible so we proceed regardless.
             //shared = nil;
             //return;
             */
            
        }
    });
    return shared;
}


/*
 *  Allows token/secret prefetch operation to be performed as early as possible. This
 *  permits a token to be available while an application might be loading resources
 *  or is awaiting user input. Since the initial network connection is the most
 *  expensive the prefetch seems reasonable.
 */

+ (void)prefetch {
    if (approovSDK != nil){
        // We succeeded initializing Approov SDK, fetch a token
        [Approov fetchApproovToken:^(ApproovTokenFetchResult* result) {
            // Prefetch done, no need to process response
        }:@"approov.io"];
    }
}

/* The ApproovService error enum status codes mapped to a NSString
 * This is just a convenient function that uses an Approov SDK function
 */
+ (NSString*)stringFromApproovTokenFetchStatus:(NSUInteger)status {
    return [Approov stringFromApproovTokenFetchStatus:status];
}


/* Get bindHeader content
 *
 */
+ (NSString*)getBindHeader {
    @synchronized (bindHeader) {
        return bindHeader;
    }
}

/* Set bindHeader content
 *
 */
+ (void)setBindHeader:(NSString*)newHeader {
    @synchronized (bindHeader) {
        bindHeader = newHeader;
    }
}

/* Get approovTokenHeader content
 *
 */
- (NSString*)getApproovTokenHeader {
    @synchronized (approovTokenHeader) {
        return approovTokenHeader;
    }
}

/* Set approovTokenHeader content
 *
 */
- (void)setApproovTokenHeader:(NSString*)newHeader {
    @synchronized (approovTokenHeader) {
        approovTokenHeader = newHeader;
    }
}

/* Get approovTokenPrefix content
 *
 */
- (NSString*)getApproovTokenPrefix {
    @synchronized (approovTokenPrefix) {
        return approovTokenPrefix;
    }
}

/* Set approovTokenPrefix content
 *
 */
- (void)setApproovTokenPrefix:(NSString*)newHeader {
    @synchronized (approovTokenPrefix) {
        approovTokenPrefix = newHeader;
    }
}

/*
 * Adds the name of a header which should be subject to secure strings substitution. This
 * means that if the header is present then the value will be used as a key to look up a
 * secure string value which will be substituted into the header value instead. This allows
 * easy migration to the use of secure strings. A required
 * prefix may be specified to deal with cases such as the use of "Bearer " prefixed before values
 * in an authorization header.
 *
 * @param header is the header to be marked for substitution
 * @param requiredPrefix is any required prefix to the value being substituted or nil if not required
 */
- (void)addSubstitutionHeader:(NSString*)header requiredPrefix:(NSString*)prefix {
    if (prefix == nil) {
        @synchronized(substitutionHeaders){
            [substitutionHeaders setValue:@"" forKey:header];
        }
    } else {
        @synchronized(substitutionHeaders){
            [substitutionHeaders setValue:prefix forKey:header];
        }
    }
}

/*
 * Removes a header previously added using addSubstitutionHeader.
 *
 * @param header is the header to be removed for substitution
 */
-(void)removeSubstitutionHeader:(NSString*)header {
    @synchronized(substitutionHeaders){
        [substitutionHeaders removeObjectForKey:header];
    }
}

/*
 * Fetches a secure string with the given key. If newDef is not null then a
 * secure string for the particular app instance may be defined. In this case the
 * new value is returned as the secure string. Use of an empty string for newDef removes
 * the string entry. Note that this call may require network transaction and thus may block
 * for some time, so should not be called from the UI thread. If the attestation fails
 * for any reason then nil is returned. Note that the returned string
 * should NEVER be cached by your app, you should call this function when it is needed.
 *
 * @param key is the secure string key to be looked up
 * @param newDef is any new definition for the secure string, or nil for lookup only
 * @param error is a pointer to a NSError type containing optional error message
 * @return secure string (should not be cached by your app) or nil if it was not defined or an error ocurred
 */
-(NSString*)fetchSecureString:(NSString*)key newDefinition:(NSString*)newDef error:(NSError**)error  {
    // determine the type of operation as the values themselves cannot be logged
    NSString* type = @"lookup";
    if (newDef != nil)
        type = @"definition";
    // fetch any secure string keyed by the value, catching any exceptions the SDK might throw
    ApproovTokenFetchResult* approovResult = [Approov fetchSecureStringAndWait:key :newDef];
    // Log result of token fetch operation but do not log the value
    NSLog(@"ApproovURLSession: fetchSecureString %@ : %@", type, [ApproovService stringFromApproovTokenFetchStatus:approovResult.status]);
    // Process the returned Approov status
    if (approovResult.status == ApproovTokenFetchStatusDisabled) {
        *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Secure String feature must be enabled using CLI" ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:NO];
        return nil;
    } else if (approovResult.status == ApproovTokenFetchStatusBadKey) {
        if (error != nil) {
            *error = [NSError errorWithDomain:@"io.approov.ApproovURLSession" code:ApproovTokenFetchStatusBadKey userInfo:@{@"Error reason":@"Bad/Missing key"}];
        }
        return nil;
    } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
        // if the request is rejected then we provide a special exception with additional information
        NSString* details = [[NSMutableString alloc] initWithString:@"fetchSecureString rejected"];
        *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:NO];
        return nil;
    } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the secure string due to network conditions so the request can
        // be retried by the user later
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchSecureString network error, retry needed."];
        *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:YES];
        return nil;
    } else if ((approovResult.status != ApproovTokenFetchStatusSuccess) && (approovResult.status != ApproovTokenFetchStatusUnknownKey)) {
        // we are unable to get the secure string due to a more permanent error
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchSecureString permanent error"];
        *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:NO];
        return nil;
    }
    return approovResult.secureString;
}

/*
 * Fetches a custom JWT with the given payload. Note that this call will require network
 * transaction and thus will block for some time, so should not be called from the UI thread.
 * If the attestation fails for any reason and the NSError paramether is not nil, the  ApproovSDKError
 * and the ApproovSDKRejectionReasons will be populated to contain the underlying Approov SDK error
 * messages.
 *
 * @param payload is the marshaled JSON object for the claims to be included
 * @param error is a pointer to a NSError type containing optional error message
 * @return custom JWT string or nil if an error occurred
 */
-(NSString*)fetchCustomJWT:(NSString*)payload error:(NSError**)error {
    // fetch the custom JWT
    ApproovTokenFetchResult* approovResult = [Approov fetchCustomJWTAndWait:payload];
    // Log result of token fetch operation but do not log the value
    NSLog(@"ApproovURLSession: fetchCustomJWT %@", [Approov stringFromApproovTokenFetchStatus:approovResult.status]);
    // process the returned Approov status
    if (approovResult.status == ApproovTokenFetchStatusBadPayload) {
        if (error != nil){
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"fetchCustomJWT: Malformed JSON" ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC  canRetry:NO];
        }
        return nil;
    } else if(approovResult.status == ApproovTokenFetchStatusDisabled){
        if (error != nil){
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"fetchCustomJWT: This feature must be enabled using CLI" ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:NO];
        }
        return nil;
    } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
        // if the request is rejected then we provide a special exception with additional information
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchCustomJWT rejected"];
        if (error != nil){
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC  canRetry:NO];
        }
        return nil;
    } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the JWT due to network conditions so the request can
        // be retried by the user later
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchCustomJWT Network error, retry needed."];
        if (error != nil){
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC  canRetry:YES];
        }
        return nil;
    } else if (approovResult.status != ApproovTokenFetchStatusSuccess) {
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchCustomJWT Failure during attestation."];
        [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
        if (error != nil){
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC  canRetry:NO];
        }
        return nil;
    }
    
    return approovResult.token;
}

/*
 *  Convenience function fetching the Approov token
 *
 */
- (ApproovData*)fetchApproovToken:(NSURLRequest*)request {
    ApproovData *returnData = [[ApproovData alloc] init];
    // Save the original request
    [returnData setRequest:request];
    // Check if Bind Header is set to a non empty String
    if (![[ApproovService getBindHeader] isEqualToString:@""]){
        /*  Query the NSURLSessionConfiguration for user set headers. They would be set like so:
        *  [config setHTTPAdditionalHeaders:@{@"Authorization Bearer " : @"token"}];
        *  Since the NSURLSessionConfiguration is part of the init call and we store its reference
        *  we check for the presence of a user set header there.
        */
        if([request valueForHTTPHeaderField:[ApproovService getBindHeader]] != nil){
            // Add the Bind Header as a data hash to Approov token
            [Approov setDataHashInToken:[request valueForHTTPHeaderField:[ApproovService getBindHeader]]];
        }
    }
    // Invoke fetch token sync
    ApproovTokenFetchResult* approovResult = [Approov fetchApproovTokenAndWait:request.URL.absoluteString];
    // Log result of token fetch
    NSLog(@"ApproovURLSession: Host: %@ : %@", request.URL.host, approovResult.loggableToken);
    // Update the message
    returnData.sdkMessage = [Approov stringFromApproovTokenFetchStatus:approovResult.status];

    switch (approovResult.status) {
        case ApproovTokenFetchStatusSuccess: {
            // Can go ahead and make the API call with the provided request object
            returnData.decision = ShouldProceed;
            // Set Approov-Token header. We need to modify the original request.
            NSMutableURLRequest *newRequest = [returnData.request mutableCopy];
            [newRequest setValue:[NSString stringWithFormat:@"%@%@",approovTokenPrefix,approovResult.token] forHTTPHeaderField: approovTokenHeader];
            returnData.request = newRequest;
            break;
        }
        case ApproovTokenFetchStatusNoNetwork:
        case ApproovTokenFetchStatusPoorNetwork:
        case ApproovTokenFetchStatusMITMDetected: {
            // Must not proceed with network request and inform user a retry is needed
            returnData.decision = ShouldRetry;
            NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Network issue, retry later." ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:nil ApproovSDKARC:nil  canRetry:YES];
            returnData.error = error;
            break;
        }
        case ApproovTokenFetchStatusUnprotectedURL:
        case ApproovTokenFetchStatusUnknownURL:
        case ApproovTokenFetchStatusNoApproovService: {
            // We do NOT add the Approov-Token header to the request headers
            returnData.decision = ShouldProceed;
            break;
        }
        default: {
            returnData.decision = ShouldFail;
            NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Unknown SDK error" ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            returnData.error = error;
            break;
        }
    }
    
    // we now deal with any header substitutions, which may require further fetches but these
    // should be using cached results
    BOOL isIllegalSubstitution = (approovResult.status == ApproovTokenFetchStatusUnknownURL);
    // Make a copy of the original request
    NSMutableURLRequest *newRequest = [returnData.request mutableCopy];
    NSDictionary<NSString*,NSString*>* allHeaders = newRequest.allHTTPHeaderFields;
    for (NSString* key in substitutionHeaders.allKeys) {
        NSString* header = key;
        NSString* prefix = [substitutionHeaders objectForKey:key];
        NSString* value = [allHeaders objectForKey:header];
        // Check if the request contains the header we want to replace
        if ((value != nil) && ([value hasPrefix:prefix]) && (value.length > prefix.length)){
            approovResult = [Approov fetchSecureStringAndWait:[value substringFromIndex:prefix.length] :nil];
            NSLog(@"Substituting header: %@, %@", header, [Approov stringFromApproovTokenFetchStatus:approovResult.status]);
            if (approovResult.status == ApproovTokenFetchStatusSuccess) {
                if (isIllegalSubstitution){
                    // don't allow substitutions on unadded API domains to prevent them accidentally being
                    // subject to a Man-in-the-Middle (MitM) attack
                    NSString* message = [NSString stringWithFormat:@"Header substitution for %@ illegal for %@ that is not an added API domain",header, newRequest.URL];
                    NSError *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusSuccess userMessage:message ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:NO];
                    returnData.error = error;
                    break;
                }
                // We add the modified header to the new copy of request
                [newRequest setValue:[NSString stringWithFormat:@"%@%@",prefix,approovResult.secureString] forHTTPHeaderField: header];
            } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
                // if the request is rejected then we provide a special exception with additional information
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[NSString stringWithFormat:@" %@", [Approov stringFromApproovTokenFetchStatus:approovResult.status]]];
                [details appendString:[NSString stringWithFormat:@" %@  %@",approovResult.ARC,approovResult.rejectionReasons]];
                NSError *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusRejected userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC canRetry:NO];
                returnData.error = error;
                break;
            } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
                // we are unable to get the secure string due to network conditions so the request can
                // be retried by the user later
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                NSError *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusRejected userMessage:@"Network issue, retry later." ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:nil ApproovSDKARC:nil  canRetry:YES];
                returnData.error = error;
                break;
            } else if (approovResult.status != ApproovTokenFetchStatusUnknownKey) {
                // we have failed to get a secure string with a more serious permanent error
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                NSError *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusRejected userMessage:@"permanent error" ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status] ApproovSDKRejectionReasons:approovResult.rejectionReasons ApproovSDKARC:approovResult.ARC  canRetry:NO];
                returnData.error = error;
                break;
            }
        }
    }//for loop
    // Add the modified request to the return data
    returnData.request = newRequest;
    return returnData;
}

/* Create an error message filling in Approov SDK error codes and optional Approov SDK device information/failure reason
 *  Also shows if an additional attempt to repeat the last operation might be possible by setting the RetryLastOperationKey
 *  key to "YES"
 */
+ (NSError*)createErrorWithCode:(NSInteger)code userMessage:(NSString*)message ApproovSDKError:(NSString*)sdkError
     ApproovSDKRejectionReasons:(NSString*)rejectionReasons ApproovSDKARC:(NSString*)arc canRetry:(BOOL)retry {
    NSDictionary *userInfo = @{
    NSLocalizedDescriptionKey: NSLocalizedString(message, nil),
    NSLocalizedFailureReasonErrorKey: NSLocalizedString(message, nil),
    NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(message, nil),
    ApproovSDKErrorKey: NSLocalizedString(sdkError,nil),
    ApproovSDKRejectionReasonsKey: NSLocalizedString(rejectionReasons,nil),
    ApproovSDKARCKey: NSLocalizedString(arc,nil),
    RetryLastOperationKey: NSLocalizedString(retry ? @"YES" : @"NO",nil)
                            };
    NSError* error = [[NSError alloc] initWithDomain:@"io.approov.ApproovURLSession" code:code userInfo:userInfo];
    return error;
}


@end


@implementation ApproovURLSessionDelegate
id<NSURLSessionDelegate,NSURLSessionTaskDelegate,NSURLSessionDataDelegate,NSURLSessionDownloadDelegate> approovURLDelegate;
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
        approovURLDelegate = delegate;
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
    [approovURLDelegate URLSession:session didBecomeInvalidWithError:error];
}

/*  Tells the delegate that all messages enqueued for a session have been delivered
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1617185-urlsessiondidfinisheventsforback?language=objc
 */
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    [approovURLDelegate URLSessionDidFinishEventsForBackgroundURLSession:session];
}

/*  Requests credentials from the delegate in response to a session-level authentication request from the remote server
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1409308-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    // we are only interested in server trust requests
    if(![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]){
        [approovURLDelegate URLSession:session didReceiveChallenge:challenge completionHandler: completionHandler];
        return;
    }
    NSError* error;
    SecTrustRef serverTrust = [self shouldAcceptAuthenticationChallenge:challenge error:&error];
    if ((error == nil) && (serverTrust != nil)) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [[NSURLCredential alloc]initWithTrust:serverTrust]);
        [approovURLDelegate URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
        return;
    }
    if(error != nil){
        // Log error message
        NSLog(@"Pinning: %@", error.localizedDescription);
    } else {
        // serverTrust == nil
        NSLog(@"Pinning: No pins match for host %@", challenge.protectionSpace.host);
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
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)]){
        // we are only interested in server trust requests
        if(![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]){
            [approovURLDelegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
            return;
        }
        NSError* error;
        SecTrustRef serverTrust = [self shouldAcceptAuthenticationChallenge:challenge error:&error];
        if ((error == nil) && (serverTrust != nil)) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, [[NSURLCredential alloc]initWithTrust:serverTrust]);
            [approovURLDelegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
            return;
        }
        if(error != nil){
            // Log error message
            NSLog(@"Pinning: %@", error.localizedDescription);
        } else {
            // serverTrust == nil
            NSLog(@"Pinning: No pins match for host %@", challenge.protectionSpace.host);
        }
        // Cancel connection
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    }
}

/*  Tells the delegate that the task finished transferring data
 *   https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411610-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]){
        [approovURLDelegate URLSession:session task:task didCompleteWithError:error];
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
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]){
        [approovURLDelegate URLSession:session task:task willPerformHTTPRedirection:response newRequest:request completionHandler:completionHandler];
    }
}

/*  Tells the delegate when a task requires a new request body stream to send to the remote server
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1410001-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
             task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:needNewBodyStream:)]){
        [approovURLDelegate URLSession:session task:task needNewBodyStream:completionHandler];
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
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)]){
        [approovURLDelegate URLSession:session task:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
    }
}

/*  Tells the delegate that a delayed URL session task will now begin loading
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2873415-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willBeginDelayedRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLSessionDelayedRequestDisposition disposition, NSURLRequest *newRequest))completionHandler  API_AVAILABLE(ios(11.0)){
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:willBeginDelayedRequest:completionHandler:)]){
        [approovURLDelegate URLSession:session task:task willBeginDelayedRequest:request completionHandler:completionHandler];
    }
}

/*  Tells the delegate that the session finished collecting metrics for the task
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1643148-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:task:didFinishCollectingMetrics:)]){
        [approovURLDelegate URLSession:session task:task didFinishCollectingMetrics:metrics];
    }
}

/*  Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2908819-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
taskIsWaitingForConnectivity:(NSURLSessionTask *)task API_AVAILABLE(ios(11.0)) {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:taskIsWaitingForConnectivity:)]){
        [approovURLDelegate URLSession:session taskIsWaitingForConnectivity:task];
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
    if([approovURLDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]){
        [approovURLDelegate URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
    }
}

/*  Tells the delegate that the data task was changed to a download task
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1409936-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:dataTask:didBecomeDownloadTask:)]){
        [approovURLDelegate URLSession:session dataTask:dataTask didBecomeDownloadTask:downloadTask];
    }
}

/*  Tells the delegate that the data task was changed to a stream task
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411648-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeStreamTask:(NSURLSessionStreamTask *)streamTask {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:dataTask:didBecomeStreamTask:)]){
        [approovURLDelegate URLSession:session dataTask:dataTask didBecomeStreamTask:streamTask];
    }
}

/*  Tells the delegate that the data task has received some of the expected data
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]){
        [approovURLDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

/*  Asks the delegate whether the data (or upload) task should store the response in the cache
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411612-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
         dataTask:(NSURLSessionDataTask *)dataTask
willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:dataTask:willCacheResponse:completionHandler:)]){
        [approovURLDelegate URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
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
    if([approovURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)]){
        [approovURLDelegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    }
}

/*  Tells the delegate that the download task has resumed downloading
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1408142-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    if([approovURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes:)]){
        [approovURLDelegate URLSession:session downloadTask:downloadTask didResumeAtOffset:fileOffset expectedTotalBytes:expectedTotalBytes];
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
    if([approovURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)]){
        [approovURLDelegate URLSession:session downloadTask:downloadTask didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
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

/*  Evaluates a URLAuthenticationChallenge deciding if to proceed further
 *  @param  challenge: NSURLAuthenticationChallenge
 *  @return SecTrustRef: valid SecTrust if authentication should proceed, nil otherwise
 */
- (SecTrustRef)shouldAcceptAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge error:(NSError **)error {
    // check we have a server trust
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    if(!serverTrust) {
        // Set error message and return
        *error = [ApproovService createErrorWithCode:NOT_SERVER_TRUST userMessage:@"FATAL: ApproovURLSession not a server trust" ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil  canRetry:NO];
        return nil;
    }
    // check the validity of the server cert
    SecTrustResultType result;
    OSStatus status = SecTrustEvaluate(serverTrust, &result);
    if(status != errSecSuccess){
        // Set error message and return
        *error = [ApproovService createErrorWithCode:SERVER_CERTIFICATE_FAILED_VALIDATION userMessage:@"FATAL: ApproovURLSession: server certificate validation failed" ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    } else if((result != kSecTrustResultUnspecified) && (result != kSecTrustResultProceed)){
        // Set error message and return
        *error = [ApproovService createErrorWithCode:SERVER_TRUST_EVALUATION_FAILURE userMessage:@"FATAL: ApproovURLSession: server trust evaluation failed" ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    }
    NSDictionary* pins = [Approov getPins:@"public-key-sha256"];
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
            *error = [ApproovService createErrorWithCode:CERTIFICATE_CHAIN_READ_ERROR userMessage:@"FATAL: ApproovURLSession: failed to read certificate from chain" ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return nil;
        }
        // get the subject public key info from the certificate
        NSData* publicKeyInfo = [self publicKeyInfoOfCertificate:serverCert];
        if(publicKeyInfo == nil){
            // Set error message and return
            *error = [ApproovService createErrorWithCode:PUBLIC_KEY_INFORMATION_READ_FAILURE userMessage:@"FATAL: ApproovURLSession: failed reading public key information" ApproovSDKError:nil ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
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
 * gets a certificate's subject public key info (SPKI)
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
 * gets the subject public key info (SPKI) header depending on a public key's type and size
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




