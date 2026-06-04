/*
 * MIT License
 *
 * Copyright (c) 2016-present, CriticalBlue Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
 * associated documentation files (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge, publish, distribute,
 * sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or
 * substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
 * NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
 * OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <Foundation/Foundation.h>

/// type definition of a completion handler function
typedef void (^CompletionHandlerType)(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error);

NS_ASSUME_NONNULL_BEGIN

/// ApproovSessionTaskObserver is able to observe resume events on SessionDataTask and use that as a trigger to initiate the Approov protection.
/// The initial call to resume is intercepted and not made to allow time for the request to be updated with Approov protection on a different thread
/// so that the calling thread is not blocked. The task is then resumed once the final request is in place. Tasks that need to have Approov protection
/// added must be marked at the point of their creation so that other datta tasks can be passed through without modification.
@interface ApproovSessionTaskObserver: NSObject

/**
 * Initializes a new ApproovSessionTaskObserver.
 */
-(instancetype)init;

/**
 * Obtains an ID for the task that can be used consistently in logging.
 *
 * @param sessionTask is the task whose ID is to be obtained
 * @return the identifier for the task
 */
 - (NSString *)sessionTaskID:(NSURLSessionTask *)sessionTask;

/**
 * Adds completion handler information about a new session task. This allows the completion handler to be called if the task must be cancelled
 * after the Approov protection step before the main task is resumed.
 *
 * @param sessionTask is the session task being added
 * @param sessionConfig is the session configuration being used
 * @param completionHandler is the completion handler to be called if the task is cancelled, or nil if not required
 */
 - (void)addWithTask:(NSURLSessionTask *)sessionTask sessionConfig:(NSURLSessionConfiguration *)sessionConfig
        completionHandler:(CompletionHandlerType)completionHandler;

 /**
  * Should be called if a resume is being attempted on the session task and determines if it should be executed or not. The first time an Approov
  * protected task resume call is made the actual resume not executed, but is used as an indicator that the Approov protection should be added. The
  * task can then be resumed with an Approov protected request in place. The resume will then be executed.
  *
  * @param sessionTask is the session task being resumed
  * @return YES if the task resume should be called, or NO otherwise
  */
- (BOOL)shouldExecuteTaskResume:(NSURLSessionTask *)sessionTask;

@end

NS_ASSUME_NONNULL_END
