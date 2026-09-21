#import "CEFBrowserHost.h"

#if __has_include("include/cef_app.h")
#define LEAN_HAS_CEF 1
#include <cmath>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_display_handler.h"
#include "include/cef_download_handler.h"
#include "include/cef_frame.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_task.h"

// Internal bookkeeping used by LeanCefClient. A category at global scope
// (not in the public header) because the signatures carry C++ types that
// Swift must never see.
@interface CEFBrowserHost (CEFInternal)
- (int64_t)nextCompletionId;
- (void)storeJSDialogCallback:(CefRefPtr<CefJSDialogCallback>)callback forId:(int64_t)id;
- (void)storeAuthCallback:(CefRefPtr<CefAuthCallback>)callback forId:(int64_t)id;
- (void)storeMediaCallback:(CefRefPtr<CefMediaAccessCallback>)callback
               permissions:(uint32_t)permissions
                     forId:(int64_t)id;
- (NSString *)registerDownload:(uint32_t)cefId
                      callback:(CefRefPtr<CefBeforeDownloadCallback>)callback;
- (nullable NSString *)downloadIdForCefId:(uint32_t)cefId;
- (void)noteDownloadCallback:(CefRefPtr<CefDownloadItemCallback>)callback
                forDownload:(NSString *)downloadId;
- (void)finishDownload:(NSString *)downloadId;
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser;
- (void)browserGone;
@end

namespace {

NSString *NSStringFromCef(const CefString &s) {
  std::string std = s.ToString();
  return [NSString stringWithUTF8String:std.c_str()];
}

NSArray<NSString *> *NSArrayFromCef(const std::vector<CefString> &v) {
  NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:v.size()];
  for (const auto &s : v) {
    [out addObject:NSStringFromCef(s)];
  }
  return out;
}

class ClosureTask : public CefTask {
 public:
  explicit ClosureTask(std::function<void()> fn) : fn_(std::move(fn)) {}
  void Execute() override { fn_(); }

 private:
  std::function<void()> fn_;
  IMPLEMENT_REFCOUNTING(ClosureTask);
};

void PostToUI(std::function<void()> fn) {
  CefPostTask(TID_UI, new ClosureTask(std::move(fn)));
}

void PostToMain(dispatch_block_t block) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

