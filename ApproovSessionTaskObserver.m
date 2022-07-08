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

#import "ApproovSessionTaskObserver.h"
#import "ApproovService.h"

@implementation ApproovSessionTaskObserver

// tag for logging
static const NSString *TAG = @"ApproovService";

// the map holding the session tasks to their session configurations
static NSMutableDictionary<NSString *, NSURLSessionConfiguration *> *tasksSessionConfig;

// the map holding the completion handler for the session task
static NSMutableDictionary<NSString *, CompletionHandlerType> *tasksCompletionHandler;

// dispatch queue used for updating the actual requests with Approov protection - this needs
// to be done asynchronously since we cannot perform this network blocking action in the same thread
// as the caller that calls task resume
static dispatch_queue_t updateRequestQueue;

/**
 * Initializes a new ApproovSessionTaskObserver.
 */
-(instancetype)init {
    if ([super init]) {
        tasksSessionConfig = [[NSMutableDictionary alloc]init];
        tasksCompletionHandler = [[NSMutableDictionary alloc]init];
        dispatch_queue_attr_t queueAttrs =
                    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, -1);
        updateRequestQueue = dispatch_queue_create("Approov Update Request", queueAttrs);
        return self;
    }
    return nil;
}

/**
 * Obtains an ID for the task that can be used consistently in logging. These uses a combination of both the task identifier and the address of the object, as there
 * appears to be a chance that different tasks can be assigned the same identifier, see:
 *   https://stackoverflow.com/questions/22054823/non-unique-nsurlsessiondatatask-taskidentifiers
 * We rely on the fact that ARC does not relocate objects so the address should be constant once allocated.
 *
 * @param sessionTask is the task whose ID is to be obtained
 * @return the idnetifier for the task
 */
- (NSString *)sessionTaskID:(NSURLSessionTask *)sessionTask {
    return [NSString stringWithFormat:@"#%lu:%08lx",
            (unsigned long)sessionTask.taskIdentifier, (unsigned long)sessionTask];
}

/**
 * Adds completion handler information about a new session task. This allows the completion handler to be called if the task must be cancelled
 * after the Approov protection step before the main task is resumed.
 *
 * @param sessionTask is the session task being added
 * @param sessionConfig is the session configuration being used
 * @param completionHandler is the completion handler to be called if the task is cancelled, or nil if not required
 */
- (void)addWithTask:(NSURLSessionTask *)sessionTask sessionConfig:(NSURLSessionConfiguration *)sessionConfig
    completionHandler:(CompletionHandlerType)completionHandler {
    NSString *key = [self sessionTaskID:sessionTask];
    @synchronized(tasksSessionConfig) {
        [tasksSessionConfig setValue:sessionConfig forKey:key];
    }
    @synchronized(tasksCompletionHandler) {
        [tasksCompletionHandler setValue:completionHandler forKey:key];
    }
}

/**
  * Should be called if a resume is being attempted on the session task and determines if it should be executed or not. The first time an Approov
  * protected task resume call is made the actual resume not executed, but is used as an indicator that the Approov protection should be added. The
  * task can then be resumed with an Approov protected request in place. The resume will then be executed.
  *
  * @param sessionTask is the session task being resumed
  * @return YES if the task resume should be called, or NO otherwise
  */
- (BOOL)shouldExecuteTaskResume:(NSURLSessionTask *)sessionTask {
    // get the task state and clear it since we only require it for the initial resume
    NSString *taskID = [self sessionTaskID:sessionTask];
    NSURLSessionConfiguration *sessionConfig = nil;
    @synchronized(tasksSessionConfig) {
        sessionConfig = [tasksSessionConfig objectForKey:taskID];
        [tasksSessionConfig removeObjectForKey:taskID];
    }
    CompletionHandlerType completionHandler = nil;
    @synchronized(tasksCompletionHandler) {
        completionHandler = [tasksCompletionHandler objectForKey:taskID];
        [tasksCompletionHandler removeObjectForKey:taskID];
    }

    // determine if the actual resume should proceed or not
    if (sessionConfig != nil) {
        // we have a session task that requires Approov protection but adding Approov protection may require network
        // access and we cannot execute it in the context of the caller of this function because that is the main
        // Javascript thread which we cannot block, so we perform this on an asynchronous background thread
        dispatch_async(updateRequestQueue, ^{
            // update the request with Approov
            NSError *error = nil;
            NSURLRequest *newRequest = [ApproovService updateRequestWithApproov:sessionTask.currentRequest
                                                                  sessionConfig:sessionConfig error:&error];
             
            // handle the result from the request update
            if (error != nil) {
                 // we got an error so provide it to any completion handler or cancel the task
                 if (completionHandler != nil)
                     completionHandler(nil, nil, error);
                 else
                     [sessionTask cancel];
                 NSLog(@"%@: session task %@ cancelled due to error", TAG, taskID);
            }
            else if ([sessionTask state] == NSURLSessionTaskStateSuspended) {
                 // the update was successful so now we need to update the original request, if the task
                 // is still in its expected suspended state, by calling the function to update the request
                 // by its hook (since it is not normally accessible) - this allows an update before the
                 // network request itself has been processed
                 SEL selector = NSSelectorFromString(@"updateCurrentRequest:");
                 if ([sessionTask respondsToSelector:selector]) {
                     IMP imp = [sessionTask methodForSelector:selector];
                     void (*func)(id, SEL, NSURLRequest*) = (void *)imp;
                     func(sessionTask, selector, newRequest);
                 }
                 else {
                     // this means that NSURLRequest has removed the `updateCurrentRequest` method or we are observing an object that
                     // is not an instance of NSURLRequest
                     NSLog(@"%@: unable to modify NSURLRequest, object instance is of type %@", TAG, NSStringFromClass([sessionTask class]));
                 }
                 
                 // the task can now be resumed with the updated request
                 NSLog(@"%@: session task %@ request update completed", TAG, taskID);
                 [sessionTask resume];
            }
            else
                 NSLog(@"%@: session task %@ in unexpected state after request update", TAG, taskID);
        });
        
        // we have initiated the background thread and don't pass on the resume
        NSLog(@"%@: session task %@ resume intercepted", TAG, taskID);
        return NO;
    }
    
    // if we don't know about the task then we just pass on the resume
    return YES;
}

@end
