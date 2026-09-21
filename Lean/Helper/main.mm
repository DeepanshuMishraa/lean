#import <Cocoa/Cocoa.h>

#if __has_include("include/cef_app.h")
#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"
#define LEAN_HAS_CEF 1
#endif

/// Subprocess entry point: every CEF renderer/GPU/plugin process re-enters
/// here via the browser_subprocess_path executable (Lean Helper.app).
int main(int argc, char *argv[]) {
#if LEAN_HAS_CEF
  CefMainArgs main_args(argc, argv);
  @autoreleasepool {
    CefScopedLibraryLoader loader;
    if (!loader.LoadInHelper()) {
      return 1;
    }
    return CefExecuteProcess(main_args, nullptr, nullptr);
  }
#else
  (void)argc;
  (void)argv;
  return 1;
#endif
}
