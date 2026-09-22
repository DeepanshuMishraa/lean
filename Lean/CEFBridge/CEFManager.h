#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Process-wide CEF lifecycle. All methods are safe to call from the main
/// thread. Compiled-in support (`isSupported`) only means the headers were
/// present at build time; the framework must also be bundled at runtime
/// (see `CEFIntegration.isAvailable()` in BrowserEngine.swift).
@interface CEFManager : NSObject

/// YES when built with CEF headers (vendor/cef present at compile time).
+ (BOOL)isSupported;

/// Human-readable engine version, e.g. "152.0.8 (Chromium 152.0.7977.134)".
+ (NSString *)cefVersion;

/// YES after a successful initialize that has not been shut down.
+ (BOOL)isInitialized;

/// Starts the CEF browser process. Must be called once on the main thread
/// before any browser is created. Throws (NSError) when headers are missing,
/// the framework cannot load, or CefInitialize fails.
+ (BOOL)initializeWithCachePath:(NSString *)cachePath
                 subprocessPath:(NSString *)subprocessPath
                  resourcesPath:(NSString *)resourcesPath
                 mainBundlePath:(NSString *)mainBundlePath
                        logPath:(NSString *)logPath
                          error:(NSError **)error;

/// Starts the single-threaded message pump (60Hz timer driving
/// CefDoMessageLoopWork on the main thread). Required: Lean runs CEF with
/// multi_threaded_message_loop=false (the MT loop fails under App Sandbox).
+ (void)startMessagePump;

/// Keeps Chromium painting while AppKit runs the live-resize tracking loop.
/// Scoped to live resize so ordinary click tracking stays non-reentrant.
+ (void)beginLiveResizeMessagePump;
+ (void)endLiveResizeMessagePump;

/// Stops the message pump. Call at termination; do NOT follow with shutdown
/// while browsers may still be alive (v1: process exit reaps the rest).
+ (void)stopMessagePump;

/// Shuts CEF down. Call once at termination, on the main thread, after all
/// browsers are closed.
+ (void)shutdown;

@end

NS_ASSUME_NONNULL_END
