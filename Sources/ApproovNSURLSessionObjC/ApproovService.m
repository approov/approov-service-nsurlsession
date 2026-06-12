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


#if __has_include(<Approov/Approov.h>)
#import <Approov/Approov.h>
#else
#import <Approov.h>
#endif
#import "ApproovService.h"
#import "ApproovSessionTaskObserver.h"
#import "RSSwizzle.h"
#if __has_include(<approov_service_nsurlsession/approov_service_nsurlsession-Swift.h>)
#import <approov_service_nsurlsession/approov_service_nsurlsession-Swift.h>
#elif __has_include("approov_service_nsurlsession-Swift.h")
#import "approov_service_nsurlsession-Swift.h"
#endif
#import <stdarg.h>

static id<ApproovServiceMutatorBridgeProtocol> mutatorBridgeInstance = nil;
static dispatch_once_t mutatorBridgeOnceToken;

#ifdef APPROOV_TESTING
static BOOL mutatorBridgeOverrideActive = NO;
static id<ApproovServiceMutatorBridgeProtocol> mutatorBridgeOverride = nil;
#endif

// ApproovService provides a mediation layer to the underlying Approov SDK
@implementation ApproovService

+ (id<ApproovServiceMutatorBridgeProtocol> _Nullable)mutatorBridge {
#ifdef APPROOV_TESTING
    @synchronized(self) {
        if (mutatorBridgeOverrideActive) {
            return mutatorBridgeOverride;
        }
    }
#endif
    dispatch_once(&mutatorBridgeOnceToken, ^{
        Class bridgeClass = NSClassFromString(@"ApproovServiceMutatorBridge");
        if (bridgeClass) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            mutatorBridgeInstance = [bridgeClass performSelector:NSSelectorFromString(@"shared")];
            #pragma clang diagnostic pop
        }
    });
    return mutatorBridgeInstance;
}

// tag for logging
static const NSString *TAG = @"ApproovService";

// service layer logging level, defaulting to informational output for backward compatibility
static ApproovLogLevel loggingLevel = ApproovLogLevelInfo;

// header on which the Approov token is added
static NSString *approovTokenHeader = @"Approov-Token";

// Approov token custom prefix: any prefix to be added such as "Bearer "
static NSString *approovTokenPrefix = @"";

// optional Approov trace ID debug header
static NSString *approovTraceIDHeader = @"Approov-TraceID";

// bind header string
static NSString *bindingHeader = @"";

// map of headers that should have their values substituted for secure strings, mapped to their
// required prefixes
static NSMutableDictionary<NSString *, NSString *> *substitutionHeaders = nil;

// lock object used during initialization
static NSString *initializerLock = @"approov-service-nsurlsession";

// has the ApproovService been initialized already
static BOOL isInitialized = NO;

// is the Approov SDK active for request protection
static BOOL isApproovEnabled = NO;



// proceedOnNetworkFail has been removed; network failures are always fail-closed via the mutator

// if enabled and no Approov token is available, send the token fetch status in the token header
static BOOL useApproovStatusIfNoToken = NO;

// message signing is opt-in to preserve existing service layer behavior
static ApproovMessageSigningMode messageSigningMode = ApproovMessageSigningModeDisabled;

// when enabled, signed requests with replayable bodies include a Content-Digest header
static BOOL messageSigningBodyDigestEnabled = YES;

// when enabled, signed requests must include a Content-Digest header
static BOOL messageSigningBodyDigestRequired = NO;

// Set of URL regexs that should be excluded from any Approov protection, mapped to the compiled Pattern
static NSMutableSet<NSString *> *exclusionURLRegexs = nil;

// Set of query parameters that may be substituted, specified by the key name
static NSMutableSet<NSString *> *substitutionQueryParams = nil;

// session task observer for initating Approov protection when the task is initially resumed
static ApproovSessionTaskObserver *sessionTaskObserver;

// has NSURLSessionTask resume already been swizzled
static BOOL isSessionTaskSwizzled = NO;

#ifdef APPROOV_TESTING
// number of times NSURLSessionTask resume has actually been swizzled
static NSUInteger sessionTaskSwizzleCount = 0;
#endif

/**
 * Create an error resulting from using the Approov SDK.
 *
 * @param type is the type of error, should be "general" or "network"
 * @param message is the descriptive error message
 * @return the constructed error
 */
+ (NSError *)createErrorWithType:(NSString *)type message:(NSString *)message {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc]init];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedDescriptionKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedFailureReasonErrorKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedRecoverySuggestionErrorKey];
    [userInfo setValue:NSLocalizedString(type, nil) forKey:@"type"];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:@"message"];
    return [[NSError alloc] initWithDomain:@"approov" code:499 userInfo:userInfo];
}

/**
 * Create an error resulting from using the Approov SDK relating to a rejection.
 *
 * @param message is the descriptive error message
 * @param rejectionARC is the ARC for the failure
 * @param rejectionReasons is an optional list of reasons for the rejection
 * @return the constructed error
 */
+ (NSError *)createRejectionErrorWithMessage:(NSString *)message rejectionARC:(NSString *)rejectionARC
                   rejectionReasons:(NSString *)rejectionReasons {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc]init];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedDescriptionKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedFailureReasonErrorKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedRecoverySuggestionErrorKey];
    [userInfo setValue:NSLocalizedString(@"rejection", nil) forKey:@"type"];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:@"message"];
    [userInfo setValue:NSLocalizedString(rejectionARC, nil) forKey:@"rejectionARC"];
    [userInfo setValue:NSLocalizedString(rejectionReasons, nil) forKey:@"rejectionReasons"];
    return [[NSError alloc] initWithDomain:@"approov" code:499 userInfo:userInfo];
}

+ (NSString *)valueForHTTPHeaderField:(NSString *)header
                             inHeaders:(NSDictionary *)headers {
    if ((header == nil) || (headers == nil)) {
        return nil;
    }

    id directValue = [headers objectForKey:header];
    if (directValue != nil) {
        return [directValue description];
    }

    for (id key in headers) {
        if ([key isKindOfClass:[NSString class]] &&
            [(NSString *)key caseInsensitiveCompare:header] == NSOrderedSame) {
            id value = [headers objectForKey:key];
            return [value description];
        }
    }
    return nil;
}

+ (NSString *)valueForHTTPHeaderField:(NSString *)header
                            inRequest:(NSURLRequest *)request
                         sessionConfig:(NSURLSessionConfiguration *)sessionConfig {
    if (header == nil) {
        return nil;
    }

    NSString *requestValue = [request valueForHTTPHeaderField:header];
    if (requestValue != nil) {
        return requestValue;
    }

    requestValue = [ApproovService valueForHTTPHeaderField:header
                                                 inHeaders:request.allHTTPHeaderFields];
    if (requestValue != nil) {
        return requestValue;
    }

    return [ApproovService valueForHTTPHeaderField:header
                                         inHeaders:sessionConfig.HTTPAdditionalHeaders];
}

