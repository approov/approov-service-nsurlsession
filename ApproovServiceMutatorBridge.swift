import Approov
import Foundation

@objc public class ApproovServiceMutatorBridge: NSObject {
    @objc public static let shared = ApproovServiceMutatorBridge()

    private let defaultMessageSigner: ApproovDefaultMessageSigning
    public var serviceMutator: ApproovServiceMutator
    private var useAccountSigning = false
    private var bodyDigestEnabled = true
    private var bodyDigestRequired = false

    private override init() {
        let signer = ApproovDefaultMessageSigning()
        self.defaultMessageSigner = signer
        self.serviceMutator = signer
        super.init()
        configureDefaultMessageSigner()
    }

    @objc public func setUseAccountSigning(_ useAccountSigning: Bool) {
        self.useAccountSigning = useAccountSigning
        configureDefaultMessageSigner()
    }

    @objc public func setBodyDigestRequired(_ bodyDigestRequired: Bool) {
        self.bodyDigestRequired = bodyDigestRequired
        configureDefaultMessageSigner()
    }

    @objc public func setBodyDigestEnabled(_ bodyDigestEnabled: Bool) {
        self.bodyDigestEnabled = bodyDigestEnabled
        configureDefaultMessageSigner()
    }

    @objc public func resetServiceMutator() {
        serviceMutator = defaultMessageSigner
        configureDefaultMessageSigner()
    }

    private func configureDefaultMessageSigner() {
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
        if useAccountSigning {
            _ = factory.setUseAccountMessageSigning()
        } else {
            _ = factory.setUseInstallMessageSigning()
        }
        do {
            if bodyDigestEnabled {
                _ = try factory.setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256,
                                                    required: bodyDigestRequired)
            } else {
                _ = try factory.setBodyDigestConfig(nil, required: false)
            }
        } catch {
            if ApproovService.shouldLog(at: .error) {
                NSLog("[ApproovServiceMutatorBridge] Error configuring body digest: %@", error.localizedDescription)
            }
        }
        _ = defaultMessageSigner.setDefaultFactory(factory)
    }

    private func headerValue(forHTTPHeaderField header: String,
                             in request: URLRequest) -> String? {
        if let value = request.value(forHTTPHeaderField: header) {
            return value
        }
        guard let headers = request.allHTTPHeaderFields else {
            return nil
        }
        for (key, value) in headers where key.caseInsensitiveCompare(header) == .orderedSame {
            return value
        }
        return nil
    }

    @objc public func processRequest(_ request: NSMutableURLRequest, tokenHeader: String?) {
        processRequest(request, tokenHeader: tokenHeader, traceIDHeader: nil)
    }

    @objc public func processRequest(_ request: NSMutableURLRequest, tokenHeader: String?, traceIDHeader: String?) {
        processRequest(request,
                       tokenHeader: tokenHeader,
                       traceIDHeader: traceIDHeader,
                       substitutionHeaders: nil,
                       originalURL: nil,
                       substitutionQueryParams: nil)
    }

    @objc public func processRequest(_ request: NSMutableURLRequest,
                                     tokenHeader: String?,
                                     traceIDHeader: String?,
                                     substitutionHeaders: [String]?,
                                     originalURL: String?,
                                     substitutionQueryParams: [String]?) {
        let urlRequest = request as URLRequest
        let changes = ApproovRequestMutations()
        if let tokenHeader,
           let tokenValue = headerValue(forHTTPHeaderField: tokenHeader, in: urlRequest),
           !tokenValue.isEmpty {
            changes.setTokenHeaderKey(tokenHeader)
        }
        if let traceIDHeader,
           let traceIDValue = headerValue(forHTTPHeaderField: traceIDHeader, in: urlRequest),
           !traceIDValue.isEmpty {
            changes.setTraceIDHeaderKey(traceIDHeader)
        }
        changes.setSubstitutionHeaderKeys(substitutionHeaders ?? [])
        if let originalURL, let substitutionQueryParams {
            changes.setSubstitutionQueryParamResults(originalURL: originalURL,
                                                     substitutionQueryParamKeys: substitutionQueryParams)
        }

        do {
            let processedRequest = try serviceMutator.handleInterceptorProcessedRequest(urlRequest, changes: changes)
            if let url = processedRequest.url {
                request.url = url
            }
            request.cachePolicy = processedRequest.cachePolicy
            request.mainDocumentURL = processedRequest.mainDocumentURL
            request.networkServiceType = processedRequest.networkServiceType
            request.allowsCellularAccess = processedRequest.allowsCellularAccess
            request.httpShouldHandleCookies = processedRequest.httpShouldHandleCookies
            request.httpShouldUsePipelining = processedRequest.httpShouldUsePipelining
            if #available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *) {
                request.allowsExpensiveNetworkAccess = processedRequest.allowsExpensiveNetworkAccess
                request.allowsConstrainedNetworkAccess = processedRequest.allowsConstrainedNetworkAccess
            }
            if let method = processedRequest.httpMethod {
                request.httpMethod = method
            }
            if let bodyData = processedRequest.httpBody {
                request.httpBody = bodyData
            } else if let stream = processedRequest.httpBodyStream {
                request.httpBodyStream = stream
            } else {
                request.httpBody = nil
                request.httpBodyStream = nil
            }
            request.timeoutInterval = processedRequest.timeoutInterval
            request.allHTTPHeaderFields = processedRequest.allHTTPHeaderFields
        } catch {
            if ApproovService.shouldLog(at: .error) {
                NSLog("[ApproovServiceMutatorBridge] Error processing request: %@", error.localizedDescription)
            }
        }
    }

    @objc public func shouldProcessPinningRequest(_ request: NSURLRequest) -> Bool {
        return serviceMutator.handlePinningShouldProcessRequest(request as URLRequest)
    }

    @objc public func handleInterceptorFetchTokenResult(_ result: Any, url: String, errorPointer: NSErrorPointer) -> Bool {
        guard let fetchResult = result as? ApproovTokenFetchResult else {
            if ApproovService.shouldLog(at: .error) {
                NSLog("[ApproovServiceMutatorBridge] Invalid result type passed to handleInterceptorFetchTokenResult")
            }
            return false
        }

        do {
            return try serviceMutator.handleInterceptorFetchTokenResult(fetchResult, url: url)
        } catch {
            if errorPointer != nil {
                errorPointer?.pointee = error as NSError
            }
            return false
        }
    }
}
