#import "CEFBrowserHost.h"

#if __has_include("include/cef_app.h")
#define LEAN_HAS_CEF 1
#include <algorithm>
#include <atomic>
#include <cctype>
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
#include "include/cef_request_context.h"
#include "include/cef_request_handler.h"
#include "include/cef_resource_handler.h"
#include "include/cef_resource_request_handler.h"
#include "include/cef_response.h"
#include "include/cef_task.h"
#include "include/cef_urlrequest.h"

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
- (BOOL)shouldBlockURL:(const CefString &)url
                frameURL:(const CefString &)frameURL
            resourceType:(cef_resource_type_t)resourceType
        isMainNavigation:(BOOL)isMainNavigation;
- (BOOL)shouldBlockPopupURL:(const CefString &)url
                  openerURL:(const CefString &)openerURL;
/// Atomic snapshot of the toggle for IO-thread C++ callers (ivar access
/// is not available outside ObjC methods).
- (BOOL)adBlockingSnapshot;
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

/// ABP content-kind bits for scoped network rules. Request types that have
/// no ABP equivalent (favicon, workers, prefetch, …) map to the closest
/// kind; see TypeBitForResourceType.
enum AdBlockTypeBits : uint32_t {
  kAdTypeScript = 1u << 0,
  kAdTypeStylesheet = 1u << 1,
  kAdTypeImage = 1u << 2,
  kAdTypeFont = 1u << 3,
  kAdTypeMedia = 1u << 4,
  kAdTypeObject = 1u << 5,
  kAdTypeOther = 1u << 6,
  kAdTypeXHR = 1u << 7,
  kAdTypeWebSocket = 1u << 8,
  kAdTypePing = 1u << 9,
  kAdTypeSubdocument = 1u << 10,
  kAdTypeDocument = 1u << 11,
};

/// A network rule carrying ABP option scoping (`$third-party`, `$domain=`,
/// content kinds, `$popup`, `$important`). Unscoped rules stay in the fast
/// domain/pattern sets; everything with options lands here.
struct AdBlockNetworkRule {
  bool is_domain = false;
  std::string value;
  bool exception = false;
  int third_party = -1;
  std::unordered_set<std::string> domains;
  std::unordered_set<std::string> not_domains;
  uint32_t types = 0;
  bool important = false;
  bool popup_only = false;
  bool exclude_popup = false;
  int pattern_id = -1;
};

/// First-party when the hosts are equal or one is a subdomain of the other.
bool IsFirstParty(const std::string &host, const std::string &frame_host) {
  if (frame_host.empty()) {
    return true;
  }
  if (host == frame_host) {
    return true;
  }
  if (host.size() > frame_host.size() + 1 &&
      host.compare(host.size() - frame_host.size() - 1, frame_host.size() + 1,
                   "." + frame_host) == 0) {
    return true;
  }
  if (frame_host.size() > host.size() + 1 &&
      frame_host.compare(frame_host.size() - host.size() - 1, host.size() + 1,
                         "." + host) == 0) {
    return true;
  }
  return false;
}

uint32_t TypeBitForResourceType(cef_resource_type_t type) {
  switch (type) {
    case RT_SCRIPT:
    case RT_WORKER:
    case RT_SHARED_WORKER:
    case RT_SERVICE_WORKER:
      return kAdTypeScript;
    case RT_STYLESHEET:
      return kAdTypeStylesheet;
    case RT_IMAGE:
    case RT_FAVICON:
      return kAdTypeImage;
    case RT_FONT_RESOURCE:
      return kAdTypeFont;
    case RT_MEDIA:
      return kAdTypeMedia;
    case RT_OBJECT:
    case RT_PLUGIN_RESOURCE:
      return kAdTypeObject;
    case RT_XHR:
      return kAdTypeXHR;
    case RT_PING:
      return kAdTypePing;
    case RT_SUB_FRAME:
      return kAdTypeSubdocument;
    case RT_MAIN_FRAME:
      return kAdTypeDocument;
    default:
      // RT_SUB_RESOURCE, RT_PREFETCH, RT_CSP_REPORT, navigation preloads:
      // no ABP equivalent — closest bucket is `other`.
      return kAdTypeOther;
  }
}

