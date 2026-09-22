#import "CEFBrowserHost.h"

#if __has_include("include/cef_app.h")
#define LEAN_HAS_CEF 1
#include <atomic>
#include <cmath>
#include <functional>
#include <map>
#include <memory>
#include <queue>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_display_handler.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_download_handler.h"
#include "include/cef_frame.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_parser.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_resource_request_handler.h"
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
- (void)completeSnapshot:(int)messageId
                 success:(bool)success
                  result:(const void *)result
                    size:(size_t)resultSize;
- (BOOL)shouldBlockURL:(const CefString &)url isMainNavigation:(BOOL)isMainNavigation;
- (std::string)cosmeticScriptForURL:(const CefString &)url;
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

std::string LowerASCII(std::string value) {
  for (char &c : value) {
    if (c >= 'A' && c <= 'Z') {
      c += 'a' - 'A';
    }
  }
  return value;
}

std::string HostFromURL(const CefString &url) {
  // CefParseURL CHECK-fails (SIGTRAP) on empty input instead of returning
  // false. Frames routinely have no URL yet at startup / during navigation,
  // so guard here — an empty URL has no host by definition.
  if (url.empty()) {
    return {};
  }
  CefURLParts parts;
  if (!CefParseURL(url, parts)) {
    return {};
  }
  return LowerASCII(CefString(&parts.host).ToString());
}

bool MatchesDomain(const std::unordered_set<std::string> &domains,
                   const std::string &host) {
  if (host.empty()) {
    return false;
  }
  std::string_view suffix = host;
  while (true) {
    if (domains.contains(std::string(suffix))) {
      return true;
    }
    size_t dot = suffix.find('.');
    if (dot == std::string_view::npos) {
      return false;
    }
    suffix.remove_prefix(dot + 1);
  }
}

class PatternMatcher {
 public:
  PatternMatcher() : nodes_(1) {}

  explicit PatternMatcher(NSArray<NSString *> *patterns) : nodes_(1) {
    for (NSString *pattern in patterns) {
      Add(LowerASCII(pattern.UTF8String ?: ""));
    }
    Build();
  }

  bool Matches(std::string_view text) const {
    size_t state = 0;
    for (unsigned char c : text) {
      while (state != 0 && !nodes_[state].next.contains(c)) {
        state = nodes_[state].failure;
      }
      auto edge = nodes_[state].next.find(c);
      if (edge != nodes_[state].next.end()) {
        state = edge->second;
      }
      if (nodes_[state].terminal) {
        return true;
      }
    }
    return false;
  }

 private:
  struct Node {
    std::unordered_map<unsigned char, size_t> next;
    size_t failure = 0;
    bool terminal = false;
  };

  void Add(const std::string &pattern) {
    if (pattern.empty()) {
      return;
    }
    size_t state = 0;
    for (unsigned char c : pattern) {
      auto edge = nodes_[state].next.find(c);
      if (edge != nodes_[state].next.end()) {
        state = edge->second;
        continue;
      }
      size_t child = nodes_.size();
      nodes_[state].next.emplace(c, child);
      nodes_.emplace_back();
      state = child;
    }
    nodes_[state].terminal = true;
  }

  void Build() {
    std::queue<size_t> pending;
    for (const auto &[_, child] : nodes_[0].next) {
      pending.push(child);
    }
    while (!pending.empty()) {
      size_t parent = pending.front();
      pending.pop();
      for (const auto &[c, child] : nodes_[parent].next) {
        size_t fallback = nodes_[parent].failure;
        while (fallback != 0 && !nodes_[fallback].next.contains(c)) {
          fallback = nodes_[fallback].failure;
        }
        auto edge = nodes_[fallback].next.find(c);
        if (edge != nodes_[fallback].next.end() && edge->second != child) {
          nodes_[child].failure = edge->second;
        }
        nodes_[child].terminal = nodes_[child].terminal ||
                                 nodes_[nodes_[child].failure].terminal;
        pending.push(child);
      }
    }
  }

  std::vector<Node> nodes_;
};

std::string CSSForSelectors(NSArray<NSString *> *selectors) {
  std::string css;
  constexpr NSUInteger kSelectorsPerRule = 400;
  for (NSUInteger start = 0; start < selectors.count; start += kSelectorsPerRule) {
    NSUInteger end = std::min(selectors.count, start + kSelectorsPerRule);
    css += ":where(";
    for (NSUInteger index = start; index < end; ++index) {
      if (index > start) {
        css += ',';
      }
      css += [selectors[index] UTF8String] ?: "";
    }
    css += "){display:none!important;}\n";
  }
  return css;
}

