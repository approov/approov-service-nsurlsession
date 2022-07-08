
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

#import "ApproovPinningURLSessionDelegate.h"
#import "ApproovService.h"
#import <CommonCrypto/CommonCrypto.h>

// Declare state to be held on the pinning session delegate instance
@interface ApproovPinningURLSessionDelegate()

// optional further delegate to be called
@property id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate> optionalURLDelegate;

// Subject public key info (SPKI) headers for public keys' type and size. Only RSA-2048, RSA-4096, EC-256 and EC-384 are supported.
@property NSDictionary<NSString *, NSDictionary<NSNumber *, NSData *> *> *spkiHeaders;

@end

// ApproovPinningURLSessionDelegate provides a delegate for applying the dynamic pins provided by Approov
@implementation ApproovPinningURLSessionDelegate

// tag for logging
static const NSString *TAG = @"ApproovService";

/**
 * Initialize the SPKI header constants.
 */
- (void)initializeSPKI {
    const unsigned char rsa2048SPKIHeader[] = {
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
        0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    };
    const unsigned char rsa4096SPKIHeader[] = {
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05,
        0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    };
    const unsigned char ecdsaSecp256r1SPKIHeader[] = {
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48,
        0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    };
    const unsigned char ecdsaSecp384r1SPKIHeader[] = {
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04,
        0x00, 0x22, 0x03, 0x62, 0x00
    };
    self.spkiHeaders = @{
        (NSString *)kSecAttrKeyTypeRSA : @{
              @2048 : [NSData dataWithBytes:rsa2048SPKIHeader length:sizeof(rsa2048SPKIHeader)],
              @4096 : [NSData dataWithBytes:rsa4096SPKIHeader length:sizeof(rsa4096SPKIHeader)]
        },
        (NSString *)kSecAttrKeyTypeECSECPrimeRandom : @{
              @256 : [NSData dataWithBytes:ecdsaSecp256r1SPKIHeader length:sizeof(ecdsaSecp256r1SPKIHeader)],
              @384 : [NSData dataWithBytes:ecdsaSecp384r1SPKIHeader length:sizeof(ecdsaSecp384r1SPKIHeader)]
        }
    };
}

/**
 * Constructs a new ApproovPinningURLSessionDelegate with the given optional delegate.
 *
 * @param delegate is an optional further delegate to be used, nor nil otherwise
 */
- (instancetype)initWithDelegate:(id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>)delegate {
    if ([super init]) {
        if (self.spkiHeaders == nil) {
            [self initializeSPKI];
        }
        self.optionalURLDelegate = delegate;
        return self;
    }
    return nil;
}

/**
 *  Tells the URL session that the session has been invalidated
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1407776-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    [self.optionalURLDelegate URLSession:session didBecomeInvalidWithError:error];
}

/**
 *  Tells the delegate that all messages enqueued for a session have been delivered
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1617185-urlsessiondidfinisheventsforback?language=objc
 */
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    [self.optionalURLDelegate URLSessionDidFinishEventsForBackgroundURLSession:session];
}

