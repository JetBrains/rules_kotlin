// The XCTest case of a kt_native_xctest_library: XCTest finds it in the test bundle and runs it,
// and it runs the Kotlin tests of the library in the process of the test.
//
// A template: the rule appends a suffix for its target to the name of the class and to the name of
// the function, so that a test bundle links the test cases of several libraries.

#import <XCTest/XCTest.h>

// XCTestLauncher.kt, compiled with the Kotlin tests.
extern int rules_kotlin_xctest_run(void);

@interface KotlinNativeTests : XCTestCase
@end

@implementation KotlinNativeTests

- (void)testKotlin {
  XCTAssertEqual(rules_kotlin_xctest_run(), 0,
                 @"Kotlin tests failed: see the output of the Kotlin test runner above");
}

@end
