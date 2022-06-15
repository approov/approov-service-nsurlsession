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


#import "Approov/Approov.h"
#import "ApproovService.h"


/*
 *  Encapsulates Approov SDK errors, decisions to proceed or not and any user defined headers
 */
@implementation ApproovData

- (instancetype)init {
    if([super init]){
        [self setDecision:ShouldFail];
        return self;
    }
    return nil;
}

@end

/*  The ApproovService implementation
 *
 */
@implementation ApproovService
static NSString* approovTokenHeader = @"Approov-Token";
/* Approov token custom prefix: any prefix to be added such as "Bearer " */
static NSString* approovTokenPrefix = @"";
/* Bind header string */
static NSString* bindHeader = @"";
/* map of headers that should have their values substituted for secure strings, mapped to their
 required prefixes
 */
static NSMutableDictionary<NSString*, NSString*>* substitutionHeaders = nil;
/* NSError dictionary keys to hold Approov SDK Errors and additional status messages */
static NSString* ApproovSDKErrorKey = @"ApproovServiceError";
static NSString* ApproovSDKRejectionReasonsKey = @"RejectionReasons";
static NSString* ApproovSDKARCKey = @"ARC";
static NSString* RetryLastOperationKey = @"RetryLastOperation";
// Lock object used during initialization
static NSString* initializerLock = @"approov-service-nsurlsession";
// Has the ApproovService been initialized already
static BOOL approovServiceInitialised = NO;
// The original config string used during initialization
static NSString* initialConfigString = nil;
// Should we proceed with network request in case of network failure
static BOOL proceedOnNetworkFail = NO;
/* Set of URL regexs that should be excluded from any Approov protection, mapped to the compiled Pattern */
static NSMutableSet<NSString*>* exclusionURLRegexs = nil;
/* Set of query parameters that may be substituted, specified by the key name */
static NSMutableSet<NSString*>* substitutionQueryParams = nil;

/*
 * Initializes the ApproovService with the provided configuration string. The call is ignored if the
 * ApproovService has already been initialized with the same configuration string.
 *
 * @param configString is the string to be used for initialization
 * @param error is populated with an error if there was a problem during initialization, or nil if not required
 */
+ (void)initialize: (NSString*)configString errorMessage:(NSError**)error {
    @synchronized (initializerLock) {
        // Initialize headers map, exclusion dictionary and query parameters set
        if (substitutionHeaders == nil) substitutionHeaders = [[NSMutableDictionary alloc] init];
        if (exclusionURLRegexs == nil) exclusionURLRegexs = [[NSMutableSet alloc] init];
        if (substitutionQueryParams == nil) substitutionQueryParams = [[NSMutableSet alloc] init];
        // Check if we already have single instance initialized and we attempt to use a different configString
        if ((approovServiceInitialised) && (initialConfigString != nil)) {
            if (![initialConfigString isEqualToString:configString]) {
                *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusInternalError
                    userMessage:@"Approov SDK already initialized with different configuration"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:ApproovTokenFetchStatusInternalError]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
                return;
            }
            // We are initializing with same config string
            return;
        }
        /* Initialise Approov SDK only ever once */
        /* Check we have short config string */
        if(configString == nil){
            NSLog(@"ApproovURLSession: Unable to initialize Approov SDK with provided config");
            *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusNotInitialized
                userMessage:@"Approov SDK can not be initialized with nil"
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:ApproovTokenFetchStatusNotInitialized]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return;
        }
        NSError* localError = nil;
        // Allow empty config string to set SDK as initialized
        if (configString.length > 0){
            [Approov initialize:configString updateConfig:@"auto" comment:nil error:&localError];
        }
        [Approov setUserProperty:initializerLock];
        if (localError != nil) {
            NSLog(@"ApproovURLSession: Error initializing Approov SDK: %@", localError.localizedDescription);
            *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusNotInitialized
                userMessage:localError.localizedDescription
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:ApproovTokenFetchStatusNotInitialized]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return;
        }
        initialConfigString = configString;
        approovServiceInitialised = YES;
    }
}

