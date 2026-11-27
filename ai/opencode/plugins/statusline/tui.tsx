// Statusline for the OpenCode TUI: subscription limits for OpenAI, Kimi and OpenCode Go.
// Limits are fetched from the local OpenCode server and the providers' own usage endpoints.
import { Plugin } from "@opencode/plugin/tui"
import { createSignal } from "solid-js"

type Window = {
  label: string
  percent: number
  resetsAt?: number
  limited?: boolean
}

type Provider = {
  id: "openai" | "kimi" | "go"
  name: string
  plan?: string
  windows: Window[]
  error?: string
}

type Snapshot = {
  at: number
  providers: Provider[]
  error?: string
}

type Seg = { text: string; fg?: any; bg?: any }

const OPENAI_URLS = [
  "https://chatgpt.com/backend-api/wham/usage",
  "https://chatgpt.com/backend-api/codex/usage",
]

const KIMI_HOSTS: Record<string, string> = {
  "kimi-code-plan-global": "https://api.kimi.ai/coding/v1",
  "kimi-code-plan-cn": "https://api.kimi.com/coding/v1",
}

const CACHE_MS = 60_000
let cache: Snapshot | undefined
let inflight: Promise<Snapshot> | undefined

function toMs(value: number | undefined) {
  if (!value) return undefined
  return value > 1e12 ? value : value * 1000
}

function timeMs(value: string | undefined) {
  if (!value) return undefined
  const ms = Date.parse(value)
  return Number.isFinite(ms) ? ms : undefined
}

function ratio(value: unknown) {
  const n = Number(value)
  if (!Number.isFinite(n)) return 0
  return n <= 1 ? n * 100 : n
}