class LeanCefClient : public CefClient,
                      public CefDisplayHandler,
                      public CefLifeSpanHandler,
                      public CefLoadHandler,
                      public CefRequestHandler,
                      public CefJSDialogHandler,
                      public CefPermissionHandler,
                      public CefDownloadHandler {
 public:
  explicit LeanCefClient(CEFBrowserHost *owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }

  // CefDisplayHandler
  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString &title) override {
    NSString *t = NSStringFromCef(title);
    CEFBrowserHost *owner = owner_;
    PostToMain(^{
      if (owner.onTitle) {
        owner.onTitle(t);
      }
    });
  }

  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                       const CefString &url) override {
    if (!frame->IsMain()) {
      return;
    }
    NSString *u = NSStringFromCef(url);
    CEFBrowserHost *owner = owner_;
    PostToMain(^{
      if (owner.onURL) {
        owner.onURL(u);
      }
    });
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool is_loading,
                            bool can_go_back, bool can_go_forward) override {
    CEFBrowserHost *owner = owner_;
    if (getenv("LEAN_CEF_DEBUG") != nullptr) {
      NSLog(@"CEF loading state: loading=%d back=%d fwd=%d", (int)is_loading,
            (int)can_go_back, (int)can_go_forward);
    }
    PostToMain(^{
      if (owner.onLoadingState) {
        owner.onLoadingState(is_loading ? YES : NO, can_go_back ? YES : NO,
                             can_go_forward ? YES : NO);
      }
    });
    (void)browser;
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser>,
                          const std::vector<CefString> &icon_urls) override {
    NSArray<NSString *> *urls = NSArrayFromCef(icon_urls);
    CEFBrowserHost *owner = owner_;
    PostToMain(^{
      if (owner.onFaviconURLs) {
        owner.onFaviconURLs(urls);
      }
    });
  }

  // CefLifeSpanHandler
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEFBrowserHost *owner = owner_;
    if (owner) {
      [owner browserCreated:browser];
    }
    PostToMain(^{
      if (owner.onCreated) {
        owner.onCreated();
      }
    });
  }

  bool DoClose(CefRefPtr<CefBrowser>) override {
    CEFBrowserHost *owner = owner_;
    PostToMain(^{
      if (owner.onClose) {
        owner.onClose();
      }
    });
    return false;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    CEFBrowserHost *owner = owner_;
    if (owner) {
      [owner browserGone];
    }
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
                     int, const CefString &target_url, const CefString &,
                     WindowOpenDisposition, bool,
                     const CefPopupFeatures &, CefWindowInfo &,
                     CefRefPtr<CefClient> &, CefBrowserSettings &,
                     CefRefPtr<CefDictionaryValue> &, bool *) override {
    // v1: cancel the popup window, open its URL as a plain new tab.
    NSString *u = NSStringFromCef(target_url);
    CEFBrowserHost *owner = owner_;
    PostToMain(^{
      if (owner.onPopupURL) {
        owner.onPopupURL(u);
      }
    });
    return true;
  }

  // CefLoadHandler
  void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode, const CefString &error_text,
                   const CefString &failed_url) override {
    if (!frame->IsMain()) {
      return;
    }
    if (getenv("LEAN_CEF_DEBUG") != nullptr) {
      NSLog(@"CEF load error: %@ code=%d text=%@", NSStringFromCef(failed_url),
            (int)errorCode, NSStringFromCef(error_text));
    }
    // ERR_ABORTED is routine (stopped loads, new navigations superseding).
    NSString *url = NSStringFromCef(failed_url);
    NSString *text = NSStringFromCef(error_text);
    CEFBrowserHost *owner = owner_;
    PostToMain(^{
      if (owner.onLoadError) {
        owner.onLoadError(url, text);
      }
    });
  }

  // CefRequestHandler
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                 TerminationStatus status, int error_code,
                                 const CefString &error_string) override {
    const char *name = "unknown";
    switch (status) {
      case TS_ABNORMAL_TERMINATION: name = "ABNORMAL_TERMINATION"; break;
      case TS_PROCESS_WAS_KILLED: name = "WAS_KILLED"; break;
      case TS_PROCESS_CRASHED: name = "CRASHED"; break;
      case TS_PROCESS_OOM: name = "OOM"; break;
      case TS_LAUNCH_FAILED: name = "LAUNCH_FAILED"; break;
      case TS_INTEGRITY_FAILURE: name = "INTEGRITY_FAILURE"; break;
    }
    NSLog(@"CEF renderer terminated: %s code=%d text=%@ browser=%p", name,
          error_code, NSStringFromCef(error_string), browser.get());
    (void)browser;
  }

  bool GetAuthCredentials(CefRefPtr<CefBrowser>, const CefString &,
                          bool, const CefString &host, int,
                          const CefString &realm, const CefString &,
                          CefRefPtr<CefAuthCallback> callback) override {
    CEFBrowserHost *owner = owner_;
    if (!owner) {
      return false;
    }
    int64_t id = [owner nextCompletionId];
    [owner storeAuthCallback:callback forId:id];
    NSString *h = NSStringFromCef(host);
    NSString *r = NSStringFromCef(realm);
    PostToMain(^{
      if (owner.onAuthChallenge) {
        owner.onAuthChallenge(h, r, id);
      }
    });
    return true;
  }

  bool OnSelectClientCertificate(CefRefPtr<CefBrowser>, bool, const CefString &,
                                 int,
                                 const X509CertificateList &,
                                 CefRefPtr<CefSelectClientCertificateCallback>) override {
    // No picker UI (matches WebKit path): fail fast instead of hanging.
    return false;
  }

  // CefJSDialogHandler
  bool OnJSDialog(CefRefPtr<CefBrowser>, const CefString &,
                  JSDialogType dialog_type, const CefString &message_text,
                  const CefString &default_prompt_text,
                  CefRefPtr<CefJSDialogCallback> callback,
                  bool &suppress_message) override {
    suppress_message = true;
    CEFBrowserHost *owner = owner_;
    if (!owner) {
      return false;
    }
    int64_t id = [owner nextCompletionId];
    [owner storeJSDialogCallback:callback forId:id];
    NSString *message = NSStringFromCef(message_text);
    NSString *def = NSStringFromCef(default_prompt_text);
    PostToMain(^{
      if (dialog_type == JSDIALOGTYPE_PROMPT) {
        if (owner.onJSPrompt) {
          owner.onJSPrompt(message, def, id);
        }
      } else if (dialog_type == JSDIALOGTYPE_CONFIRM) {
        if (owner.onJSConfirm) {
          owner.onJSConfirm(message, id);
        }
      } else {
        if (owner.onJSAlert) {
          owner.onJSAlert(message, id);
        }
      }
    });
    return true;
  }

  // CefPermissionHandler
  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString &requesting_url,
      uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override {
    CEFBrowserHost *owner = owner_;
    if (!owner) {
      return false;
    }
    int64_t id = [owner nextCompletionId];
    [owner storeMediaCallback:callback permissions:requested_permissions forId:id];
    NSString *url = NSStringFromCef(requesting_url);
    PostToMain(^{
      if (owner.onMediaPermission) {
        owner.onMediaPermission(url, id);
      }
    });
    return true;
  }

  // CefDownloadHandler
  bool OnBeforeDownload(CefRefPtr<CefBrowser>,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString &suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override {
    CEFBrowserHost *owner = owner_;
    if (!owner) {
      return false;
    }
    uint32_t cefId = download_item->GetId();
    std::string name = suggested_name.ToString();
    std::string url = download_item->GetURL().ToString();
    int64_t total = static_cast<int64_t>(download_item->GetTotalBytes());
    NSString *downloadId = [owner registerDownload:cefId callback:callback];
    NSString *suggested = [NSString stringWithUTF8String:name.c_str()];
    NSString *source = [NSString stringWithUTF8String:url.c_str()];
    PostToMain(^{
      if (owner.onDownloadStarted) {
        owner.onDownloadStarted(downloadId, suggested ?: @"download",
                                source ?: @"", total);
      }
    });
    return true;
  }

  void OnDownloadUpdated(CefRefPtr<CefBrowser>,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> item_callback) override {
    CEFBrowserHost *owner = owner_;
    if (!owner) {
      return;
    }
    NSString *downloadId = [owner downloadIdForCefId:download_item->GetId()];
    if (!downloadId) {
      return;
    }
    [owner noteDownloadCallback:item_callback forDownload:downloadId];
    int64_t received = download_item->GetReceivedBytes();
    int64_t total = download_item->GetTotalBytes();
    if (download_item->IsComplete()) {
      NSString *path = NSStringFromCef(download_item->GetFullPath());
      [owner finishDownload:downloadId];
      PostToMain(^{
        if (owner.onDownloadFinished) {
          owner.onDownloadFinished(downloadId, path);
        }
      });
    } else if (download_item->IsCanceled()) {
      [owner finishDownload:downloadId];
      PostToMain(^{
        if (owner.onDownloadFailed) {
          owner.onDownloadFailed(downloadId, YES);
        }
      });
    } else if (download_item->IsInProgress()) {
      PostToMain(^{
        if (owner.onDownloadProgress) {
          owner.onDownloadProgress(downloadId, received, total);
        }
      });
    }
  }

 private:
  __weak CEFBrowserHost *owner_;
  IMPLEMENT_REFCOUNTING(LeanCefClient);
};

