//
//  ApproovService.h
//  ApproovShapes
//
//  Created by ivo liondov on 28/04/2022.
//  Copyright © 2022 ivo liondov. All rights reserved.
//

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
@end

#endif /* ApproovService_h */
