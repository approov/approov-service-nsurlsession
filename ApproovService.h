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

typedef NS_ENUM(NSInteger, ApproovMessageSigningMode) {
    ApproovMessageSigningModeDisabled = 0,
    ApproovMessageSigningModeInstall,
    ApproovMessageSigningModeAccount,
};

typedef NS_ENUM(NSInteger, ApproovLogLevel) {
    ApproovLogLevelOff = 0,
    ApproovLogLevelError,
    ApproovLogLevelWarning,
    ApproovLogLevelInfo,
    ApproovLogLevelDebug,
};

// ApproovService provides a mediation layer to the underlying Approov SDK
@interface ApproovService: NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (void)initialize:(NSString *)configString error:(NSError **)error;
+ (void)initialize:(NSString *)configString comment:(NSString *)comment error:(NSError **)error;
+ (BOOL)isInitialized;
+ (BOOL)isApproovEnabled;
+ (void)setLoggingLevel:(ApproovLogLevel)level;
+ (ApproovLogLevel)getLoggingLevel;
+ (BOOL)shouldLogAtLevel:(ApproovLogLevel)level NS_SWIFT_NAME(shouldLog(at:));
+ (void)logWithLevel:(ApproovLogLevel)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);
+ (void)setProceedOnNetworkFailure:(BOOL)proceed;
+ (void)setDevKey:(NSString *)devKey;
+ (void)setBindingHeader:(NSString *)newHeader;
+ (NSString *)getBindingHeader;
+ (void)setApproovTokenHeader:(NSString *)newHeader;
+ (NSString *)getApproovTokenHeader;
+ (void)setApproovTokenPrefix:(NSString *)newHeaderPrefix;
+ (NSString *)getApproovTokenPrefix;
+ (void)setApproovTraceIDHeader:(NSString *)newHeader;
+ (NSString *)getApproovTraceIDHeader;
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
+ (void)setMessageSigningMode:(ApproovMessageSigningMode)mode;
+ (ApproovMessageSigningMode)getMessageSigningMode;
+ (void)setMessageSigningBodyDigestEnabled:(BOOL)enabled;
+ (BOOL)getMessageSigningBodyDigestEnabled;
+ (void)setMessageSigningBodyDigestRequired:(BOOL)required;
+ (BOOL)getMessageSigningBodyDigestRequired;
+ (void)setUseApproovStatusIfNoToken:(BOOL)shouldUse;
+ (NSString *)getMessageSignature:(NSString *)message __attribute__((deprecated("Use getAccountMessageSignature or getInstallMessageSignature instead")));
+ (NSString *)getAccountMessageSignature:(NSString *)message;
+ (NSString *)getInstallMessageSignature:(NSString *)message;
+ (NSString *)fetchToken:(NSString *)url error:(NSError **)error;
+ (NSString *)fetchSecureString:(NSString *)key newDef:(NSString *)newDef error:(NSError **)error;
+ (NSString *)fetchCustomJWT:(NSString*)payload error:(NSError **)error;
+ (NSDictionary *)getPins:(NSString *)pinType;
+ (NSString *)getLastARC;
+ (void)setInstallAttrsInToken:(NSString *)attrs;
+ (void)interceptSessionTask:(NSURLSessionTask *)task sessionConfig:(NSURLSessionConfiguration *)sessionConfig
        completionHandler:(CompletionHandlerType)completionHandler;
+ (NSURLRequest *)updateRequestWithApproov:(NSURLRequest *)request
        sessionConfig:(NSURLSessionConfiguration *)sessionConfig error:(NSError **)error;
+ (BOOL)sharedUseApproovStatusIfNoToken;
+ (NSMutableSet<NSString *> *)sharedExclusionURLRegexs;
@end

#endif