struct PendingMedia {
  CefRefPtr<CefMediaAccessCallback> callback;
  uint32_t permissions;
};

struct PendingDownload {
  CefRefPtr<CefBeforeDownloadCallback> before_callback;
  CefRefPtr<CefDownloadItemCallback> item_callback;
  uint32_t cefId;
};

}  // namespace

@implementation CEFBrowserHost {
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<LeanCefClient> _client;
  __weak NSView *_parentView;
  std::string _pendingURL;
  double _zoomRatio;
  int64_t _nextId;
  uint64_t _downloadSeq;
  std::map<int64_t, CefRefPtr<CefJSDialogCallback>> _jsDialogs;
  std::map<int64_t, CefRefPtr<CefAuthCallback>> _auths;
  std::map<int64_t, PendingMedia> _mediaReqs;
  std::map<std::string, PendingDownload> _downloads;
  std::map<uint32_t, std::string> _cefToLeanDownload;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _client = new LeanCefClient(self);
    _zoomRatio = 1.0;
    _nextId = 1;
    _downloadSeq = 1;
  }
  return self;
}

// Internal helpers used by LeanCefClient (UI thread only).
- (int64_t)nextCompletionId {
  return _nextId++;
}

- (void)storeJSDialogCallback:(CefRefPtr<CefJSDialogCallback>)callback forId:(int64_t)id {
  _jsDialogs[id] = callback;
}

- (void)storeAuthCallback:(CefRefPtr<CefAuthCallback>)callback forId:(int64_t)id {
  _auths[id] = callback;
}

