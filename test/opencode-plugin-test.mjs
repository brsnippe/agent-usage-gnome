// Run with: node test/opencode-plugin-test.mjs
//
// The OpenCode plugin (hooks/opencode-agent-usage.js) with a stand-in for
// OpenCode: two folders' instances of the plugin, one event stream, and the
// session files they leave. The events are shaped as OpenCode 2 sends them.

import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const state = mkdtempSync(join(tmpdir(), "opencode-plugin-test-"))
process.env.XDG_STATE_HOME = state
const SESSIONS = join(state, "omarchy", "agents", "sessions")

let failures = 0
function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`)
}

// ---- a stand-in for OpenCode's server
const subscribers = new Set()
const known = {
  ses_old: { id: "ses_old", location: { directory: "/old" } },
  ses_oldchild: { id: "ses_oldchild", parentID: "ses_old", location: { directory: "/old" } },
}

async function* stream(subscriber, signal) {
  while (!signal.aborted) {
    if (subscriber.queue.length > 0) {
      yield subscriber.queue.shift()
      continue
    }
    await new Promise((resolve) => (subscriber.wake = resolve))
  }
}

function context(directory) {
  return {
    location: { directory },
    session: { get: async ({ sessionID }) => known[sessionID] ?? { id: sessionID } },
    event: {
      subscribe({ signal }) {
        const subscriber = { queue: [], wake: null }
        subscribers.add(subscriber)
        signal.addEventListener("abort", () => {
          subscribers.delete(subscriber)
          subscriber.wake?.()
        })
        return stream(subscriber, signal)
      },
    },
  }
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 20))
async function send(type, data) {
  for (const subscriber of subscribers) {
    subscriber.queue.push({ type, data })
    subscriber.wake?.()
  }
  await settle()
}

const file = (id) => join(SESSIONS, `opencode-${id}.json`)
const read = (id) => (existsSync(file(id)) ? JSON.parse(readFileSync(file(id), "utf8")) : null)
const stateOf = (id) => read(id)?.state ?? null
const files = () => (existsSync(SESSIONS) ? readdirSync(SESSIONS).filter((name) => name.endsWith(".json")).sort() : [])

// ---- leftovers from an earlier run of OpenCode's service
mkdirSync(SESSIONS, { recursive: true })
writeFileSync(file("ses_gone"), JSON.stringify({ agent: "opencode", state: "waiting", pid: process.pid + 1 }))
writeFileSync(join(SESSIONS, "claude-abc.json"), JSON.stringify({ agent: "claude", state: "ready" }))

const plugin = (await import("../agent-usage@local/hooks/opencode-agent-usage.js")).default
check("an OpenCode 2 plugin: an id and setup()", [plugin.id, typeof plugin.setup], ["agent-usage.sessions", "function"])

const cleanupA = plugin.setup(context("/a"))
const cleanupB = plugin.setup(context("/b"))
await settle()
check("one instance per folder, one of them follows the events", subscribers.size, 1)
check("files from OpenCode's last run go, Claude Code's stay", files(), ["claude-abc.json"])

// ---- a session's turn
await send("session.created", { sessionID: "ses_1", location: { directory: "/a/project" } })
check("a new session has no file yet", stateOf("ses_1"), null)
await send("session.execution.started", { sessionID: "ses_1" })
check("a running turn is working", [stateOf("ses_1"), read("ses_1")?.pid, read("ses_1")?.cwd], ["working", process.pid, "/a/project"])
await send("permission.asked", { id: "per_1", sessionID: "ses_1", action: "external_directory" })
check("a permission request waits for you", stateOf("ses_1"), "waiting")
await send("form.created", { form: { id: "frm_1", sessionID: "ses_1", title: "Questions" } })
await send("permission.replied", { sessionID: "ses_1", requestID: "per_1", reply: "once" })
check("still waiting while a question is open", stateOf("ses_1"), "waiting")
await send("form.replied", { id: "frm_1", sessionID: "ses_1" })
check("working again once everything's answered", stateOf("ses_1"), "working")
await send("form.created", { form: { id: "frm_g", sessionID: "global", title: "Pick a provider" } })
check("forms outside any session don't count", files(), ["claude-abc.json", "opencode-ses_1.json"])
await send("session.execution.succeeded", { sessionID: "ses_1" })
check("a finished turn is ready", stateOf("ses_1"), "ready")
const since = read("ses_1").since
await send("session.execution.started", { sessionID: "ses_1" })
await send("permission.asked", { id: "per_2", sessionID: "ses_1" })
await send("session.execution.failed", { sessionID: "ses_1", error: { message: "boom" } })
check("a failed turn is your turn too, and nothing is left waiting", [stateOf("ses_1"), read("ses_1").since > since], ["ready", true])
await send("permission.replied", { sessionID: "ses_1", requestID: "per_2", reply: "reject" })
check("a late reply doesn't make it work again", stateOf("ses_1"), "ready")
await send("session.execution.started", { sessionID: "ses_1" })
await send("session.execution.interrupted", { sessionID: "ses_1", reason: "user" })
check("stopping it yourself makes it idle", stateOf("ses_1"), "idle")

// ---- subagents
await send("session.created", { sessionID: "ses_child", parentID: "ses_1", location: { directory: "/a/project" } })
await send("session.execution.started", { sessionID: "ses_child" })
check("a working subagent has no file", stateOf("ses_child"), null)
await send("permission.asked", { id: "per_3", sessionID: "ses_child" })
check("a subagent waiting for you has one", [stateOf("ses_child"), read("ses_child")?.parent], ["waiting", "ses_1"])
await send("permission.replied", { sessionID: "ses_child", requestID: "per_3", reply: "always" })
check("until it's answered", stateOf("ses_child"), null)
await send("session.execution.succeeded", { sessionID: "ses_child" })
check("a subagent finishing doesn't count as ready", stateOf("ses_child"), null)

// ---- sessions that started before the plugin did
await send("session.execution.started", { sessionID: "ses_old" })
check("their folder is looked up", [stateOf("ses_old"), read("ses_old")?.cwd], ["working", "/old"])
await send("permission.asked", { id: "per_4", sessionID: "ses_oldchild" })
check("and whether they're a subagent's", read("ses_oldchild")?.parent, "ses_old")

await send("session.deleted", { sessionID: "ses_old" })
check("a deleted session's file goes", stateOf("ses_old"), null)

// ---- the following instance unloads
cleanupA()
await settle()
check("another instance takes over the events", subscribers.size, 1)
await send("session.execution.started", { sessionID: "ses_2" })
check("and keeps the files going", stateOf("ses_2"), "working")
await send("permission.replied", { sessionID: "ses_oldchild", requestID: "per_4", reply: "once" })
check("with what the first one knew", stateOf("ses_oldchild"), null)
cleanupB()
await settle()
check("with every instance gone, nobody follows", subscribers.size, 0)

rmSync(state, { recursive: true, force: true })
console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`)
process.exit(failures ? 1 : 0)
