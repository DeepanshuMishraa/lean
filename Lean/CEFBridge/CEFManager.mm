#import "CEFManager.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#if __has_include("include/cef_app.h")
#define LEAN_HAS_CEF 1
#include <crt_externs.h>
#include <memory>
#include "include/cef_app.h"
#include "include/cef_version.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_library_loader.h"

namespace {
// CEF's nested event pump (inside CefDoMessageLoopWork) calls the private
// AppKit method -[NSApplication isHandlingSendEvent] to decide whether it
// may dispatch events directly. That method no longer exists on macOS 27 —
// and never did on SwiftUI's AppKitApplication subclass — so the first
// nested pump kills the app with "unrecognized selector". Provide it when
// absent. NO matches the real implementation's common-case value (not
// inside -sendEvent:) and tells CEF direct dispatch is safe.
BOOL LeanIsHandlingSendEvent(id, SEL) { return NO; }

void LeanInstallEventPumpShim(void) {
  SEL sel = @selector(isHandlingSendEvent);
  if (![[NSApplication class] instancesRespondToSelector:sel]) {
    class_addMethod([NSApplication class], sel,
                    (IMP)LeanIsHandlingSendEvent, "c@:");
  }
}
class LeanCefApp : public CefApp, public CefBrowserProcessHandler {
 public:
  LeanCefApp() = default;

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  void OnBeforeChildProcessLaunch(
      CefRefPtr<CefCommandLine> command_line) override {
    if (getenv("LEAN_CEF_DEBUG") != nullptr) {
      NSLog(@"CEF child launch: %s",
            command_line->GetCommandLineString().ToString().c_str());
    }
  }

  void OnBeforeCommandLineProcessing(
      const CefString &process_type,
      CefRefPtr<CefCommandLine> command_line) override {
    if (process_type.empty()) {
      // The GPU process cannot nest Chromium's sandbox inside Lean's App
      // Sandbox; run it without the inner sandbox (it still inherits ours).
      command_line->AppendSwitch("disable-gpu-sandbox");
#if DEBUG
      // Debug only: DevTools + CDP screenshot harness (scripts/cef-shot.sh).
      // Never ship open (no auth on the port).
      command_line->AppendSwitchWithValue("remote-debugging-port", "9222");
      command_line->AppendSwitchWithValue("remote-allow-origins", "*");
      if (getenv("LEAN_CEF_DEBUG") != nullptr) {
        command_line->AppendSwitch("enable-logging");
        command_line->AppendSwitchWithValue("v", "1");
      }
#endif
    }
  }

 private:
  IMPLEMENT_REFCOUNTING(LeanCefApp);
};
}  // namespace
#endif

static NSString *const LEAN_CEF_ERROR_DOMAIN = @"com.dipxsy.lean.cef";

@implementation CEFManager {
}

static BOOL gCEFInitialized = NO;

+ (BOOL)isSupported {
#if LEAN_HAS_CEF
  return YES;
#else
  return NO;
#endif
}

+ (NSString *)cefVersion {
#if LEAN_HAS_CEF
  return [NSString stringWithFormat:@"%d.%d.%d (Chromium %d.%d.%d.%d)",
          CEF_VERSION_MAJOR, CEF_VERSION_MINOR, CEF_VERSION_PATCH,
          CHROME_VERSION_MAJOR, CHROME_VERSION_MINOR,
          CHROME_VERSION_BUILD, CHROME_VERSION_PATCH];
#else
  return @"unavailable";
#endif
}

+ (BOOL)isInitialized {
  return gCEFInitialized;
}