std::string EscapeJavaScriptString(std::string_view value) {
  std::string escaped;
  escaped.reserve(value.size() + 32);
  for (unsigned char c : value) {
    switch (c) {
      case '\\': escaped += "\\\\"; break;
      case '\"': escaped += "\\\""; break;
      case '\n': escaped += "\\n"; break;
      case '\r': escaped += "\\r"; break;
      case '\t': escaped += "\\t"; break;
      default: escaped += static_cast<char>(c); break;
    }
  }
  return escaped;
}

struct AdBlockRules {
  std::unordered_set<std::string> blocked_domains;
  std::unordered_set<std::string> allowed_domains;
  PatternMatcher blocked_patterns;
  PatternMatcher allowed_patterns;
  std::string global_css;
  std::unordered_map<std::string, std::string> domain_css;
};

std::shared_ptr<const AdBlockRules> gAdBlockRules;

class LeanCefClient : public CefClient,
                      public CefDevToolsMessageObserver,
                      public CefDisplayHandler,
                      public CefLifeSpanHandler,
                      public CefLoadHandler,
                      public CefRequestHandler,
                      public CefJSDialogHandler,
                      public CefPermissionHandler,
                      public CefDownloadHandler,
                      public CefResourceRequestHandler {
 public:
  explicit LeanCefClient(CEFBrowserHost *owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int message_id,
                              bool success, const void* result,
                              size_t result_size) override {
    CEFBrowserHost *owner = owner_;
    if (owner) {
      [owner completeSnapshot:message_id
                     success:success
                      result:result
                        size:result_size];
    }
  }
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
  void OnLoadStart(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                   TransitionType) override {
    CEFBrowserHost *owner = owner_;
    if (!owner || !frame) {
      return;
    }
    // Inject for every frame so iframe ads are hidden too — the CSS is
    // idempotent (single #lean-adblock-css node per document).
    std::string script = [owner cosmeticScriptForURL:frame->GetURL()];
    if (!script.empty()) {
      frame->ExecuteJavaScript(script, frame->GetURL(), 0);
    }
  }

  void OnLoadEnd(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                 int) override {
    CEFBrowserHost *owner = owner_;
    if (!owner || !frame) {
      return;
    }
    std::string script = [owner cosmeticScriptForURL:frame->GetURL()];
    if (!script.empty()) {
      frame->ExecuteJavaScript(script, frame->GetURL(), 0);
    }
  }

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
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
      CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>,
      bool, bool, const CefString &, bool &) override {
    return this;
  }

  ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser>,
                                   CefRefPtr<CefFrame> frame,
                                   CefRefPtr<CefRequest> request,
                                   CefRefPtr<CefCallback>) override {
    CEFBrowserHost *owner = owner_;
    BOOL isMainNavigation = frame && frame->IsMain() &&
                            request->GetResourceType() == RT_MAIN_FRAME;
    if (owner && [owner shouldBlockURL:request->GetURL()
                         isMainNavigation:isMainNavigation]) {
      return RV_CANCEL;
    }
    return RV_CONTINUE;
  }

  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                 TerminationStatus status, int error_code,
                                 const CefString &error_string) override {
    CEFBrowserHost *owner = owner_;
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
    NSString *statusName = [NSString stringWithUTF8String:name];
    PostToMain(^{
      if (owner.onRendererTerminated) {
        owner.onRendererTerminated(statusName);
      }
    });
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
      } else {
        // No UI handler: fail fast instead of leaving the CEF auth
        // callback pending forever (page hangs).
        [owner completeAuth:id username:nil password:nil];
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
        } else {
          [owner completeJSDialog:id ok:NO text:nil];
        }
      } else if (dialog_type == JSDIALOGTYPE_CONFIRM) {
        if (owner.onJSConfirm) {
          owner.onJSConfirm(message, id);
        } else {
          [owner completeJSDialog:id ok:NO text:nil];
        }
      } else {
        if (owner.onJSAlert) {
          owner.onJSAlert(message, id);
        } else {
          [owner completeJSDialog:id ok:YES text:nil];
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
      } else {
        // No UI handler: explicitly deny instead of hanging the request.
        [owner completeMediaPermission:id allow:NO];
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
      } else {
        // No start handler: continue to a default destination so the
        // before-download callback never stays pending forever.
        NSString *name = (suggested.length > 0) ? suggested : @"download";
        NSString *dest = [NSHomeDirectory()
            stringByAppendingPathComponent:[@"Downloads" stringByAppendingPathComponent:name]];
        [owner continueDownload:downloadId path:dest];
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
  CefRefPtr<CefRegistration> _devToolsRegistration;
  __weak NSView *_parentView;
  std::string _pendingURL;
  double _zoomRatio;
  std::atomic_bool _adBlockingEnabled;
  int64_t _nextId;
  uint64_t _downloadSeq;
  std::map<int64_t, CefRefPtr<CefJSDialogCallback>> _jsDialogs;
  std::map<int64_t, CefRefPtr<CefAuthCallback>> _auths;
  std::map<int64_t, PendingMedia> _mediaReqs;
  std::map<std::string, PendingDownload> _downloads;
  std::map<uint32_t, std::string> _cefToLeanDownload;
  NSMutableDictionary<NSNumber *, void (^)(NSData *_Nullable)> *_snapshotCompletions;
}

+ (void)configureAdBlockerWithBlockedDomains:(NSArray<NSString *> *)blockedDomains
                              allowedDomains:(NSArray<NSString *> *)allowedDomains
                             blockedPatterns:(NSArray<NSString *> *)blockedPatterns
                             allowedPatterns:(NSArray<NSString *> *)allowedPatterns
                             globalSelectors:(NSArray<NSString *> *)globalSelectors
                             domainSelectors:(NSDictionary<NSString *, NSArray<NSString *> *> *)domainSelectors {
  auto rules = std::make_shared<AdBlockRules>();
  for (NSString *domain in blockedDomains) {
    rules->blocked_domains.insert(LowerASCII(domain.UTF8String ?: ""));
  }
  for (NSString *domain in allowedDomains) {
    rules->allowed_domains.insert(LowerASCII(domain.UTF8String ?: ""));
  }
  rules->blocked_patterns = PatternMatcher(blockedPatterns);
  rules->allowed_patterns = PatternMatcher(allowedPatterns);
  rules->global_css = CSSForSelectors(globalSelectors);
  for (NSString *domain in domainSelectors) {
    rules->domain_css.emplace(
        LowerASCII(domain.UTF8String ?: ""),
        CSSForSelectors(domainSelectors[domain]));
  }
  std::atomic_store(&gAdBlockRules,
                    std::static_pointer_cast<const AdBlockRules>(rules));
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _client = new LeanCefClient(self);
    _zoomRatio = 1.0;
    _adBlockingEnabled = false;
    _nextId = 1;
    _downloadSeq = 1;
    _snapshotCompletions = [NSMutableDictionary dictionary];
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
  _devToolsRegistration = browser->GetHost()->AddDevToolsMessageObserver(_client);
  [self notifyParentResized];
}

- (void)browserGone {
  _devToolsRegistration = nullptr;
  _browser = nullptr;
  for (NSNumber *key in _snapshotCompletions.allKeys) {
    _snapshotCompletions[key](nil);
  }
  [_snapshotCompletions removeAllObjects];
}

- (void)completeSnapshot:(int)messageId
                 success:(bool)success
                  result:(const void *)result
                    size:(size_t)resultSize {
  NSNumber *key = @(messageId);
  void (^completion)(NSData *_Nullable) = _snapshotCompletions[key];
  if (!completion) {
    return;
  }
  [_snapshotCompletions removeObjectForKey:key];

  NSData *imageData = nil;
  if (success && result && resultSize > 0) {
    NSData *jsonData = [NSData dataWithBytes:result length:resultSize];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    NSString *base64 = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
    if ([base64 isKindOfClass:NSString.class]) {
      imageData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    }
  }
  completion(imageData);
}

- (BOOL)shouldBlockURL:(const CefString &)url isMainNavigation:(BOOL)isMainNavigation {
  if (!_adBlockingEnabled.load()) {
    return NO;
  }
  (void)isMainNavigation;
  // Network filters also enforce top-level matches: a direct navigation to
  // a blocked domain/URL is cancelled like any subresource. Allow-rules
  // still win below, so explicit exceptions keep working.
  auto rules = std::atomic_load(&gAdBlockRules);
  if (!rules) {
    return NO;
  }
  std::string host = HostFromURL(url);
  std::string requestURL = LowerASCII(url.ToString());
  if (MatchesDomain(rules->allowed_domains, host) ||
      rules->allowed_patterns.Matches(requestURL)) {
    return NO;
  }
  return MatchesDomain(rules->blocked_domains, host) ||
         rules->blocked_patterns.Matches(requestURL);
}

- (std::string)cosmeticScriptForURL:(const CefString &)url {
  if (!_adBlockingEnabled.load()) {
    return {};
  }
  auto rules = std::atomic_load(&gAdBlockRules);
  if (!rules) {
    return {};
  }
  std::string css = rules->global_css;
  std::string host = HostFromURL(url);
  std::string_view suffix = host;
  while (!suffix.empty()) {
    auto found = rules->domain_css.find(std::string(suffix));
    if (found != rules->domain_css.end()) {
      css += found->second;
    }
    size_t dot = suffix.find('.');
    if (dot == std::string_view::npos) {
      break;
    }
    suffix.remove_prefix(dot + 1);
  }
  if (css.empty()) {
    return {};
  }
  return "(()=>{const c=\"" + EscapeJavaScriptString(css) +
         "\",a=()=>{const r=document.documentElement;if(!r){requestAnimationFrame(a);return;}"
         "let s=document.getElementById('lean-adblock-css');if(!s){s=document.createElement('style');"
         "s.id='lean-adblock-css';r.appendChild(s);}s.textContent=c;};a();})();";
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
    // Honor the public initialURL: without an external onCreated navigation
    // CreateBrowser with "" opens blank and _pendingURL is only consumed by
    // browserCreated callers that navigate. Pass it here so the parameter
    // is never ignored.
    std::string startURL = selfRef->_pendingURL;
    selfRef->_pendingURL.clear();
    CefBrowserHost::CreateBrowser(windowInfo, selfRef->_client, startURL, settings,
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

- (void)focus {
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef] {
    if (selfRef->_browser) {
      selfRef->_browser->GetHost()->SetFocus(true);
    }
  });
}

- (void)setAdBlockingEnabled:(BOOL)enabled {
  _adBlockingEnabled.store(enabled);
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, enabled] {
    if (!selfRef->_browser) {
      return;
    }
    CefRefPtr<CefFrame> frame = selfRef->_browser->GetMainFrame();
    if (!frame) {
      return;
    }
    std::string script = enabled
        ? [selfRef cosmeticScriptForURL:frame->GetURL()]
        : "document.getElementById('lean-adblock-css')?.remove();";
    if (!script.empty()) {
      frame->ExecuteJavaScript(script, frame->GetURL(), 0);
    }
  });
}

