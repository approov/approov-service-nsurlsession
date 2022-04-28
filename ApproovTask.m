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

-(instancetype)initWithSession:(NSURLSession *)session configuration:(NSURLSessionConfiguration*)configuration {
    if ([super init]) {
        aUrlSession = session;
        aUrlSessionConfiguration = configuration;
        return self;
    }
    return nil;
}
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1411554-datataskwithurl?language=objc
*/
- (void)dataTaskWithURL:(NSURL *)url {
     [self dataTaskWithRequest:[[NSURLRequest alloc] initWithURL:url]];
}
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410330-datataskwithurl?language=objc
*/
- (void)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
     [self dataTaskWithRequest:[[NSURLRequest alloc] initWithURL:url] completionHandler:completionHandler];
}
/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1410592-datataskwithrequest?language=objc
*/
- (void)dataTaskWithRequest:(NSURLRequest *)request{
     [[NSURLSessionDataTask alloc] init];
}

/*  Add any additional session defined headers to a NSURLRequest object
 *  @param  request URLRequest
 *  @return copy of original request with additional session headers
 */
- (NSURLRequest*)addUserHeadersToRequest:(NSURLRequest*)userRequest {
    // Make a mutable copy
    NSMutableURLRequest *newRequest = [userRequest mutableCopy];
    NSDictionary* allHeaders = aUrlSessionConfiguration.HTTPAdditionalHeaders;
    for (NSString* key in allHeaders){
        [newRequest addValue:[allHeaders valueForKey:key] forHTTPHeaderField:key];
    }
    return [newRequest copy];
}

/*
*  https://developer.apple.com/documentation/foundation/nsurlsession/1407613-datataskwithrequest?language=objc
*/
- (void)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Add user headers to request
    NSURLRequest* requestWithHeaders = [self addUserHeadersToRequest:request];
    // Fetch Token
    ApproovData* approovData = [ApproovService fetchApproovToken:requestWithHeaders];
    // Decision
    if ([approovData getDecision] ==  ShouldProceed) {
        NSLog(@"PROTO: ShouldProceed");
        // Go ahead and make the API call with the provided request object
        NSURLSessionDataTask* sessionDataTask = [aUrlSession dataTaskWithRequest:[approovData getRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
            // Invoke completition handler
            NSLog(@"PROTO: Before completionHandler");
            completionHandler(data,response,error);
            NSLog(@"PROTO: After completionHandler");
        }];
        [sessionDataTask resume];
        NSLog(@"PROTO: ShouldProceed break;");
    }
    NSLog(@"PROTO: ShouldRetry");
    // Invoke completition handler
    completionHandler(nil,nil,[approovData error]);
    NSLog(@"PROTO: ShouldRetry break;");
    
}

- (void) resume {
    NSLog(@"ZZZ: resume");
    //[super resume];
    NSLog(@"ZZZ: super resume");
}

@end
