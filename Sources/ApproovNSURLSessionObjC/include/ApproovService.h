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

#define ApproovLogError(fmt, ...) [ApproovService logWithLevel:ApproovLogLevelError format:(fmt), ##__VA_ARGS__]
#define ApproovLogWarning(fmt, ...) [ApproovService logWithLevel:ApproovLogLevelWarning format:(fmt), ##__VA_ARGS__]
#define ApproovLogInfo(fmt, ...) [ApproovService logWithLevel:ApproovLogLevelInfo format:(fmt), ##__VA_ARGS__]
#define ApproovLogDebug(fmt, ...) [ApproovService logWithLevel:ApproovLogLevelDebug format:(fmt), ##__VA_ARGS__]

@class ApproovTokenFetchResult;

@protocol ApproovServiceMutatorBridgeProtocol <NSObject>
- (void)setUseAccountSigning:(BOOL)useAccountSigning;
- (void)setBodyDigestRequired:(BOOL)bodyDigestRequired;
- (void)setBodyDigestEnabled:(BOOL)bodyDigestEnabled;
- (void)resetServiceMutator;
- (void)processRequest:(NSMutableURLRequest * _Nonnull)request tokenHeader:(NSString * _Nullable)tokenHeader;
- (void)processRequest:(NSMutableURLRequest * _Nonnull)request tokenHeader:(NSString * _Nullable)tokenHeader traceIDHeader:(NSString * _Nullable)traceIDHeader;
- (void)processRequest:(NSMutableURLRequest * _Nonnull)request
           tokenHeader:(NSString * _Nullable)tokenHeader
         traceIDHeader:(NSString * _Nullable)traceIDHeader
    substitutionHeaders:(NSArray<NSString *> * _Nullable)substitutionHeaders
           originalURL:(NSString * _Nullable)originalURL
substitutionQueryParams:(NSArray<NSString *> * _Nullable)substitutionQueryParams;
- (NSInteger)processRequest:(NSMutableURLRequest * _Nonnull)request
                tokenHeader:(NSString * _Nullable)tokenHeader
              traceIDHeader:(NSString * _Nullable)traceIDHeader
         substitutionHeaders:(NSArray<NSString *> * _Nullable)substitutionHeaders
                originalURL:(NSString * _Nullable)originalURL
    substitutionQueryParams:(NSArray<NSString *> * _Nullable)substitutionQueryParams
               errorPointer:(NSError * _Nullable * _Nullable)errorPointer;
- (BOOL)shouldProcessPinningRequest:(NSURLRequest * _Nonnull)request;
- (NSInteger)handleInterceptorFetchTokenResult:(id _Nonnull)result url:(NSString * _Nonnull)url errorPointer:(NSError * _Nullable * _Nullable)errorPointer;
// Substitution decisions. Return 1 to substitute, 0 to skip. A mutator that wants the request to fail
// throws, which arrives here as a non-nil errorPointer alongside 0; a 0 with no error means "skip this
// substitution", which is how the default mutator reports UNKNOWN_KEY.
- (NSInteger)handleInterceptorHeaderSubstitutionResult:(id _Nonnull)result
                                                header:(NSString * _Nonnull)header
                                          errorPointer:(NSError * _Nullable * _Nullable)errorPointer;
- (NSInteger)handleInterceptorQueryParamSubstitutionResult:(id _Nonnull)result
                                                  queryKey:(NSString * _Nonnull)queryKey
                                              errorPointer:(NSError * _Nullable * _Nullable)errorPointer;
@end

NS_ASSUME_NONNULL_BEGIN

// ApproovService provides a mediation layer to the underlying Approov SDK
@interface ApproovService: NSObject
- (instancetype)init NS_UNAVAILABLE;

/**
 * Initializes the ApproovService with an account configuration.
 *
 * Initialization must succeed before any protected request: call this once at app startup,
 * before creating any ApproovNSURLSession or making any API call. Pass an empty string ("") for
 * bypass mode (the native SDK is not initialized and requests are unprotected). On failure the
 * @c error out-parameter is set and the service stays uninitialized — log it and decide whether to
 * block startup or continue unprotected; do not assume protection is active. On success, log
 * @c getDeviceID together with an app-generated session/correlation id so an install can be
 * correlated across your app logs, backend, and the Approov metrics.
 *
 * @param configString the account configuration string, or "" for bypass mode
 * @param error out-parameter set if initialization fails
 */
