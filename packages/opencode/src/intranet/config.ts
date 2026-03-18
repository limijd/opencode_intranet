// OpenCode Intranet Configuration
// When OPENCODE_INTRANET=1 is set, all external network access is disabled.
// Only openai-compatible providers connecting to internal LLM services are allowed.

export const INTRANET = process.env.OPENCODE_INTRANET === "1"
