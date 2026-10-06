// Agent Usage's OpenCode plugin (agent-usage.sessions): the session colors.
// The robot in the top bar turns orange while an OpenCode session waits for
// you (a permission, a question) and green when one has finished its turn.
//
// agent-usage-session copies this file to ~/.config/opencode/plugins/, where
// OpenCode 2 loads it on its own; switching off Session colors in Agent
// Usage's settings removes it again. It keeps one small JSON file per session
// in ~/.local/state/omarchy/agents/sessions/, as the Claude Code hooks do (see
// sessions.js in the extension), and imports nothing beyond Node's own
// modules, so there's nothing to install.

import { mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const AGENT = "opencode"

// OpenCode starts a global plugin once for every folder it works in, all in
// one process, and every instance sees every session's events. One instance
// follows the events and writes the files; the rest stand by in case it
// unloads. The sessions they track outlive a reload of this file.
const shared = (globalThis.__agentUsageSessions1 ??= { instances: [], sessions: new Map(), cleaned: false })

function sessionsDir() {
  const state = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state")
  return join(state, "omarchy", "agents", "sessions")
}

function sessionFile(id) {
  return join(sessionsDir(), `${AGENT}-${String(id).replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 128)}.json`)
}

function remove(path) {
  rmSync(path, { force: true })
}

function writeAtomic(path, text) {
  mkdirSync(sessionsDir(), { recursive: true })
  const temporary = join(sessionsDir(), `.${AGENT}-${process.pid}-${Math.random().toString(36).slice(2)}.tmp`)
  writeFileSync(temporary, text)
  renameSync(temporary, path)
}

// Files from an earlier run of OpenCode's service: those sessions stopped
// with it.
function cleanStaleFiles() {
  if (shared.cleaned) return
  shared.cleaned = true
  let names = []
  try {
    names = readdirSync(sessionsDir())
  } catch {
    return
  }
  for (const name of names) {
    if (!name.startsWith(`${AGENT}-`) || !name.endsWith(".json")) continue
    try {
      const record = JSON.parse(readFileSync(join(sessionsDir(), name), "utf8"))
      if (record.pid !== process.pid) remove(join(sessionsDir(), name))
    } catch {
      remove(join(sessionsDir(), name))
    }
  }
}

function entry(id) {
  let session = shared.sessions.get(id)
  if (!session) {
    session = { state: null, since: 0, parent: undefined, cwd: "", pending: new Set(), lookedUp: false }
    shared.sessions.set(id, session)
  }
  return session
}

function save(id, session) {
  // A subagent's session only matters while it waits for you; its parent's
  // file tells the rest.
  if (session.parent && session.state !== "waiting") {
    remove(sessionFile(id))
    return
  }
  if (!session.state) return
  const record = {
    agent: AGENT,
    session: id,
    state: session.state,
    since: session.since,
    updated: Date.now(),
    pid: process.pid,
    cwd: session.cwd,
  }
  if (session.parent) record.parent = session.parent
  writeAtomic(sessionFile(id), JSON.stringify(record) + "\n")
}

function setState(ctx, id, state) {
  if (!id || id === "global") return
  const session = entry(id)
  if (session.state !== state) {
    session.state = state
    session.since = Date.now()
  }
  if (session.parent === undefined) lookUp(ctx, id, session)
  save(id, session)
}

// Sessions that started before this plugin did: whether they belong to a
// subagent, and where they run.
function lookUp(ctx, id, session) {
  if (session.lookedUp || !ctx.session?.get) return
  session.lookedUp = true
  Promise.resolve(ctx.session.get({ sessionID: id }))
    .then((info) => {
      if (shared.sessions.get(id) !== session) return
      if (session.parent === undefined) session.parent = info?.parentID ?? null
      if (!session.cwd) session.cwd = info?.location?.directory ?? ""
      save(id, session)
    })
    .catch(() => {})
}

function answered(ctx, id, requestID) {
  const session = shared.sessions.get(id)
  if (!session) return
  session.pending.delete(requestID)
  if (session.pending.size === 0 && session.state === "waiting") setState(ctx, id, "working")
}

// One event from OpenCode's stream. Synchronous, so the files always follow
// the events in order.
function handle(ctx, event) {
  const data = event?.data ?? {}
  const id = data.sessionID
  if (!id && event?.type !== "form.created") return
  switch (event?.type) {
    case "session.created": {
      const session = entry(id)
      session.parent = data.parentID ?? null
      session.cwd = data.location?.directory ?? session.cwd
      return
    }
    case "session.execution.started":
      return setState(ctx, id, "working")
    case "session.execution.succeeded":
    case "session.execution.failed":
      entry(id).pending.clear()
      return setState(ctx, id, "ready")
    case "session.execution.interrupted":
      // You stopped it yourself, so you're already there.
      entry(id).pending.clear()
      return setState(ctx, id, "idle")
    case "permission.asked":
      entry(id).pending.add(data.id)
      return setState(ctx, id, "waiting")
    case "permission.replied":
      return answered(ctx, id, data.requestID)
    case "form.created": {
      const form = data.form ?? {}
      if (!form.sessionID || form.sessionID === "global") return
      entry(form.sessionID).pending.add(form.id)
      return setState(ctx, form.sessionID, "waiting")
    }
    case "form.replied":
    case "form.cancelled":
      return answered(ctx, id, data.id)
    case "session.deleted":
      shared.sessions.delete(id)
      remove(sessionFile(id))
      return
  }
}

function follow(instance) {
  const controller = new AbortController()
  instance.controller = controller
  cleanStaleFiles()
  ;(async () => {
    try {
      for await (const event of instance.ctx.event.subscribe({ signal: controller.signal })) {
        try {
          handle(instance.ctx, event)
        } catch (error) {
          console.error(`agent-usage: ${error}`)
        }
      }
    } catch (error) {
      if (!controller.signal.aborted) console.error(`agent-usage: ${error}`)
    }
    // The stream ended without being asked to: pick it up again.
    if (!controller.signal.aborted && instance.controller === controller)
      setTimeout(() => {
        if (instance.controller === controller) instance.follow()
      }, 1000)
  })()
}

export default {
  id: "agent-usage.sessions",
  setup(ctx) {
    const instance = { ctx, controller: null }
    // Kept on the instance, so a handover runs the code this instance was
    // loaded with, also when an older copy of this file hands over.
    instance.follow = () => follow(instance)
    shared.instances.push(instance)
    if (!shared.instances.some((other) => other.controller)) instance.follow()
    return () => {
      const index = shared.instances.indexOf(instance)
      if (index >= 0) shared.instances.splice(index, 1)
      if (!instance.controller) return
      instance.controller.abort()
      instance.controller = null
      shared.instances[0]?.follow()
    }
  },
}