+ (NSString *)headerValueForTokenFetchStatus:(ApproovTokenFetchStatus)status {
    NSString *statusString = [Approov stringFromApproovTokenFetchStatus:status];
    statusString = [statusString stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    return statusString.uppercaseString;
}

+ (void)setLoggingLevel:(ApproovLogLevel)level {
    @synchronized(initializerLock) {
        loggingLevel = level;
    }
    ApproovLogInfo(@"%@: setLoggingLevel %ld", TAG, (long)level);
}

+ (ApproovLogLevel)getLoggingLevel {
    @synchronized(initializerLock) {
        return loggingLevel;
    }
}

+ (BOOL)shouldLogAtLevel:(ApproovLogLevel)level {
    if ((level == ApproovLogLevelOff) || (level < ApproovLogLevelOff) || (level > ApproovLogLevelDebug)) {
        return NO;
    }
    @synchronized(initializerLock) {
        return loggingLevel >= level;
    }
}

+ (void)logWithLevel:(ApproovLogLevel)level format:(NSString *)format, ... {
    if (![ApproovService shouldLogAtLevel:level]) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@", message);
}

/**
 * Swizzles the NSURLSessionTask resume method that is called when a task is to be transitioned
 * from its initial suspended state into the running state. This provides an opportunity to intercept (and
 * nullify) this inital call to initiate the Approov protection addition in a different thread so that the
 * calling thread is not blocked.
 */
+ (void)swizzleSessionTask {
    if (isSessionTaskSwizzled) {
        return;
    }
    RSSwizzleInstanceMethod(NSClassFromString(@"NSURLSessionTask"),
        @selector(resume),
        RSSWReturnType(void),
        RSSWArguments(),
        RSSWReplacement({
            if ((sessionTaskObserver == nil) ||
                [sessionTaskObserver shouldExecuteTaskResume:(NSURLSessionTask *)self])
                RSSWCallOriginal();
        }),
    0, NULL);
    isSessionTaskSwizzled = YES;
#ifdef APPROOV_TESTING
    sessionTaskSwizzleCount += 1;
#endif
}

/**
 * Initializes the ApproovService with the provided configuration string. The call is ignored if the
 * ApproovService has already been initialized with the same configuration string.
 *
 * @param configString is the string to be used for initialization
 * @param error is populated with an error if there was a problem during initialization, or nil if not required
 */
+ (void)initialize:(NSString * _Nonnull)configString error:(NSError **)error {
    [ApproovService initialize:configString comment:nil error:error];
}

+ (void)initialize:(NSString * _Nonnull)configString comment:(NSString *)comment error:(NSError **)error {
    @synchronized(initializerLock) {
        if (error != nil) {
            *error = nil;
        }

        // If we are already initialized with a valid config, ignore any subsequent
        // empty config initialization
        if (isInitialized && isApproovEnabled && (configString.length == 0)) {
            ApproovLogInfo(@"%@: ApproovService already initialized with a valid config; ignoring empty configuration", TAG);
            return;
        }

        // Initialize the platform SDK if not in bypass mode (empty config).
        // The SDK returns YES if initialization succeeded, NO if already initialized
        // with the same config even by another service layer instance. Any other
        // failure surfaces as localError.
        BOOL sdkInitialized = YES;
        if (configString.length > 0) {
            if ([ApproovService mutatorBridge] == nil) {
                ApproovLogError(@"%@: Approov initialization failed: ApproovServiceMutatorBridge class not found. Ensure the Swift target is linked and not dead-code stripped.", TAG);
                if (error != nil) {
                    *error = [ApproovService createErrorWithType:@"general"
                                  message:@"ApproovServiceMutatorBridge class not found. Ensure the Swift target is linked and not dead-code stripped."];
                }
                return;
            }
            NSError *localError = nil;
            sdkInitialized = [Approov initialize:configString updateConfig:@"auto"
                                         comment:comment error:&localError];
            if (localError != nil) {
                ApproovLogError(@"%@: Approov initialization failed: %@", TAG, localError.localizedDescription);
                if (error != nil) {
                    *error = [ApproovService createErrorWithType:@"general"
                                  message:localError.localizedDescription];
                }
                return;
            }
        }

        // SDK succeeded (or bypass) — now reset and commit new service-layer state.
        isInitialized = NO;
        isApproovEnabled = NO;

        sessionTaskObserver = nil;
        approovTokenHeader = @"Approov-Token";
        approovTokenPrefix = @"";
        approovTraceIDHeader = @"Approov-TraceID";
        bindingHeader = @"";
        useApproovStatusIfNoToken = NO;
        messageSigningMode = ApproovMessageSigningModeDisabled;
        messageSigningBodyDigestEnabled = YES;
        messageSigningBodyDigestRequired = NO;
        substitutionHeaders = [[NSMutableDictionary alloc] init];
        exclusionURLRegexs = [[NSMutableSet alloc] init];
        substitutionQueryParams = [[NSMutableSet alloc] init];

        // Reset the service mutator
        [[ApproovService mutatorBridge] resetServiceMutator];

        if (configString.length > 0) {
            if (!sdkInitialized) {
                ApproovLogDebug(@"%@: Approov SDK already initialized", TAG);
            }
            [Approov setUserProperty:(NSString *)initializerLock];
            sessionTaskObserver = [[ApproovSessionTaskObserver alloc] init];
            [ApproovService swizzleSessionTask];
        } else {
            ApproovLogInfo(@"%@: initialized without Approov SDK protection", TAG);
        }


        isApproovEnabled = (configString.length > 0);
        isInitialized = YES;
    }
}

+ (BOOL)isInitialized {
    @synchronized(initializerLock) {
        return isInitialized;
    }
}

+ (BOOL)isApproovEnabled {
    @synchronized(initializerLock) {
        return isInitialized && isApproovEnabled;
    }
}

#ifdef APPROOV_TESTING
+ (void)resetForTesting {
    @synchronized(initializerLock) {
        isInitialized = NO;
        isApproovEnabled = NO;
        sessionTaskObserver = nil;
        approovTokenHeader = @"Approov-Token";
        approovTokenPrefix = @"";
        approovTraceIDHeader = @"Approov-TraceID";
        bindingHeader = @"";
        useApproovStatusIfNoToken = NO;
        messageSigningMode = ApproovMessageSigningModeDisabled;
        messageSigningBodyDigestEnabled = YES;
        messageSigningBodyDigestRequired = NO;
        substitutionHeaders = [[NSMutableDictionary alloc] init];
        exclusionURLRegexs = [[NSMutableSet alloc] init];
        substitutionQueryParams = [[NSMutableSet alloc] init];
    }
}

+ (void)setMutatorBridgeOverrideForTesting:(id<ApproovServiceMutatorBridgeProtocol> _Nullable)bridge {
    @synchronized(self) {
        mutatorBridgeOverride = bridge;
        mutatorBridgeOverrideActive = YES;
    }
}

+ (void)clearMutatorBridgeOverrideForTesting {
    @synchronized(self) {
        mutatorBridgeOverride = nil;
        mutatorBridgeOverrideActive = NO;
    }
}

+ (NSUInteger)sessionTaskSwizzleCountForTesting {
    return sessionTaskSwizzleCount;
}

+ (BOOL)isSessionTaskSwizzledForTesting {
    return isSessionTaskSwizzled;
}
#endif

/**
 * Deprecated. Use the Swift ApproovServiceMutator API to override network failure behavior.
 * This method is retained for source compatibility only and has no effect.
 *
 * @param proceed unused
 */
+ (void)setProceedOnNetworkFailure:(BOOL)proceed {
    ApproovLogWarning(@"%@: setProceedOnNetworkFailure is deprecated and has no effect. Use ApproovServiceMutatorBridge to override network failure behavior.", TAG);
}

/**
 * Sets a development key indicating that the app is a development version and it should
 * pass attestation even if the app is not registered or it is running on an emulator. The
 * development key value can be rotated at any point in the account if a version of the app
 * containing the development key is accidentally released. This is primarily
 * used for situations where the app package must be modified or resigned in
 * some way as part of the testing process.
 *
 * @param devKey is the development key to be used
 */
+ (void)setDevKey:(NSString *)devKey {
    if (![ApproovService isApproovEnabled]) {
        return;
    }
    ApproovLogDebug(@"%@: setDevKey", TAG);
    [Approov setDevKey:devKey];
}

/**
 * Get the binding header.
 *
 * @return the binding header
 */
+ (NSString *)getBindingHeader {
    @synchronized(initializerLock) {
        return bindingHeader;
    }
}

/**
 * Set the binding header.
 *
 * @param header is the new binding header
 */
+ (void)setBindingHeader:(NSString *)header {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setBindingHeader %@", TAG, header);
        bindingHeader = header;
    }
}

