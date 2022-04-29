//
//  Protocol.m
//  ShapesApp
//
//  Created by ivo liondov on 27/04/2022.
//  Copyright © 2022 ivo liondov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ApproovTask.h"
#import "ApproovService.h"

@interface ApproovTask()

@end

@implementation ApproovTask

NSURLSession* aUrlSession;
NSURLSessionConfiguration* aUrlSessionConfiguration;
id<NSURLSessionDelegate> approovTaskSessionDelegate;

-(instancetype)initWithSession:(NSURLSession *)session configuration:(NSURLSessionConfiguration*)configuration delegate:(id<NSURLSessionDelegate>)delegate {
    if ([super init]) {
        aUrlSession = session;
        aUrlSessionConfiguration = configuration;
        approovTaskSessionDelegate = delegate;
        return self;
    }
    return nil;
}


/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410592-datataskwithrequest?language=objc
*/
- (void)dataTaskWithRequest:(NSURLRequest *)request{
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSURLSessionDataTask* sessionDataTask = [aUrlSession dataTaskWithRequest:[approovData getRequest]];
        [sessionDataTask resume];
    } else {
        // Tell the delagate we are marking the session as invalid
        [approovTaskSessionDelegate URLSession:aUrlSession didBecomeInvalidWithError:[approovData error]];
    }
}

/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1407613-datataskwithrequest?language=objc
*/
- (void)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        // Go ahead and make the API call with the provided request object
        NSURLSessionDataTask* sessionDataTask = [aUrlSession dataTaskWithRequest:[approovData getRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
            // Invoke completition handler
            completionHandler(data,response,error);
        }];
        [sessionDataTask resume];
    } else {
        // Invoke completition handler
        completionHandler(nil,nil,[approovData error]);
        // TODO: [sessionDataTask cancel]; ??????????
    }
}



- (void)downloadTaskWithRequest:(NSURLRequest *)request {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSURLSessionDownloadTask* sessionDataTask = [aUrlSession downloadTaskWithRequest:[approovData getRequest]];
        [sessionDataTask resume];
    } else {
        // Tell the delagate we are marking the session as invalid
        [approovTaskSessionDelegate URLSession:aUrlSession didBecomeInvalidWithError:[approovData error]];
    }
}


- (void)downloadTaskWithRequest:(NSURLRequest *)request
              completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        // Go ahead and make the API call with the provided request object
        NSURLSessionDownloadTask* sessionDataTask = [aUrlSession downloadTaskWithRequest:[approovData getRequest] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error){
            // Invoke completition handler
            completionHandler(location,response,error);
        }];
        [sessionDataTask resume];
    } else {
        // Invoke completition handler
        completionHandler(nil,nil,[approovData error]);
    }
}


//////
- (void)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSURLSessionUploadTask* sessionUploadTask = [aUrlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL];
        [sessionUploadTask resume];
    } else {
        // Tell the delagate we are marking the session as invalid
        [approovTaskSessionDelegate URLSession:aUrlSession didBecomeInvalidWithError:[approovData error]];
    }
    
}
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411638-uploadtaskwithrequest?language=objc
*/
- (void)uploadTaskWithRequest:(NSURLRequest *)request
         fromFile:(NSURL *)fileURL
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        // Go ahead and make the API call with the provided request object
        NSURLSessionUploadTask* sessionUploadTask = [aUrlSession uploadTaskWithRequest:[approovData getRequest] fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Invoke completition handler
            completionHandler(data,response,error);
        }];
        [sessionUploadTask resume];
    } else {
        // Invoke completition handler
        completionHandler(nil,nil,[approovData error]);
    }
}

///////
- (void)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSURLSessionUploadTask* sessionUploadTask = [aUrlSession uploadTaskWithStreamedRequest:[approovData getRequest]];
        [sessionUploadTask resume];
    } else {
        // Tell the delagate we are marking the session as invalid
        [approovTaskSessionDelegate URLSession:aUrlSession didBecomeInvalidWithError:[approovData error]];
    }
}
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/3235750-websockettaskwithrequest?language=objc
*/
- (void)webSocketTaskWithRequest:(NSURLRequest *)request  API_AVAILABLE(ios(13.0)) {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSURLSessionWebSocketTask* sessionWebSocketTask = [aUrlSession webSocketTaskWithRequest:[approovData getRequest]];
        [sessionWebSocketTask resume];
    } else {
        // Tell the delagate we are marking the session as invalid
        [approovTaskSessionDelegate URLSession:aUrlSession didBecomeInvalidWithError:[approovData error]];
    }
}
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1409763-uploadtaskwithrequest?language=objc
*/
- (void)uploadTaskWithRequest:(NSURLRequest *)request
                     fromData:(NSData *)bodyData {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSURLSessionUploadTask* sessionUploadTask = [aUrlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData];
        [sessionUploadTask resume];
    } else {
        // Tell the delagate we are marking the session as invalid
        [approovTaskSessionDelegate URLSession:aUrlSession didBecomeInvalidWithError:[approovData error]];
    }
    
}
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411518-uploadtaskwithrequest?language=objc
*/
- (void)uploadTaskWithRequest:(NSURLRequest *)request
         fromData:(NSData *)bodyData
            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:request];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        // Go ahead and make the API call with the provided request object
        NSURLSessionUploadTask* sessionUploadTask = [aUrlSession uploadTaskWithRequest:[approovData getRequest] fromData:bodyData completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Invoke completition handler
            completionHandler(data,response,error);
        }];
        [sessionUploadTask resume];
    } else {
        // Invoke completition handler
        completionHandler(nil,nil,[approovData error]);
    }
}

@end
