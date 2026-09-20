import { createFileRoute } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import {
  GithubLogo,
  Sidebar as SidebarIcon,
  X,
  Lightning,
  ShieldCheck,
  Copy,
  Check,
} from '@phosphor-icons/react'

export const Route = createFileRoute('/')({ component: Home })

const XATTR_COMMAND =
  'sudo xattr -rd com.apple.quarantine /Applications/Lean.app'
const REPO_URL = 'https://github.com/DeepanshuMishraa/lean'
const RELEASES_URL = 'https://github.com/DeepanshuMishraa/lean/releases'
const LATEST_RELEASE_API =
  'https://api.github.com/repos/DeepanshuMishraa/lean/releases/latest'

type MacArch = 'arm64' | 'x86_64'

type GitHubRelease = {
  tag_name: string
  assets: Array<{ name: string; browser_download_url: string }>
}

// Safari and Firefox don't expose navigator.userAgentData and report "Intel"
// even on Apple Silicon, so sniffing can't tell them apart. Chrome-based
// browsers report the real architecture; everyone else defaults to arm64
// (correct for the vast majority of Macs) with a manual override link.
async function detectMacArch(): Promise<MacArch> {
  try {
    const userAgentData = (
      navigator as Navigator & {
        userAgentData?: {
          architecture?: string
          getHighEntropyValues?: (hints: Array<string>) => Promise<{
            architecture?: string
          }>
        }
      }
    ).userAgentData
    const architecture =
      userAgentData?.architecture ??
      (await userAgentData?.getHighEntropyValues?.(['architecture']))
        ?.architecture
    if (architecture === 'x86') return 'x86_64'
    if (architecture === 'arm') return 'arm64'
  } catch {
    // Fall through to the default below.
  }
  return 'arm64'
}

// Resolves the download button to the newest release DMG matching the
// visitor's chip. Falls back to the releases page until loaded or on error.
function useLatestDownload() {
  const [arch, setArch] = useState<MacArch>('arm64')
  const [release, setRelease] = useState<GitHubRelease | null>(null)

  useEffect(() => {
    let cancelled = false
    detectMacArch().then((detected) => {
      if (!cancelled) setArch(detected)
    })
    fetch(LATEST_RELEASE_API, {
      headers: { Accept: 'application/vnd.github+json' },
    })
      .then((res) => (res.ok ? res.json() : null))
      .then((data: GitHubRelease | null) => {
        if (!cancelled && data) setRelease(data)
      })
      .catch(() => {
        // Offline, rate-limited, or API error: keep the releases fallback.
      })
    return () => {
      cancelled = true
    }
  }, [])

  const asset = release?.assets.find((a) => a.name.endsWith(`-${arch}.dmg`))
  const otherArch: MacArch = arch === 'arm64' ? 'x86_64' : 'arm64'

  return {
    href: asset?.browser_download_url ?? RELEASES_URL,
    label: `Download Lean${release ? ` ${release.tag_name}` : ''} for ${
      arch === 'arm64' ? 'Apple Silicon' : 'Intel'
    }`,
    sublabel: release
      ? `${release.tag_name} · ${arch === 'arm64' ? 'Apple Silicon' : 'Intel'} · Free and open source`
      : 'Free and open source.',
    otherArchLabel:
      otherArch === 'arm64' ? 'Apple Silicon build' : 'Intel build',
    switchArch: () => setArch(otherArch),
    ready: release !== null,
  }
}

function AppleLogo({ className = 'w-4 h-4' }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      xmlSpace="preserve"
      viewBox="0 0 814 1000"
      className={className}
      fill="currentColor"
    >
      <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
    </svg>
  )
}