/**
 * Get the Approov token header.
 *
 * @return the Approov token header
 */
+ (NSString *)getApproovTokenHeader {
    @synchronized(initializerLock) {
        return approovTokenHeader;
    }
}

/**
 * Set the Approov token header.
 *
 * @param header is the new Approov token header
 */
+ (void)setApproovTokenHeader:(NSString *)header {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setApproovTokenHeader %@", TAG, header);
        approovTokenHeader = header;
    }
}

/**
 * Get the Approov token prefix.
 *
 * @return the Approov token prefix
 */
+ (NSString *)getApproovTokenPrefix {
    @synchronized(initializerLock) {
        return approovTokenPrefix;
    }
}

/**
 * Set the Approov token prefix.
 *
 * @param prefix the Approov token prefix
 */
+ (void)setApproovTokenPrefix:(NSString *)prefix {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setApproovTokenPrefix %@", TAG, prefix);
        approovTokenPrefix = prefix ?: @"";
    }
}

/**
 * Gets the header used for the Approov trace ID.
 *
 * @return Header name
 */
+ (NSString *)getApproovTraceIDHeader {
    @synchronized(initializerLock) {
        return approovTraceIDHeader;
    }
}

/**
 * Sets the header used for the Approov trace ID. Pass nil or an empty string to disable.
 *
 * @param header is the header to use
 */
+ (void)setApproovTraceIDHeader:(NSString *)header {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setApproovTraceIDHeader %@", TAG, header);
        approovTraceIDHeader = header ?: @"";
    }
}

/**
 * Adds the name of a header which should be subject to secure strings substitution. This
 * means that if the header is present then the value will be used as a key to look up a
 * secure string value which will be substituted into the header value instead. This allows
 * easy migration to the use of secure strings. A required prefix may be specified to deal
 * with cases such as the use of "Bearer " prefixed before values in an authorization header.
 *
 * @param header is the header to be marked for substitution
 * @param requiredPrefix is any required prefix to the value being substituted or nil if not required
 */
+ (void)addSubstitutionHeader:(NSString *)header requiredPrefix:(NSString *)requiredPrefix {
    if ([ApproovService isInitialized]){
        @synchronized(substitutionHeaders){
            ApproovLogDebug(@"%@: addSubstitutionHeader %@, prefix: %@", TAG, header, requiredPrefix);
            if (requiredPrefix == nil) {
                    [substitutionHeaders setValue:@"" forKey:header];
            } else {
                    [substitutionHeaders setValue:requiredPrefix forKey:header];
            }
        }
    }
}

/**
 * Removes a header previously added using addSubstitutionHeader.
 *
 * @param header is the header to be removed for substitution
 */
+ (void)removeSubstitutionHeader:(NSString *)header {
    if ([ApproovService isInitialized]){
        @synchronized(substitutionHeaders){
            ApproovLogDebug(@"%@: removeSubstitutionHeader %@", TAG, header);
            [substitutionHeaders removeObjectForKey:header];
        }
    }
}

/**
 * Adds a key name for a query parameter that should be subject to secure strings substitution.
 * This means that if the query parameter is present in a URL then the value will be used as a
 * key to look up a secure string value which will be substituted as the query parameter value
 * instead. This allows easy migration to the use of secure strings.
 *
 * @param key is the query parameter key name to be added for substitution
 */
+ (void)addSubstitutionQueryParam:(NSString *)key {
    @synchronized (substitutionQueryParams) {
        if ([ApproovService isInitialized]) {
            [substitutionQueryParams addObject:key];
            ApproovLogDebug(@"%@: addSubstitutionQueryParam: %@", TAG, key);
        }
    }
}

/**
 * Removes a query parameter key name previously added using addSubstitutionQueryParam.
 *
 * @param key is the query parameter key name to be removed for substitution
 */
+ (void)removeSubstitutionQueryParam:(NSString *)key {
    @synchronized (substitutionQueryParams) {
        if ([ApproovService isInitialized]) {
            [substitutionQueryParams removeObject:key];
            ApproovLogDebug(@"%@: removeSubstitutionQueryParam: %@", TAG, key);
        }
    }
}

/**
 * Adds an exclusion URL regular expression. If a URL for a request matches this regular expression
 * then it will not be subject to any Approov protection. Note that this facility must be used with
 * EXTREME CAUTION due to the impact of dynamic pinning. Pinning may be applied to all domains added
 * using Approov, and updates to the pins are received when an Approov fetch is performed. If you
 * exclude some URLs on domains that are protected with Approov, then these will be protected with
 * Approov pins but without a path to update the pins until a URL is used that is not excluded. Thus
 * you are responsible for ensuring that there is always a possibility of calling a non-excluded
 * URL, or you should make an explicit call to fetchToken if there are persistent pinning failures.
 * Conversely, use of those option may allow a connection to be established before any dynamic pins
 * have been received via Approov, thus potentially opening the channel to a MitM.
 *
 * @param urlRegex is the regular expression that will be compared against URLs to exclude them
 */