/*
 * Sets a flag indicating if the network interceptor should proceed anyway if it is
 * not possible to obtain an Approov token due to a networking failure. If this is set
 * then your backend API can receive calls without the expected Approov token header
 * being added, or without header/query parameter substitutions being made. Note that
 * this should be used with caution because it may allow a connection to be established
 * before any dynamic pins have been received via Approov, thus potentially opening the channel to a MitM.
 *
 * @param proceed is true if Approov networking fails should allow continuation
 */
+ (void)setProceedOnNetworkFailure:(BOOL)proceed {
    @synchronized (initializerLock) {
        NSLog(@"ApproovService: setProceedOnNetworkFailure %@", proceed ? @"YES" : @"NO");
        proceedOnNetworkFail = proceed;
    }
}

/*
 *  Allows token/secret prefetch operation to be performed as early as possible. This
 *  permits a token to be available while an application might be loading resources
 *  or is awaiting user input. Since the initial network connection is the most
 *  expensive the prefetch seems reasonable.
 */
+ (void)prefetch {
    if (approovServiceInitialised){
        NSLog(@"ApproovService: prefetch");
        // We succeeded initializing Approov SDK, fetch a token
        [Approov fetchApproovToken:^(ApproovTokenFetchResult* result) {
            // Prefetch done, no need to process response
        }:@"approov.io"];
    }
}

/* The ApproovService error enum status codes mapped to a NSString
 * This is just a convenient function that uses an Approov SDK function
 */
+ (NSString*)stringFromApproovTokenFetchStatus:(NSUInteger)status {
    return [Approov stringFromApproovTokenFetchStatus:status];
}


/* Get bindHeader content
 *
 */
+ (NSString*)getBindHeader {
    @synchronized (bindHeader) {
        return bindHeader;
    }
}

/* Set bindHeader content
 *
 */
+ (void)setBindHeader:(NSString*)newHeader {
    @synchronized (bindHeader) {
        NSLog(@"ApproovService: setBindHeader %@", newHeader);
        bindHeader = newHeader;
    }
}

/* Get approovTokenHeader content
 *
 */
+ (NSString*)getApproovTokenHeader {
    @synchronized (approovTokenHeader) {
        return approovTokenHeader;
    }
}

/* Set approovTokenHeader content
 *
 */
+ (void)setApproovTokenHeader:(NSString*)newHeader {
    @synchronized (approovTokenHeader) {
        NSLog(@"ApproovService: setApproovTokenHeader %@", newHeader);
        approovTokenHeader = newHeader;
    }
}

/* Get approovTokenPrefix content
 *
 */
+ (NSString*)getApproovTokenPrefix {
    @synchronized (approovTokenPrefix) {
        return approovTokenPrefix;
    }
}

/* Set approovTokenPrefix content
 *
 */
+ (void)setApproovTokenPrefix:(NSString*)newHeaderPrefix {
    @synchronized (approovTokenPrefix) {
        NSLog(@"ApproovService: setApproovTokenPrefix %@", newHeaderPrefix);
        approovTokenPrefix = newHeaderPrefix;
    }
}

/*
 * Adds the name of a header which should be subject to secure strings substitution. This
 * means that if the header is present then the value will be used as a key to look up a
 * secure string value which will be substituted into the header value instead. This allows
 * easy migration to the use of secure strings. A required prefix may be specified to deal
 * with cases such as the use of "Bearer " prefixed before values in an authorization header.
 *
 * @param header is the header to be marked for substitution
 * @param requiredPrefix is any required prefix to the value being substituted or nil if not required
 */

+ (void)addSubstitutionHeader:(NSString*)header requiredPrefix:(NSString*)requiredPrefix {
    if (approovServiceInitialised){
        @synchronized(substitutionHeaders){
            NSLog(@"ApproovService: addSubstitutionHeader %@ prefix: %@", header, requiredPrefix);
            if (requiredPrefix == nil) {
                    [substitutionHeaders setValue:@"" forKey:header];
            } else {
                    [substitutionHeaders setValue:requiredPrefix forKey:header];
                }
        }
    }
}

/*
 * Removes a header previously added using addSubstitutionHeader.
 *
 * @param header is the header to be removed for substitution
 */
