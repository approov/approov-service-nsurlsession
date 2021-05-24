# Approov Service for NSURLSession 

A wrapper for the [Approov SDK](https://github.com/approov/approov-ios-sdk) to enable easy integration when using [`NSURLSession`](https://developer.apple.com/documentation/foundation/nsurlsession) for making the API calls that you wish to protect with Approov. In order to use this you will need a trial or paid [Approov](https://www.approov.io) account.

## Adding ApproovService Dependency
The Approov integration is available via [`cocoapods`](https://cocoapods.org/). This allows inclusion into the project by simply specifying a dependency in the `Podfile` for the app:

```
target 'YourApplication' do
    use_frameworks!
    platform :ios, '10.0'
    pod 'approov-service-nsurlsession', '2.6.1', :source => "https://github.com/approov/approov-service-nsurlsession.git"
    pod 'approov-ios-sdk', '2.6.1', :source => "https://github.com/approov/approov-ios-sdk.git"
end
```

This package is actually an open source wrapper layer that allows you to easily use Approov with `NSURLSession`. This has a further dependency to the closed source [Approov SDK](https://github.com/approov/approov-ios-sdk).

## Using the approov service nsurlsession
The `ApproovURLSession` class mimics the interface of the `NSURLSession` class provided by Apple but includes an additional ApproovSDK attestation call. The simplest way to use the `ApproovURLSession` is to find and replace all the `NSURLSession` with `ApproovURLSession`. Additionaly, the Approov SDK needs to be initialized before use. As mentioned above, you will need a paid or trial account for [Approov](https://www.approov.io). Using the command line tools:

```
$ approov sdk -getConfigString
```

This will output a configuration string, something like `#123456#K/XPlLtfcwnWkzv99Wj5VmAxo4CrU267J1KlQyoz8Qo=`, that will identify your Approov account. Use this configuration string as an additional parameter when initializing the `ApproovURLSession`, like so:

```ObjectiveC
ApproovURLSession* defaultSession = [ApproovURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration configString: @"#123456#K/XPlLtfcwnWkzv99Wj5VmAxo4CrU267J1KlQyoz8Qo="];
```

## Bitcode Support
It is possible to use bitcode enabled Approov SDK by providing a slightly different `Podfile` in your test app:

```
target 'YourApplication' do
    use_frameworks!
    platform :ios, '10.0'
    pod 'approov-service-nsurlsession', '2.6.1-bitcode', :source => "https://github.com/approov/approov-service-nsurlsession.git"
    pod 'approov-ios-sdk-bitcode', '2.6.1', :source => "https://github.com/approov/approov-ios-sdk-bitcode.git"
end
```

Note the changes in the `tag` name of the approov service and also the use of a different repository for the Approov SDK. The wrapper code is the same for both native and bitcode versions of the Approov SDK, only the pod dependency changes. 
Please, also remember to use the `-bitcode` flag when using the Approov [admin tools](https://www.approov.io/docs/latest/approov-installation/#approov-tool) to register your application with the Approov service.

## Discovery Mode

If you are performing a quick assessment of the environments that you app is running in, and also if there are any requests being made that are not emanating from your apps, then you can use discovery mode. This is a minimal implementation of Approov that doesn't automatically check Approov tokens at the backend. Requesting the Approov tokens in your apps gathers metrics. Once you have pushed the version of the app using Approov to all of your users you can do an informal check using logs of your backend requests to see if there are any requests that are not presenting an Approov token.

Setting up Approov to work in this way is extremely simple. You must enabled the wildcard option on your account as follows:

```
approov api -setWildcardMode on
```

This ensures that Approov will provide an Approov token for every API request being made, without having to specifically add API domains. The Approov token will be added as an `Approov-Token` header for all requests that are made via an `ApproovURLSession`.

These Approov tokens will not be valid are are simply provided to assess if they are reaching your backend API or not. Since they are not valid they do not need to be protected via pinning and thus none is applied by Approov. Furthermore, if you are only performing discovery you do not need to register your apps.

It is possible to see the properties of all of your running apps using [metrics graphs](https://approov.io/docs/latest/approov-usage-documentation/#metrics-graphs). You can also [assess the validity](https://approov.io/docs/latest/approov-usage-documentation/#checking-token-validity) of individual Approov tokens if required.

Remember to [switch](https://approov.io/docs/latest/approov-usage-documentation/#setting-wildcard-mode) to `off` again before completing a full Approov integration.

## Approov Token Header
The default header name of `Approov-Token` can be changed by invoking the class method `setApproovTokenHeader` like so:

```ObjectiveC
[[ApproovSDK sharedInstance] setApproovTokenHeader:@"Authorization"];
```

You may also prefix the actual value bound to the above token header by using `setApproovTokenPrefix`:
```ObjectiveC
[[ApproovSDK sharedInstance] setApproovTokenPrefix:@"Bearer "];
```

This will result in the Approov JWT token being appended to the `Bearer ` value of the `Authorization` header allowing your back end solution to reuse any code relying in `Authorization` header.


## Token Binding
If you are using [Token Binding](https://approov.io/docs/latest/approov-usage-documentation/#token-binding) then set the header holding the value to be used for binding as follows:

```ObjectiveC
[[ApproovSDK sharedInstance] setBindHeader: @"Authorization"]
```

The Approov SDK allows any string value to be bound to a particular token by computing its SHA256 hash and placing its base64 encoded value inside the pay claim of the JWT token. The method `setBindHeader` takes the name of the header holding the value to be bound. This only needs to be called once but the header needs to be present on all API requests using Approov. It is also crucial to use `setBindHeader` before any token fetch occurs, like token prefetching being enabled, since setting the value to be bound invalidates any (pre)fetched token.

## Token Prefetching
If you wish to reduce the latency associated with fetching the first Approov token, then a call to `[ApproovSDK prefetchApproovToken]` can be made immediately after initialization of the Approov SDK (this happens automatically during ApproovURLSession construction0). This initiates the process of fetching an Approov token as a background task, so that a cached token is available immediately when subsequently needed, or at least the fetch time is reduced. Note that if this feature is being used with [Token Binding](https://approov.io/docs/latest/approov-usage-documentation/#token-binding) then the binding must be set prior to the prefetch, as changes to the binding invalidate any cached Approov token.

## Configuration Persistence
An Approov app automatically downloads any new configurations of APIs and their pins that are available. These are stored in the [`UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults) for the app in a preference key `approov-dynamic`. You can store the preferences differently by modifying or overriding the methods `storeDynamicConfig` and `readDynamicApproovConfig` in `ApproovURLSession.m`.