+ (void)addExclusionURLRegex:(NSString *)urlRegex {
    //NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:urlRegex options:nil error:&error];
    @synchronized (exclusionURLRegexs) {
        if ([ApproovService isInitialized]){
            [exclusionURLRegexs addObject:urlRegex];
            ApproovLogDebug(@"%@: addExclusionURLRegex: %@", TAG, urlRegex);
        }
    }
    
}

/**
 * Removes an exclusion URL regular expression previously added using addExclusionURLRegex.
 *
 * @param urlRegex is the regular expression that will be compared against URLs to exclude them
 */
+ (void)removeExclusionURLRegex:(NSString *)urlRegex {
    @synchronized (exclusionURLRegexs) {
        if ([ApproovService isInitialized]) {
            [exclusionURLRegexs removeObject:urlRegex];
            ApproovLogDebug(@"%@: removeExclusionURLRegex: %@", TAG, urlRegex);
        }
    }
}

/**
 *  Allows token/secret prefetch operation to be performed as early as possible. This
 *  permits a token to be available while an application might be loading resources
 *  or is awaiting user input. Since the initial network connection is the most
 *  expensive the prefetch seems reasonable.
 */
+ (void)prefetch {
    if ([ApproovService isApproovEnabled]) {
        ApproovLogDebug(@"%@: prefetch", TAG);
        [Approov fetchApproovToken:^(ApproovTokenFetchResult *result) {
            if (result.status == ApproovTokenFetchStatusUnknownURL)
                ApproovLogInfo(@"%@: prefetch: success", TAG);
            else
                ApproovLogInfo(@"%@: prefetch: %@", TAG, [Approov stringFromApproovTokenFetchStatus:result.status]);
        }:@"approov.io"];
    }
}

/**
 * Performs a precheck to determine if the app will pass attestation. This requires secure
 * strings to be enabled for the account, although no strings need to be set up. This will
 * likely require network access so may take some time to complete. It may return an error
 * if the precheck fails or if there is some other problem.
 *
 * @param error is a pointer to a return NSError which might indicate an error during the precheck
 */