+(void)removeSubstitutionHeader:(NSString*)header {
    if (approovServiceInitialised){
        @synchronized(substitutionHeaders){
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
+(void)addSubstitutionQueryParam:(NSString*)key {
    @synchronized (substitutionQueryParams) {
        if (approovServiceInitialised) {
            [substitutionQueryParams addObject:key];
            NSLog(@"ApproovService: addSubstitutionQueryParam: %@", key);
        }
    }
}

/**
 * Removes a query parameter key name previously added using addSubstitutionQueryParam.
 *
 * @param key is the query parameter key name to be removed for substitution
 */
+(void)removeSubstitutionQueryParam:(NSString*)key {
    @synchronized (substitutionQueryParams) {
        if (approovServiceInitialised) {
            [substitutionQueryParams removeObject:key];
            NSLog(@"ApproovService: removeSubstitutionQueryParam: %@", key);
        }
    }
}

/*
 * Fetches a secure string with the given key. If newDef is not null then a
 * secure string for the particular app instance may be defined. In this case the
 * new value is returned as the secure string. Use of an empty string for newDef removes
 * the string entry. Note that this call may require network transaction and thus may block
 * for some time, so should not be called from the UI thread. If the attestation fails
 * for any reason then nil is returned. Note that the returned string should NEVER be cached
 * by your app, you should call this function when it is needed. If the fetch fails for any reason
 * and the error paramether is not nil, the ApproovServiceError, RejectionReasons and canRetry will
 * be populated.
 *
 * @param key is the secure string key to be looked up
 * @param newDef is any new definition for the secure string, or nil for lookup only
 * @param error is a pointer to a NSError type containing optional error message
 * @return secure string (should not be cached by your app) or nil if it was not defined or an error ocurred
 */
+(NSString*)fetchSecureString:(NSString*)key newDefinition:(NSString*)newDef error:(NSError**)error  {
    // determine the type of operation as the values themselves cannot be logged
    NSString* type = @"lookup";
    if (newDef != nil)
        type = @"definition";
    // fetch any secure string keyed by the value, catching any exceptions the SDK might throw
    ApproovTokenFetchResult* approovResult = [Approov fetchSecureStringAndWait:key :newDef];
    // Log result of token fetch operation but do not log the value
    NSLog(@"ApproovURLSession: fetchSecureString %@: %@", type, [ApproovService stringFromApproovTokenFetchStatus:approovResult.status]);
    // Process the returned Approov status
    if (approovResult.status == ApproovTokenFetchStatusDisabled) {
        *error = [ApproovService createErrorWithCode:approovResult.status
            userMessage:@"Secure String feature must be enabled using CLI"
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    } else if (approovResult.status == ApproovTokenFetchStatusBadKey) {
            *error = [ApproovService createErrorWithCode:approovResult.status
                userMessage:@"fetchSecureString bad key"
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
        // if the request is rejected then we provide a special exception with additional information
        NSString* details = [[NSMutableString alloc] initWithString:@"fetchSecureString rejected"];
        // Find out if user has enabled rejection reasons and arc features
        BOOL rejectionReasonsEnabled = (approovResult.rejectionReasons != nil);
        BOOL arcEnabled = (approovResult.ARC != nil);
        *error = [ApproovService createErrorWithCode:approovResult.status
            userMessage:details ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                          ApproovSDKRejectionReasons:rejectionReasonsEnabled?approovResult.rejectionReasons:nil ApproovSDKARC:arcEnabled?approovResult.ARC:nil canRetry:NO];
        return nil;
    } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the secure string due to network conditions so the request can
        // be retried by the user later
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchSecureString network error, retry needed."];
        *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
        return nil;
    } else if ((approovResult.status != ApproovTokenFetchStatusSuccess) && (approovResult.status != ApproovTokenFetchStatusUnknownKey)) {
        // we are unable to get the secure string due to a more permanent error
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchSecureString permanent error"];
        *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    }
    return approovResult.secureString;
}

/*
 * Fetches a custom JWT with the given payload. Note that this call will require network
 * transaction and thus will block for some time, so should not be called from the UI thread.
 * If the fetch fails for any reason and the error paramether is not nil, the ApproovServiceError,
 * RejectionReasons and canRetry will be populated.
 *
 * @param payload is the marshaled JSON object for the claims to be included
 * @param error is a pointer to a NSError type containing optional error message
 * @return custom JWT string or nil if an error occurred
 */
+(NSString*)fetchCustomJWT:(NSString*)payload error:(NSError**)error {
    // fetch the custom JWT
    ApproovTokenFetchResult* approovResult = [Approov fetchCustomJWTAndWait:payload];
    // Log result of token fetch operation but do not log the value
    NSLog(@"ApproovURLSession: fetchCustomJWT %@", [Approov stringFromApproovTokenFetchStatus:approovResult.status]);
    // process the returned Approov status
    if (approovResult.status == ApproovTokenFetchStatusBadPayload) {
            *error = [ApproovService createErrorWithCode:approovResult.status
                userMessage:@"fetchCustomJWT: Malformed payload JSON"
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    } else if(approovResult.status == ApproovTokenFetchStatusDisabled){
            *error = [ApproovService createErrorWithCode:approovResult.status
                userMessage:@"fetchCustomJWT: This feature must be enabled using CLI"
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
        // if the request is rejected then we provide a special exception with additional information
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchCustomJWT rejected"];
        // Find out if user has enabled rejection reasons and arc features
        BOOL rejectionReasonsEnabled = (approovResult.rejectionReasons != nil);
        BOOL arcEnabled = (approovResult.ARC != nil);
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                              ApproovSDKRejectionReasons:rejectionReasonsEnabled?approovResult.rejectionReasons:nil ApproovSDKARC:arcEnabled?approovResult.ARC:nil canRetry:NO];
        return nil;
    } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
               (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the JWT due to network conditions so the request can
        // be retried by the user later
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchCustomJWT network error, retry needed"];
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
        return nil;
    } else if (approovResult.status != ApproovTokenFetchStatusSuccess) {
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"fetchCustomJWT permanent error"];
        [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
            *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
        return nil;
    }
    return approovResult.token;
}

/*
 *  Convenience function fetching the Approov token
 *  @param  request The request to be updated
 *  @return ApproovData object
 */
+ (ApproovData*)updateRequestWithApproov:(NSURLRequest*)request {
    ApproovData *returnData = [[ApproovData alloc] init];
    // Save the original request
    [returnData setRequest:request];
    // Check if the URL matches one of the exclusion regexs and just return if it does
    if ([ApproovService checkURLIsExcluded:request.URL]) {
        // We should ignore the request and not modify it since is in the exclusion set
        returnData.decision = ShouldIgnore;
        return returnData;
    }
    // Check if Bind Header is set to a non empty String
    if (![[ApproovService getBindHeader] isEqualToString:@""]){
        /*  Query the NSURLSessionConfiguration for user set headers. They would be set like so:
        *  [config setHTTPAdditionalHeaders:@{@"Authorization Bearer " : @"token"}];
        *  Since the NSURLSessionConfiguration is part of the init call and we store its reference
        *  we check for the presence of a user set header there.
        */
        if([request valueForHTTPHeaderField:[ApproovService getBindHeader]] != nil){
            // Add the Bind Header as a data hash to Approov token
            [Approov setDataHashInToken:[request valueForHTTPHeaderField:[ApproovService getBindHeader]]];
        }
    }
    // Invoke fetch token sync
    ApproovTokenFetchResult* approovResult = [Approov fetchApproovTokenAndWait:request.URL.absoluteString];
    // Log result of token fetch
    NSLog(@"ApproovURLSession: fetchApproovToken for %@: %@", request.URL.host, approovResult.loggableToken);
    // Update the message
    returnData.sdkMessage = [Approov stringFromApproovTokenFetchStatus:approovResult.status];

    switch (approovResult.status) {
        case ApproovTokenFetchStatusSuccess: {
            // Can go ahead and make the API call with the provided request object
            returnData.decision = ShouldProceed;
            // Set Approov-Token header. We need to modify the original request.
            NSMutableURLRequest *newRequest = [returnData.request mutableCopy];
            [newRequest setValue:[NSString stringWithFormat:@"%@%@",approovTokenPrefix,approovResult.token] forHTTPHeaderField: approovTokenHeader];
            returnData.request = newRequest;
            break;
        }
        case ApproovTokenFetchStatusNoNetwork:
        case ApproovTokenFetchStatusPoorNetwork:
        case ApproovTokenFetchStatusMITMDetected: {
            /* We are unable to get the secure string due to network conditions so the request can
            *  be retried by the user later
            *  We are unable to get the secure string due to network conditions, so - unless this is
            *  overridden - we must not proceed. The request can be retried by the user later.
            */
            if (!proceedOnNetworkFail) {
                returnData.decision = ShouldRetry;
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Network issue, retry later"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
                returnData.error = error;
                return returnData;
            }
        }
        case ApproovTokenFetchStatusUnprotectedURL:
        case ApproovTokenFetchStatusUnknownURL:
        case ApproovTokenFetchStatusNoApproovService: {
            // We do NOT add the Approov-Token header to the request headers
            returnData.decision = ShouldProceed;
            break;
        }
        default: {
            returnData.decision = ShouldFail;
            NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Permanent error"
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            returnData.error = error;
            return returnData;
        }
    }
    
    // We only continue additional processing if we had a valid status from Approov, to prevent additional delays
    // by trying to fetch from Approov again and this also protects against header substitutions in domains not
    // protected by Approov and therefore are potentially subject to a MitM.
    if ((approovResult.status != ApproovTokenFetchStatusSuccess) && (approovResult.status != ApproovTokenFetchStatusUnprotectedURL)) {
        return returnData;
    }
    
    // Make a copy of the original request
    NSMutableURLRequest *newRequest = [returnData.request mutableCopy];
    NSDictionary<NSString*,NSString*>* allHeaders = newRequest.allHTTPHeaderFields;
    // obtain a copy of the substitution headers in a thread safe way
    NSDictionary<NSString *, NSString *> *subsHeaders;
    @synchronized (substitutionHeaders) {
        subsHeaders = [[NSDictionary alloc] initWithDictionary:substitutionHeaders copyItems:NO];
    }
    for (NSString* key in subsHeaders.allKeys) {
        NSString* header = key;
        NSString* prefix = [subsHeaders objectForKey:key];
        NSString* value = [allHeaders objectForKey:header];
        // Check if the request contains the header we want to replace
        BOOL valueHasPrefixNotNil = (prefix != nil) && (prefix.length >= 0);
        if ((valueHasPrefixNotNil) && (value.length > prefix.length)){
            approovResult = [Approov fetchSecureStringAndWait:[value substringFromIndex:prefix.length] :nil];
            NSLog(@"Substituting header: %@, %@", header, [Approov stringFromApproovTokenFetchStatus:approovResult.status]);
            if (approovResult.status == ApproovTokenFetchStatusSuccess) {
                // We add the modified header to the new copy of request
                [newRequest setValue:[NSString stringWithFormat:@"%@%@", prefix, approovResult.secureString] forHTTPHeaderField: header];
                // Add the modified request to the return data
                returnData.request = newRequest;
            } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
                // if the request is rejected then we provide a special exception with additional information
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[NSString stringWithFormat:@" %@", [Approov stringFromApproovTokenFetchStatus:approovResult.status]]];
                // Find out if user has enabled rejection reasons and arc features
                BOOL rejectionReasonsEnabled = (approovResult.rejectionReasons != nil);
                BOOL arcEnabled = (approovResult.ARC != nil);
                if (arcEnabled) [details appendString:[NSString stringWithFormat:@" %@", approovResult.ARC]];
                if (rejectionReasonsEnabled) [details appendString:[NSString stringWithFormat:@" %@", approovResult.rejectionReasons]];
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                                          ApproovSDKRejectionReasons:rejectionReasonsEnabled?approovResult.rejectionReasons:nil ApproovSDKARC:arcEnabled?approovResult.ARC:nil canRetry:NO];
                returnData.error = error;
                return returnData;
            } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
                /* We are unable to get the secure string due to network conditions so the request can
                *  be retried by the user later
                *  We are unable to get the secure string due to network conditions, so - unless this is
                *  overridden - we must not proceed. The request can be retried by the user later.
                */
                if (!proceedOnNetworkFail){
                    NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                    [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                    NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Network issue, retry later"
                        ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                        ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
                    returnData.error = error;
                    return returnData;
                }
            } else if (approovResult.status != ApproovTokenFetchStatusUnknownKey) {
                // we have failed to get a secure string with a more serious permanent error
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Permanent error"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
                returnData.error = error;
                return returnData;
            }
        }
    }//for loop
    
    // At this point we have updated the request and we will need the URL to perform query substitution
    NSString* updatedURL = returnData.request.URL.absoluteString;
    // obtain a copy of the substitution query parameter in a thread safe way
    NSSet<NSString *> *subsQueryParams;
    @synchronized(substitutionQueryParams) {
        subsQueryParams = [[NSSet alloc] initWithSet:substitutionQueryParams copyItems:NO];
    }

    // we now deal with any query parameter substitutions, which may require further fetches but these
    // should be using cached results
    for (NSString *key in subsQueryParams) {
        NSString *pattern = [NSString stringWithFormat:@"[\\?&]%@=([^&;]+)", key];
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
        if (error) {
            NSString *detail = [NSString stringWithFormat: @"Approov query parameter substitution regex error: %@", [error localizedDescription]];
            returnData.error = [ApproovService createErrorWithCode:0 userMessage:detail
                                                   ApproovSDKError:nil
                                                   ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return returnData;
        }
        NSTextCheckingResult *match = [regex firstMatchInString:updatedURL options:0 range:NSMakeRange(0, [updatedURL length])];
        if (match) {
            // the request contains the query parameter we want to replace
            NSString *matchText = [updatedURL substringWithRange:[match rangeAtIndex:1]];
            approovResult = [Approov fetchSecureStringAndWait:matchText :nil];
            NSLog(@"substituting query parameter %@: %@", key, [Approov stringFromApproovTokenFetchStatus:approovResult.status]);
            if (approovResult.status == ApproovTokenFetchStatusSuccess) {
                NSString* newURL = [updatedURL stringByReplacingCharactersInRange:[match rangeAtIndex:1] withString:approovResult.secureString];
                NSMutableURLRequest* newRequest = [returnData.request copy];
                [newRequest setURL:[[NSURL alloc] initWithString:newURL]];
                returnData.request = newRequest;
            } else if (approovResult.status == ApproovTokenFetchStatusRejected) {
                // if the request is rejected then we provide a special exception with additional information
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Query Parameter substitution "];
                [details appendString:[NSString stringWithFormat:@" %@", [Approov stringFromApproovTokenFetchStatus:approovResult.status]]];
                // Find out if user has enabled rejection reasons and arc features
                BOOL rejectionReasonsEnabled = (approovResult.rejectionReasons != nil);
                BOOL arcEnabled = (approovResult.ARC != nil);
                if (arcEnabled) [details appendString:[NSString stringWithFormat:@" %@", approovResult.ARC]];
                if (rejectionReasonsEnabled) [details appendString:[NSString stringWithFormat:@" %@", approovResult.rejectionReasons]];
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                                          ApproovSDKRejectionReasons:rejectionReasonsEnabled?approovResult.rejectionReasons:nil ApproovSDKARC:arcEnabled?approovResult.ARC:nil canRetry:NO];
                returnData.error = error;
                return returnData;
            } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
                // we are unable to get the secure string due to network conditions so the request can
                // be retried by the user later - unless overridden
                if (!proceedOnNetworkFail) {
                    NSMutableString* details = [[NSMutableString alloc] initWithString:@"Query Parameter substitution: Network issue, retry later: "];
                    [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                    NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:details
                        ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                        ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
                    returnData.error = error;
                    return returnData;
                }
            } else if (approovResult.status != ApproovTokenFetchStatusUnknownKey) {
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Query Parameter substitution error "];
                [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Permanent error"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
                returnData.error = error;
                return returnData;
            }
        }//if
    }// for
    
    return returnData;
}


/*  Convenient function that just forwards the call to the Approov SDK. Requests a pin type and returns
 *  a dictionary of host to pins
 */
+ (NSDictionary*)getPins:(NSString*)pinType {
    NSDictionary* returnDictionary = [Approov getPins:pinType];
    return returnDictionary;
}


/* Performs a precheck to determine if the app will pass attestation. This requires secure
* strings to be enabled for the account, although no strings need to be set up. This will
* likely require network access so may take some time to complete. It may return an error
* if the precheck fails or if there is some other problem. ApproovTokenFetchStatusRejected is
* an error returnedif the app has failed Approov checks or ApproovTokenFetchStatusNoNetwork for networking
* issues where a user initiated retry of the operation should be allowed. An ApproovTokenFetchStatusRejected
* may provide additional information about the cause of the rejection.
*/
+(void)precheck:(NSError**)error {
    // try to fetch a non-existent secure string in order to check for a rejection
    ApproovTokenFetchResult *approovResults = [Approov fetchSecureStringAndWait:@"precheck-dummy-key" :nil];
    // process the returned Approov status
    if (approovResults.status == ApproovTokenFetchStatusRejected){
        // if the request is rejected then we provide a special exception with additional information
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"precheck "];
        [details appendString:[NSString stringWithFormat:@" %@", [Approov stringFromApproovTokenFetchStatus:approovResults.status]]];
        // Find out if user has enabled rejection reasons and arc features
        BOOL rejectionReasonsEnabled = (approovResults.rejectionReasons != nil);
        BOOL arcEnabled = (approovResults.ARC != nil);
        if (arcEnabled) [details appendString:[NSString stringWithFormat:@" %@", approovResults.ARC]];
        if (rejectionReasonsEnabled) [details appendString:[NSString stringWithFormat:@" %@", approovResults.rejectionReasons]];
        *error = [ApproovService createErrorWithCode:approovResults.status userMessage:details
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResults.status]
                                  ApproovSDKRejectionReasons:rejectionReasonsEnabled?approovResults.rejectionReasons:nil ApproovSDKARC:arcEnabled?approovResults.ARC:nil canRetry:NO];
    } else if ((approovResults.status == ApproovTokenFetchStatusNoNetwork) ||
               (approovResults.status == ApproovTokenFetchStatusPoorNetwork) ||
               (approovResults.status == ApproovTokenFetchStatusMITMDetected)) {
        // we are unable to get the secure string due to network conditions so the request can
        // be retried by the user later
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"precheck "];
        [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResults.status]];
        *error = [ApproovService createErrorWithCode:approovResults.status userMessage:@"Network issue, retry later"
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResults.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
    } else if ((approovResults.status != ApproovTokenFetchStatusSuccess) && (approovResults.status != ApproovTokenFetchStatusUnknownKey)) {
        // we are unable to get the secure string due to a more permanent error
        NSMutableString* details = [[NSMutableString alloc] initWithString:@"prefetch permanent error"];
        *error = [ApproovService createErrorWithCode:approovResults.status userMessage:details
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResults.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
    }
}

/**
 * Checks if the url matches one of the exclusion regexs defined in exclusionURLRegexs
 *
 * @param   url is the URL for which the check is performed
 * @return  Bool true if url matches preset pattern in Dictionary
 */

+(BOOL)checkURLIsExcluded:(NSURL*)url {
    NSString* urlString = url.absoluteString;
    // obtain a copy of the exclusion URL regular expressions in a thread safe way
    NSSet<NSString *> *exclusionURLs;
    @synchronized (exclusionURLRegexs) {
        exclusionURLs = [[NSSet alloc] initWithSet:exclusionURLRegexs copyItems:NO];
    }
    // we just return with the existing URL if it matches any of the exclusion URL regular expressions provided
    for (NSString *exclusionURL in exclusionURLs) {
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:exclusionURL options:0 error:&error];
        if (error == nil) {
            NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, [urlString length])];
            if (match) {
                NSLog(@"ApproovService: excluded url: %@", urlString);
                return YES;
            }
        }
    }
    return NO;
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
+(void)addExclusionURLRegex:(NSString*)urlRegex {
    //NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:urlRegex options:nil error:&error];
    @synchronized (exclusionURLRegexs) {
        if (approovServiceInitialised){
            [exclusionURLRegexs addObject:urlRegex];
            NSLog(@"ApproovService: addExclusionURLRegex: %@", urlRegex);
        }
    }
    
}

