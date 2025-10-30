//
//  APIConfiguration.swift
//  GuideLight v3
//
//  Secure API key management for OpenAI integration
//

import Foundation

struct APIConfiguration {
    
    // MARK: - OpenAI Configuration
    
    /// Get OpenAI API key from secure storage
    static func getOpenAIApiKey() -> String {
        // Method 1: From Info.plist (RECOMMENDED)
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "OpenAI_API_Key") as? String,
           !apiKey.isEmpty {
            print("🔑 SUCCESS: OpenAI API key found.")
            return apiKey
        }
        // Fallback - should not be used in production
        print("⚠️ WARNING: No OpenAI API key found. Please configure API key.")
        return ""
    }
    
    /// Check if OpenAI integration is available
    static var isOpenAIAvailable: Bool {
        return !getOpenAIApiKey().isEmpty
    }
    
    /// Validate API key format
    static func validateOpenAIKey(_ key: String) -> Bool {
        // OpenAI keys start with "sk-" and are typically 51 characters
        return key.hasPrefix("sk-") && key.count >= 40
    }
}

// MARK: - Setup Instructions

/*
 ═══════════════════════════════════════════════════════════════════════════════
 📋 SETUP INSTRUCTIONS FOR OPENAI INTEGRATION
 ═══════════════════════════════════════════════════════════════════════════════

 🔑 STEP 1: GET OPENAI API KEY
 ────────────────────────────────────────────────────────────────────────────────
 1. Go to: https://platform.openai.com/api-keys
 2. Sign in or create an OpenAI account
 3. Click "Create new secret key"
 4. Copy the key (starts with "sk-...")
 5. IMPORTANT: Store it securely - you won't see it again!

 💳 STEP 2: ADD BILLING (Required)
 ────────────────────────────────────────────────────────────────────────────────
 1. Go to: https://platform.openai.com/account/billing
 2. Add a payment method
 3. Set usage limits (recommended: $5-10/month)
 
 💰 Cost estimate for this app:
    - GPT-3.5-turbo: $0.0015 per 1K tokens
    - Average description: ~50 tokens
    - Cost per announcement: ~$0.000075
    - 1000 announcements ≈ $0.075 (7.5 cents)

 🔧 STEP 3: CONFIGURE API KEY IN YOUR APP
 ────────────────────────────────────────────────────────────────────────────────
 
 Option A: Info.plist (RECOMMENDED for production)
 1. Open Info.plist in Xcode
 2. Add new key: "OpenAI_API_Key"
 3. Set value to your API key
 4. Add Info.plist to .gitignore to keep key secure
 
 Option B: UserDefaults (for development/testing)
 1. In your app's settings or debug menu:
    UserDefaults.standard.set("your-api-key-here", forKey: "openai_api_key")
 
 Option C: Environment Variables (for debugging)
 1. In Xcode scheme settings, add environment variable:
    Name: OPENAI_API_KEY
    Value: your-api-key-here

 📱 STEP 4: UPDATE NAVIGATIONVIEWMODEL
 ────────────────────────────────────────────────────────────────────────────────
 Replace the getOpenAIApiKey() method in NavigationViewModel with:
 
 ```swift
 private func getOpenAIApiKey() -> String {
     return APIConfiguration.getOpenAIApiKey()
 }
 ```

 🧪 STEP 5: TEST THE INTEGRATION
 ────────────────────────────────────────────────────────────────────────────────
 1. Build and run your app
 2. Complete calibration
 3. Check console for "🗣️ AI Location announcement:" logs
 4. If you see "⚠️ AI description failed", check your API key and internet connection

 🔒 SECURITY BEST PRACTICES
 ────────────────────────────────────────────────────────────────────────────────
 ✅ DO:
 - Store API key in Info.plist
 - Add Info.plist to .gitignore
 - Use different keys for development/production
 - Set usage limits in OpenAI dashboard
 - Monitor API usage regularly

 ❌ DON'T:
 - Hardcode API keys in source code
 - Commit API keys to version control
 - Share API keys in public repositories
 - Use production keys in development

 🚨 IF API KEY IS COMPROMISED:
 1. Immediately revoke the key in OpenAI dashboard
 2. Generate a new key
 3. Update your app configuration
 4. Review usage logs for suspicious activity

 ═══════════════════════════════════════════════════════════════════════════════
*/

// MARK: - Development Helpers

#if DEBUG
extension APIConfiguration {
    
    /// Set API key for development/testing
    static func setDevelopmentAPIKey(_ key: String) {
        guard validateOpenAIKey(key) else {
            print("⚠️ Invalid API key format")
            return
        }
        UserDefaults.standard.set(key, forKey: "openai_api_key")
        print("✅ Development API key configured")
    }
    
    /// Clear stored API key
    static func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: "openai_api_key")
        print("🗑️ API key cleared")
    }
    
    /// Test API key availability
    static func testAPIKeySetup() {
        let key = getOpenAIApiKey()
        if key.isEmpty {
            print("❌ No API key found")
        } else if validateOpenAIKey(key) {
            print("✅ Valid API key configured (length: \(key.count))")
        } else {
            print("⚠️ API key found but format seems invalid")
        }
    }
}
#endif
