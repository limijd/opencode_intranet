- To regenerate the JavaScript SDK, run `./packages/sdk/js/script/build.ts`.
- ALWAYS USE PARALLEL TOOLS WHEN APPLICABLE.
- The default branch in this repo is `dev`.
- Local `main` ref may not exist; use `dev` or `origin/dev` for diffs.
- Prefer automation: execute requested actions without confirmation unless blocked by missing info or safety/irreversibility.

## Style Guide

### General Principles

- Keep things in one function unless composable or reusable
- Avoid `try`/`catch` where possible
- Avoid using the `any` type
- Prefer single word variable names where possible
- Use Bun APIs when possible, like `Bun.file()`
- Rely on type inference when possible; avoid explicit type annotations or interfaces unless necessary for exports or clarity
- Prefer functional array methods (flatMap, filter, map) over for loops; use type guards on filter to maintain type inference downstream

### Naming

Prefer single word names for variables and functions. Only use multiple words if necessary.

### Naming Enforcement (Read This)

THIS RULE IS MANDATORY FOR AGENT WRITTEN CODE.

- Use single word names by default for new locals, params, and helper functions.
- Multi-word names are allowed only when a single word would be unclear or ambiguous.
- Do not introduce new camelCase compounds when a short single-word alternative is clear.
- Before finishing edits, review touched lines and shorten newly introduced identifiers where possible.
- Good short names to prefer: `pid`, `cfg`, `err`, `opts`, `dir`, `root`, `child`, `state`, `timeout`.
- Examples to avoid unless truly required: `inputPID`, `existingClient`, `connectTimeout`, `workerPath`.

```ts
// Good
const foo = 1
function journal(dir: string) {}

// Bad
const fooBar = 1
function prepareJournal(dir: string) {}
```

Reduce total variable count by inlining when a value is only used once.

```ts
// Good
const journal = await Bun.file(path.join(dir, "journal.json")).json()

// Bad
const journalPath = path.join(dir, "journal.json")
const journal = await Bun.file(journalPath).json()
```

### Destructuring

Avoid unnecessary destructuring. Use dot notation to preserve context.

```ts
// Good
obj.a
obj.b

// Bad
const { a, b } = obj
```

### Variables

Prefer `const` over `let`. Use ternaries or early returns instead of reassignment.

```ts
// Good
const foo = condition ? 1 : 2

// Bad
let foo
if (condition) foo = 1
else foo = 2
```

### Control Flow

Avoid `else` statements. Prefer early returns.

```ts
// Good
function foo() {
  if (condition) return 1
  return 2
}

// Bad
function foo() {
  if (condition) return 1
  else return 2
}
```

### Schema Definitions (Drizzle)

Use snake_case for field names so column names don't need to be redefined as strings.

```ts
// Good
const table = sqliteTable("session", {
  id: text().primaryKey(),
  project_id: text().notNull(),
  created_at: integer().notNull(),
})

// Bad
const table = sqliteTable("session", {
  id: text("id").primaryKey(),
  projectID: text("project_id").notNull(),
  createdAt: integer("created_at").notNull(),
})
```

## Testing

- Avoid mocks as much as possible
- Test actual implementation, do not duplicate logic into tests
- Tests cannot run from repo root (guard: `do-not-run-tests-from-root`); run from package dirs like `packages/opencode`.

## Type Checking

- Always run `bun typecheck` from package directories (e.g., `packages/opencode`), never `tsc` directly.

## Intranet Fork Notes

This is a fork of [anomalyco/opencode](https://github.com/anomalyco/opencode) for air-gapped intranet deployment.
See `docs/` for full documentation.

### Key Learnings

- **Bun on CentOS 7.6**: Bun requires glibc 2.25+, CentOS 7.6 only has 2.17. Must use `--target=bun-linux-x64-musl`.
- **musl binary is NOT static**: Bun musl builds still dynamically link `ld-musl-x86_64.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`. Must bundle these from Alpine.
- **Invoking via ld-musl breaks Bun compiled mode**: Running `ld-musl-x86_64.so.1 ./opencode-bin` causes Bun to show its own help instead of the embedded app. The binary must be invoked directly — use `patchelf --set-interpreter` to rewrite the ELF interpreter path.
- **patchelf can break Bun binaries**: Some patchelf operations cause segfaults. The `--set-interpreter` flag alone is safe; avoid `--set-rpath` combined with interpreter changes on Bun binaries.
- **`bun install --ignore-scripts`**: The monorepo has `electron` whose postinstall fails in Docker. Safe to skip — only `packages/opencode` is needed.
- **build.ts models.dev fetch**: The build script fetches from `models.dev/api.json` and embeds it. Don't set `MODELS_DEV_API_JSON` to empty `{}` — it generates invalid TypeScript. Let the build fetch normally (build machine has internet).
- **`--single` flag skips musl**: The upstream `--single` flag filters out `abi: "musl"` targets. Use our `--musl` flag instead.
- **Wrapper must run patchelf via musl linker**: Alpine's patchelf is musl-linked. Invoke it as `ld-musl-x86_64.so.1 --library-path ... patchelf` — this works because argv[0] doesn't matter for patchelf (unlike Bun).
- **CentOS 7.6 UTF-8 locale**: CentOS 7.6 may default to non-UTF-8 locale (`LANG=en_US` or `LANG=C`), causing Unicode box-drawing characters (`┃` etc.) to render as boxes. The wrapper script must set `LANG=en_US.UTF-8` and `LC_ALL`.
- **Kitty keyboard protocol**: `@opentui` sends Kitty keyboard CSI sequences that leak as garbled text (e.g. "66;w=1") on unsupported terminals. The whitelist in `supportsKittyKeyboard()` checks `TERM`, `TERM_PROGRAM`, and `KITTY_WINDOW_ID`. Only Kitty, WezTerm, Ghostty, Foot, and Rio are known to support it.
- **TERM=xterm on CentOS**: Default `TERM=xterm` may lack 256-color support. Wrapper upgrades it to `xterm-256color`.
- **Method Not Allowed (405)**: If `@ai-sdk/openai-compatible` returns 405, check that the LLM server's `/v1/chat/completions` endpoint actually accepts POST. The SDK always sends `POST`. Common cause: nginx reverse proxy or server misconfiguration. The config `api` field should be the base URL (e.g. `http://host/v1`), not the full endpoint path.