- (void)storeMediaCallback:(CefRefPtr<CefMediaAccessCallback>)callback
               permissions:(uint32_t)permissions
                     forId:(int64_t)id {
  _mediaReqs[id] = {callback, permissions};
}

- (NSString *)registerDownload:(uint32_t)cefId
                      callback:(CefRefPtr<CefBeforeDownloadCallback>)callback {
  std::string id = "cef-" + std::to_string(_downloadSeq++);
  _downloads[id] = {callback, nullptr, cefId};
  _cefToLeanDownload[cefId] = id;
  return [NSString stringWithUTF8String:id.c_str()];
}

- (nullable NSString *)downloadIdForCefId:(uint32_t)cefId {
  auto it = _cefToLeanDownload.find(cefId);
  if (it == _cefToLeanDownload.end()) {
    return nil;
  }
  return [NSString stringWithUTF8String:it->second.c_str()];
}

- (void)noteDownloadCallback:(CefRefPtr<CefDownloadItemCallback>)callback
                forDownload:(NSString *)downloadId {
  std::string id = [downloadId UTF8String];
  auto it = _downloads.find(id);
  if (it != _downloads.end()) {
    it->second.item_callback = callback;
  }
}

- (void)finishDownload:(NSString *)downloadId {
  std::string id = [downloadId UTF8String];
  auto it = _downloads.find(id);
  if (it != _downloads.end()) {
    _cefToLeanDownload.erase(it->second.cefId);
    _downloads.erase(it);
  }
}

- (void)browserCreated:(CefRefPtr<CefBrowser>)browser {
  _browser = browser;
  [self notifyParentResized];
}

- (void)browserGone {
  _browser = nullptr;
}

// Public API (main thread; hops to CEF UI thread).

- (BOOL)createInView:(NSView *)view initialURL:(nullable NSString *)urlString {
  _parentView = view;
  if (urlString) {
    _pendingURL = [urlString UTF8String];
  }
  CGFloat w = view.bounds.size.width;
  CGFloat h = view.bounds.size.height;
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, view, w, h] {
    CefWindowInfo windowInfo;
    windowInfo.SetAsChild((__bridge CefWindowHandle)view,
                          CefRect(0, 0, (int)w, (int)h));
    CefBrowserSettings settings;
    CefBrowserHost::CreateBrowser(windowInfo, selfRef->_client, "", settings,
                                  nullptr, nullptr);
  });
  return YES;
}

- (void)loadURL:(NSString *)urlString {
  std::string url = [urlString UTF8String];
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, url] {
    if (selfRef->_browser) {
      selfRef->_pendingURL.clear();
      selfRef->_browser->GetMainFrame()->LoadURL(url);
    } else {
      selfRef->_pendingURL = url;
    }
  });
}

- (void)goBack {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->GoBack();
    }
  });
}

- (void)goForward {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->GoForward();
    }
  });
}

- (void)reload {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->Reload();
    }
  });
}

- (void)reloadFromOrigin {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->ReloadIgnoreCache();
    }
  });
}

- (void)stopLoading {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->StopLoad();
    }
  });
}

- (void)find:(NSString *)query {
  std::string text = [query UTF8String];
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, text] {
    if (selfRef->_browser) {
      selfRef->_browser->GetHost()->Find(text, true /*forward*/,
                                         false /*matchCase*/, false /*findNext*/);
    }
  });
}

- (void)stopFinding {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->GetHost()->StopFinding(true /*clearSelection*/);
    }
  });
}

- (void)applyZoom {
  double ratio = _zoomRatio;
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, ratio] {
    if (selfRef->_browser) {
      selfRef->_browser->GetHost()->SetZoomLevel(std::log(ratio) / std::log(1.2));
    }
  });
}

- (void)zoomIn {
  _zoomRatio = std::min(_zoomRatio + 0.1, 3.0);
  [self applyZoom];
}

- (void)zoomOut {
  _zoomRatio = std::max(_zoomRatio - 0.1, 0.5);
  [self applyZoom];
}

- (void)resetZoom {
  _zoomRatio = 1.0;
  [self applyZoom];
}

- (void)completeJSDialog:(long long)dialogId ok:(BOOL)ok text:(nullable NSString *)text {
  std::string input = text ? [text UTF8String] : "";
  bool success = ok ? true : false;
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, dialogId = (int64_t)dialogId, input, success] {
    auto it = selfRef->_jsDialogs.find(dialogId);
    if (it != selfRef->_jsDialogs.end()) {
      it->second->Continue(success, input);
      selfRef->_jsDialogs.erase(it);
    }
  });
}

