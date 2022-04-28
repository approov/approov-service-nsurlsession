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
-(instancetype)initWithSession:(NSURLSession *)session configuration:(NSURLSessionConfiguration*)configuration;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1411554-datataskwithurl?language=objc
*/
- (void)dataTaskWithURL:(NSURL *)url;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410330-datataskwithurl?language=objc
*/
- (void)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410592-datataskwithrequest?language=objc
*/
- (void)dataTaskWithRequest:(NSURLRequest *)request;
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1407613-datataskwithrequest?language=objc
*/
- (void)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
@end
#endif /* Protocol_h */