function planName(value: unknown) {
  if (typeof value !== "string" || !value) return undefined
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function windowLabel(seconds: number | undefined) {
  if (!seconds || seconds <= 0) return "limit"
  if (seconds >= 86400) return `${Math.round(seconds / 86400)}d`
  if (seconds >= 3600) return `${Math.round(seconds / 3600)}h`
  return `${Math.max(1, Math.round(seconds / 60))}m`
}

function kimiWindowLabel(window: any) {
  const duration = Number(window?.duration)
  const unit = String(window?.timeUnit ?? "")
  if (!Number.isFinite(duration) || duration <= 0) return undefined
  if (unit.includes("DAY")) return `${duration}d`
  if (unit.includes("HOUR")) return `${duration}h`
  if (unit.includes("MINUTE")) {
    return duration >= 60 && duration % 60 === 0 ? `${duration / 60}h` : `${duration}m`
  }
  return undefined
}

function pct(value: number) {
  const n = Math.max(0, Number(value) || 0)
  if (n >= 10 || n === 0) return `${Math.round(n)}%`
  return `${n.toFixed(1).replace(/\.0$/, "")}%`
}

function formatReset(at: number, now: number) {
  const diff = at - now
  if (diff < 60_000) return "now"
  const minutes = Math.floor(diff / 60_000)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  const restMinutes = minutes % 60
  if (hours < 24) return restMinutes ? `${hours}h ${restMinutes}m` : `${hours}h`
  const days = Math.floor(hours / 24)
  const restHours = hours % 24
  return restHours ? `${days}d ${restHours}h` : `${days}d`
}

const BAR_CELLS = 5
const PARTIAL = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

function barParts(value: number) {
  const percent = Math.max(0, Math.min(100, Number(value) || 0))
  const stepsPerCell = PARTIAL.length
  const steps = Math.max(percent > 0 ? 1 : 0, Math.round(percent * BAR_CELLS * stepsPerCell / 100))
  const full = Math.floor(steps / stepsPerCell)
  const partial = PARTIAL[steps % stepsPerCell]
  const empty = BAR_CELLS - full - (partial ? 1 : 0)
  return { full, partial, empty }
}

function maxWindow(provider: Provider) {
  return provider.windows.reduce<Window | undefined>((best, window) => {
    if (!best) return window
    if (window.percent > best.percent) return window
    if (window.percent === best.percent) {
      if ((window.resetsAt ?? Infinity) < (best.resetsAt ?? Infinity)) return window
    }
    return best
  }, undefined)
}

function errorText(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  return message.length > 80 ? `${message.slice(0, 77)}…` : message
}

async function fetchOpenAI(credential: any): Promise<Provider | undefined> {
  const value = credential?.value
  if (!value?.access) return undefined
  const headers: Record<string, string> = {
    Authorization: `Bearer ${value.access}`,
    originator: "codex_cli_rs",
    "User-Agent": "codex_cli_rs/0.1.0",
    Accept: "application/json",
  }
  if (typeof value.metadata?.accountID === "string") {
    headers["chatgpt-account-id"] = value.metadata.accountID
  }

  let response: Response | undefined
  let lastError: unknown
  for (const url of OPENAI_URLS) {
    try {
      response = await fetch(url, { headers })
      if (response.ok || response.status !== 404) break
    } catch (error) {
      lastError = error
    }
  }
  if (!response) throw lastError ?? new Error("OpenAI usage unavailable")
  if (!response.ok) throw new Error(`OpenAI HTTP ${response.status}`)
  const data: any = await response.json()
  const limits = data?.rate_limit
  const windows: Window[] = []
  for (const raw of [limits?.primary_window, limits?.secondary_window]) {
    if (!raw) continue
    windows.push({
      label: windowLabel(Number(raw.limit_window_seconds)),
      percent: Number(raw.used_percent) || 0,
      resetsAt: toMs(Number(raw.reset_at)),
      limited: Boolean(limits?.limit_reached || data?.rate_limit_reached_type),
    })
  }
  return {
    id: "openai",
    name: "OPENAI",
    plan: planName(data?.plan_type),
    windows,
  }
}

async function fetchKimi(credential: any): Promise<Provider | undefined> {
  const value = credential?.value
  if (!value?.key) return undefined
  const bases = [
    KIMI_HOSTS[credential.integrationID],
    "https://api.kimi.ai/coding/v1",
    "https://api.kimi.com/coding/v1",
  ].filter((base, index, all) => Boolean(base) && all.indexOf(base) === index) as string[]

  const headers = {
    Authorization: `Bearer ${value.key}`,
    Accept: "application/json",
  }

  let usage: any
  let me: any
  let lastError: unknown
  for (const base of bases) {
    try {
      const response = await fetch(`${base}/usages`, { headers })
      if (!response.ok) {
        lastError = new Error(`Kimi HTTP ${response.status}`)
        continue
      }
      usage = await response.json()
      const profile = await fetch(`${base}/me`, { headers }).catch(() => undefined)
      if (profile?.ok) me = await profile.json().catch(() => undefined)
      break
    } catch (error) {
      lastError = error
    }
  }
  if (!usage) throw lastError ?? new Error("Kimi usage unavailable")

  const windows: Window[] = []
  const usages = usage.usages ?? {}
  if (usages.limit_5h) {
    windows.push({
      label: "5h",
      percent: ratio(usages.limit_5h.used_ratio),
      resetsAt: timeMs(usages.limit_5h.reset_time),
    })
  }
  if (usages.limit_month_total) {
    windows.push({
      label: "30d",
      percent: ratio(usages.limit_month_total.used_ratio),
      resetsAt: timeMs(usages.limit_month_total.reset_time),
    })
  }
  if (windows.length === 0 && Array.isArray(usage.limits)) {
    for (const item of usage.limits) {
      const detail = item?.detail ?? item
      const limit = Number(detail?.limit)
      const remaining = Number(detail?.remaining)
      if (!Number.isFinite(limit) || limit <= 0) continue
      const used = Number.isFinite(remaining) ? limit - remaining : Number(detail?.used) || 0
      windows.push({
        label: kimiWindowLabel(item?.window) ?? "limit",
        percent: (used / limit) * 100,
        resetsAt: timeMs(detail?.resetTime),
      })
    }
  }

  return {
    id: "kimi",
    name: "KIMI",
    plan: typeof me?.user_level_name === "string" ? me.user_level_name : undefined,
    windows,
  }
}

async function fetchGo(client: any, location: any): Promise<Provider | undefined> {
  const usage = client.experimental?.usage ?? client.usage
  const response: any = await usage.limits({ location })
  const data = response?.data ?? response
  const go = data?.go
  if (!go) return undefined
  const windows: Window[] = []
  for (const [key, label] of [
    ["rolling", "5h"],
    ["weekly", "7d"],
    ["monthly", "30d"],
  ] as const) {
    const meter = go[key]
    if (!meter) continue
    windows.push({
      label,
      percent: Number(meter.percent) || 0,
      resetsAt: toMs(Number(meter.resetsAt)),
      limited: Boolean(meter.limited),
    })
  }
  return { id: "go", name: "GO", windows }
}

async function safe(id: Provider["id"], name: string, load: () => Promise<Provider | undefined>) {
  try {
    return await load()
  } catch (error) {
    return { id, name, windows: [], error: errorText(error) } satisfies Provider
  }
}

async function loadSnapshot(client: any, location: any): Promise<Snapshot> {
  let credentials: any[] = []
  let credentialsError: string | undefined
  try {
    const response: any = await client.credential.list()
    credentials = Array.isArray(response) ? response : (response?.data ?? [])
  } catch (error) {
    credentialsError = errorText(error)
  }

  const active = (predicate: (credential: any) => boolean) =>
    credentials.find((credential) => credential.active && predicate(credential)) ??
    credentials.find(predicate)

  const [openai, kimi, go] = await Promise.all([
    safe("openai", "OPENAI", () => fetchOpenAI(active((c) => c.integrationID === "openai"))),
    safe("kimi", "KIMI", () =>
      fetchKimi(active((c) => String(c.integrationID ?? "").startsWith("kimi-code-plan"))),
    ),
    safe("go", "GO", () => fetchGo(client, location)),
  ])

  return {
    at: Date.now(),
    providers: [openai, kimi, go].filter(Boolean) as Provider[],
    ...(credentialsError ? { error: `credentials: ${credentialsError}` } : {}),
  }
}

async function getSnapshot(client: any, location: any, force = false) {
  if (!force && cache && Date.now() - cache.at < CACHE_MS) return cache
  if (inflight) return inflight
  inflight = loadSnapshot(client, location)
    .then((snapshot) => {
      cache = snapshot
      return snapshot
    })
    .finally(() => {
      inflight = undefined
    })
  return inflight
}

function makePalette(theme: any) {
  const success = theme?.text?.feedback?.success
  const warning = theme?.text?.feedback?.warning
  const error = theme?.text?.feedback?.error
  return {
    text: theme?.text?.base,
    muted: theme?.text?.muted,
    faint: theme?.text?.faint ?? theme?.text?.muted,
    track: theme?.background?.raised?.max ?? theme?.text?.faint ?? theme?.text?.muted,
    success: success?.base ?? success ?? theme?.text?.muted,
    warning: warning?.base ?? warning ?? theme?.text?.muted,
    error: error?.base ?? error ?? theme?.text?.muted,
    providers: [
      theme?.categorical?.[0]?.[500] ?? theme?.hue?.accent?.[500] ?? theme?.text?.base,
      theme?.categorical?.[1]?.[500] ?? theme?.hue?.purple?.[500] ?? theme?.text?.base,
      theme?.categorical?.[2]?.[500] ?? theme?.hue?.green?.[500] ?? theme?.text?.base,
    ] as any[],
  }
}

function tone(palette: ReturnType<typeof makePalette>, window: Window) {
  if (window.limited || window.percent >= 85) return palette.error
  if (window.percent >= 50) return palette.warning
  return palette.success
}

type Variant = {
  bars: "none" | "max" | "all"
  all: boolean
  plan: boolean
  reset: "none" | "high" | "all"
  windowLabel: boolean
}

function providerSegments(
  provider: Provider,
  palette: ReturnType<typeof makePalette>,
  providerIndex: number,
  variant: Variant,
  now: number,
) {
  const segments: Seg[] = [{ text: provider.name, fg: palette.providers[providerIndex] }]
  if (variant.plan && provider.plan) {
    segments.push({ text: ` ${provider.plan.toLowerCase()}`, fg: palette.faint })
  }
  if (provider.error) {
    segments.push({ text: " !", fg: palette.error })
    return segments
  }

  const primary = maxWindow(provider)
  const windows = variant.all ? provider.windows : primary ? [primary] : []
  windows.forEach((window, index) => {
    const color = tone(palette, window)
    segments.push({ text: index === 0 ? " " : " · ", fg: palette.faint })
    if (variant.bars === "all" || (variant.bars === "max" && window === primary)) {
      const { full, partial, empty } = barParts(window.percent)
      if (full) segments.push({ text: " ".repeat(full), bg: color })
      if (partial) segments.push({ text: partial, fg: color, bg: palette.track })
      if (empty) segments.push({ text: " ".repeat(empty), bg: palette.track })
      segments.push({ text: " ", fg: palette.faint })
    }
    segments.push({ text: pct(window.percent), fg: color })
    if (variant.windowLabel) segments.push({ text: ` ${window.label}`, fg: palette.faint })
    const wantReset =
      variant.reset === "all" ||
      (variant.reset === "high" && (window.limited || window.percent >= 50))
    if (wantReset && window === primary && window.resetsAt) {
      segments.push({ text: ` (${formatReset(window.resetsAt, now)})`, fg: palette.faint })
    }
  })
  return segments
}

function renderLine(
  snapshot: Snapshot | undefined,
  palette: ReturnType<typeof makePalette>,
  columns: number,
  now: number,
) {
  if (!snapshot) return [{ text: "· · ·", fg: palette.faint }]

  const providers = snapshot.providers.filter((provider) => provider.error || provider.windows.length > 0)
  if (providers.length === 0) {
    return [{ text: snapshot.error ?? "limits unavailable", fg: palette.faint }]
  }

  const variants: Variant[] = [
    { bars: "all", all: true, plan: true, reset: "all", windowLabel: true },
    { bars: "all", all: true, plan: true, reset: "high", windowLabel: true },
    { bars: "all", all: true, plan: true, reset: "none", windowLabel: true },
    { bars: "all", all: true, plan: false, reset: "none", windowLabel: true },
    { bars: "max", all: true, plan: true, reset: "high", windowLabel: true },
    { bars: "max", all: true, plan: false, reset: "high", windowLabel: true },
    { bars: "max", all: true, plan: false, reset: "none", windowLabel: true },
    { bars: "none", all: true, plan: true, reset: "none", windowLabel: true },
    { bars: "none", all: true, plan: false, reset: "none", windowLabel: true },
    { bars: "none", all: false, plan: false, reset: "none", windowLabel: true },
    { bars: "none", all: false, plan: false, reset: "none", windowLabel: false },
  ]

  const available = Math.max(20, columns - 2)
  let fallback: Seg[] = []
  for (const variant of variants) {
    const segments: Seg[] = []
    providers.forEach((provider, index) => {
      const colorIndex = provider.id === "openai" ? 0 : provider.id === "kimi" ? 1 : 2
      if (index > 0) segments.push({ text: " ║ ", fg: palette.text })
      segments.push(...providerSegments(provider, palette, colorIndex, variant, now))
    })
    fallback = segments
    const length = segments.reduce((total, segment) => total + [...segment.text].length, 0)
    if (length <= available) return segments
  }
  return fallback
}

function details(snapshot: Snapshot | undefined, now: number) {
  if (!snapshot) return "Still loading usage limits…"
  const lines: string[] = []
  for (const provider of snapshot.providers) {
    const head = `${provider.name}${provider.plan ? ` · ${provider.plan}` : ""}`
    lines.push(head)
    if (provider.error) {
      lines.push(`  ⚠ ${provider.error}`)
      continue
    }
    if (provider.windows.length === 0) {
      lines.push("  no data")
      continue
    }
    for (const window of provider.windows) {
      const { full, partial, empty } = barParts(window.percent)
      const bar = "█".repeat(full) + partial + "░".repeat(empty)
      const percent = pct(window.percent).padStart(5)
      const remaining = window.resetsAt ? formatReset(window.resetsAt, now) : undefined
      const reset = remaining ? (remaining === "now" ? "resets now" : `resets in ${remaining}`) : ""
      lines.push(`  ${window.label.padEnd(3)}  ${bar} ${percent}   ${reset}`.trimEnd())
    }
  }
  if (snapshot.error) lines.push("", `⚠ ${snapshot.error}`)
  return lines.join("\n")
}

function Statusline(props: {
  palette: ReturnType<typeof makePalette>
  state: () => Snapshot | undefined
  columns: () => number
  tick: () => number
  indent?: number
}) {
  const [width, setWidth] = createSignal(props.columns())
  const segments = () => {
    props.tick()
    const now = Date.now()
    return renderLine(props.state(), props.palette, width(), now)
  }

  return (
    <box
      width="100%"
      height={1}
      flexShrink={0}
      paddingLeft={props.indent ?? 0}
      onSizeChange={function () {
        setWidth((this as any).width)
      }}
    >
      <text wrapMode="none" truncate>
        {segments().map((segment) => (
          <span style={{ fg: segment.fg, bg: segment.bg }}>{segment.text}</span>
        ))}
      </text>
    </box>
  )
}

export default Plugin.define({
  id: "statusline.tui",
  async setup(context) {
    const location = context.location ?? context.data.location.default()
    const palette = makePalette(context.theme)
    const [state, setState] = createSignal<Snapshot | undefined>(cache)
    const [columns, setColumns] = createSignal(process.stdout.columns || 120)
    const [tick, setTick] = createSignal(0)

    const refresh = async (force = false) => {
      try {
        setState(await getSnapshot(context.client, location, force))
      } catch {
        // Keep the last good snapshot.
      }
    }

    const resize = () => setColumns(process.stdout.columns || 120)
    try {
      process.stdout.on("resize", resize)
    } catch {
      // Not a TTY; keep the initial width.
    }

    let turns = 0
    let pendingRefresh: ReturnType<typeof setTimeout> | undefined
    const timer = setInterval(() => {
      setTick((value) => value + 1)
      if (++turns % 2 === 0) void refresh()
    }, 30_000)

    const off = context.data.on("session.execution.succeeded", () => {
      if (pendingRefresh) clearTimeout(pendingRefresh)
      pendingRefresh = setTimeout(() => void refresh(true), 2_500)
    })

    context.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "statusline.limits",
          title: "Usage limits (OpenAI, Kimi, Go)",
          group: "Statusline",
          palette: true,
          slash: { name: "limits" },
          run: async () => {
            await refresh(true)
            await context.ui.dialog.alert({
              title: "Usage limits",
              message: details(state(), Date.now()),
            })
          },
        },
      ],
    }))

    context.ui.slot({
      append: "session.composer.top",
      render: () => (
        <Statusline palette={palette} state={state} columns={columns} tick={tick} />
      ),
    })

    context.ui.slot({
      append: "home.footer",
      render: () => (
        <Statusline palette={palette} state={state} columns={columns} tick={tick} indent={2} />
      ),
    })

    void refresh()

    return () => {
      clearInterval(timer)
      if (pendingRefresh) clearTimeout(pendingRefresh)
      try {
        process.stdout.off("resize", resize)
      } catch {
        // Ignore.
      }
      off?.()
    }
  },
})