- (void)completeAuth:(long long)challengeId
            username:(nullable NSString *)username
            password:(nullable NSString *)password {
  std::string user = username ? [username UTF8String] : "";
  std::string pass = password ? [password UTF8String] : "";
  bool hasCreds = username != nil;
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, challengeId = (int64_t)challengeId, user, pass, hasCreds] {
    auto it = selfRef->_auths.find(challengeId);
    if (it != selfRef->_auths.end()) {
      if (hasCreds) {
        it->second->Continue(user, pass);
      } else {
        it->second->Cancel();
      }
      selfRef->_auths.erase(it);
    }
  });
}

- (void)completeMediaPermission:(long long)requestId allow:(BOOL)allow {
  bool granted = allow ? true : false;
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, requestId = (int64_t)requestId, granted] {
    auto it = selfRef->_mediaReqs.find(requestId);
    if (it != selfRef->_mediaReqs.end()) {
      uint32_t perms = granted ? it->second.permissions : 0;
      it->second.callback->Continue(perms);
      selfRef->_mediaReqs.erase(it);
    }
  });
}

- (void)continueDownload:(NSString *)downloadId path:(NSString *)path {
  std::string id = [downloadId UTF8String];
  std::string dest = [path UTF8String];
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, id, dest] {
    auto it = selfRef->_downloads.find(id);
    if (it != selfRef->_downloads.end() && it->second.before_callback) {
      // Show dialog = false: Swift already chose the destination.
      it->second.before_callback->Continue(dest, false);
      it->second.before_callback = nullptr;
    }
  });
}

- (void)cancelDownload:(NSString *)downloadId {
  std::string id = [downloadId UTF8String];
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, id] {
    auto it = selfRef->_downloads.find(id);
    if (it != selfRef->_downloads.end()) {
      if (it->second.item_callback) {
        it->second.item_callback->Cancel();
      }
      // If the download never started (no item callback yet), dropping
      // tracking is enough: the pending Continue is never issued.
      selfRef->_cefToLeanDownload.erase(it->second.cefId);
      selfRef->_downloads.erase(it);
    }
  });
}

- (void)close {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->GetHost()->CloseBrowser(true /*force*/);
    }
  });
}

- (void)notifyParentResized {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (!selfRef->_browser) {
      return;
    }
    NSView *browserView = (__bridge NSView *)selfRef->_browser->GetHost()->GetWindowHandle();
    NSView *parentView = selfRef->_parentView;
    if (!parentView) {
      return;
    }
    if (browserView.superview != parentView) {
      [browserView removeFromSuperview];
      [parentView addSubview:browserView];
    }
    browserView.frame = parentView.bounds;
    browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (getenv("LEAN_CEF_DEBUG") != nullptr) {
      NSLog(@"CEF native view: %@ frame=%@ parent=%@ window=%@",
            NSStringFromClass(browserView.class), NSStringFromRect(browserView.frame),
            NSStringFromRect(parentView.bounds), parentView.window);
    }
  });
}

@end

#else

// Built without CEF headers: every method is a safe no-op.

@implementation CEFBrowserHost

- (BOOL)createInView:(NSView *)view initialURL:(nullable NSString *)urlString {
  (void)view;
  (void)urlString;
  return NO;
}

- (void)loadURL:(NSString *)urlString { (void)urlString; }
- (void)goBack {}
- (void)goForward {}
- (void)reload {}
- (void)reloadFromOrigin {}
- (void)stopLoading {}
- (void)find:(NSString *)query { (void)query; }
- (void)stopFinding {}
- (void)zoomIn {}
- (void)zoomOut {}
- (void)resetZoom {}
- (void)completeJSDialog:(long long)dialogId ok:(BOOL)ok text:(nullable NSString *)text {
  (void)dialogId; (void)ok; (void)text;
}
- (void)completeAuth:(long long)challengeId
            username:(nullable NSString *)username
            password:(nullable NSString *)password {
  (void)challengeId; (void)username; (void)password;
}
- (void)completeMediaPermission:(long long)requestId allow:(BOOL)allow {
  (void)requestId; (void)allow;
}
- (void)continueDownload:(NSString *)downloadId path:(NSString *)path {
  (void)downloadId; (void)path;
}
- (void)cancelDownload:(NSString *)downloadId { (void)downloadId; }
- (void)close {}
- (void)notifyParentResized {}

@end

#endif
