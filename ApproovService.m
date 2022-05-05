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
static NSMutableDictionary<NSString*, NSString*>* substitutionHeaders;
/* NSError dictionary keys to hold Approov SDK Errors and additional status messages */
static NSString* ApproovSDKErrorKey = @"ApproovServiceError";
static NSString* ApproovSDKRejectionReasonsKey = @"RejectionReasons";
static NSString* ApproovSDKARCKey = @"ARC";
static NSString* RetryLastOperationKey = @"RetryLastOperation";
// Lock object used during initialization
static id initializerLock = nil;
// The original config string used during initialization
static NSString* initialConfigString = nil;


/*
 * Initializes the ApproovService with the provided configuration string. The call is ignored if the
 * ApproovService has already been initialized with the same configuration string.
 *
 * @param configString is the string to be used for initialization
 * @param error is populated with an error if there was a problem during initialization, or nil if not required
 */
+ (void)initialize: (NSString*)configString errorMessage:(NSError**)error {
    @synchronized (initializerLock) {
        // Initialize headers map
        if (substitutionHeaders == nil) substitutionHeaders = [[NSMutableDictionary alloc] init];
        // Check if we already have single instance initialized and we attempt to use a different configString
        if ((initializerLock != nil) && (initialConfigString != nil)) {
            if (![initialConfigString isEqualToString:configString]) {
                *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusInternalError
                    userMessage:@"Approov SDK already initialized with different configuration"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:ApproovTokenFetchStatusInternalError]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
                return;
            }
        }
        // Did we initialize before?
        if (initializerLock != nil) return;
        /* Initialise Approov SDK only ever once */
        initializerLock = [[self alloc] init];
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
        [Approov initialize:configString updateConfig:@"auto" comment:nil error:&localError];
        [Approov setUserProperty:@"approov-service-nsurlsession"];
        if (localError != nil) {
            NSLog(@"ApproovURLSession: Error initializing Approov SDK: %@", localError.localizedDescription);
            *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusNotInitialized
                userMessage:localError.localizedDescription
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:ApproovTokenFetchStatusNotInitialized]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
            return;
        }
        initialConfigString = configString;
    }
}


/*
 *  Allows token/secret prefetch operation to be performed as early as possible. This
 *  permits a token to be available while an application might be loading resources
 *  or is awaiting user input. Since the initial network connection is the most
 *  expensive the prefetch seems reasonable.
 */
+ (void)prefetch {
    if (initializerLock != nil){
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
+ (void)setApproovTokenPrefix:(NSString*)newHeader {
    @synchronized (approovTokenPrefix) {
        approovTokenPrefix = newHeader;
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
    if (requiredPrefix == nil) {
        @synchronized(substitutionHeaders){
            [substitutionHeaders setValue:@"" forKey:header];
        }
    } else {
        @synchronized(substitutionHeaders){
            [substitutionHeaders setValue:requiredPrefix forKey:header];
        }
    }
}

/*
 * Removes a header previously added using addSubstitutionHeader.
 *
 * @param header is the header to be removed for substitution
 */
+(void)removeSubstitutionHeader:(NSString*)header {
    @synchronized(substitutionHeaders){
        [substitutionHeaders removeObjectForKey:header];
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
 *  This function is internal and accessed by the ApproovURLSesssion class
 */
+ (ApproovData*)fetchApproovToken:(NSURLRequest*)request {
    ApproovData *returnData = [[ApproovData alloc] init];
    // Save the original request
    [returnData setRequest:request];
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
            // Must not proceed with network request and inform user a retry is needed
            returnData.decision = ShouldRetry;
            NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Network issue, retry later"
                ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
            returnData.error = error;
            return returnData;
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
    
    // we now deal with any header substitutions, which may require further fetches but these
    // should be using cached results
    BOOL isIllegalSubstitution = (approovResult.status == ApproovTokenFetchStatusUnknownURL);
    // Make a copy of the original request
    NSMutableURLRequest *newRequest = [returnData.request mutableCopy];
    NSDictionary<NSString*,NSString*>* allHeaders = newRequest.allHTTPHeaderFields;
    for (NSString* key in substitutionHeaders.allKeys) {
        NSString* header = key;
        NSString* prefix = [substitutionHeaders objectForKey:key];
        NSString* value = [allHeaders objectForKey:header];
        // Check if the request contains the header we want to replace
        BOOL valueHasPrefixNotNil = (prefix != nil) && (prefix.length >= 0);
        if ((valueHasPrefixNotNil) && (value.length > prefix.length)){
            approovResult = [Approov fetchSecureStringAndWait:[value substringFromIndex:prefix.length] :nil];
            NSLog(@"Substituting header: %@, %@", header, [Approov stringFromApproovTokenFetchStatus:approovResult.status]);
            if (approovResult.status == ApproovTokenFetchStatusSuccess) {
                if (isIllegalSubstitution){
                    // don't allow substitutions on unadded API domains to prevent them accidentally being
                    // subject to a Man-in-the-Middle (MitM) attack
                    NSString* message = [NSString stringWithFormat:@"Header substitution for %@ illegal for %@ that is not an added API domain",
                        header, newRequest.URL];
                    NSError *error = [ApproovService createErrorWithCode:ApproovTokenFetchStatusSuccess userMessage:message
                        ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                        ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
                    returnData.error = error;
                    break;
                }
                // We add the modified header to the new copy of request
                [newRequest setValue:[NSString stringWithFormat:@"%@%@", prefix, approovResult.secureString] forHTTPHeaderField: header];
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
                break;
            } else if ((approovResult.status == ApproovTokenFetchStatusNoNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusPoorNetwork) ||
                       (approovResult.status == ApproovTokenFetchStatusMITMDetected)) {
                // we are unable to get the secure string due to network conditions so the request can
                // be retried by the user later
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Network issue, retry later"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:YES];
                returnData.error = error;
                break;
            } else if (approovResult.status != ApproovTokenFetchStatusUnknownKey) {
                // we have failed to get a secure string with a more serious permanent error
                NSMutableString* details = [[NSMutableString alloc] initWithString:@"Header substitution "];
                [details appendString:[Approov stringFromApproovTokenFetchStatus:approovResult.status]];
                NSError *error = [ApproovService createErrorWithCode:approovResult.status userMessage:@"Permanent error"
                    ApproovSDKError:[ApproovService stringFromApproovTokenFetchStatus:approovResult.status]
                    ApproovSDKRejectionReasons:nil ApproovSDKARC:nil canRetry:NO];
                returnData.error = error;
                break;
            }
        }
    }//for loop
    // Add the modified request to the return data
    returnData.request = newRequest;
    return returnData;
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


@end
