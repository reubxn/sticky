//
//  AppBundleConfiguration.swift
//  leanring-buddy
//
//  Shared helper for reading runtime configuration from the built app bundle,
//  with a fallback to a local secrets.plist in Application Support so API keys
//  can stay out of git and out of the shipped binary during development.
//

import Foundation

enum AppBundleConfiguration {
    static func stringValue(forKey key: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        if let resourceInfoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let resourceInfo = NSDictionary(contentsOfFile: resourceInfoPath),
           let value = resourceInfo[key] as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        // Application Support fallback — keys live outside the repo and
        // outside the app bundle, so they never get committed or shipped.
        if let value = applicationSupportSecrets()?[key] as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        return nil
    }

    private static func applicationSupportSecrets() -> NSDictionary? {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let secretsFileURL = applicationSupportDirectory
            .appendingPathComponent("com.learning-buddy.clicky", isDirectory: true)
            .appendingPathComponent("secrets.plist")

        return NSDictionary(contentsOf: secretsFileURL)
    }
}