uint32_t TypeBitsForNames(NSArray<NSString *> *names) {
  static const std::unordered_map<std::string, uint32_t> kBits = {
      {"script", kAdTypeScript},         {"stylesheet", kAdTypeStylesheet},
      {"image", kAdTypeImage},           {"font", kAdTypeFont},
      {"media", kAdTypeMedia},           {"object", kAdTypeObject},
      {"other", kAdTypeOther},           {"xhr", kAdTypeXHR},
      {"websocket", kAdTypeWebSocket},   {"ping", kAdTypePing},
      {"subdocument", kAdTypeSubdocument}, {"document", kAdTypeDocument},
  };
  uint32_t bits = 0;
  for (NSString *name in names) {
    auto found = kBits.find(LowerASCII(name.UTF8String ?: ""));
    if (found != kBits.end()) {
      bits |= found->second;
    }
  }
  return bits;
}

/// Scope check for one candidate rule (kind match already established).
/// type_bit is ignored for popup-only rules; callers filter by popup-ness.
bool RuleScopeMatches(const AdBlockNetworkRule &rule, bool is_first_party,
                      const std::string &frame_host, uint32_t type_bit) {
  if (rule.third_party == 1 && is_first_party) {
    return false;
  }
  if (rule.third_party == 0 && !is_first_party) {
    return false;
  }
  if (!rule.domains.empty() && !MatchesDomain(rule.domains, frame_host)) {
    return false;
  }
  if (!rule.not_domains.empty() && MatchesDomain(rule.not_domains, frame_host)) {
    return false;
  }
  if (rule.types != 0 && (rule.types & type_bit) == 0) {
    return false;
  }
  return true;
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

  /// Adds a pattern tagged with an id; Build() must follow. MatchAll
  /// reports every tagged id whose pattern occurs in the text.
  void AddTagged(const std::string &pattern, int tag) {
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
    nodes_[state].tags.push_back(tag);
  }

  void MatchAll(std::string_view text, std::vector<int> &out) const {
    size_t state = 0;
    for (unsigned char c : text) {
      while (state != 0 && !nodes_[state].next.contains(c)) {
        state = nodes_[state].failure;
      }
      auto edge = nodes_[state].next.find(c);
      if (edge != nodes_[state].next.end()) {
        state = edge->second;
      }
      for (int tag : nodes_[state].tags) {
        out.push_back(tag);
      }
    }
  }

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
        const std::vector<int> &inherited = nodes_[nodes_[child].failure].tags;
        nodes_[child].tags.insert(nodes_[child].tags.end(), inherited.begin(),
                                  inherited.end());
        pending.push(child);
      }
    }
  }

 private:
  struct Node {
    std::unordered_map<unsigned char, size_t> next;
    size_t failure = 0;
    bool terminal = false;
    std::vector<int> tags;
  };

  std::vector<Node> nodes_;
};

/// youtube.com / youtu.be and their subdomains.
bool IsYouTubeHost(const std::string &host) {
  auto matches = [](std::string_view h, std::string_view base) {
    return h == base ||
           (h.size() > base.size() + 1 &&
            h.compare(h.size() - base.size() - 1, base.size() + 1,
                      std::string(".") + std::string(base)) == 0);
  };
  return matches(host, "youtube.com") || matches(host, "youtu.be");
}

