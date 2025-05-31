//
//  RustTestBridge.swift
//  LocalPeerSync
//
//  Test functions for Rust integration verification and shared types
//

import Foundation

// MARK: - Shared Types

/// Clipboard content type enum - shared across the app
enum ClipboardContentType: Int32, CaseIterable {
    case text = 0
    case url = 1
    case image = 2
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .image:
            return "Image"
        }
    }
    
    var iconName: String {
        switch self {
        case .text:
            return "doc.text"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }
}

// MARK: - Test Helper Functions

struct RustTester {
    
    /// Test the basic Rust integration
    static func testIntegration() {
        print("🧪 Testing Rust integration...")
        
        // Test 1: Simple integer return
        testIntegerFunction()
        
        // Test 2: String return and memory management
        testStringFunction()
        
        print("🧪 Rust integration tests completed!")
    }
    
    /// Test integer function
    private static func testIntegerFunction() {
        print("🧪 Testing integer function...")
        
        let result = rust_test_connection()
        print("🧪 Rust test result: \(result)")
        
        if result == 42 {
            print("✅ Rust integer test PASSED!")
        } else {
            print("❌ Rust integer test FAILED! Expected 42, got \(result)")
        }
    }
    
    /// Test string function and memory management
    private static func testStringFunction() {
        print("🧪 Testing string function...")
        
        if let stringPtr = rust_test_string() {
            let rustString = String(cString: stringPtr)
            print("🧪 Rust string result: '\(rustString)'")
            
            // Free the string - important for memory management
            rust_sync_free_string(stringPtr)
            
            if rustString == "Hello from Rust!" {
                print("✅ Rust string test PASSED!")
            } else {
                print("❌ Rust string test FAILED! Expected 'Hello from Rust!', got '\(rustString)'")
            }
        } else {
            print("❌ Rust string test FAILED! Got null pointer")
        }
    }
    
    /// Test clipboard content type functionality
    static func testClipboardTypes() {
        print("🧪 Testing clipboard content types...")
        
        for contentType in ClipboardContentType.allCases {
            print("📋 Content Type: \(contentType.displayName) (raw: \(contentType.rawValue)) - Icon: \(contentType.iconName)")
        }
        
        print("✅ Clipboard content types test completed!")
    }
    
    /// Comprehensive test suite
    static func runAllTests() {
        print("🚀 Running comprehensive Rust integration tests...")
        print("=" * 50)
        
        testIntegration()
        print("-" * 30)
        testClipboardTypes()
        
        print("=" * 50)
        print("🎉 All tests completed!")
    }
}

// MARK: - String Utilities

private extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// MARK: - Rust Integration Status Helper

struct RustIntegrationStatus {
    
    /// Check if Rust functions are available
    static func checkAvailability() -> IntegrationStatus {
        var status = IntegrationStatus()
        
        // Test integer function
        let intResult = rust_test_connection()
        status.integerFunctionWorking = (intResult == 42)
        
        // Test string function
        if let stringPtr = rust_test_string() {
            let rustString = String(cString: stringPtr)
            rust_sync_free_string(stringPtr)
            status.stringFunctionWorking = (rustString == "Hello from Rust!")
        } else {
            status.stringFunctionWorking = false
        }
        
        return status
    }
    
    /// Print integration status
    static func printStatus() {
        let status = checkAvailability()
        
        print("🔍 Rust Integration Status:")
        print("   Integer Function: \(status.integerFunctionWorking ? "✅ Working" : "❌ Failed")")
        print("   String Function:  \(status.stringFunctionWorking ? "✅ Working" : "❌ Failed")")
        print("   Overall Status:   \(status.isFullyWorking ? "✅ All Good" : "❌ Issues Detected")")
    }
}

// MARK: - Integration Status Structure

struct IntegrationStatus {
    var integerFunctionWorking: Bool = false
    var stringFunctionWorking: Bool = false
    
    var isFullyWorking: Bool {
        return integerFunctionWorking && stringFunctionWorking
    }
    
    var workingFunctionsCount: Int {
        var count = 0
        if integerFunctionWorking { count += 1 }
        if stringFunctionWorking { count += 1 }
        return count
    }
    
    var totalFunctionsCount: Int {
        return 2
    }
    
    var successRate: Double {
        return Double(workingFunctionsCount) / Double(totalFunctionsCount)
    }
    
    var statusDescription: String {
        switch (integerFunctionWorking, stringFunctionWorking) {
        case (true, true):
            return "Fully functional"
        case (true, false):
            return "Integer function working, string function failed"
        case (false, true):
            return "String function working, integer function failed"
        case (false, false):
            return "Both functions failed"
        }
    }
}

// MARK: - Usage Examples and Documentation

/*
 USAGE EXAMPLES:
 
 1. Basic integration test:
    RustTester.testIntegration()
 
 2. Test all functionality:
    RustTester.runAllTests()
 
 3. Check integration status:
    RustIntegrationStatus.printStatus()
 
 4. Use clipboard content types:
    let textType = ClipboardContentType.text
    print("Icon: \(textType.iconName)")
 
 5. Get integration status programmatically:
    let status = RustIntegrationStatus.checkAvailability()
    if status.isFullyWorking {
        print("Ready to use Rust functions!")
    }
*/