+ (void)precheck:(NSError **)error {
    if (![ApproovService isApproovEnabled]) {
        return;
    }
    ApproovTokenFetchResult *result = [Approov fetchSecureStringAndWait:@"precheck-dummy-key" :nil];
    if (result.status == ApproovTokenFetchStatusUnknownKey)
        ApproovLogInfo(@"%@: precheck: success", TAG);
    else
        ApproovLogInfo(@"%@: precheck: %@", TAG, [Approov stringFromApproovTokenFetchStatus:result.status]);
    if (result.status == ApproovTokenFetchStatusRejected){
        // if the request is rejected then we provide a special exception with additional information
        NSString *details = [NSString stringWithFormat:@"precheck rejection: %@ %@",
            result.ARC, result.rejectionReasons];
        if (error != nil)
            *error = [ApproovService createRejectionErrorWithMessage:details rejectionARC:result.ARC
                                                    rejectionReasons:result.rejectionReasons];
    } else if ((result.status == ApproovTokenFetchStatusNoNetwork) ||
               (result.status == ApproovTokenFetchStatusPoorNetwork) ||
               (result.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the secure string due to network conditions so the request can
        // be retried by the user later
        NSString *details = [NSString stringWithFormat:@"precheck network error: %@",
            [Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"network" message:details];
    } else if ((result.status != ApproovTokenFetchStatusSuccess) && (result.status != ApproovTokenFetchStatusUnknownKey)) {
        // we are unable to get the secure string due to a more permanent error
        NSString *details = [NSString stringWithFormat:@"precheck error: %@",
            [Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"general" message:details];
    }
}

/**
 * Gets the device ID used by Approov to identify the particular device that the SDK is running on. Note
 * that different Approov apps on the same device will return a different ID. Moreover, the ID may be
 * changed by an uninstall and reinstall of the app.
 *
 * @return String of the device ID or nil in case of an error
 */
+ (NSString *)getDeviceID {
    if (![ApproovService isApproovEnabled]) {
        return nil;
    }
    NSString* deviceID = [Approov getDeviceID];
    if (deviceID != nil)
        ApproovLogDebug(@"%@: getDeviceID %@", TAG, deviceID);
    else
        ApproovLogError(@"%@: getDeviceID error", TAG);
    return deviceID;
}

/**
 * Directly sets the data hash to be included in subsequently fetched Approov tokens. If the hash is
 * different from any previously set value then this will cause the next token fetch operation to
 * fetch a new token with the correct payload data hash. The hash appears in the
 * 'pay' claim of the Approov token as a base64 encoded string of the SHA256 hash of the
 * data. Note that the data is hashed locally and never sent to the Approov cloud service.
 *
 * @param data is the data to be hashed and set in the token
 */
+ (void)setDataHashInToken:(NSString *)data {
    if (![ApproovService isApproovEnabled]) {
        return;
    }
    ApproovLogDebug(@"%@: setDataHashInToken", TAG);
    [Approov setDataHashInToken:data];
}

/**
 * Performs an Approov token fetch for the given URL. This should be used in situations where it
 * is not possible to use the networking interception to add the token. This will
 * likely require network access so may take some time to complete. If the attestation fails
 * for any reason then an ApproovError is thrown. This will be ApproovNetworkException for
 * networking issues where a user initiated retry of the operation should be allowed. Note that
 * the returned token should NEVER be cached by your app, you should call this function when
 * it is needed.
 *
 * @param url is the URL giving the domain for the token fetch
 * @param error is a pointer to a return NSError which might indicate an error during fetch
 * @return String of the fetched token or nil if there was an error
 */
+ (NSString *)fetchToken:(NSString *)url error:(NSError **)error {
    if (![ApproovService isApproovEnabled]) {
        return nil;
    }
    ApproovTokenFetchResult *result = [Approov fetchApproovTokenAndWait:url];
    ApproovLogInfo(@"%@: fetchToken for %@: %@", TAG, url, result.loggableToken);
    if ((result.status == ApproovTokenFetchStatusNoNetwork) ||
        (result.status == ApproovTokenFetchStatusPoorNetwork) ||
        (result.status == ApproovTokenFetchStatusMITMDetected)) {
        // fetch failed with a network related error
        NSMutableString *details = [[NSMutableString alloc] initWithString:@"fetchToken network error: "];
        [details appendString:[Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"network" message:details];
        return nil;
    } else if (result.status != ApproovTokenFetchStatusSuccess) {
        // fetch failed with a more permanent error
        NSMutableString *details = [[NSMutableString alloc] initWithString:@"fetchToken error: "];
        [details appendString:[Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"general" message:details];
        return nil;
    } else
        // token fetch was successful
        return result.token;
}

+ (NSString *)getMessageSignature:(NSString *)message {
    return [self getAccountMessageSignature:message];
}

/**
 * Gets the signature for the given message using the account-specific message signing key.
 *
 * @param message is the message whose content is to be signed
 * @return String of the base64 encoded message signature
 */
+ (NSString *)getAccountMessageSignature:(NSString *)message {
    if (![ApproovService isApproovEnabled]) {
        return nil;
    }
    ApproovLogDebug(@"%@: getAccountMessageSignature", TAG);
    return [Approov getMessageSignature:message];
}

/**
 * Gets the signature for the given message using the install-specific private key.
 *
 * @param message is the message whose content is to be signed
 * @return String of the base64 encoded message signature
 */
+ (NSString *)getInstallMessageSignature:(NSString *)message {
    if (![ApproovService isApproovEnabled]) {
        return nil;
    }
    ApproovLogDebug(@"%@: getInstallMessageSignature", TAG);
    return [Approov getInstallMessageSignature:message];
}

/**
 * Sets the message signing mode to be applied to protected requests.
 *
 * @param mode is the message signing mode to use
 */
+ (void)setMessageSigningMode:(ApproovMessageSigningMode)mode {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setMessageSigningMode %ld", TAG, (long)mode);
        messageSigningMode = mode;
    }
}

/**
 * Gets the current message signing mode.
 *
 * @return the message signing mode
 */
+ (ApproovMessageSigningMode)getMessageSigningMode {
    @synchronized(initializerLock) {
        return messageSigningMode;
    }
}

/**
 * Sets whether signed requests with replayable bodies should include a Content-Digest header.
 *
 * @param enabled is YES if body digest generation should be attempted
 */
+ (void)setMessageSigningBodyDigestEnabled:(BOOL)enabled {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setMessageSigningBodyDigestEnabled %@", TAG, enabled ? @"YES" : @"NO");
        messageSigningBodyDigestEnabled = enabled;
    }
}

/**
 * Gets whether signed requests with replayable bodies include a Content-Digest header.
 *
 * @return YES if body digest generation is enabled
 */
+ (BOOL)getMessageSigningBodyDigestEnabled {
    @synchronized(initializerLock) {
        return messageSigningBodyDigestEnabled;
    }
}

/**
 * Sets whether signed requests with bodies should include a Content-Digest header.
 *
 * @param required is YES if body digest generation should be required
 */
+ (void)setMessageSigningBodyDigestRequired:(BOOL)required {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setMessageSigningBodyDigestRequired %@", TAG, required ? @"YES" : @"NO");
        messageSigningBodyDigestRequired = required;
    }
}

/**
 * Gets whether signed requests with bodies include a Content-Digest header.
 *
 * @return YES if body digest generation is required
 */
+ (BOOL)getMessageSigningBodyDigestRequired {
    @synchronized(initializerLock) {
        return messageSigningBodyDigestRequired;
    }
}

/**
 * Sets whether the Approov token header should be populated with the token fetch status
 * when no token is available and the request is allowed to proceed.
 *
 * @param shouldUse is YES if token fetch statuses should be sent in the token header
 */
+ (void)setUseApproovStatusIfNoToken:(BOOL)shouldUse {
    @synchronized(initializerLock) {
        ApproovLogDebug(@"%@: setUseApproovStatusIfNoToken %@", TAG, shouldUse ? @"YES" : @"NO");
        useApproovStatusIfNoToken = shouldUse;
    }
}

/**
 * Returns the current state of use Approov status if no token.
 *
 * @return YES if token fetch statuses should be sent in the token header
 */
+ (BOOL)sharedUseApproovStatusIfNoToken {
    @synchronized(initializerLock) {
        return useApproovStatusIfNoToken;
    }
}

/**
 * Returns a copy of the current exclusion URL regexs for Swift mutator support.
 *
 * @return a mutable set containing the exclusion URL regexs
 */
+ (NSMutableSet<NSString *> *)sharedExclusionURLRegexs {
    @synchronized(exclusionURLRegexs) {
        if (exclusionURLRegexs == nil) {
            return [[NSMutableSet alloc] init];
        }
        return [[NSMutableSet alloc] initWithSet:exclusionURLRegexs copyItems:NO];
    }
}

/**
 * Fetches a secure string with the given key. If newDef is not null then a
 * secure string for the particular app instance may be defined. In this case the
 * new value is returned as the secure string. Use of an empty string for newDef removes
 * the string entry. Note that this call may require network transaction and thus may block
 * for some time, so should not be called from the UI thread. If the attestation fails
 * for any reason then nil is returned. Note that the returned string should NEVER be cached
 * by your app, you should call this function when it is needed.
 *
 * @param key is the secure string key to be looked up
 * @param newDef is any new definition for the secure string, or nil for lookup only
 * @param error is a pointer to a NSError type containing optional error message
 * @return secure string (should not be cached by your app) or nil if it was not defined or an error ocurred
 */
+ (NSString *)fetchSecureString:(NSString *)key newDef:(NSString *)newDef error:(NSError **)error  {
    if (![ApproovService isApproovEnabled]) {
        return nil;
    }
    // determine the type of operation as the values themselves cannot be logged
    NSString* type = @"lookup";
    if (newDef != nil)
        type = @"definition";
    
    // fetch any secure string keyed by the value, catching any exceptions the SDK might throw
    ApproovTokenFetchResult *result = [Approov fetchSecureStringAndWait:key :newDef];
    ApproovLogInfo(@"%@: fetchSecureString %@: %@", TAG, type, [Approov stringFromApproovTokenFetchStatus:result.status]);
    if (result.status == ApproovTokenFetchStatusRejected) {
        // if the request is rejected then we provide a special exception with additional information
        NSString *details = [NSString stringWithFormat:@"fetchSecureString rejection: %@ %@",
            result.ARC, result.rejectionReasons];
        if (error != nil)
            *error = [ApproovService createRejectionErrorWithMessage:details rejectionARC:result.ARC
                                                    rejectionReasons:result.rejectionReasons];
        return nil;
    } else if ((result.status == ApproovTokenFetchStatusNoNetwork) ||
               (result.status == ApproovTokenFetchStatusPoorNetwork) ||
               (result.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the secure string due to network conditions so the request can
        // be retried by the user later
        NSString *details = [NSString stringWithFormat:@"fetchSecureString network error: %@",
            [Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"network" message:details];
        return nil;
    } else if ((result.status != ApproovTokenFetchStatusSuccess) && (result.status != ApproovTokenFetchStatusUnknownKey)) {
        // we are unable to get the secure string due to a more permanent error
        NSString *details = [NSString stringWithFormat:@"fetchSecureString error: %@",
            [Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"general" message:details];
        return nil;
    } else
        // secure string fetch was successful or it did not exist
        return result.secureString;
}

/**
 * Fetches a custom JWT with the given payload. Note that this call will require network
 * transaction and thus will block for some time, so should not be called from the UI thread.
 *
 * @param payload is the marshaled JSON object for the claims to be included
 * @param error is a pointer to a NSError type containing optional error message
 * @return custom JWT string or nil if an error occurred
 */
+ (NSString *)fetchCustomJWT:(NSString *)payload error:(NSError **)error {
    if (![ApproovService isApproovEnabled]) {
        return nil;
    }
    ApproovTokenFetchResult* result = [Approov fetchCustomJWTAndWait:payload];
    ApproovLogInfo(@"%@: fetchCustomJWT %@", TAG, [Approov stringFromApproovTokenFetchStatus:result.status]);
    if (result.status == ApproovTokenFetchStatusRejected) {
        // if the request is rejected then we provide a special exception with additional information
        NSString *details = [NSString stringWithFormat:@"fetchCustomJWT rejection: %@ %@",
            result.ARC, result.rejectionReasons];
        if (error != nil)
            *error = [ApproovService createRejectionErrorWithMessage:details rejectionARC:result.ARC
                                                    rejectionReasons:result.rejectionReasons];
        return nil;
    } else if ((result.status == ApproovTokenFetchStatusNoNetwork) ||
               (result.status == ApproovTokenFetchStatusPoorNetwork) ||
               (result.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the JWT due to network conditions so the request can
        // be retried by the user later
        NSString *details = [NSString stringWithFormat:@"fetchCustomJWT network error: %@",
            [Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"network" message:details];
        return nil;
    } else if (result.status != ApproovTokenFetchStatusSuccess) {
        NSString *details = [NSString stringWithFormat:@"fetchCustomJWT error: %@",
            [Approov stringFromApproovTokenFetchStatus:result.status]];
        if (error != nil)
            *error = [ApproovService createErrorWithType:@"general" message:details];
        return nil;
    } else
        // custom JWT was successfully fetched
        return result.token;
}


/**
 * Convenient function that just forwards the call to the Approov SDK. Requests a pin type and returns
 * a dictionary of host to pins.
 *
 * @param pinType is the type of pins to be obtained
 * @return dictionary of the pins for different host domains
 */
+ (NSDictionary *)getPins:(NSString*)pinType {
    if (![ApproovService isApproovEnabled]) {
        return @{};
    }
    NSDictionary* returnDictionary = [Approov getPins:pinType];
    return returnDictionary;
}

/**
 * Gets the last ARC (Attestation Response Code) code.
 *
 * NOTE: You MUST only call this method upon successful attestation completion. Any networking
 * errors returned from the service layer will not return a meaningful ARC code if the method is called!!!
 * @return String ARC from last attestation request or empty string if network unavailable (not used here)
 */
+ (NSString *)getLastARC {
    if (![ApproovService isApproovEnabled]) {
        return @"";
    }
    // Get the dynamic pins from Approov
    NSDictionary<NSString *, NSArray<NSString *> *> *approovPins = [Approov getPins:@"public-key-sha256"];
    if (approovPins == nil || approovPins.count == 0) {
        ApproovLogInfo(@"%@: no host pinning information available", TAG);
        return @"";
    }
    // The approovPins contains a map of hostnames to pin strings. Skip '*' and use another hostname if available.
    NSString *hostname = nil;
    for (NSString *key in approovPins.allKeys) {
        if (![key isEqualToString:@"*"]) {
            hostname = key;
            break;
        }
    }
    if (hostname != nil) {
        ApproovTokenFetchResult *result = [Approov fetchApproovTokenAndWait:hostname];
        // Check if a token was fetched successfully and return its arc code
        if (result.token != nil && result.token.length > 0) {
            if (result.ARC != nil) {
                return result.ARC;
            }
        }
    }
    ApproovLogInfo(@"%@: no ARC available", TAG);
    return @"";
}

/**
 * Sets an install attributes token to be sent to the server and associated with this particular
 * app installation for future Approov token fetches. The token must be signed, within its
 * expiry time and bound to the correct device ID for it to be accepted by the server.
 * Calling this method ensures that the next call to fetch an Approov
 * token will not use a cached version, so that this information can be transmitted to the server.
 *
 * @param attrs is the signed JWT holding the new install attributes
 */
+ (void)setInstallAttrsInToken:(NSString *)attrs {
    if (![ApproovService isApproovEnabled]) {
        return;
    }
    ApproovLogDebug(@"%@: setInstallAttrsInToken", TAG);
    [Approov setInstallAttrsInToken:attrs];
}

/**
 * Indicates that the given task, associated with the given configuration, should be intercepted. This means that the initial resume of the task is ignored but instead
 * used to initiate the process of obtaining Approov protection in a background thread. When this completes the request can be updated and the task actually
 * resumed. This avoids blocking execution on the thread that makes the resume call.
 *
 * @param task is the task that should be intercepted
 * @param sessionConfig is the session configuration ot be used from which session wide headers can be obtained
 * @param completionHandler is an completion handler to be called on any cancellation, or nil if not required
 */
+ (void)interceptSessionTask:(NSURLSessionTask *)task sessionConfig:(NSURLSessionConfiguration *)sessionConfig
        completionHandler:(CompletionHandlerType)completionHandler {
    if (sessionTaskObserver != nil)
        [sessionTaskObserver addWithTask:task sessionConfig:sessionConfig completionHandler:completionHandler];
}

+ (void)addTraceIDFromResult:(ApproovTokenFetchResult *)result
                   toRequest:(NSMutableURLRequest *)request {
    NSString *traceIDHeader;
    @synchronized(initializerLock) {
        traceIDHeader = approovTraceIDHeader;
    }
    if ((traceIDHeader.length > 0) && (result.traceID != nil)) {
        [request setValue:result.traceID forHTTPHeaderField:traceIDHeader];
    }
}

+ (BOOL)applyMessageSigningIfEnabledToRequest:(NSMutableURLRequest *)request
                           substitutedHeaders:(NSArray<NSString *> *)substitutedHeaders
                                  originalURL:(NSString *)originalURL
                        substitutedQueryParams:(NSArray<NSString *> *)substitutedQueryParams
                                         error:(NSError **)error {
    ApproovMessageSigningMode mode = [ApproovService getMessageSigningMode];
    if (mode == ApproovMessageSigningModeDisabled) {
        return YES;
    }
    BOOL useAccountSigning = (mode == ApproovMessageSigningModeAccount);
    id<ApproovServiceMutatorBridgeProtocol> bridge = [ApproovService mutatorBridge];
    if (bridge == nil) {
        if (error != nil) {
            *error = [ApproovService createErrorWithType:@"general"
                         message:@"ApproovServiceMutatorBridge class not found while processing message signing."];
        }
        return NO;
    }
    [bridge setUseAccountSigning:useAccountSigning];
    [bridge setBodyDigestEnabled:[ApproovService getMessageSigningBodyDigestEnabled]];
    [bridge setBodyDigestRequired:[ApproovService getMessageSigningBodyDigestRequired]];
    NSError *signingError = nil;
    NSInteger processed = [bridge processRequest:request
                                     tokenHeader:[ApproovService getApproovTokenHeader]
                                   traceIDHeader:[ApproovService getApproovTraceIDHeader]
                             substitutionHeaders:substitutedHeaders
                                     originalURL:originalURL
                         substitutionQueryParams:substitutedQueryParams
                                    errorPointer:&signingError];
    if (processed == 0) {
        if (error != nil) {
            *error = signingError ?: [ApproovService createErrorWithType:@"general"
                                            message:@"Approov message signing failed."];
        }
        return NO;
    }
    return YES;
}

/**
 * Adds Approov to the given request. This involves fetching an Approov token for the domain being accessed and
 * adding an Approov token to the outgoing header. This may also update the token if token binding is being used.
 * Header or query parameter values may also be substituted if this feature is enabled. The updated request is
 * returned.
 *
 * @param request is the request being updated
 * @param sessionConfig is provided to allow reading of headers defined on the session
 * @param error is the error that is set if there is a problem
 * @return the updated request, or the original request if there was an error
 */
+ (NSURLRequest *)updateRequestWithApproov:(NSURLRequest *)request
            sessionConfig:(NSURLSessionConfiguration *)sessionConfig error:(NSError **)error {
    // get the URL host domain
    NSString *host = request.URL.host;
    if (host == nil) {
        ApproovLogInfo(@"%@: request domain was missing or invalid", TAG);
        return request;
    }

    // we always allow requests to "localhost" without Approov protection as can be used for obtaining resources
    // during development
    NSString *url = request.URL.absoluteString;
    if ([host isEqualToString:@"localhost"]) {
        ApproovLogInfo(@"%@: localhost forwarded: %@", TAG, url);
        return request;
    }

    // if the Approov SDK is not active then we just return immediately without making any changes
    if (![ApproovService isApproovEnabled]) {
        ApproovLogInfo(@"%@: unprotected service forwarded: %@", TAG, url);
        return request;
    }

    // obtain a copy of the exclusion URL regular expressions in a thread safe way
    NSSet<NSString *> *exclusionURLs;
    @synchronized(exclusionURLRegexs) {
        exclusionURLs = [[NSSet alloc] initWithSet:exclusionURLRegexs copyItems:NO];
    }

    // we just return with the existing URL if it matches any of the exclusion URL regular expressions provided
    for (NSString *exclusionURL in exclusionURLs) {
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:exclusionURL options:0 error:&error];
        if (!error) {
            NSTextCheckingResult *match = [regex firstMatchInString:url options:0 range:NSMakeRange(0, [url length])];
            if (match) {
                ApproovLogInfo(@"%@: excluded url: %@", TAG, url);
                return request;
            }
        }
    }

    // update the data hash based on any token binding header
    @synchronized(initializerLock) {
        if (![bindingHeader isEqualToString:@""]) {
            NSString *headerValue = [ApproovService valueForHTTPHeaderField:bindingHeader
                                                                  inRequest:request
                                                               sessionConfig:sessionConfig];
            if (headerValue != nil) {
                [Approov setDataHashInToken:headerValue];
                ApproovLogDebug(@"%@: setting data hash for binding header %@", TAG, bindingHeader);
            }
        }
    }

    // fetch the Approov token and log the result
    ApproovTokenFetchResult *result = [Approov fetchApproovTokenAndWait:url];
    ApproovLogInfo(@"%@: token for %@: %@", TAG, host, [result loggableToken]);

    // log if a configuration update is received and call fetchConfig to clear the update state
    if (result.isConfigChanged) {
        [Approov fetchConfig];
        ApproovLogInfo(@"%@: dynamic configuration update received", TAG);
    }

    // copy request into a form were it can be updated
    NSMutableURLRequest *updatedRequest = [request mutableCopy];

    // process the token fetch result
    ApproovTokenFetchStatus status = [result status];

    // Let the service mutator decide whether non-standard token fetch statuses should proceed.
    if ((status != ApproovTokenFetchStatusSuccess) &&
        (status != ApproovTokenFetchStatusUnknownURL) &&
        (status != ApproovTokenFetchStatusUnprotectedURL)) {
        NSError *mutatorError = nil;
        BOOL shouldProceed = NO;
        @try {
            shouldProceed = [[ApproovService mutatorBridge]
                handleInterceptorFetchTokenResult:result
                                              url:url
                                     errorPointer:&mutatorError];
        } @catch (NSException *exception) {
            if (error != nil)
                *error = [ApproovService createErrorWithType:@"general" message:exception.reason];
            return request;
        }

        if (!shouldProceed) {
            if (mutatorError != nil) {
                if (error != nil)
                    *error = mutatorError;
                return request;
            }

            if ((status == ApproovTokenFetchStatusNoNetwork) ||
                (status == ApproovTokenFetchStatusPoorNetwork) ||
                (status == ApproovTokenFetchStatusMITMDetected)) {
                NSString *details = [NSString stringWithFormat:@"network error: %@",
                    [Approov stringFromApproovTokenFetchStatus:status]];
                if (error != nil)
                    *error = [ApproovService createErrorWithType:@"network" message:details];
                return request;
            } else if (status != ApproovTokenFetchStatusNoApproovService) {
                // we have a more permanent error from the Approov SDK
                NSString *details = [NSString stringWithFormat:@"error: %@",
                    [Approov stringFromApproovTokenFetchStatus:status]];
                if (error != nil)
                    *error = [ApproovService createErrorWithType:@"general" message:details];
                return request;
            }
        }
    }

    if (status == ApproovTokenFetchStatusSuccess) {
        // add the Approov token to the required header
        NSString *tokenHeader;
        @synchronized(initializerLock) {
            tokenHeader = approovTokenHeader;
        }
        NSString *tokenPrefix;
        @synchronized(initializerLock) {
            tokenPrefix = approovTokenPrefix;
        }
        NSString *tokenValue = result.token ?: @"";
        if (tokenValue.length == 0 && useApproovStatusIfNoToken) {
            tokenValue = [ApproovService headerValueForTokenFetchStatus:status];
        }
        NSString *value = [NSString stringWithFormat:@"%@%@", tokenPrefix, tokenValue];
        [updatedRequest setValue:value forHTTPHeaderField:tokenHeader];
    } else if ((status != ApproovTokenFetchStatusUnknownURL) &&
               (status != ApproovTokenFetchStatusUnprotectedURL) &&
               useApproovStatusIfNoToken) {
        NSString *tokenHeader;
        @synchronized(initializerLock) {
            tokenHeader = approovTokenHeader;
        }
        NSString *tokenPrefix;
        @synchronized(initializerLock) {
            tokenPrefix = approovTokenPrefix;
        }
        NSString *value = [NSString stringWithFormat:@"%@%@", tokenPrefix,
            [ApproovService headerValueForTokenFetchStatus:status]];
        [updatedRequest setValue:value forHTTPHeaderField:tokenHeader];
    }

    // unprotected or unknown URLs are not subject to request mutation
    if ((status == ApproovTokenFetchStatusUnknownURL) ||
        (status == ApproovTokenFetchStatusUnprotectedURL)) {
        return updatedRequest;
    }

    [ApproovService addTraceIDFromResult:result toRequest:updatedRequest];

    // we just return early with anything other than a success or unprotected URL - this is to ensure we don't
    // make further Approov fetches if there has been a problem and also that we don't do header or query
    // parameter substitutions in domains not known to Approov (which therefore might not be pinned).
    // Message signing is skipped here because it requires token artifacts (the public key for install signing
    // or the mksid for account signing) that are only present on a successful token fetch.
    if (status != ApproovTokenFetchStatusSuccess) {
        return updatedRequest;
    }

    NSMutableArray<NSString *> *substitutedHeaderKeys = [[NSMutableArray alloc] init];
    NSMutableArray<NSString *> *substitutedQueryParamKeys = [[NSMutableArray alloc] init];
    NSString *originalURL = nil;

    // obtain a copy of the substitution headers in a thread safe way
    NSDictionary<NSString *, NSString *> *subsHeaders;
    @synchronized(substitutionHeaders) {
        subsHeaders = [[NSDictionary alloc] initWithDictionary:substitutionHeaders copyItems:NO];
    }

    // we now deal with any header substitutions, which may require further fetches but these
    // should be using cached results
    for (NSString *header in subsHeaders) {
        NSString *prefix = [subsHeaders objectForKey:header];
        NSString *value = [ApproovService valueForHTTPHeaderField:header
                                                        inRequest:request
                                                     sessionConfig:sessionConfig];
        if ((value != nil) && (prefix != nil) && (value.length > prefix.length) &&
            (([prefix length] == 0) || [value hasPrefix:prefix])) {
            // the request contains the header we want to replace
            result = [Approov fetchSecureStringAndWait:[value substringFromIndex:prefix.length] :nil];
            status = [result status];
            ApproovLogInfo(@"%@: substituting header %@: %@", TAG, header, [Approov stringFromApproovTokenFetchStatus:status]);
            if (status == ApproovTokenFetchStatusSuccess) {
                if (result.secureString.length > 0) {
                    // update the header value with the actual secret
                    [updatedRequest setValue:[NSString stringWithFormat:@"%@%@", prefix, result.secureString]
                        forHTTPHeaderField:header];
                    [substitutedHeaderKeys addObject:header];
                }
            } else if (status == ApproovTokenFetchStatusRejected) {
                // the attestation has been rejected so provide additional information in the message
                NSString *details = [NSString stringWithFormat:@"Header substitution rejection: %@ %@",
                    result.ARC, result.rejectionReasons];
                *error = [ApproovService createRejectionErrorWithMessage:details rejectionARC:result.ARC
                    rejectionReasons:result.rejectionReasons];
                return request;
            } else if ((status == ApproovTokenFetchStatusNoNetwork) ||
                       (status == ApproovTokenFetchStatusPoorNetwork) ||
                       (status == ApproovTokenFetchStatusMITMDetected)) {
                // we are unable to get the secure string due to network conditions so the request can
                // be retried by the user later
                NSString *details = [NSString stringWithFormat:@"Header substitution network error: %@",
                    [Approov stringFromApproovTokenFetchStatus:status]];
                *error = [ApproovService createErrorWithType:@"network" message:details];
                return request;
            } else if (status != ApproovTokenFetchStatusUnknownKey) {
                // we have failed to get a secure string with a more serious permanent error
                NSString *details = [NSString stringWithFormat:@"Header substitution error: %@",
                        [Approov stringFromApproovTokenFetchStatus:status]];
                *error = [ApproovService createErrorWithType:@"general" message:details];
                return request;
            }
        }
    }

    // obtain a copy of the substitution query parameter in a thread safe way
    NSSet<NSString *> *subsQueryParams;
    @synchronized(substitutionQueryParams) {
        subsQueryParams = [[NSSet alloc] initWithSet:substitutionQueryParams copyItems:NO];
    }

    // we now deal with any query parameter substitutions, which may require further fetches but these
    // should be using cached results
    for (NSString *key in subsQueryParams) {
        NSString *pattern = [NSString stringWithFormat:@"[\\?&]%@=([^&;]+)",
            [NSRegularExpression escapedPatternForString:key]];
        NSError *regexError = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&regexError];
        if (regexError) {
            NSString *details = [NSString stringWithFormat: @"Approov query parameter substitution regex error: %@",
                [regexError localizedDescription]];
            *error = [ApproovService createErrorWithType:@"general" message:details];
            return request;
        }
        NSTextCheckingResult *match = [regex firstMatchInString:url options:0 range:NSMakeRange(0, [url length])];
        if (match) {
            // the request contains the query parameter we want to replace
            NSString *matchText = [url substringWithRange:[match rangeAtIndex:1]];
            result = [Approov fetchSecureStringAndWait:matchText :nil];
            status = [result status];
            ApproovLogInfo(@"%@: substituting query parameter %@: %@", TAG, key, [Approov stringFromApproovTokenFetchStatus:result.status]);
            if (status == ApproovTokenFetchStatusSuccess) {
                if (result.secureString.length > 0) {
                    // update the URL with the actual secret
                    if (originalURL == nil) {
                        originalURL = url;
                    }
                    url = [url stringByReplacingCharactersInRange:[match rangeAtIndex:1] withString:result.secureString];
                    [updatedRequest setURL:[NSURL URLWithString:url]];
                    [substitutedQueryParamKeys addObject:key];
                }
            } else if (status == ApproovTokenFetchStatusRejected) {
                // the attestation has been rejected so provide additional information in the message
                NSString *details = [NSString stringWithFormat:@"Approov query parameter substitution rejection %@ %@",
                    result.ARC, result.rejectionReasons];
                *error = [ApproovService createRejectionErrorWithMessage:details rejectionARC:result.ARC
                    rejectionReasons:result.rejectionReasons];
                return request;
            } else if ((status == ApproovTokenFetchStatusNoNetwork) ||
                       (status == ApproovTokenFetchStatusPoorNetwork) ||
                       (status == ApproovTokenFetchStatusMITMDetected)) {
                // we are unable to get the secure string due to network conditions so the request can
                // be retried by the user later
                NSString *details = [NSString stringWithFormat:@"Approov query parameter substitution network error: %@",
                    [Approov stringFromApproovTokenFetchStatus:status]];
                *error = [ApproovService createErrorWithType:@"network" message:details];
                return request;
            } else if (status != ApproovTokenFetchStatusUnknownKey) {
                // we have failed to get a secure string with a more serious permanent error
                NSString *details = [NSString stringWithFormat:@"Approov query parameter substitution error: %@",
                    [Approov stringFromApproovTokenFetchStatus:status]];
                *error = [ApproovService createErrorWithType:@"general" message:details];
                return request;
            }
        }
    }
    NSError *signingError = nil;
    if (![ApproovService applyMessageSigningIfEnabledToRequest:updatedRequest
                                            substitutedHeaders:substitutedHeaderKeys
                                                   originalURL:originalURL
                                      substitutedQueryParams:substitutedQueryParamKeys
                                                        error:&signingError]) {
        if (error != nil) {
            *error = signingError;
        }
        return request;
    }
    return updatedRequest;
}

@end
