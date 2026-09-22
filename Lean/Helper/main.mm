#import <Cocoa/Cocoa.h>

#if __has_include("include/cef_app.h")
#include <string>
#include "include/cef_app.h"
#include "include/cef_process_message.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_library_loader.h"
#define LEAN_HAS_CEF 1

namespace {

// Current adblock toggle, pushed from the browser process ("lean-yt-ads"
// message). Baked into every fresh context; live pages are flipped via
// ExecuteJavaScript in OnProcessMessageReceived.
bool gYtAdsEnabled = true;

// Timing-critical half of the YouTube adblock: inline-data traps plus
// fetch/JSON.parse pruning plus the skip fallback. Runs at V8 context
// creation — before any page script, including inline
// ytInitialPlayerResponse — which browser-process injection
// (OnLoadStart) can never guarantee. The fuller browser-side copy in
// CEFBrowserHost.mm (YouTubeAdSkipScript) and PageScripts.youtubeAds stay
// as fallback/primary for WebKit; keep the three in sync.
std::string YtEarlyPatch(bool enabled) {
  return "(()=>{try{window.__leanYtAdsEnabled=" +
         std::string(enabled ? "true" : "false") +
         ";}catch(e){}"
         "try{var h='';try{h=location.hostname||'';}catch(e){}"
         "if(!/(^|\\.)youtube\\.com$|(^|\\.)youtu\\.be$/.test(h))return;}catch(e){return;}"
         "const stripS=(o)=>{for(const k of['adPlacements','playerAds','adSlots'])"
         "{try{if(Object.prototype.hasOwnProperty.call(o,k)){delete o[k];}}catch(e){}}};"
         "const strip=(o)=>{if(!o||typeof o!=='object')return;stripS(o);"
         "let lp=false;"
         "try{lp=!!(o.playabilityStatus||o.streamingData||(o.responseContext&&o.contents));}catch(e){}"
         "if(!lp)return;"
         "const st=[o],sn=[];let b=20000;"
         "while(st.length&&b-->0){const x=st.pop();"
         "if(!x||typeof x!=='object')continue;"
         "let dp=false;for(const s of sn){if(s===x){dp=true;break;}}"
         "if(dp)continue;sn.push(x);stripS(x);"
         "if(x instanceof Array){for(const v of x){st.push(v);}}"
         "else{for(const k in x){try{st.push(x[k]);}catch(e){}}}}};"
         "try{for(const n of['ytInitialPlayerResponse','ytInitialData'])"
         "{try{let c=window[n];"
         "try{if(window.__leanYtAdsEnabled){strip(c);}}catch(e){}"
         "Object.defineProperty(window,n,{configurable:true,"
         "get:()=>c,"
         "set:(v)=>{try{if(window.__leanYtAdsEnabled){strip(v);}}catch(e){}c=v;}});}"
         "catch(e){}}}catch(e){}"
         "try{if(!window.__leanYtFetchPatched&&!JSON.parse.__leanYtWrapped){"
         "try{window.__leanYtOrigFetch=window.fetch;}catch(e){}"
         "const p=JSON.parse;"
         "try{window.__leanYtOrigParse=p;}catch(e){}"
         "const wp=function(t,r){const v=p.call(this,t,r);"
         "try{if(window.__leanYtAdsEnabled){strip(v);}}catch(e){}return v;};"
         "try{wp.__leanYtWrapped=true;}catch(e){}"
         "JSON.parse=wp;"
         "try{if(window.Response&&Response.prototype&&!Response.prototype.__leanYtWrapped){"
         "const oj=Response.prototype.json;"
         "if(oj){const wj=function(){return oj.apply(this,arguments).then((val)=>{"
         "try{if(window.__leanYtAdsEnabled){strip(val);}}catch(e){}return val;});};"
         "try{wj.__leanYtWrapped=true;}catch(e){}"
         "Response.prototype.json=wj;}}}catch(e){}"
         "if(window.fetch&&!window.fetch.__leanYtWrapped){const f=window.fetch;"
         "window.fetch=function(u,o){let s='';"
         "try{s=typeof u==='string'?u:(u&&u.url)||'';}catch(e){}"
         "if(s.indexOf('/youtubei/v1/player')===-1&&s.indexOf('/youtubei/v1/next')===-1"
         "&&s.indexOf('/youtubei/v1/browse')===-1&&s.indexOf('/youtubei/v1/get_watch')===-1)"
         "{return f.apply(this,arguments);}"
         "return f.apply(this,arguments).then((r)=>{try{"
         "return r.text().then((t)=>{"
         "if(!window.__leanYtAdsEnabled||"
         "(t.indexOf('adPlacements')===-1&&t.indexOf('playerAds')===-1&&t.indexOf('adSlots')===-1"
         "&&t.indexOf('adBreakHeartbeatParams')===-1))"
         "{return new Response(t,{status:r.status,statusText:r.statusText,headers:r.headers});}"
         "const d=JSON.parse(t);strip(d);"
         "return new Response(JSON.stringify(d),{status:r.status,statusText:r.statusText,headers:r.headers});"
         "});}catch(e){return r;}});};"
         "try{window.fetch.__leanYtWrapped=true;}catch(e){}}"
         "try{window.__leanYtFetchPatched=true;}catch(e){}}}catch(e){}"
         "try{if(window.__leanYtSkip)return;window.__leanYtSkip=true;"
         "const q=(s)=>{try{return document.querySelector(s);}catch(e){return null;}};"
         "const qAll=(s)=>{try{return document.querySelectorAll(s);}catch(e){return[];}};"
         "const skipSel='.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-skip-ad-button-modern';"
         "const clickSkip=()=>{try{const bs=qAll(skipSel);"
         "for(let i=0;i<bs.length;i++){try{bs[i].click();}catch(e){}}"
         "const p=document.getElementById('movie_player');"
         "if(p&&typeof p.skipAd==='function'){try{p.skipAd();}catch(e){}}}catch(e){}};"
         "const seekPastAd=(v)=>{try{if(q(skipSel))return;"
         "const d=v.duration;"
         "if(isFinite(d)&&d>0&&d<180&&v.currentTime<d-0.5){try{v.currentTime=d-0.2;}catch(e){}}"
         "else if(!isFinite(d)||d>=180){try{"
         "if(v.seekable&&v.seekable.length){const e=v.seekable.end(v.seekable.length-1);"
         "if(isFinite(e)&&e>0&&v.currentTime<e-0.5){v.currentTime=e-0.2;}else{v.currentTime=100000;}}"
         "else{v.currentTime=100000;}}catch(e2){}}}catch(e){}};"
         "const tame=()=>{try{"
         "if(!window.__leanYtAdsEnabled)return;"
         "const inAd=!!q('.ad-showing');"
         "const vids=qAll('video');if(!vids||!vids.length)return;"
         "for(let i=0;i<vids.length;i++){const v=vids[i];try{"
         "if(inAd){"
         "if(!v.muted&&!v.dataset.leanMuted){v.dataset.leanMuted='1';}"
         "v.muted=true;"
         "if(v.dataset.leanOrigRate===undefined){try{v.dataset.leanOrigRate=String(v.playbackRate||1);}catch(e){}}"
         "try{v.playbackRate=16;}catch(e){}"
         "clickSkip();seekPastAd(v);"
         "try{if(v.paused){const ap=v.play();if(ap&&ap.catch){ap.catch(()=>{});}}}catch(e){}"
         "}else{"
         "if(v.dataset.leanMuted){v.muted=false;delete v.dataset.leanMuted;}"
         "if(v.dataset.leanOrigRate!==undefined){"
         "try{v.playbackRate=parseFloat(v.dataset.leanOrigRate)||1;}catch(e){try{v.playbackRate=1;}catch(e2){}}"
         "delete v.dataset.leanOrigRate;}"
         "try{if(v.paused&&!v.ended&&v.readyState>=2)"
         "{const cp=v.play();if(cp&&cp.catch){cp.catch(()=>{});}}}catch(e){}}"
         "}catch(e){}}"
         "try{if(inAd&&!q(skipSel)){const p=document.getElementById('movie_player');"
         "if(p&&typeof p.seekTo==='function'&&typeof p.getDuration==='function'){"
         "const ad=p.getDuration();"
         "if(isFinite(ad)&&ad>0&&ad<180){try{p.seekTo(ad,true);}catch(e){}}}}}catch(e){}"
         "}catch(e){}};"
         "const start=()=>{try{"
         "if(!window.__leanYtAdsEnabled)return;"
         "if(!document.documentElement){requestAnimationFrame(start);return;}"
         "setInterval(tame,120);"
         "new MutationObserver(()=>{try{"
         "if(!window.__leanYtAdsEnabled)return;"
         "tame();}catch(e){}})"
         ".observe(document.documentElement,{childList:true,subtree:true,attributes:true,"
         "attributeFilter:['class']});"
         "try{const hook=function(){const vs=qAll('video');"
         "for(let i=0;i<vs.length;i++){const v=vs[i];try{"
         "if(!v.__leanYtHooked){v.__leanYtHooked=true;"
         "v.addEventListener('timeupdate',()=>{try{"
         "if(window.__leanYtAdsEnabled&&q('.ad-showing')){tame();}}catch(e){}});"
         "v.addEventListener('play',()=>{try{"
         "if(window.__leanYtAdsEnabled&&q('.ad-showing')){tame();}}catch(e){}});"
         "}}catch(e){}}};"
         "hook();const bo=new MutationObserver(()=>{try{hook();}catch(e){}});"
         "bo.observe(document.documentElement,{childList:true,subtree:true});"
         "window.__leanYtVideoObserver=bo;}catch(e){}"
         "tame();"
         "}catch(e){}};"
         "start();}catch(e){}"
         "})();";
}

class LeanRenderApp : public CefApp, public CefRenderProcessHandler {
 public:
  LeanRenderApp() = default;

  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override {
    return this;
  }