- (void)captureSnapshotWithCompletion:(void (^)(NSData *_Nullable))completion {
  if (!completion) {
    return;
  }
  CGFloat width = _parentView.bounds.size.width;
  CGFloat height = _parentView.bounds.size.height;
  if (width <= 8 || height <= 8) {
    completion(nil);
    return;
  }

  void (^completionCopy)(NSData *_Nullable) = [completion copy];
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, completionCopy] {
    if (!selfRef->_browser) {
      completionCopy(nil);
      return;
    }

    CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
    params->SetString("format", "jpeg");
    params->SetInt("quality", 82);
    params->SetBool("captureBeyondViewport", false);
    params->SetBool("fromSurface", true);
    params->SetBool("optimizeForSpeed", true);

    int messageId = selfRef->_browser->GetHost()->ExecuteDevToolsMethod(
        0, "Page.captureScreenshot", params);
    if (messageId == 0) {
      completionCopy(nil);
      return;
    }
    selfRef->_snapshotCompletions[@(messageId)] = completionCopy;
  });
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

+ (void)configureAdBlockerWithBlockedDomains:(NSArray<NSString *> *)blockedDomains
                              allowedDomains:(NSArray<NSString *> *)allowedDomains
                             blockedPatterns:(NSArray<NSString *> *)blockedPatterns
                             allowedPatterns:(NSArray<NSString *> *)allowedPatterns
                             globalSelectors:(NSArray<NSString *> *)globalSelectors
                             domainSelectors:(NSDictionary<NSString *, NSArray<NSString *> *> *)domainSelectors {
  (void)blockedDomains; (void)allowedDomains; (void)blockedPatterns;
  (void)allowedPatterns; (void)globalSelectors; (void)domainSelectors;
}

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
- (void)focus {}
- (void)setAdBlockingEnabled:(BOOL)enabled { (void)enabled; }
- (void)captureSnapshotWithCompletion:(void (^)(NSData *_Nullable))completion {
  completion(nil);
}
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