/// In-player ad handling that stylesheets cannot do: click skip buttons the
/// moment they appear, mute while an ad is showing (restoring afterwards),
/// and seek past short unskippable ad segments. Guarded re-entry (the
/// injector runs on both load-start and load-end) and scoped to ad playback
/// via `.ad-showing` so normal videos are never touched.
std::string YouTubeAdSkipScript() {
  return "(()=>{if(window.__leanYtSkip)return;window.__leanYtSkip=1;"
         "const q=(s)=>document.querySelector(s);"
         "const skipSel='.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-skip-ad-button-modern';"
         "const clickSkip=()=>{const b=q(skipSel);if(b){b.click();}};"
         "const tame=()=>{const v=q('video');if(!v)return;"
         "if(q('.ad-showing')){"
         "if(!v.dataset.leanMuted){v.dataset.leanMuted='1';}"
         "v.muted=true;clickSkip();"
         "if(!q(skipSel)&&isFinite(v.duration)&&v.duration>0&&v.duration<180&&"
         "v.currentTime<v.duration-0.5){try{v.currentTime=v.duration-0.2;}catch(e){}}"
         "}else if(v.dataset.leanMuted){v.muted=false;delete v.dataset.leanMuted;}};"
         "const start=()=>{if(!document.documentElement){requestAnimationFrame(start);return;}"
         "setInterval(tame,500);"
         "new MutationObserver(()=>{if(q(skipSel)){clickSkip();}})"
         ".observe(document.documentElement,{childList:true,subtree:true});tame();};"
         "start();})();";
}

/// Advances past one JSON value starting at pos (leading whitespace
/// skipped). Returns one-past-the-end, or npos when malformed.
size_t SkipJsonValue(const std::string &s, size_t pos) {
  while (pos < s.size() && isspace((unsigned char)s[pos])) {
    ++pos;
  }
  if (pos >= s.size()) {
    return std::string::npos;
  }
  char c = s[pos];
  if (c == '{' || c == '[') {
    char open = c;
    char close = (c == '{') ? '}' : ']';
    int depth = 0;
    bool in_str = false;
    for (size_t i = pos; i < s.size(); ++i) {
      char ch = s[i];
      if (in_str) {
        if (ch == '\\') {
          ++i;
          continue;
        }
        if (ch == '"') {
          in_str = false;
        }
        continue;
      }
      if (ch == '"') {
        in_str = true;
        continue;
      }
      if (ch == open) {
        ++depth;
      } else if (ch == close) {
        if (--depth == 0) {
          return i + 1;
        }
      }
    }
    return std::string::npos;
  }
  if (c == '"') {
    for (size_t i = pos + 1; i < s.size(); ++i) {
      if (s[i] == '\\') {
        ++i;
        continue;
      }
      if (s[i] == '"') {
        return i + 1;
      }
    }
    return std::string::npos;
  }
  size_t i = pos;
  while (i < s.size() && s[i] != ',' && s[i] != '}' && s[i] != ']' &&
         !isspace((unsigned char)s[i])) {
    ++i;
  }
  return (i == pos) ? std::string::npos : i;
}

/// Strips YouTube ad-schedule fields (`adPlacements`, `playerAds`,
/// `adSlots`) from a player/next API response body, swallowing one adjacent
/// comma so the object stays valid. Returns true when modified; on any
/// malformed input the body is left untouched (caller serves the original).
bool PruneYouTubePlayerJson(std::string &body) {
  static const char *const kKeys[] = {"adPlacements", "playerAds", "adSlots"};
  bool needle = false;
  for (const char *k : kKeys) {
    if (body.find(k) != std::string::npos) {
      needle = true;
      break;
    }
  }
  if (!needle) {
    return false;
  }
  std::string out = body;
  bool changed = false;
  for (const char *k : kKeys) {
    std::string quoted = std::string("\"") + k + "\"";
    size_t search = 0;
    while ((search = out.find(quoted, search)) != std::string::npos) {
      size_t after = search + quoted.size();
      size_t colon = after;
      while (colon < out.size() && isspace((unsigned char)out[colon])) {
        ++colon;
      }
      // Not a key (e.g. the text occurs inside a string value): skip it.
      if (colon >= out.size() || out[colon] != ':') {
        search = after;
        continue;
      }
      size_t vend = SkipJsonValue(out, colon + 1);
      if (vend == std::string::npos) {
        return false;
      }
      size_t fwd = vend;
      while (fwd < out.size() && isspace((unsigned char)out[fwd])) {
        ++fwd;
      }
      if (fwd < out.size() && out[fwd] == ',') {
        out.erase(search, fwd - search + 1);
      } else {
        size_t back = search;
        while (back > 0 && isspace((unsigned char)out[back - 1])) {
          --back;
        }
        if (back > 0 && out[back - 1] == ',') {
          out.erase(back - 1, vend - (back - 1));
        } else {
          out.erase(search, vend - search);
        }
      }
      changed = true;
    }
  }
  if (!changed) {
    return false;
  }
  body.swap(out);
  return true;
}

