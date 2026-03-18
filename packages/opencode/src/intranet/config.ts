// OpenCode Intranet Configuration
// When OPENCODE_INTRANET=1 is set, all external network access is disabled.
// Only openai-compatible providers connecting to internal LLM services are allowed.

export const INTRANET = process.env.OPENCODE_INTRANET === "1"

// Debug mode: OPENCODE_INTRANET_DEBUG=1 logs timestamps at every startup phase
export const INTRANET_DEBUG = process.env.OPENCODE_INTRANET_DEBUG === "1"

const t0 = performance.now()

export function dbg(label: string) {
  if (!INTRANET_DEBUG) return
  const ms = (performance.now() - t0).toFixed(0)
  console.error(`[dbg +${ms}ms] ${label}`)
}

dbg("intranet/config loaded")