+ (BOOL)initializeWithCachePath:(NSString *)cachePath
                 subprocessPath:(NSString *)subprocessPath
                  resourcesPath:(NSString *)resourcesPath
                 mainBundlePath:(NSString *)mainBundlePath
                        logPath:(NSString *)logPath
                          error:(NSError **)error {
#if LEAN_HAS_CEF
  if (gCEFInitialized) {
    return YES;
  }
  LeanInstallEventPumpShim();
  // All wrapper calls route through function pointers that are only filled
  // by loading the framework explicitly. Without this, the first CefString
  // assignment jumps to NULL. The loader is intentionally leaked: its
  // destructor would unload the library at process exit.
  static std::unique_ptr<CefScopedLibraryLoader> gLoader;
  if (!gLoader) {
    gLoader.reset(new CefScopedLibraryLoader);
  }
  if (!gLoader->LoadInMain()) {
    if (error) {
      *error = [NSError errorWithDomain:LEAN_CEF_ERROR_DOMAIN
                                   code:3
                               userInfo:@{
                                 NSLocalizedDescriptionKey:
                                   @"Could not load the CEF framework. Check Contents/Frameworks."
                               }];
    }
    return NO;
  }
  if (![[NSFileManager defaultManager] fileExistsAtPath:subprocessPath]) {
    if (error) {
      *error = [NSError errorWithDomain:LEAN_CEF_ERROR_DOMAIN
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey:
                                   @"CEF helper executable not found. Build the Lean Helper target."
                               }];
    }
    return NO;
  }

  int argc = *_NSGetArgc();
  char **argv = *_NSGetArgv();
  CefMainArgs args(argc, argv);

  CefRefPtr<LeanCefApp> app(new LeanCefApp);
  // Run subprocess logic if this IS a subprocess (browser process: -1, continue).
  // Mirrors cefclient main(): must precede CefInitialize.
  if (CefExecuteProcess(args, app.get(), nullptr) >= 0) {
    return YES;
  }

  CefSettings settings;
  settings.size = sizeof(settings);
  // Lean itself is App-Sandboxed; Chromium's sandbox cannot nest inside it.
  // Renderers inherit the app sandbox instead (same model as sandboxed Electron apps).
  settings.no_sandbox = true;
  // Single-threaded loop with an external pump (see startMessagePump).
  // multi_threaded_message_loop=true fails to init under App Sandbox.
  settings.multi_threaded_message_loop = false;
  settings.log_severity = getenv("LEAN_CEF_DEBUG") != nullptr
      ? LOGSEVERITY_INFO
      : LOGSEVERITY_WARNING;
  CefString(&settings.cache_path) = [cachePath UTF8String];
  CefString(&settings.root_cache_path) = [cachePath UTF8String];
  CefString(&settings.browser_subprocess_path) = [subprocessPath UTF8String];
  CefString(&settings.resources_dir_path) = [resourcesPath UTF8String];
  CefString(&settings.main_bundle_path) = [mainBundlePath UTF8String];
  CefString(&settings.log_file) = [logPath UTF8String];

  if (!CefInitialize(args, settings, app.get(), nullptr)) {
    if (error) {
      *error = [NSError errorWithDomain:LEAN_CEF_ERROR_DOMAIN
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"CefInitialize failed."
                               }];
    }
    return NO;
  }
  gCEFInitialized = YES;
  return YES;
#else
  if (error) {
    *error = [NSError errorWithDomain:LEAN_CEF_ERROR_DOMAIN
                                 code:0
                             userInfo:@{
                               NSLocalizedDescriptionKey:
                                 @"Built without CEF headers. Run scripts/fetch-cef.sh and rebuild."
                             }];
  }
   return NO;
#endif
}

#if LEAN_HAS_CEF
static NSTimer *gPumpTimer = nil;
#endif

+ (void)startMessagePump {
#if LEAN_HAS_CEF
  if (gPumpTimer) {
    return;
  }
  static BOOL debugPump = NO;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    debugPump = getenv("LEAN_CEF_DEBUG") != nullptr;
  });
  __block uint64_t ticks = 0;
  gPumpTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                               repeats:YES
                                                 block:^(NSTimer *_) {
                                                   ticks++;
                                                   if (debugPump && (ticks % 60) == 0) {
                                                     NSLog(@"CEF pump alive: %llu ticks",
                                                           (unsigned long long)ticks);
                                                   }
                                                   CefDoMessageLoopWork();
                                                 }];
#endif
}

+ (void)stopMessagePump {
#if LEAN_HAS_CEF
  [gPumpTimer invalidate];
  gPumpTimer = nil;
#endif
}

+ (void)shutdown {
#if LEAN_HAS_CEF
  if (gCEFInitialized) {
    CefShutdown();
    gCEFInitialized = NO;
  }
#endif
}

@end
