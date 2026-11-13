/*
 * Xcode 27.x iPhoneOS SDKs ship Foundation/NSURL.h and Foundation/Foundation.h
 * importing <Foundation/NSURLHandle.h>, but the header itself is missing from
 * the iOS SDK (it is present in the macOS SDK of the same Xcode). NSURL.h only
 * uses the type as the return value of a deprecated method, so a forward
 * declaration is enough; the class is unavailable on iOS anyway.
 *
 * This directory is on HEADER_SEARCH_PATHS, so both Clang and Swift's
 * ClangImporter resolve <Foundation/NSURLHandle.h> here.
 */
#import <Foundation/NSObject.h>
@class NSURLHandle;