// Maximum buffered youtubei response we'll prune (player/next bodies are
// KBs; anything larger passes through untouched by declining interception).
constexpr size_t kMaxPruneBytes = 32u * 1024u * 1024u;

/// Re-fetches a youtubei API response in the browser process, prunes the ad
/// schedule, and serves the rewritten bytes to the renderer. Runs entirely
/// on the IO thread; the rules snapshot is immutable.
class PruningResourceHandler : public CefResourceHandler {
 private:
  class PruningURLClient : public CefURLRequestClient {
   public:
    explicit PruningURLClient(PruningResourceHandler *handler) : handler_(handler) {}
    void OnRequestComplete(CefRefPtr<CefURLRequest> request) override {
      if (handler_) {
        handler_->OnFetchComplete(request);
      }
    }
    void OnUploadProgress(CefRefPtr<CefURLRequest>, int64_t, int64_t) override {}
    void OnDownloadProgress(CefRefPtr<CefURLRequest> request, int64_t, int64_t total) override {
      if (handler_) {
        handler_->OnFetchProgress(total);
      }
      (void)request;
    }
    void OnDownloadData(CefRefPtr<CefURLRequest>, const void *data, size_t data_length) override {
      if (handler_) {
        handler_->OnFetchData(data, data_length);
      }
    }
    bool GetAuthCredentials(bool, const CefString &, int, const CefString &, const CefString &,
                            CefRefPtr<CefAuthCallback>) override {
      return false;
    }

   private:
    CefRefPtr<PruningResourceHandler> handler_;
    IMPLEMENT_REFCOUNTING(PruningURLClient);
  };

 public:
  explicit PruningResourceHandler(CefRefPtr<CefBrowser> browser)
      : browser_(browser), offset_(0), complete_(false), error_(false), status_(200) {}

  bool Open(CefRefPtr<CefRequest> request, bool &handle_request,
            CefRefPtr<CefCallback> callback) override {
    handle_request = true;
    open_callback_ = callback;
    CefRefPtr<CefRequest> forward = CefRequest::Create();
    forward->SetURL(request->GetURL());
    forward->SetMethod(request->GetMethod());
    CefRequest::HeaderMap headers;
    request->GetHeaderMap(headers);
    // Marker so GetResourceHandler lets this inner fetch load normally.
    headers.insert({ "X-Lean-Prune-Bypass", "1" });
    forward->SetHeaderMap(headers);
    if (request->GetPostData()) {
      forward->SetPostData(request->GetPostData());
    }
    forward->SetFlags(request->GetFlags());
    forward->SetFirstPartyForCookies(request->GetFirstPartyForCookies());
    CefRefPtr<CefRequestContext> context;
    if (browser_ && browser_->GetHost()) {
      context = browser_->GetHost()->GetRequestContext();
    }
    client_ = new PruningURLClient(this);
    url_request_ = CefURLRequest::Create(forward, client_.get(), context.get());
    if (!url_request_) {
      error_ = true;
      CefRefPtr<CefCallback> cb = open_callback_;
      open_callback_ = nullptr;
      if (cb) {
        cb->Continue();
      }
    }
    return true;
  }

