// OpenCode Intranet Configuration
// When OPENCODE_INTRANET=1 is set, all external network access is disabled.
// Only openai-compatible providers connecting to internal LLM services are allowed.

export const INTRANET = process.env.OPENCODE_INTRANET === "1"

// Debug mode: log startup timing to help diagnose hangs
export const INTRANET_DEBUG = INTRANET && process.env.OPENCODE_INTRANET_DEBUG === "1"

if (INTRANET_DEBUG) {
  const start = performance.now()
  process.on("beforeExit", () => {
    console.error(`[intranet-debug] total runtime: ${(performance.now() - start).toFixed(0)}ms`)
  })
  console.error(`[intranet-debug] config loaded at ${new Date().toISOString()}`)
}
