#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns one CEF browser windowed into an NSView. All callbacks fire on the
/// main thread. All methods are safe to call from the main thread; work is
/// hopped to the CEF UI thread internally. Without CEF headers at build time
/// every method is a no-op and creation returns NO.
@interface CEFBrowserHost : NSObject

+ (void)configureAdBlockerWithBlockedDomains:(NSArray<NSString *> *)blockedDomains
                              allowedDomains:(NSArray<NSString *> *)allowedDomains
                             blockedPatterns:(NSArray<NSString *> *)blockedPatterns
                             allowedPatterns:(NSArray<NSString *> *)allowedPatterns
                             globalSelectors:(NSArray<NSString *> *)globalSelectors
                             domainSelectors:(NSDictionary<NSString *, NSArray<NSString *> *> *)domainSelectors
    NS_SWIFT_NAME(configureAdBlocker(blockedDomains:allowedDomains:blockedPatterns:allowedPatterns:globalSelectors:domainSelectors:));

/// Fired once the underlying CefBrowser exists.
@property (nonatomic, copy, nullable) void (^onCreated)(void);
@property (nonatomic, copy, nullable) void (^onTitle)(NSString *title);
@property (nonatomic, copy, nullable) void (^onURL)(NSString *urlString);
@property (nonatomic, copy, nullable) void (^onLoadingState)(BOOL isLoading, BOOL canGoBack, BOOL canGoForward);
@property (nonatomic, copy, nullable) void (^onFaviconURLs)(NSArray<NSString *> *urls);
@property (nonatomic, copy, nullable) void (^onLoadError)(NSString *failedURLString, NSString *errorText);
/// Renderer died (crash, OOM, Cloud failure, or launch failure).
/// Status is a short string like CRASHED, OOM, WAS_KILLED, LAUNCH_FAILED.
@property (nonatomic, copy, nullable) void (^onRendererTerminated)(NSString *statusName);
/// Page called window.close().
@property (nonatomic, copy, nullable) void (^onClose)(void);
/// Popup blocked (v1: opened as a plain new tab; window.opener handshake N/A).
@property (nonatomic, copy, nullable) void (^onPopupURL)(NSString *urlString);

@property (nonatomic, copy, nullable) void (^onJSAlert)(NSString *message, long long dialogId);
@property (nonatomic, copy, nullable) void (^onJSConfirm)(NSString *message, long long dialogId);
@property (nonatomic, copy, nullable) void (^onJSPrompt)(NSString *message, NSString *defaultText, long long dialogId);
@property (nonatomic, copy, nullable) void (^onAuthChallenge)(NSString *host, NSString *realm, long long challengeId);
@property (nonatomic, copy, nullable) void (^onMediaPermission)(NSString *originURLString, long long requestId);

@property (nonatomic, copy, nullable) void (^onDownloadStarted)(
    NSString *downloadId, NSString *suggestedName, NSString *sourceURLString, long long totalBytes);
@property (nonatomic, copy, nullable) void (^onDownloadProgress)(
    NSString *downloadId, long long receivedBytes, long long totalBytes);
@property (nonatomic, copy, nullable) void (^onDownloadFinished)(NSString *downloadId, NSString *fullPath);
@property (nonatomic, copy, nullable) void (^onDownloadFailed)(NSString *downloadId, BOOL cancelled);

/// Creates the browser as a child of `view`. Returns NO without CEF support.
- (BOOL)createInView:(NSView *)view initialURL:(nullable NSString *)urlString;

- (void)loadURL:(NSString *)urlString;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadFromOrigin;
- (void)stopLoading;
- (void)find:(NSString *)query;
- (void)stopFinding;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;
- (void)focus;
- (void)setAdBlockingEnabled:(BOOL)enabled NS_SWIFT_NAME(setAdBlockingEnabled(_:));
/// Runs a snippet in the main frame (page-feature injections such as font
/// smoothing that have no dedicated bridge call). No-op without a browser.
- (void)executeJavaScript:(NSString *)script;

/// Captures the visible page through Chromium's compositor.
- (void)captureSnapshotWithCompletion:(void (^)(NSData *_Nullable imageData))completion
    NS_SWIFT_NAME(captureSnapshot(completion:));

/// Complete a pending JS dialog / auth / media request by id.
- (void)completeJSDialog:(long long)dialogId ok:(BOOL)ok text:(nullable NSString *)text;
- (void)completeAuth:(long long)challengeId
            username:(nullable NSString *)username
            password:(nullable NSString *)password;
- (void)completeMediaPermission:(long long)requestId allow:(BOOL)allow;

/// Continue a started download once Swift has chosen the destination path.
- (void)continueDownload:(NSString *)downloadId path:(NSString *)path;

/// Cancel an in-flight download (real CEF cancel when the item exists;
/// otherwise drops the pending Continue).
- (void)cancelDownload:(NSString *)downloadId;

/// Force-close the browser. Safe to call more than once.
- (void)close;

/// Tell the renderer its parent view changed size.
- (void)notifyParentResized;

@end

NS_ASSUME_NONNULL_END