  void GetResponseHeaders(CefRefPtr<CefResponse> response, int64_t &response_length,
                          CefString &redirectUrl) override {
    redirectUrl = CefString();
    if (error_) {
      response->SetError(ERR_FAILED);
      response_length = 0;
      return;
    }
    response->SetStatus(status_);
    response->SetStatusText(status_text_);
    response->SetMimeType("application/json");
    CefResponse::HeaderMap headers;
    for (const auto &kv : resp_headers_) {
      std::string name = LowerASCII(kv.first.ToString());
      // Length/encoding are ours now; content-type is set via SetMimeType.
      if (name == "content-length" || name == "content-encoding" ||
          name == "transfer-encoding" || name == "content-type") {
        continue;
      }
      headers.insert(kv);
    }
    response->SetHeaderMap(headers);
    response_length = (int64_t)body_.size();
  }

  bool Skip(int64_t bytes_to_skip, int64_t &bytes_skipped,
            CefRefPtr<CefResourceSkipCallback>) override {
    if (error_) {
      bytes_skipped = -2;
      return false;
    }
    size_t avail = body_.size() > offset_ ? body_.size() - offset_ : 0;
    int64_t n = std::min<int64_t>(bytes_to_skip, (int64_t)avail);
    offset_ += (size_t)n;
    bytes_skipped = n;
    return true;
  }

  bool Read(void *data_out, int bytes_to_read, int &bytes_read,
            CefRefPtr<CefResourceReadCallback>) override {
    if (error_) {
      bytes_read = -2;
      return false;
    }
    size_t avail = body_.size() > offset_ ? body_.size() - offset_ : 0;
    size_t n = std::min<size_t>(avail, (size_t)bytes_to_read);
    if (n == 0) {
      bytes_read = 0;
      return false;
    }
    memcpy(data_out, body_.data() + offset_, n);
    offset_ += n;
    bytes_read = (int)n;
    return true;
  }

  void Cancel() override {
    if (url_request_) {
      url_request_->Cancel();
    }
    open_callback_ = nullptr;
    client_ = nullptr;
    url_request_ = nullptr;
  }

  void OnFetchData(const void *data, size_t data_length) {
    if (complete_ || error_) {
      return;
    }
    if (buffer_.size() + data_length > kMaxPruneBytes) {
      if (url_request_) {
        url_request_->Cancel();
      }
      OnFetchError();
      return;
    }
    buffer_.append((const char *)data, data_length);
  }

  void OnFetchProgress(int64_t total) {
    if (total > 0 && (uint64_t)total > kMaxPruneBytes && url_request_) {
      url_request_->Cancel();
      OnFetchError();
    }
  }

  void OnFetchComplete(CefRefPtr<CefURLRequest> url_request) {
    if (complete_ || error_) {
      return;
    }
    complete_ = true;
    if (url_request->GetRequestStatus() == UR_SUCCESS) {
      CefRefPtr<CefResponse> orig = url_request->GetResponse();
      if (orig) {
        status_ = orig->GetStatus();
        status_text_ = orig->GetStatusText().ToString();
        orig->GetHeaderMap(resp_headers_);
      }
      std::string body = std::move(buffer_);
      PruneYouTubePlayerJson(body);
      body_ = std::move(body);
    } else {
      error_ = true;
    }
    CefRefPtr<CefCallback> cb = open_callback_;
    open_callback_ = nullptr;
    client_ = nullptr;
    url_request_ = nullptr;
    if (cb) {
      cb->Continue();
    }
  }

