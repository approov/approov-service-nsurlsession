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

/* Token fetch decision code */
typedef NS_ENUM(NSUInteger, ApproovTokenNetworkFetchDecision) {
    ShouldProceed,
    ShouldRetry,
    ShouldFail,
};

/* Approov SDK token fetch return object */
@interface ApproovData: NSObject
@property (getter=getRequest)NSURLRequest* request;
@property (getter=getDecision)ApproovTokenNetworkFetchDecision decision;
@property (getter=getSdkMessage)NSString* sdkMessage;
@property NSError* error;
@end

/* The ApproovService interface wrapper */
@interface ApproovService : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (void)initialize:(NSString*)configString errorMessage:(NSError**)error;
+ (void)setBindHeader:(NSString*)newHeader;
+ (NSString*)getBindHeader;
+ (void)prefetch;
+ (NSString*)getApproovTokenHeader;
+ (void)setApproovTokenHeader:(NSString*)newHeader;
+ (NSString*)getApproovTokenPrefix;
+ (void)setApproovTokenPrefix:(NSString*)newHeader;
+ (void)addSubstitutionHeader:(NSString*)header requiredPrefix:(NSString*)prefix;
+ (void)removeSubstitutionHeader:(NSString*)header;
+ (NSString*)fetchSecureString:(NSString*)key newDefinition:(NSString*)newDef error:(NSError**)error;
+ (NSString*)fetchCustomJWT:(NSString*)payload error:(NSError**)error;
+ (void)precheck:(NSError**)error;
+ (ApproovData*)fetchApproovToken:(NSURLRequest*)request;
+ (NSError*)createErrorWithCode:(NSInteger)code userMessage:(NSString*)message ApproovSDKError:(NSString*)sdkError
     ApproovSDKRejectionReasons:(NSString*)rejectionReasons ApproovSDKARC:(NSString*)arc canRetry:(BOOL)retry;
/* The underlying Approov SDK error enum status codes mapped to a NSString */
+ (NSString*)stringFromApproovTokenFetchStatus:(NSUInteger)status;
@end

#endif