/**
 * Removes an exclusion URL regular expression previously added using addExclusionURLRegex.
 *
 * @param urlRegex is the regular expression that will be compared against URLs to exclude them
 */
+(void)removeExclusionURLRegex:(NSString*)urlRegex {
    @synchronized (exclusionURLRegexs) {
        if (approovServiceInitialised) {
            [exclusionURLRegexs removeObject:urlRegex];
            NSLog(@"ApproovService: removeExclusionURLRegex: %@", urlRegex);
        }
    }
}

/* Create an error message filling in Approov SDK error codes and optional Approov SDK device information/failure reason
 *  Also shows if an additional attempt to repeat the last operation might be possible by setting the RetryLastOperationKey
 *  key to "YES"
 */
+ (NSError*)createErrorWithCode:(NSInteger)code userMessage:(NSString*)message ApproovSDKError:(NSString*)sdkError
     ApproovSDKRejectionReasons:(NSString*)rejectionReasons ApproovSDKARC:(NSString*)arc canRetry:(BOOL)retry {
    // Prepare default set of error codes (check nil values and ignore if those are nil)
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc]init];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedDescriptionKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedFailureReasonErrorKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedRecoverySuggestionErrorKey];
    [userInfo setValue: NSLocalizedString(sdkError, nil) forKey:ApproovSDKErrorKey];
    if(rejectionReasons != nil) [userInfo setValue:NSLocalizedString(rejectionReasons, nil) forKey:ApproovSDKRejectionReasonsKey];
    if(arc != nil) [userInfo setValue:NSLocalizedString(arc, nil) forKey:ApproovSDKARCKey];
    if (retry) [userInfo setValue:NSLocalizedString(@"YES", nil) forKey:RetryLastOperationKey];
    NSError* error = [[NSError alloc] initWithDomain:@"io.approov.ApproovURLSession" code:code userInfo:userInfo];
    return error;
}

