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

#ifndef ApproovService_h
#define ApproovService_h

#import "ApproovSessionTaskObserver.h"
#import <Foundation/Foundation.h>

// ApproovService provides a mediation layer to the underlying Approov SDK
@interface ApproovService: NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (void)initialize:(NSString *)configString error:(NSError **)error;
+ (void)setProceedOnNetworkFailure:(BOOL)proceed;
+ (void)setBindingHeader:(NSString *)newHeader;
+ (NSString *)getBindingHeader;
+ (void)setApproovTokenHeader:(NSString *)newHeader;
+ (NSString *)getApproovTokenHeader;
+ (void)setApproovTokenPrefix:(NSString *)newHeaderPrefix;
+ (NSString *)getApproovTokenPrefix;
+ (void)addSubstitutionHeader:(NSString *)header requiredPrefix:(NSString *)prefix;
+ (void)removeSubstitutionHeader:(NSString *)header;
+ (void)addSubstitutionQueryParam:(NSString *)key;
+ (void)removeSubstitutionQueryParam:(NSString *)key;
+ (void)addExclusionURLRegex:(NSString *)urlRegex;
+ (void)removeExclusionURLRegex:(NSString *)urlRegex;
+ (void)prefetch;
+ (void)precheck:(NSError **)error;
+ (NSString *)getDeviceID;
+ (void)setDataHashInToken:(NSString *)data;
+ (NSString *)getMessageSignature:(NSString *)message;
+ (NSString *)fetchToken:(NSString *)url error:(NSError **)error;
+ (NSString *)fetchSecureString:(NSString *)key newDef:(NSString *)newDef error:(NSError **)error;
+ (NSString *)fetchCustomJWT:(NSString*)payload error:(NSError **)error;
+ (NSDictionary *)getPins:(NSString *)pinType;
+ (void)interceptSessionTask:(NSURLSessionTask *)task sessionConfig:(NSURLSessionConfiguration *)sessionConfig
        completionHandler:(CompletionHandlerType)completionHandler;
+ (NSURLRequest *)updateRequestWithApproov:(NSURLRequest *)request
        sessionConfig:(NSURLSessionConfiguration *)sessionConfig error:(NSError **)error;
@end

#endif
