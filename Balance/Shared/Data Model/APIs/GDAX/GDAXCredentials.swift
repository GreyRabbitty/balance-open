//
//  Credentials.swift
//  BalanceOpen
//
//  Created by Red Davis on 27/07/2017.
//  Copyright © 2017 Balanced Software, Inc. All rights reserved.
//

import Foundation

internal extension GDAXAPIClient
{
    internal struct Credentials: APICredentials
    {
        // Internal
        internal let components: APICredentialsComponents
        internal let hmacAlgorithm = CCHmacAlgorithm(kCCHmacAlgSHA256)
        internal let hmacAlgorithmDigestLength = Int(CC_SHA256_DIGEST_LENGTH)
        
        // Private
        private let secretKeyData: Data
        
        // MARK: Initialization
        
        internal init(key: String, secret: String, passphrase: String) throws
        {
            let components = try APICredentialsComponents(key: key, secret: secret, passphrase: passphrase)
            try self.init(component: components)
        }
        
        internal init(component: APICredentialsComponents) throws
        {
            guard let decodedSecretData = Data(base64Encoded: component.secret) else
            {
                throw APICredentialsComponents.Error.invalidSecret(message: "Secret is not base64 encoded")
            }
            
            self.secretKeyData = decodedSecretData
            self.components = component
        }
        
        internal init(identifier: String) throws
        {
            // :( Unable to use the namespacing function (self.namespacedKeychainIdentifier())
            // as we can't call self before intialization, making this brital.
            // There are tests to catch this being an issue though.
            let namespacedIdentifier = "com.GDAXAPIClient.Credentials.\(identifier)"
            var components = try? APICredentialsComponents(identifier: namespacedIdentifier)
            if components == nil {
                let oldNamespacedIdentifier = "com.GDAXAPIClient.Credentials.main"
                components = try? APICredentialsComponents(identifier: oldNamespacedIdentifier)
                //one time run if the fetching of the old credentials succeeds to delete old ones
                keychain[oldNamespacedIdentifier, "key"] = nil
                keychain[oldNamespacedIdentifier, "secret"] = nil
                keychain[oldNamespacedIdentifier, "passphrase"] = nil
            }
            guard let unwrapedComponents = components else {
                throw APICredentialsComponents.Error.dataNotFound(identifier: identifier)
            }
            try self.init(component: unwrapedComponents)
        }
        
        // MARK: Signature
        
        internal func generateSignature(timestamp: Date, requestPath: String, body: Data?, method: String) throws -> String
        {
            // Turn body into JSON string
            let bodyString: String
            if let unwrappedBody = body,
               let dataString = String(data: unwrappedBody, encoding: .utf8)
            {
                bodyString = dataString
            }
            else
            {
                bodyString = ""
            }

            // Message
            let message = "\(timestamp.timeIntervalSince1970)\(method)\(requestPath)\(bodyString)"
            guard let messageData = message.data(using: .utf8) else {
                throw APICredentialsComponents.Error.standard(message: "Unable to turn message string into Data")
            }
            
            let signatureData = self.createSignatureData(with: messageData, secretKeyData: self.secretKeyData)
            return signatureData.base64EncodedString()
        }
        
        // MARK: Keychain
        
        internal func namespacedKeychainIdentifier(_ identifier: String) -> String
        {
            return "com.GDAXAPIClient.Credentials.\(identifier)"
        }
    }
}