  void OnFetchError() {
    if (complete_ || error_) {
      return;
    }
    error_ = true;
    CefRefPtr<CefCallback> cb = open_callback_;
    open_callback_ = nullptr;
    client_ = nullptr;
    url_request_ = nullptr;
    if (cb) {
      cb->Continue();
    }
  }

  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefURLRequest> url_request_;
  CefRefPtr<PruningURLClient> client_;
  CefRefPtr<CefCallback> open_callback_;
  std::string buffer_;
  std::string body_;
  size_t offset_;
  bool complete_;
  bool error_;
  int status_;
  std::string status_text_;
  CefResponse::HeaderMap resp_headers_;
  IMPLEMENT_REFCOUNTING(PruningResourceHandler);
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
  std::vector<AdBlockNetworkRule> network_rules;
  /// Suffix-keyed index into network_rules for domain-kind rules.
  std::unordered_map<std::string, std::vector<size_t>> domain_rule_index;
  PatternMatcher scoped_patterns;
  /// scoped pattern id -> index into network_rules.
  std::vector<size_t> scoped_pattern_rules;
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

  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                     int, const CefString &target_url, const CefString &,
                     WindowOpenDisposition, bool,
                     const CefPopupFeatures &, CefWindowInfo &,
                     CefRefPtr<CefClient> &, CefBrowserSettings &,
                     CefRefPtr<CefDictionaryValue> &, bool *) override {
    CEFBrowserHost *owner = owner_;
    CefString openerURL;
    if (frame) {
      openerURL = frame->GetURL();
    }
    if (owner && [owner shouldBlockPopupURL:target_url openerURL:openerURL]) {
      // Ad popup: swallow entirely — no window, no tab.
      return true;
    }
    // Legit popup (OAuth/SSO): cancel the popup window, open its URL as a
    // plain new tab.
    NSString *u = NSStringFromCef(target_url);
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

  CefRefPtr<CefResourceHandler> GetResourceHandler(
      CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
      CefRefPtr<CefRequest> request) override {
    CEFBrowserHost *owner = owner_;
    if (!owner || ![owner adBlockingSnapshot]) {
      return nullptr;
    }
    // Never intercept our own re-issued fetch (see PruningResourceHandler).
    if (!request->GetHeaderByName("X-Lean-Prune-Bypass").empty()) {
      return nullptr;
    }
    std::string url = LowerASCII(request->GetURL().ToString());
    if (url.find("youtubei/v1/player") == std::string::npos &&
        url.find("youtubei/v1/next") == std::string::npos) {
      return nullptr;
    }
    return new PruningResourceHandler(browser);
  }

  ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser>,
                                   CefRefPtr<CefFrame> frame,
                                   CefRefPtr<CefRequest> request,
                                   CefRefPtr<CefCallback>) override {
    CEFBrowserHost *owner = owner_;
    BOOL isMainNavigation = frame && frame->IsMain() &&
                            request->GetResourceType() == RT_MAIN_FRAME;
    CefString frameURL;
    if (frame) {
      frameURL = frame->GetURL();
    }
    if (owner && [owner shouldBlockURL:request->GetURL()
                              frameURL:frameURL
                          resourceType:request->GetResourceType()
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
                              domainSelectors:(NSDictionary<NSString *, NSArray<NSString *> *> *)domainSelectors
                                 networkRules:(NSArray<NSDictionary *> *)networkRules {
  auto rules = std::make_shared<AdBlockRules>();
  for (NSString *domain in blockedDomains) {
    rules->blocked_domains.insert(LowerASCII(domain.UTF8String ?: ""));
  }
  for (NSString *domain in allowedDomains) {
    rules->allowed_domains.insert(LowerASCII(domain.UTF8String ?: ""));
  }
  rules->blocked_patterns = PatternMatcher(blockedPatterns);
  rules->allowed_patterns = PatternMatcher(allowedPatterns);
  for (NSDictionary *entry in networkRules) {
    if (![entry isKindOfClass:NSDictionary.class]) {
      continue;
    }
    AdBlockNetworkRule rule;
    NSString *kind = entry[@"kind"];
    NSString *value = entry[@"value"];
    if (![kind isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) {
      continue;
    }
    rule.is_domain = [kind isEqualToString:@"domain"];
    rule.value = LowerASCII(value.UTF8String ?: "");
    if (rule.value.empty()) {
      continue;
    }
    rule.exception = [entry[@"exception"] boolValue];
    rule.third_party = (int)[entry[@"thirdParty"] integerValue];
    rule.third_party = std::clamp(rule.third_party, -1, 1);
    id domains = entry[@"domains"];
    if ([domains isKindOfClass:NSArray.class]) {
      for (NSString *domain in (NSArray *)domains) {
        if ([domain isKindOfClass:NSString.class]) {
          rule.domains.insert(LowerASCII(domain.UTF8String ?: ""));
        }
      }
    }
    id notDomains = entry[@"notDomains"];
    if ([notDomains isKindOfClass:NSArray.class]) {
      for (NSString *domain in (NSArray *)notDomains) {
        if ([domain isKindOfClass:NSString.class]) {
          rule.not_domains.insert(LowerASCII(domain.UTF8String ?: ""));
        }
      }
    }
    rule.types = TypeBitsForNames(entry[@"types"]);
    rule.important = [entry[@"important"] boolValue];
    rule.popup_only = [entry[@"popupOnly"] boolValue];
    rule.exclude_popup = [entry[@"excludePopup"] boolValue];
    size_t index = rules->network_rules.size();
    if (rule.is_domain) {
      rules->domain_rule_index[rule.value].push_back(index);
    } else {
      rule.pattern_id = (int)rules->scoped_pattern_rules.size();
      rules->scoped_patterns.AddTagged(rule.value, rule.pattern_id);
      rules->scoped_pattern_rules.push_back(index);
    }
    rules->network_rules.push_back(std::move(rule));
  }
  rules->scoped_patterns.Build();
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

/// uBO-approximate precedence across the fast sets and scoped rules:
/// important exception > important block > exception > block.
- (BOOL)decideBlock:(bool)fastBlock
      fastException:(bool)fastException
          scopedHit:(const bool [4])scopedHit {
  if (scopedHit[3]) {
    return NO;
  }
  if (scopedHit[1]) {
    return YES;
  }
  if (fastException || scopedHit[2]) {
    return NO;
  }
  if (fastBlock || scopedHit[0]) {
    return YES;
  }
  return NO;
}

/// Collects scoped-rule hits into [block, importantBlock, exception,
/// importantException]. popup_path selects `$popup` semantics: popup-only
/// rules apply (scope-checked, type ignored); general rules apply only when
/// unconstrained by content kind; `$~popup` rules never apply.
- (void)collectScopedHits:(const std::shared_ptr<const AdBlockRules> &)rules
                     host:(const std::string &)host
              requestURL:(const std::string &)requestURL
               frameHost:(const std::string &)frameHost
                 typeBit:(uint32_t)typeBit
               popupPath:(BOOL)popupPath
                    hits:(bool [4])hits {
  hits[0] = hits[1] = hits[2] = hits[3] = false;
  if (rules->network_rules.empty()) {
    return;
  }
  const bool is_first_party = IsFirstParty(host, frameHost);
  std::vector<size_t> candidates;
  std::string_view suffix = host;
  while (true) {
    auto found = rules->domain_rule_index.find(std::string(suffix));
    if (found != rules->domain_rule_index.end()) {
      candidates.insert(candidates.end(), found->second.begin(),
                        found->second.end());
    }
    size_t dot = suffix.find('.');
    if (dot == std::string_view::npos) {
      break;
    }
    suffix.remove_prefix(dot + 1);
  }
  std::vector<int> pattern_ids;
  rules->scoped_patterns.MatchAll(requestURL, pattern_ids);
  for (int pattern_id : pattern_ids) {
    if (pattern_id >= 0 &&
        (size_t)pattern_id < rules->scoped_pattern_rules.size()) {
      candidates.push_back(rules->scoped_pattern_rules[(size_t)pattern_id]);
    }
  }
  for (size_t index : candidates) {
    const AdBlockNetworkRule &rule = rules->network_rules[index];
    if (popupPath) {
      if (rule.exclude_popup) {
        continue;
      }
      if (!rule.popup_only && rule.types != 0) {
        // Kind-constrained network rules (e.g. `$script`) don't judge popup
        // navigations; `$popup` and unconstrained rules do.
        continue;
      }
    } else if (rule.popup_only) {
      continue;
    }
    if (!RuleScopeMatches(rule, is_first_party, frameHost, typeBit)) {
      continue;
    }
    if (rule.exception) {
      hits[rule.important ? 3 : 2] = true;
    } else {
      hits[rule.important ? 1 : 0] = true;
    }
    if (hits[3]) {
      return;
    }
  }
}

- (BOOL)shouldBlockURL:(const CefString &)url
                frameURL:(const CefString &)frameURL
            resourceType:(cef_resource_type_t)resourceType
        isMainNavigation:(BOOL)isMainNavigation {
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
  std::string frameHost = HostFromURL(frameURL);
  const uint32_t type_bit = TypeBitForResourceType(resourceType);
  const bool fastBlock = MatchesDomain(rules->blocked_domains, host) ||
                         rules->blocked_patterns.Matches(requestURL);
  const bool fastException = MatchesDomain(rules->allowed_domains, host) ||
                             rules->allowed_patterns.Matches(requestURL);
  bool scopedHit[4];
  [self collectScopedHits:rules
                     host:host
              requestURL:requestURL
               frameHost:frameHost
                 typeBit:type_bit
               popupPath:NO
                    hits:scopedHit];
  return [self decideBlock:fastBlock
            fastException:fastException
                scopedHit:scopedHit];
}

/// Popup navigations (`window.open`, `target=_blank` to a new window).
/// `$popup`-scoped rules plus unconstrained general rules judge the target;
/// a match swallows the popup instead of opening it as a new tab.
- (BOOL)shouldBlockPopupURL:(const CefString &)url
                  openerURL:(const CefString &)openerURL {
  if (!_adBlockingEnabled.load()) {
    return NO;
  }
  if (url.empty()) {
    return NO;
  }
  auto rules = std::atomic_load(&gAdBlockRules);
  if (!rules) {
    return NO;
  }
  std::string host = HostFromURL(url);
  if (host.empty()) {
    return NO;
  }
  std::string requestURL = LowerASCII(url.ToString());
  std::string openerHost = HostFromURL(openerURL);
  const bool fastBlock = MatchesDomain(rules->blocked_domains, host) ||
                         rules->blocked_patterns.Matches(requestURL);
  const bool fastException = MatchesDomain(rules->allowed_domains, host) ||
                             rules->allowed_patterns.Matches(requestURL);
  bool scopedHit[4];
  [self collectScopedHits:rules
                     host:host
              requestURL:requestURL
               frameHost:openerHost
                 typeBit:kAdTypeDocument
               popupPath:YES
                    hits:scopedHit];
  return [self decideBlock:fastBlock
            fastException:fastException
                scopedHit:scopedHit];
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
  std::string script =
      "(()=>{const c=\"" + EscapeJavaScriptString(css) +
      "\",a=()=>{const r=document.documentElement;if(!r){requestAnimationFrame(a);return;}"
      "let s=document.getElementById('lean-adblock-css');if(!s){s=document.createElement('style');"
      "s.id='lean-adblock-css';r.appendChild(s);}s.textContent=c;};a();})();";
  if (IsYouTubeHost(host)) {
    script += YouTubeAdSkipScript();
  }
  return script;
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

- (BOOL)adBlockingSnapshot {
  return _adBlockingEnabled.load();
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

- (void)executeJavaScript:(NSString *)script {
  if (!script || script.length == 0) {
    return;
  }
  std::string snippet = [script UTF8String];
  CEFBrowserHost *selfRef = self;
  PostToUI([selfRef, snippet] {
    if (!selfRef->_browser) {
      return;
    }
    CefRefPtr<CefFrame> frame = selfRef->_browser->GetMainFrame();
    if (!frame) {
      return;
    }
    frame->ExecuteJavaScript(snippet, frame->GetURL(), 0);
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
                              domainSelectors:(NSDictionary<NSString *, NSArray<NSString *> *> *)domainSelectors
                                 networkRules:(NSArray<NSDictionary *> *)networkRules {
  (void)blockedDomains; (void)allowedDomains; (void)blockedPatterns;
  (void)allowedPatterns; (void)globalSelectors; (void)domainSelectors;
  (void)networkRules;
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
- (void)executeJavaScript:(NSString *)script { (void)script; }
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