/**
 *  Requests credentials from the delegate in response to a session-level authentication request from the remote server
 *  https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1409308-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        // handle any server trust requests - we don't allow these to be further delegated
        NSError* error;
        SecTrustRef serverTrust = [self shouldAcceptAuthenticationChallenge:challenge error:&error];
        if (error != nil) {
            NSLog(@"%@: pinning check error: %@", TAG, error.localizedDescription);
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        } else if (serverTrust == nil) {
            NSLog(@"%@: pins rejected", TAG);
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        } else {
            NSLog(@"%@: pins accepted", TAG);
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
        }
    } else {
        // other challenges are passed to a delegate if they can be, otherwise passed on for default handling
        if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:didReceiveChallenge:completionHandler:)]) {
            [self.optionalURLDelegate URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
        } else {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
    }
}

/**
 *  Requests credentials from the delegate in response to an authentication request from the remote server
 *  https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411595-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    BOOL respondsToSelector = [self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)];
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    if (respondsToSelector) {
        [self.optionalURLDelegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
    } else if (completionHandler != nil) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [[NSURLCredential alloc]initWithTrust:serverTrust]);
    }
}

/**
 *  Tells the delegate that the task finished transferring data
 *  https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411610-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [self.optionalURLDelegate URLSession:session task:task didCompleteWithError:error];
    }
}

/**
 *  Tells the delegate that the remote server requested an HTTP redirect
 *  https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411626-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]) {
        [self.optionalURLDelegate URLSession:session task:task willPerformHTTPRedirection:response newRequest:request completionHandler:completionHandler];
    }
}

/**
 *  Tells the delegate when a task requires a new request body stream to send to the remote server
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1410001-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
             task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:needNewBodyStream:)]) {
        [self.optionalURLDelegate URLSession:session task:task needNewBodyStream:completionHandler];
    }
}

/**
 *  Periodically informs the delegate of the progress of sending body content to the server
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1408299-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)]) {
        [self.optionalURLDelegate URLSession:session task:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
    }
}

/**
 *  Tells the delegate that a delayed URL session task will now begin loading
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2873415-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willBeginDelayedRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLSessionDelayedRequestDisposition disposition, NSURLRequest *newRequest))completionHandler API_AVAILABLE(ios(11.0)){
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:willBeginDelayedRequest:completionHandler:)]) {
        [self.optionalURLDelegate URLSession:session task:task willBeginDelayedRequest:request completionHandler:completionHandler];
    }
}

/**
 *  Tells the delegate that the session finished collecting metrics for the task
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1643148-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:task:didFinishCollectingMetrics:)]) {
        [self.optionalURLDelegate URLSession:session task:task didFinishCollectingMetrics:metrics];
    }
}

/**
 *  Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load
 *  https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/2908819-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
taskIsWaitingForConnectivity:(NSURLSessionTask *)task API_AVAILABLE(ios(11.0)) {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:taskIsWaitingForConnectivity:)]) {
        [self.optionalURLDelegate URLSession:session taskIsWaitingForConnectivity:task];
    }
}

/**
 *  Tells the delegate that the data task received the initial reply (headers) from the server
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1410027-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
        [self.optionalURLDelegate URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
    }
}

/**
 *  Tells the delegate that the data task was changed to a download task
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1409936-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didBecomeDownloadTask:)]) {
        [self.optionalURLDelegate URLSession:session dataTask:dataTask didBecomeDownloadTask:downloadTask];
    }
}

/**
 *  Tells the delegate that the data task was changed to a stream task
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411648-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeStreamTask:(NSURLSessionStreamTask *)streamTask {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didBecomeStreamTask:)]) {
        [self.optionalURLDelegate URLSession:session dataTask:dataTask didBecomeStreamTask:streamTask];
    }
}

/**
 *  Tells the delegate that the data task has received some of the expected data
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [self.optionalURLDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

/**
 *  Asks the delegate whether the data (or upload) task should store the response in the cache
 *  https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411612-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
         dataTask:(NSURLSessionDataTask *)dataTask
willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:dataTask:willCacheResponse:completionHandler:)]) {
        [self.optionalURLDelegate URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
    }
}

/**
 *  Tells the delegate that a download task has finished downloading
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1411575-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)]) {
        [self.optionalURLDelegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    }
}

/**
 *  Tells the delegate that the download task has resumed downloading
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1408142-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes:)]) {
        [self.optionalURLDelegate URLSession:session downloadTask:downloadTask didResumeAtOffset:fileOffset expectedTotalBytes:expectedTotalBytes];
    }
}

/**
 *  Periodically informs the delegate about the download’s progress
 *  https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/1409408-urlsession?language=objc
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if ([self.optionalURLDelegate respondsToSelector:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)]) {
        [self.optionalURLDelegate URLSession:session downloadTask:downloadTask didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}


// Error codes related to TLS certificate processing
typedef NS_ENUM(NSUInteger, SecCertificateRefError)
{
    NOT_SERVER_TRUST = 1100,
    SERVER_CERTIFICATE_FAILED_VALIDATION,
    SERVER_TRUST_EVALUATION_FAILURE,
    CERTIFICATE_CHAIN_READ_ERROR,
    PUBLIC_KEY_INFORMATION_READ_FAILURE
};

/**
 * Create an error as a result of a pinning issue.
 *
 * @param code is the status code to return
 * @param message is the descriptive error message
 * @return constructed error
 */
