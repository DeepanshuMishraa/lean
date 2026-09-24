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
  Bookmark,
  BookmarkSimple,
  MagnifyingGlass,
  Columns,
  Key,
  Lock,
  ArrowRight,
  Sliders,
  Sparkle,
  Tabs as TabsIcon,
  ArrowSquareOut,
  Folder,
  Star,
  Compass,
  Cpu,
} from '../icons'

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
    // Fall through to default
  }
  return 'arm64'
}

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
        // Offline or rate-limited fallback
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
      ? `${release.tag_name} · ${arch === 'arm64' ? 'Apple Silicon' : 'Intel'} · Free & Open Source`
      : 'Free & Open Source.',
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
      <header className="max-w-5xl mx-auto px-6 pt-10 pb-5 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="w-2.5 h-2.5 rounded-full bg-[#111111]" />
          <span className="text-sm font-medium tracking-tight text-[#111111]">
            lean
          </span>
          <span className="text-[11px] text-[#777777] px-2 py-0.5 rounded border border-[#e5e5e5] bg-[#fafafa]">
            macOS
          </span>
        </div>

        <nav className="flex items-center gap-6 text-xs text-[#666666]">
          <a
            href="#features"
            className="hidden sm:inline hover:text-[#111111] transition-colors"
          >
            Features
          </a>
          <a
            href="#shortcuts"
            className="hidden sm:inline hover:text-[#111111] transition-colors"
          >
            Shortcuts
          </a>
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
        </nav>
      </header>

      {/* Main Content */}
      <main className="max-w-5xl mx-auto px-6 pt-8 pb-24">
        {/* Hero Section */}
        <div className="max-w-2xl">
          <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded-full border border-[#e5e5e5] bg-[#fafafa] text-[11px] text-[#666666] mb-5">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
            <span>Native macOS browser on WebKit</span>
          </div>

          <h1 className="font-mono text-3xl sm:text-5xl font-normal text-[#111111] leading-tight tracking-tight">
            A quiet browser for your Mac.
          </h1>
          <p className="mt-5 text-xs sm:text-sm text-[#555555] leading-relaxed">
            Lean is built directly on the WebKit engine already on your Mac.
            Zero bundled Chromium bloat, zero background daemons, zero tracking.
            Wrapped in a quiet, keyboard-first interface designed to get out of
            your way.
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
              className="underline underline-offset-2 hover:text-[#111111] transition-colors cursor-pointer"
            >
              Need the {download.otherArchLabel}?
            </button>
          </p>
        </div>

        {/* Hero Window Graphic */}
        <div className="mt-12 rounded-2xl border border-[#eeeeee] p-1.5 bg-[#fafafa] shadow-[0_12px_40px_rgba(0,0,0,0.04)]">
          <img
            src="/hero-browser.png"
            alt="Lean displaying the browser in a minimal macOS window"
            width={2320}
            height={1504}
            fetchPriority="high"
            className="w-full rounded-xl border border-[#e5e5e5]"
          />
        </div>

        {/* Core Specs Bar */}
        <div className="mt-14 grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee]">
            <div className="text-[11px] text-[#888888] uppercase tracking-wider">
              Bundle Size
            </div>
            <div className="text-xl font-medium text-[#111111] mt-1">
              &lt; 15 MB
            </div>
            <div className="text-[11px] text-[#666666] mt-0.5">
              Zero Chromium bloat
            </div>
          </div>
          <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee]">
            <div className="text-[11px] text-[#888888] uppercase tracking-wider">
              Engine
            </div>
            <div className="text-xl font-medium text-[#111111] mt-1">
              Apple WebKit
            </div>
            <div className="text-[11px] text-[#666666] mt-0.5">
              Native system engine
            </div>
          </div>
          <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee]">
            <div className="text-[11px] text-[#888888] uppercase tracking-wider">
              Telemetry
            </div>
            <div className="text-xl font-medium text-[#111111] mt-1">
              0 Packets
            </div>
            <div className="text-[11px] text-[#666666] mt-0.5">
              No analytics or tracking
            </div>
          </div>
          <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee]">
            <div className="text-[11px] text-[#888888] uppercase tracking-wider">
              Storage
            </div>
            <div className="text-xl font-medium text-[#111111] mt-1">
              Local SQLite
            </div>
            <div className="text-[11px] text-[#666666] mt-0.5">
              Private on your disk
            </div>
          </div>
        </div>

        {/* Featured Showcase: Omnibar & Bookmarks Palette */}
        <div id="features" className="mt-28">
          <div className="flex items-center gap-2 text-xs uppercase tracking-widest text-[#888888] mb-3">
            <span className="w-1.5 h-1.5 rounded-full bg-[#111111]" />
            <span>Command Center</span>
          </div>
          <h2 className="text-2xl sm:text-3xl font-normal text-[#111111] tracking-tight">
            Built for speed and keyboard mastery.
          </h2>

          <div className="mt-8 grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Omnibar Card */}
            <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between">
                  <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                    <MagnifyingGlass size={16} />
                  </div>
                  <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#444444] shadow-xs">
                    ⌘L
                  </kbd>
                </div>
                <h3 className="text-sm font-medium text-[#111111] uppercase tracking-wider mt-4">
                  Floating Omnibar
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Unified command palette for URLs, search, open tabs, and
                  browsing history. Navigate suggestions with arrow keys, and
                  press{' '}
                  <kbd className="px-1.5 py-0.2 rounded bg-white border border-[#e5e5e5] text-[#222]">
                    →
                  </kbd>{' '}
                  to fill the input field instantly.
                </p>
              </div>

              {/* Omnibar Mockup */}
              <div className="mt-6 p-3 rounded-xl bg-white border border-[#e5e5e5] shadow-xs space-y-2">
                <div className="flex items-center gap-2 px-2.5 py-1.5 rounded-lg bg-[#fafafa] border border-[#eeeeee] text-xs">
                  <MagnifyingGlass size={13} className="text-[#888888]" />
                  <span className="text-[#111111]">github.com/lean</span>
                  <span className="ml-auto text-[10px] text-[#888888]">
                    → to fill
                  </span>
                </div>
                <div className="space-y-1 text-[11px]">
                  <div className="flex items-center justify-between px-2.5 py-1 rounded-md bg-[#f5f5f5] text-[#111111]">
                    <div className="flex items-center gap-2 truncate">
                      <span className="w-1.5 h-1.5 rounded-full bg-blue-500" />
                      <span className="truncate">DeepanshuMishraa/lean</span>
                    </div>
                    <span className="text-[10px] text-[#777777] shrink-0">
                      Switch Tab
                    </span>
                  </div>
                  <div className="flex items-center justify-between px-2.5 py-1 rounded-md text-[#555555]">
                    <div className="flex items-center gap-2 truncate">
                      <span className="w-1.5 h-1.5 rounded-full bg-neutral-300" />
                      <span className="truncate">github.com/releases</span>
                    </div>
                    <span className="text-[10px] text-[#888888] shrink-0">
                      History
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Bookmarks Palette Card */}
            <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between">
                  <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                    <BookmarkSimple size={16} />
                  </div>
                  <div className="flex items-center gap-1.5">
                    <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#444444] shadow-xs">
                      ⌘B
                    </kbd>
                    <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#444444] shadow-xs">
                      ⌘D
                    </kbd>
                  </div>
                </div>
                <h3 className="text-sm font-medium text-[#111111] uppercase tracking-wider mt-4">
                  Bookmarks & Folders
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Fast bookmarks palette with custom folder support. Press{' '}
                  <kbd className="px-1.5 py-0.2 rounded bg-white border border-[#e5e5e5] text-[#222]">
                    ←
                  </kbd>{' '}
                  /{' '}
                  <kbd className="px-1.5 py-0.2 rounded bg-white border border-[#e5e5e5] text-[#222]">
                    →
                  </kbd>{' '}
                  to cycle folders, fuzzy search items, and bookmark any page
                  with a sleek confirmation dialog.
                </p>
              </div>

              {/* Bookmarks Mockup */}
              <div className="mt-6 p-3 rounded-xl bg-white border border-[#e5e5e5] shadow-xs space-y-2.5">
                {/* Folder Strip */}
                <div className="flex items-center gap-1.5 text-[10px] overflow-hidden">
                  <span className="px-2 py-0.5 rounded-md bg-[#111111] text-white flex items-center gap-1">
                    <Star size={10} className="text-amber-400" />
                    <span>Favorites</span>
                  </span>
                  <span className="px-2 py-0.5 rounded-md bg-[#f0f0f0] text-[#555555] flex items-center gap-1">
                    <Folder size={10} />
                    <span>Work</span>
                  </span>
                  <span className="px-2 py-0.5 rounded-md bg-[#f0f0f0] text-[#555555] flex items-center gap-1">
                    <Folder size={10} />
                    <span>Dev</span>
                  </span>
                </div>
                {/* Sample Rows */}
                <div className="space-y-1 text-[11px]">
                  <div className="flex items-center justify-between px-2.5 py-1 rounded-md bg-[#f5f5f5] text-[#111111]">
                    <span className="truncate">Hacker News</span>
                    <span className="text-[9px] px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5] text-[#777]">
                      news.ycombinator.com
                    </span>
                  </div>
                  <div className="flex items-center justify-between px-2.5 py-1 rounded-md text-[#555555]">
                    <span className="truncate">GitHub Dashboard</span>
                    <span className="text-[9px] px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5] text-[#777]">
                      github.com
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Feature Grid: 6 Pillars */}
        <div className="mt-14 grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Zen Mode */}
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                  <Sparkle size={16} />
                </div>
                <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#444444] shadow-xs">
                  ⌘⇧Z
                </kbd>
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Zen Mode & Dynamic Frame
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Drop all window chrome for pure web immersion. A hairline
                  border gently tints to reflect your current page accents.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-purple-500" />
              <span>Distraction-free</span>
              <span>·</span>
              <span>Adaptive border</span>
            </div>
          </div>

          {/* Split View */}
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                  <Columns size={16} />
                </div>
                <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#444444] shadow-xs">
                  ⌥↩
                </kbd>
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Split View Browsing
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Open links side-by-side in dual active panes. Compare
                  references, review documentation, or multitask without window
                  clutter.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-blue-500" />
              <span>Dual panes</span>
              <span>·</span>
              <span>Parallel workflow</span>
            </div>
          </div>

          {/* Password Vault */}
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                  <Key size={16} />
                </div>
                <span className="text-[10px] text-[#777777] px-2 py-0.5 rounded border border-[#e5e5e5] bg-white">
                  Keychain
                </span>
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Keychain Password Vault
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Integrated with Apple Keychain. Secure in-page autofill
                  suggestions with zero cloud sync or external password
                  extensions required.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-amber-500" />
              <span>Apple Keychain</span>
              <span>·</span>
              <span>Native autofill</span>
            </div>
          </div>

          {/* 1-Click Migration */}
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                <Compass size={16} />
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  1-Click Browser Migration
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Instant data migration from Chrome, Arc, Safari, Brave, and
                  Edge. Transfer bookmarks, browsing history, and passwords with
                  one click.
                </p>
              </div>
            </div>
            <div className="mt-6 flex flex-wrap gap-1.5 text-[10px] text-[#666666]">
              <span className="px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5]">
                Chrome
              </span>
              <span className="px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5]">
                Arc
              </span>
              <span className="px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5]">
                Safari
              </span>
              <span className="px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5]">
                Brave
              </span>
              <span className="px-1.5 py-0.5 rounded bg-white border border-[#e5e5e5]">
                Edge
              </span>
            </div>
          </div>

          {/* Ad & Tracker Blocking */}
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                <ShieldCheck size={16} />
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  Engine-Level Ad Blocking
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Pre-compiled WebKit content rules block intrusive ads, cookie
                  banners, and telemetry before network requests fire, saving
                  CPU cycles.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
              <span>Zero overhead</span>
              <span>·</span>
              <span>WebKit rules</span>
            </div>
          </div>

          {/* Extensions */}
          <div className="p-6 rounded-2xl bg-[#fafafa] border border-[#eeeeee] flex flex-col justify-between">
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="w-8 h-8 rounded-lg bg-white border border-[#e5e5e5] flex items-center justify-center text-[#111111] shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
                  <Lightning size={16} />
                </div>
                <span className="text-[10px] text-[#777777] px-2 py-0.5 rounded border border-[#e5e5e5] bg-white">
                  macOS 15.4+
                </span>
              </div>
              <div>
                <h3 className="text-xs font-medium text-[#111111] uppercase tracking-wider">
                  WebExtension Support
                </h3>
                <p className="text-xs text-[#555555] leading-relaxed mt-2">
                  Install Chrome Web Store extensions with per-install security
                  reviews, sandboxed runtime permissions, and isolated storage.
                </p>
              </div>
            </div>
            <div className="mt-6 flex items-center gap-2 text-[11px] text-[#888888]">
              <span className="w-1.5 h-1.5 rounded-full bg-blue-500" />
              <span>WebExtensions</span>
              <span>·</span>
              <span>Permission review</span>
            </div>
          </div>
        </div>

        {/* Minimal Keyboard Shortcuts Strip */}
        <div id="shortcuts" className="mt-28">
          <div className="flex items-center gap-2 text-xs uppercase tracking-widest text-[#888888] mb-3">
            <span className="w-1.5 h-1.5 rounded-full bg-[#111111]" />
            <span>Keyboard First</span>
          </div>
          <h2 className="text-2xl sm:text-3xl font-normal text-[#111111] tracking-tight">
            Designed for hands on the keyboard.
          </h2>

          <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">New Tab</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘T
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Address / Omnibar</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘L
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Bookmarks Palette</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘B
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Bookmark Current Page</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘D
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Open in Split View</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌥↩
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Fill URL Suggestion</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                →
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Toggle Sidebar</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘S
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Toggle Tab Bar</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘⇧T
              </kbd>
            </div>
            <div className="p-4 rounded-xl bg-[#fafafa] border border-[#eeeeee] flex items-center justify-between text-xs">
              <span className="text-[#555555]">Toggle Zen Mode</span>
              <kbd className="px-2 py-0.5 text-[11px] rounded bg-white border border-[#e5e5e5] text-[#222222] shadow-xs">
                ⌘⇧Z
              </kbd>
            </div>
          </div>
        </div>

        {/* Bottom CTA Card */}
        <div className="mt-28 p-8 rounded-2xl bg-[#fafafa] border border-[#eeeeee] text-center space-y-4">
          <h2 className="text-xl sm:text-2xl font-normal text-[#111111] tracking-tight">
            Ready for a quieter browsing experience?
          </h2>
          <p className="text-xs text-[#666666] max-w-lg mx-auto">
            Lightweight, native, open source, and built specifically for your
            Mac. Set Lean as your default browser in seconds.
          </p>
          <div className="pt-2 flex items-center justify-center gap-3">
            <a
              href={download.href}
              onClick={openDownloadModal}
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-[#111111] text-white hover:bg-[#2b2b2b] text-xs font-medium transition-all shadow-xs cursor-pointer"
            >
              <AppleLogo className="w-3.5 h-3.5" />
              <span>{download.label}</span>
            </a>
            <a
              href={REPO_URL}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white border border-[#e5e5e5] text-[#111111] hover:bg-[#f5f5f5] text-xs font-medium transition-all cursor-pointer"
            >
              <GithubLogo size={14} />
              <span>Source</span>
            </a>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="max-w-5xl mx-auto px-6 pt-12 pb-12 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-[#888888] border-t border-[#eeeeee]">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-[#111111]" />
          <span className="font-medium text-[#111111]">lean</span>
          <span>· Made for macOS · Free & Open Source</span>
        </div>

        <div className="flex items-center gap-5">
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            className="hover:text-[#111111] transition-colors"
          >
            GitHub
          </a>
          <a
            href={RELEASES_URL}
            target="_blank"
            rel="noreferrer"
            className="hover:text-[#111111] transition-colors"
          >
            Releases
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