/**
 * Gets the device ID used by Approov to identify the particular device that the SDK is running on. Note
 * that different Approov apps on the same device will return a different ID. Moreover, the ID may be
 * changed by an uninstall and reinstall of the app.
 *
 * @return String of the device ID or nil in case of an error
 */
+(NSString*)getDeviceID {
    NSString* deviceId = [Approov getDeviceID];
    if (deviceId != nil)
        NSLog(@"ApproovService: getDeviceID %@", deviceId);
    else
        NSLog(@"ApproovService: getDeviceID Error obtaining device ID");
    return deviceId;
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
+(void)setDataHashInToken:(NSString*)data {
    NSLog(@"ApproovService: setDataHashInToken");
    [Approov setDataHashInToken:data];
}

/**
 * Gets the signature for the given message. This uses an account specific message signing key that is
 * transmitted to the SDK after a successful fetch if the facility is enabled for the account. Note
 * that if the attestation failed then the signing key provided is actually random so that the
 * signature will be incorrect. An Approov token should always be included in the message
 * being signed and sent alongside this signature to prevent replay attacks.
 *
 * @param message is the message whose content is to be signed
 * @return String of the base64 encoded message signature
 */
+(NSString*)getMessageSignature:(NSString*)message {
    NSLog(@"ApproovService: getMessageSignature");
    return [Approov getMessageSignature:message];
}

/**
 * Performs an Approov token fetch for the given URL. This should be used in situations where it
 * is not possible to use the networking interception to add the token. This will
 * likely require network access so may take some time to complete. If the attestation fails
 * for any reason then an ApproovError is thrown. This will be ApproovNetworkException for
 * networking issues wher a user initiated retry of the operation should be allowed. Note that
 * the returned token should NEVER be cached by your app, you should call this function when
 * it is needed.
 *
 * @param url is the URL giving the domain for the token fetch
 * @param error is a pointer to a return NSError which might indicate an error during fetch
 * @return String of the fetched token
 */
+(NSString*)fetchToken:(NSString*)url error:(NSError**)error {
    // Fetch the Approov Token
    // Invoke fetch token sync
    ApproovTokenFetchResult* result = [Approov fetchApproovTokenAndWait:url];
    // Log result of token fetch
    NSLog(@"ApproovService: fetchToken for %@: %@", url, result.loggableToken);
    if ((result.status == ApproovTokenFetchStatusNoNetwork) ||
        (result.status == ApproovTokenFetchStatusPoorNetwork) ||
        (result.status == ApproovTokenFetchStatusMITMDetected)) {
        // fetch failed with a network related error
        *error = [ApproovService createErrorWithCode:result.status userMessage:@"Network issue, retry later"
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:result.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
    } else if (result.status != ApproovTokenFetchStatusSuccess) {
        // fetch failed with a more permanent error
        *error = [ApproovService createErrorWithCode:result.status userMessage:@"Error"
            ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:result.status]
            ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
    }
    // we successfully fetched a token
    return result.token;
}

@end