+ (NSError *)createErrorWithCode:(NSInteger)code userMessage:(NSString *)message {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc]init];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedDescriptionKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedFailureReasonErrorKey];
    [userInfo setValue:NSLocalizedString(message, nil) forKey:NSLocalizedRecoverySuggestionErrorKey];
    return [[NSError alloc] initWithDomain:@"approov" code:code userInfo:userInfo];
}

/**
 * Gets the subject public key info (SPKI) header depending on a public key's type and size.
 *
 * @param publicKey is the public key being analyzed
 * @return NSData* of the coresponding SPKI header that will be used
 */
- (NSData *)publicKeyInfoHeaderForKey:(SecKeyRef)publicKey {
    CFDictionaryRef publicKeyAttributes = SecKeyCopyAttributes(publicKey);
    NSString *keyType = CFDictionaryGetValue(publicKeyAttributes, kSecAttrKeyType);
    NSNumber *keyLength = CFDictionaryGetValue(publicKeyAttributes, kSecAttrKeySizeInBits);
    NSData *aSPKIHeader = self.spkiHeaders[keyType][keyLength];
    CFRelease(publicKeyAttributes);
    return aSPKIHeader;
}

/**
 * Gets a certificate's Subject Public Key Info (SPKI).
 *
 * @param certificate is the certificate being analyzed
 * @return NSData* of the SPKI certificate information
 */
- (NSData *)publicKeyInfoOfCertificate:(SecCertificateRef)certificate {
    // get the public key from the certificate
    SecKeyRef publicKey = nil;
    if (@available(iOS 12.0, *)) {
        publicKey = SecCertificateCopyKey(certificate);
    } else {
        // fallback on earlier versions
        // from TrustKit https://github.com/datatheorem/TrustKit/blob/master/TrustKit/Pinning/TSKSPKIHashCache.m lines
        // 221-234:
        // Create an X509 trust using the using the certificate
        SecTrustRef trust;
        SecPolicyRef policy = SecPolicyCreateBasicX509();
        SecTrustCreateWithCertificates(certificate, policy, &trust);
        
        // get a public key reference for the certificate from the trust
        SecTrustResultType result;
        SecTrustEvaluate(trust, &result);
        publicKey = SecTrustCopyPublicKey(trust);
        CFRelease(policy);
        CFRelease(trust);
    }
    if (publicKey == nil)
        return nil;
    
    // get the SPKI header depending on the public key's type and size
    NSData *spkiHeader = [self publicKeyInfoHeaderForKey:publicKey];
    if (spkiHeader == nil)
        return nil;
    
    // combine the public key header and the public key data to form the public key info
    CFDataRef publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil);
    if (publicKeyData == nil)
        return nil;
    NSMutableData *returnData = [NSMutableData dataWithData:spkiHeader];
    [returnData appendData:(__bridge NSData * _Nonnull)(publicKeyData)];
    CFRelease(publicKeyData);
    return [NSData dataWithData:returnData];
}

/**
 * Evaluates a URLAuthenticationChallenge deciding if to proceed further.
 *
 * @param challenge NSURLAuthenticationChallenge
 * @param error provides an error generated from the challenge
 * @return SecTrustRef: valid SecTrust if authentication should proceed, nil otherwise
 */