+ (void)initialize:(NSString *)configString error:(NSError * _Nullable * _Nullable)error;
+ (void)initialize:(NSString *)configString comment:(nullable NSString *)comment error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)isInitialized;
+ (BOOL)isApproovEnabled;
+ (void)setLoggingLevel:(ApproovLogLevel)level;
+ (ApproovLogLevel)getLoggingLevel;
+ (BOOL)shouldLogAtLevel:(ApproovLogLevel)level NS_SWIFT_NAME(shouldLog(at:));
+ (void)logWithLevel:(ApproovLogLevel)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3) NS_SWIFT_UNAVAILABLE("");
+ (void)setProceedOnNetworkFailure:(BOOL)proceed;
+ (void)setDevKey:(NSString *)devKey;
+ (void)setBindingHeader:(NSString *)newHeader;
+ (NSString *)getBindingHeader;
+ (void)setApproovTokenHeader:(NSString *)newHeader;
+ (NSString *)getApproovTokenHeader;
+ (void)setApproovTokenPrefix:(nullable NSString *)newHeaderPrefix;
+ (NSString *)getApproovTokenPrefix;
+ (void)setApproovTraceIDHeader:(NSString *)newHeader;
+ (NSString *)getApproovTraceIDHeader;
+ (void)addSubstitutionHeader:(NSString *)header requiredPrefix:(nullable NSString *)prefix;
+ (void)removeSubstitutionHeader:(NSString *)header;
+ (void)addSubstitutionQueryParam:(NSString *)key;
+ (void)removeSubstitutionQueryParam:(NSString *)key;
+ (void)addExclusionURLRegex:(NSString *)urlRegex;
+ (void)removeExclusionURLRegex:(NSString *)urlRegex;
+ (void)prefetch;
+ (void)precheck:(NSError * _Nullable * _Nullable)error;
+ (NSString *)getDeviceID;
+ (void)setDataHashInToken:(NSString *)data;
+ (void)setMessageSigningMode:(ApproovMessageSigningMode)mode;
+ (ApproovMessageSigningMode)getMessageSigningMode;
+ (void)setMessageSigningBodyDigestEnabled:(BOOL)enabled;
+ (BOOL)getMessageSigningBodyDigestEnabled;
+ (void)setMessageSigningBodyDigestRequired:(BOOL)required;
+ (BOOL)getMessageSigningBodyDigestRequired;
+ (void)setUseApproovStatusIfNoToken:(BOOL)shouldUse;
+ (nullable NSString *)getMessageSignature:(NSString *)message __attribute__((deprecated("Use getAccountMessageSignature or getInstallMessageSignature instead")));
+ (nullable NSString *)getAccountMessageSignature:(NSString *)message;
+ (nullable NSString *)getInstallMessageSignature:(NSString *)message;
+ (nullable NSString *)fetchToken:(NSString *)url error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSString *)fetchSecureString:(NSString *)key newDef:(nullable NSString *)newDef error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSString *)fetchCustomJWT:(NSString *)payload error:(NSError * _Nullable * _Nullable)error;
+ (NSDictionary *)getPins:(NSString *)pinType;
+ (NSString *)getLastARC;
+ (void)setInstallAttrsInToken:(NSString *)attrs;
+ (void)interceptSessionTask:(NSURLSessionTask *)task sessionConfig:(nullable NSURLSessionConfiguration *)sessionConfig
        completionHandler:(nullable CompletionHandlerType)completionHandler;
+ (nullable NSURLRequest *)updateRequestWithApproov:(NSURLRequest *)request
        sessionConfig:(nullable NSURLSessionConfiguration *)sessionConfig error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)sharedUseApproovStatusIfNoToken;
+ (NSMutableSet<NSString *> *)sharedExclusionURLRegexs;
+ (id<ApproovServiceMutatorBridgeProtocol> _Nullable)mutatorBridge;
#ifdef APPROOV_TESTING
+ (void)resetForTesting;
+ (void)setMutatorBridgeOverrideForTesting:(id<ApproovServiceMutatorBridgeProtocol> _Nullable)bridge;
+ (void)clearMutatorBridgeOverrideForTesting;
+ (NSUInteger)sessionTaskSwizzleCountForTesting;
+ (BOOL)isSessionTaskSwizzledForTesting;
#endif
@end

NS_ASSUME_NONNULL_END

#endif