  void OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefV8Context> context) override {
    // Earliest deterministic hook: the fresh main-world context, before any
    // page script (inline or external) runs in it.
    CefRefPtr<CefV8Value> ignored;
    CefRefPtr<CefV8Exception> exception;
    context->Eval(YtEarlyPatch(gYtAdsEnabled), CefString(), 0, ignored, exception);
    (void)browser;
    (void)frame;
  }

  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override {
    if (source_process != PID_BROWSER) {
      return false;
    }
    if (message->GetName().ToString() != "lean-yt-ads") {
      return false;
    }
    gYtAdsEnabled = message->GetArgumentList()->GetBool(0);
    // Flip live pages: new contexts bake the flag, existing ones need it set.
    std::string flip = std::string("try{window.__leanYtAdsEnabled=") +
                       (gYtAdsEnabled ? "true" : "false") + ";}catch(e){}";
    std::vector<CefString> ids;
    browser->GetFrameIdentifiers(ids);
    for (const CefString &id : ids) {
      CefRefPtr<CefFrame> frame = browser->GetFrameByIdentifier(id);
      if (frame) {
        frame->ExecuteJavaScript(flip, frame->GetURL(), 0);
      }
    }
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(LeanRenderApp);
};

}  // namespace
#endif  // __has_include("include/cef_app.h")

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
    CefRefPtr<LeanRenderApp> app(new LeanRenderApp);
    return CefExecuteProcess(main_args, app.get(), nullptr);
  }
#else
  (void)argc;
  (void)argv;
  return 1;
#endif
}