- (SecTrustRef)shouldAcceptAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge error:(NSError **)error {
    // check we have a server trust
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    if (!serverTrust) {
        *error = [ApproovPinningURLSessionDelegate createErrorWithCode:NOT_SERVER_TRUST
            userMessage:@"not a server trust"];
        return nil;
    }
    
    // check the validity of the server cert
    SecTrustResultType result;
    OSStatus status = SecTrustEvaluate(serverTrust, &result);
    if (status != errSecSuccess) {
        *error = [ApproovPinningURLSessionDelegate createErrorWithCode:SERVER_CERTIFICATE_FAILED_VALIDATION
            userMessage:@"server certificate validation failed"];
        return nil;
    } else if ((result != kSecTrustResultUnspecified) && (result != kSecTrustResultProceed)) {
        *error = [ApproovPinningURLSessionDelegate createErrorWithCode:SERVER_TRUST_EVALUATION_FAILURE
            userMessage:@"server trust evaluation failed"];
        return nil;
    }
    
    // get the Approov pins for the host domain
    NSDictionary<NSString *, NSArray<NSString *> *> *approovPins = [ApproovService getPins:@"public-key-sha256"];
    NSString *host = challenge.protectionSpace.host;
    NSArray<NSString *> *pinsForHost = approovPins[host];

    // if there are no pins for the domain (but the host is present) then use any managed trust roots instead
    if ((pinsForHost != nil) && [pinsForHost count] == 0)
        pinsForHost = approovPins[@"*"];

    // if we are not pinning then we consider this level of trust to be acceptable
    if ((pinsForHost == nil) || [pinsForHost count] == 0) {
        NSLog(@"%@: host %@ not pinned", TAG, host);
        return serverTrust;
    }
    
    // iterate over the certificate chain
    int certCountInChain = (int)SecTrustGetCertificateCount(serverTrust);
    int indexCurrentCert = 0;
    while (indexCurrentCert < certCountInChain) {
        // get the certificate at the current chain position
        SecCertificateRef serverCert = SecTrustGetCertificateAtIndex(serverTrust, indexCurrentCert);
        if (serverCert == nil) {
            *error = [ApproovPinningURLSessionDelegate createErrorWithCode:CERTIFICATE_CHAIN_READ_ERROR
                userMessage:@"failed to read certificate from chain"];
            return nil;
        }
        
        // get the subject public key info from the certificate
        NSData *publicKeyInfo = [self publicKeyInfoOfCertificate:serverCert];
        if (publicKeyInfo == nil) {
            *error = [ApproovPinningURLSessionDelegate createErrorWithCode:PUBLIC_KEY_INFORMATION_READ_FAILURE
                userMessage:@"failed reading public key information"];
            return nil;
        }
        
        // compute the SHA-256 hash of the public key info and base64 encode the result
        CC_SHA256_CTX shaCtx;
        CC_SHA256_Init(&shaCtx);
        CC_SHA256_Update(&shaCtx,(void*)[publicKeyInfo bytes],(unsigned)publicKeyInfo.length);
        unsigned char publicKeyHash[CC_SHA256_DIGEST_LENGTH] = {'\0',};
        CC_SHA256_Final(publicKeyHash, &shaCtx);
        NSString *publicKeyHashBase64 = [[NSData dataWithBytes:publicKeyHash length:CC_SHA256_DIGEST_LENGTH] base64EncodedStringWithOptions:0];
        
        // match pins on the receivers host
        for (NSString *pinHashB64 in pinsForHost) {
            if ([pinHashB64 isEqualToString:publicKeyHashBase64]) {
                NSLog(@"%@: %@ matched public key pin %@ from %lu pins", TAG, host, pinHashB64, [pinsForHost count]);
                return serverTrust;
            }
        }
        
        // move to the next certificate in the chain
        indexCurrentCert += 1;
    }
    
    // we return nil if no match in current set of pins and certificate chain seen during TLS handshake
    NSLog(@"%@: pin verification failed for %@ with no match for %lu pins", TAG, host, [pinsForHost count]);
    return nil;
}

@end
