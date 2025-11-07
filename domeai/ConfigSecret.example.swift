//
//  ConfigSecret.example.swift
//  domeai
//
//  Copy this file to ConfigSecret.swift (which is git-ignored) and fill in
//  the secrets for your local environment.
//

import Foundation

struct ConfigSecret {
    /// Application token used to authenticate requests to the Vercel relay.
    /// Copy this file to `ConfigSecret.swift` and replace the value below with
    /// the APP_TOKEN configured in your Vercel project. DO NOT commit the real token.
    static let appToken = ""
}

