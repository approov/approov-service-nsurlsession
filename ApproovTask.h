//
//  Protocol.h
//  ApproovShapes
//
//  Created by ivo liondov on 27/04/2022.
//  Copyright © 2022 ivo liondov. All rights reserved.
//

#ifndef Protocol_h
#define Protocol_h

@interface ApproovTask : NSURLSessionTask
-(instancetype)initWithSession:(NSURLSession *)session configuration:(NSURLSessionConfiguration*)configuration delegate:(id<NSURLSessionDelegate>)delegate;

//**** DataTask
- (void)dataTaskWithRequest:(NSURLRequest *)request;

- (void)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;

//*** DownloadTask
- (void)downloadTaskWithRequest:(NSURLRequest *)request;
- (void)downloadTaskWithRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler;

//*** UploadTask
- (void)uploadTaskWithRequest:(NSURLRequest *)request
fromFile:(NSURL *)fileURL;
- (void)uploadTaskWithRequest:(NSURLRequest *)request
         fromFile:(NSURL *)fileURL
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
- (void)uploadTaskWithStreamedRequest:(NSURLRequest *)request;
- (void)uploadTaskWithRequest:(NSURLRequest *)request
fromData:(NSData *)bodyData;
- (void)uploadTaskWithRequest:(NSURLRequest *)request
         fromData:(NSData *)bodyData
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;

//*** WebSocketTask
- (void)webSocketTaskWithRequest:(NSURLRequest *)request  API_AVAILABLE(ios(13.0));
@end
#endif /* Protocol_h */