function Home() {
  const [isDownloadOpen, setIsDownloadOpen] = useState(false)
  const [countdown, setCountdown] = useState(5)
  const [hasDownloaded, setHasDownloaded] = useState(false)
  const [copiedCommand, setCopiedCommand] = useState(false)
  const download = useLatestDownload()

  const triggerDownload = () => {
    const a = document.createElement('a')
    a.href = download.href
    a.setAttribute('download', '')
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
  }

  const handleCopyCommand = () => {
    navigator.clipboard.writeText(XATTR_COMMAND)
    setCopiedCommand(true)
    setTimeout(() => setCopiedCommand(false), 2000)
  }

  const openDownloadModal = (e: React.MouseEvent) => {
    e.preventDefault()
    setCountdown(5)
    setHasDownloaded(false)
    setIsDownloadOpen(true)
  }

  useEffect(() => {
    if (!isDownloadOpen) return

    if (countdown > 0) {
      const timer = setTimeout(() => {
        setCountdown((c) => c - 1)
      }, 1000)
      return () => clearTimeout(timer)
    } else if (countdown === 0 && !hasDownloaded) {
      setHasDownloaded(true)
      triggerDownload()
    }
  }, [isDownloadOpen, countdown, hasDownloaded, download.href])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setIsDownloadOpen(false)
      }
    }
    if (isDownloadOpen) {
      window.addEventListener('keydown', handleKeyDown)
    }
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isDownloadOpen])

  return (
    <div className="min-h-screen bg-white text-[#111111] font-mono antialiased selection:bg-[#111111] selection:text-white">
      {/* Header */}
      <header className="max-w-4xl mx-auto px-6 pt-10 pb-5 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="w-2.5 h-2.5 rounded-full bg-[#111111]" />
          <span className="text-sm font-medium text-[#111111]">lean</span>
          <span className="text-[11px] text-[#777777] px-2 py-0.5 rounded border border-[#e5e5e5] bg-[#fafafa]">
            macOS
          </span>
        </div>

        <div className="flex items-center gap-5 text-xs text-[#666666]">
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 hover:text-[#111111] transition-colors"
          >
            <GithubLogo size={15} />
            <span>GitHub</span>
          </a>
          <a
            href={download.href}
            onClick={openDownloadModal}
            className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-[#111111] text-white hover:bg-[#2b2b2b] transition-all cursor-pointer"
          >
            <AppleLogo className="w-3.5 h-3.5" />
            <span>Download</span>
          </a>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-4xl mx-auto px-6 pt-7 pb-20">
        <div className="max-w-2xl">
          <h1 className="font-mono text-2xl sm:text-4xl font-normal text-[#111111] leading-snug">
            A quiet browser for your Mac.
          </h1>
          <p className="mt-4 text-xs sm:text-sm text-[#555555] leading-relaxed">
            Lean is a personal experiment, not a daily driver: the WebKit
            already on your Mac, wrapped in just enough native UI to browse. No
            bundled engine, no daemons, no accounts — a clean, minimal window
            onto the web.
          </p>

          {/* Download Action Button */}
          <div className="mt-8 flex flex-col sm:flex-row items-start sm:items-center gap-3">
            <a
              id="download"
              href={download.href}
              onClick={openDownloadModal}
              className="inline-flex items-center gap-2.5 px-5 py-2.5 rounded-xl bg-[#111111] text-white hover:bg-[#2b2b2b] active:scale-[0.98] transition-all text-xs font-medium shadow-sm cursor-pointer"
            >
              <AppleLogo className="w-4 h-4" />
              <span>{download.label}</span>
            </a>
          </div>

          <p className="mt-3 text-[11px] text-[#888888]">
            {download.sublabel}{' '}
            <button
              onClick={download.switchArch}
              className="underline underline-offset-2 hover:text-[#111111] transition-colors"
            >
              Need the {download.otherArchLabel}?
            </button>
          </p>
        </div>

        <img
          src="/hero-browser.png"
          alt="Lean displaying the website in a macOS browser window"
          width={2320}
          height={1504}
          fetchPriority="high"
          className="mt-14 w-full rounded-2xl"
        />

        {/* Feature Cards Grid */}
        <div className="mt-24 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                <Lightning size={16} weight="duotone" />
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Swift and WebKit
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Built natively for macOS on WebKit — no bundled engine, no
                  background daemons, no accounts. It starts fast and stays out
                  of the way.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
              <span>No bundled engine</span>
              <span>·</span>
              <span>Native UI</span>
            </div>
          </div>

          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                <SidebarIcon size={16} weight="duotone" />
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Zen mode and framing
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Hide the whole interface with one keystroke for pure
                  immersion, toggle the subtle window frame, or collapse the
                  sidebar tabs when you don't need them.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-blue-500" />
              <span>Zen mode</span>
              <span>·</span>
              <span>Collapsible sidebar</span>
            </div>
          </div>

          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                <ShieldCheck size={16} weight="duotone" />
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Quiet and private
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  No analytics, no accounts, and no tracking. Your history stays
                  on your machine in a local SQLite database, and WebKit content
                  blocking keeps ads and trackers out.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-amber-500" />
              <span>Local SQLite</span>
              <span>·</span>
              <span>Zero telemetry</span>
            </div>
          </div>
        </div>

        {/* Minimal Keyboard Shortcuts Strip */}
        <div className="mt-12 flex flex-wrap items-center justify-center gap-x-8 gap-y-3 text-xs text-[#666666]">
          <div className="flex items-center gap-2">
            <kbd className="px-2 py-0.5 text-[11px] rounded bg-[#fafafa] border border-[#e5e5e5] text-[#222222] shadow-[0_1px_0_rgba(0,0,0,0.05)]">
              ⌘T
            </kbd>
            <span>New Tab</span>
          </div>
          <div className="flex items-center gap-2">
            <kbd className="px-2 py-0.5 text-[11px] rounded bg-[#fafafa] border border-[#e5e5e5] text-[#222222] shadow-[0_1px_0_rgba(0,0,0,0.05)]">
              ⌘S
            </kbd>
            <span>Toggle Sidebar</span>
          </div>
          <div className="flex items-center gap-2">
            <kbd className="px-2 py-0.5 text-[11px] rounded bg-[#fafafa] border border-[#e5e5e5] text-[#222222] shadow-[0_1px_0_rgba(0,0,0,0.05)]">
              ⌘L
            </kbd>
            <span>Address Bar</span>
          </div>
          <div className="flex items-center gap-2">
            <kbd className="px-2 py-0.5 text-[11px] rounded bg-[#fafafa] border border-[#e5e5e5] text-[#222222] shadow-[0_1px_0_rgba(0,0,0,0.05)]">
              ⌘⇧Z
            </kbd>
            <span>Zen Mode</span>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="max-w-4xl mx-auto px-6 pt-16 pb-12 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-[#888888]">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-[#111111]" />
          <span className="font-medium text-[#111111]">lean</span>
          <span>· Made for macOS</span>
        </div>

        <div className="flex items-center gap-5">
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            className="hover:text-[#111111] transition-colors"
          >
            Source Code
          </a>
        </div>
      </footer>

      {/* Download & Gatekeeper Bypass Dialog */}
      {isDownloadOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/35 backdrop-blur-[2px]">
          <div
            className="absolute inset-0"
            onClick={() => setIsDownloadOpen(false)}
          />

          <div className="relative w-full max-w-lg bg-white rounded-2xl border border-[#e5e5e5] p-6 shadow-[0_24px_64px_rgba(0,0,0,0.12)] text-[#111111] font-mono space-y-5 select-text">
            {/* Dialog Header */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <AppleLogo className="w-4 h-4" />
                <span className="text-sm font-medium text-[#111111]">
                  Download Lean
                </span>
                <span className="text-[10px] text-[#777777] px-1.5 py-0.5 rounded border border-[#e5e5e5] bg-[#fafafa]">
                  macOS
                </span>
              </div>
              <button
                onClick={() => setIsDownloadOpen(false)}
                className="p-1 rounded-lg hover:bg-[#f0f0f0] text-[#777777] hover:text-[#111111] transition-colors cursor-pointer"
                title="Close"
              >
                <X size={15} />
              </button>
            </div>

            {/* Countdown / Auto-download status banner */}
            <div className="flex items-center justify-between text-xs py-2.5 px-3.5 rounded-xl bg-[#fafafa] border border-[#eeeeee]">
              <div className="flex items-center gap-2">
                <span
                  className={`w-2 h-2 rounded-full ${
                    hasDownloaded
                      ? 'bg-emerald-500'
                      : 'bg-amber-500 animate-pulse'
                  }`}
                />
                <span className="text-[#333333]">
                  {hasDownloaded
                    ? 'Download started'
                    : `Starting download in ${countdown}s...`}
                </span>
              </div>
              <button
                onClick={triggerDownload}
                className="underline underline-offset-2 text-[#666666] hover:text-[#111111] transition-colors cursor-pointer"
              >
                Start now
              </button>
            </div>

            {/* Gatekeeper explanation */}
            <div className="space-y-2 text-xs">
              <div className="flex items-center gap-2 font-medium text-[#111111]">
                <span>Gatekeeper Notice</span>
              </div>
              <p className="text-[#666666] leading-relaxed text-[12px]">
                Lean is currently not notarized with an Apple Developer
                certificate. macOS Gatekeeper will block it from opening by
                default on first launch.
              </p>
            </div>

            {/* Command Copy Box */}
            <div className="space-y-2">
              <label className="text-[11px] text-[#888888] uppercase tracking-wider block">
                Terminal Bypass Command
              </label>
              <div className="flex items-center justify-between gap-3 p-3 rounded-xl bg-[#111111] text-white text-xs font-mono">
                <code className="truncate selection:bg-neutral-700 selection:text-white">
                  {XATTR_COMMAND}
                </code>
                <button
                  onClick={handleCopyCommand}
                  className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 active:scale-95 text-white text-[11px] transition-all shrink-0 cursor-pointer"
                  title="Copy command"
                >
                  {copiedCommand ? (
                    <>
                      <Check size={13} className="text-emerald-400" />
                      <span>Copied</span>
                    </>
                  ) : (
                    <>
                      <Copy size={13} />
                      <span>Copy</span>
                    </>
                  )}
                </button>
              </div>
              <p className="text-[11px] text-[#888888] leading-normal">
                Move Lean to{' '}
                <code className="text-[#333333]">/Applications</code>, then run
                this command in Terminal to strip quarantine.
              </p>
            </div>

            {/* Modal Footer */}
            <div className="pt-2 flex items-center justify-between text-[11px] text-[#888888]">
              <span className="truncate max-w-[240px]">{download.label}</span>
              <button
                onClick={download.switchArch}
                className="underline underline-offset-2 hover:text-[#111111] transition-colors cursor-pointer shrink-0"
              >
                Switch to {download.otherArchLabel}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
