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

#ifndef ApproovURLSession_h
#define ApproovURLSession_h

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

@interface ApproovURLSession : NSObject
- (instancetype)init NS_UNAVAILABLE;
/*
*  URLSession initializer
*  https://developer.apple.com/documentation/foundation/nsurlsession/1411597-sessionwithconfiguration?language=objc
*/
+ (ApproovURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
/*
*  URLSession initializer
*   https://developer.apple.com/documentation/foundation/urlsession/1411474-init
*/
+ (ApproovURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                      delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1411554-datataskwithurl?language=objc
*/
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410330-datataskwithurl?language=objc
*/
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410592-datataskwithrequest?language=objc
*/
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1407613-datataskwithrequest?language=objc
*/
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1411482-downloadtaskwithurl?language=objc
*/
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411608-downloadtaskwithurl?language=objc
*/
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411481-downloadtaskwithrequest?language=objc
*/
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411511-downloadtaskwithrequest?language=objc
*/
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler;
/*  NOTE: this call is not protected by Approov
*   https://developer.apple.com/documentation/foundation/nsurlsession/1409226-downloadtaskwithresumedata?language=objc
*/
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData;
/*  NOTE: this call is not protected by Approov
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411598-downloadtaskwithresumedata?language=objc
*/
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411550-uploadtaskwithrequest?language=objc
*/
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
fromFile:(NSURL *)fileURL;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411638-uploadtaskwithrequest?language=objc
*/
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromFile:(NSURL *)fileURL
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1410934-uploadtaskwithstreamedrequest?language=objc
*/
- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/3181171-websockettaskwithurl?language=objc
*/
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url API_AVAILABLE(ios(13.0));
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/3235750-websockettaskwithrequest?language=objc
*/
- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request  API_AVAILABLE(ios(13.0));
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1409763-uploadtaskwithrequest?language=objc
*/
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
fromData:(NSData *)bodyData;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411518-uploadtaskwithrequest?language=objc
*/
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
         fromData:(NSData *)bodyData
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1407428-finishtasksandinvalidate?language=objc
*/
- (void)finishTasksAndInvalidate;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411622-flushwithcompletionhandler?language=objc
*/
- (void)flushWithCompletionHandler:(void (^)(void))completionHandler;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411578-gettaskswithcompletionhandler?language=objc
*/
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *dataTasks, NSArray<NSURLSessionUploadTask *> *uploadTasks, NSArray<NSURLSessionDownloadTask *> *downloadTasks))completionHandler;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411618-getalltaskswithcompletionhandler?language=objc
*/
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411538-invalidateandcancel?language=objc
*/
- (void)invalidateAndCancel;
/*
*   https://developer.apple.com/documentation/foundation/nsurlsession/1411479-resetwithcompletionhandler?language=objc
*/
- (void)resetWithCompletionHandler:(void (^)(void))completionHandler;
@end


/* The ApproovService interface wrapper */
@interface ApproovService : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (void)initialize:(NSString*)configString errorMessage:(NSError**)error;
+ (void)setBindHeader:(NSString*)newHeader;
+ (NSString*)getBindHeader;
+ (void)prefetch;
- (NSString*)getApproovTokenHeader;
- (void)setApproovTokenHeader:(NSString*)newHeader;
- (NSString*)getApproovTokenPrefix;
- (void)setApproovTokenPrefix:(NSString*)newHeader;
- (void)addSubstitutionHeader:(NSString*)header requiredPrefix:(NSString*)prefix;
- (void)removeSubstitutionHeader:(NSString*)header;
- (NSString*)fetchSecureString:(NSString*)key newDefinition:(NSString*)newDef error:(NSError**)error;
- (NSString*)fetchCustomJWT:(NSString*)payload error:(NSError**)error;
@end


#endif /* ApproovURLSession_h */








