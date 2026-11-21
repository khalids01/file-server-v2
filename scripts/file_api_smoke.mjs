import {randomUUID} from "node:crypto"
import {pathToFileURL} from "node:url"

const DEFAULT_BASE_URL = "http://localhost:4000"
const DEFAULT_TIMEOUT_MS = 15_000

export function configFromEnv(env = process.env) {
  const required = name => {
    const value = env[name]?.trim()
    if (!value) throw new Error(`missing required environment variable ${name}`)
    return value
  }

  return {
    baseUrl: env.FILE_API_BASE_URL?.trim() || DEFAULT_BASE_URL,
    readKey: required("FILE_API_READ_KEY"),
    writeKey: required("FILE_API_WRITE_KEY"),
    deleteKey: required("FILE_API_DELETE_KEY"),
    revokedKey: env.FILE_API_REVOKED_KEY?.trim() || null,
    allowRemote: env.FILE_API_ALLOW_REMOTE === "1",
  }
}

export async function runSmoke(options = {}) {
  const config = normalizeOptions(options)
  const base = assertSafeBaseUrl(config.baseUrl, config.allowRemote)
  const ctx = {fetchImpl: config.fetchImpl, base, timeoutMs: config.requestTimeoutMs}
  const fixture = createFixture()
  const checks = []
  let uploadedId = null
  let deleted = false

  const mark = message => {
    checks.push(message)
    config.log(`ok ${message}`)
  }

  try {
    const upload = await uploadFile(ctx, config.writeKey, fixture)
    checkStatus(upload.response, 201, "upload", upload.body)
    uploadedId = upload.body?.data?.id
    if (typeof uploadedId !== "string" || !uploadedId) throw new Error("upload: response did not include data.id")
    mark("write key uploaded fixture")

    const readOnlyUpload = await uploadFile(ctx, config.readKey, fixture)
    checkError(readOnlyUpload, 403, "INSUFFICIENT_SCOPE", "read key upload")
    mark("read key cannot upload")

    const listing = await requestJson(ctx, config.readKey, `api/v2/files?limit=50&search=${encodeURIComponent(fixture.filename)}`)
    checkStatus(listing.response, 200, "listing", listing.body)
    if (!Array.isArray(listing.body?.data) || !listing.body.data.some(file => file.id === uploadedId)) {
      throw new Error("listing: uploaded file is missing from data")
    }
    mark("listing includes uploaded file")

    const download = await request(ctx, config.readKey, `api/v2/files/${encodeURIComponent(uploadedId)}/content`)
    checkStatus(download, 200, "download")
    const downloaded = new Uint8Array(await download.arrayBuffer())
    if (!sameBytes(downloaded, fixture.bytes)) throw new Error("download: bytes do not match the uploaded fixture")
    mark("download bytes match fixture")

    const patchedTags = ["file-api-smoke", "updated"]
    const patch = await requestJson(ctx, config.writeKey, `api/v2/files/${encodeURIComponent(uploadedId)}`, {
      method: "PATCH",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({tags: patchedTags}),
    })
    checkStatus(patch.response, 200, "tag patch", patch.body)
    const metadata = await requestJson(ctx, config.readKey, `api/v2/files/${encodeURIComponent(uploadedId)}`)
    checkStatus(metadata.response, 200, "metadata", metadata.body)
    if (!sameTags(metadata.body?.data?.tags, patchedTags)) throw new Error("tag patch: metadata did not return the updated tags")
    mark("tag patch applied")

    const readOnlyDelete = await requestJson(ctx, config.readKey, `api/v2/files/${encodeURIComponent(uploadedId)}`, {method: "DELETE"})
    checkError(readOnlyDelete, 403, "INSUFFICIENT_SCOPE", "read key delete")
    const stillPresent = await requestJson(ctx, config.readKey, `api/v2/files/${encodeURIComponent(uploadedId)}`)
    checkStatus(stillPresent.response, 200, "read-only delete check", stillPresent.body)
    mark("read key cannot delete")

    const deletion = await requestJson(ctx, config.deleteKey, `api/v2/files/${encodeURIComponent(uploadedId)}`, {method: "DELETE"})
    checkStatus(deletion.response, 200, "delete", deletion.body)
    if (deletion.body?.data?.deleted !== true) throw new Error("delete: response did not confirm deletion")
    deleted = true
    const gone = await requestJson(ctx, config.readKey, `api/v2/files/${encodeURIComponent(uploadedId)}`)
    checkError(gone, 404, "FILE_NOT_FOUND", "deleted file lookup")
    mark("delete key removed uploaded file")

    if (config.revokedKey) {
      const revoked = await requestJson(ctx, config.revokedKey, "api/v2/files?limit=1")
      checkError(revoked, 401, "INVALID_API_KEY", "revoked key")
      mark("revoked key rejected")
    }
  } finally {
    if (uploadedId && !deleted) {
      try {
        const cleanup = await request(ctx, config.deleteKey, `api/v2/files/${encodeURIComponent(uploadedId)}`, {method: "DELETE"})
        if (cleanup.ok) {
          deleted = true
          config.log("ok cleanup removed uploaded fixture")
        } else {
          config.log(`cleanup could not remove uploaded fixture (status ${cleanup.status})`)
        }
      } catch {
        config.log("cleanup could not remove uploaded fixture")
      }
    }
  }

  return {
    checks,
    uploadedId,
    deleted,
    revokedChecked: Boolean(config.revokedKey),
  }
}

function normalizeOptions(options) {
  const required = (name, value) => {
    if (typeof value !== "string" || !value.trim()) throw new Error(`${name} is required`)
    return value.trim()
  }

  return {
    baseUrl: options.baseUrl?.trim() || DEFAULT_BASE_URL,
    readKey: required("readKey", options.readKey),
    writeKey: required("writeKey", options.writeKey),
    deleteKey: required("deleteKey", options.deleteKey),
    revokedKey: options.revokedKey?.trim() || null,
    allowRemote: Boolean(options.allowRemote),
    fetchImpl: options.fetchImpl ?? globalThis.fetch,
    log: options.log ?? (() => {}),
    requestTimeoutMs: options.requestTimeoutMs ?? DEFAULT_TIMEOUT_MS,
  }
}

function createFixture() {
  const filename = `file-api-smoke-${randomUUID()}.txt`
  const text = `file api smoke fixture ${randomUUID()}\n`
  return {filename, bytes: new TextEncoder().encode(text), text}
}

function buildUploadForm(fixture) {
  const form = new FormData()
  form.set("file", new Blob([fixture.bytes], {type: "text/plain"}), fixture.filename)
  form.set("tags", JSON.stringify(["file-api-smoke", "upload"]))
  return form
}

async function uploadFile(ctx, key, fixture) {
  return requestJson(ctx, key, "api/v2/files", {method: "POST", body: buildUploadForm(fixture)})
}

async function requestJson(ctx, key, path, init = {}) {
  const response = await request(ctx, key, path, init)
  const text = await response.text()
  let body = null
  if (text) {
    try {
      body = JSON.parse(text)
    } catch {
      body = null
    }
  }
  return {response, body}
}

async function request(ctx, key, path, init = {}) {
  const headers = new Headers(init.headers)
  headers.set("Authorization", `Bearer ${key}`)
  const url = new URL(path.replace(/^\//, ""), ctx.base)
  return ctx.fetchImpl(url, {
    ...init,
    headers,
    signal: init.signal ?? AbortSignal.timeout(ctx.timeoutMs),
    redirect: "error",
  })
}

function checkStatus(response, expected, label, body) {
  if (response.status !== expected) throw new Error(`${label}: expected ${expected}, got ${response.status}${describeError(body)}`)
}

function checkError(result, status, code, label) {
  if (result.response.status !== status) {
    throw new Error(`${label}: expected ${status}, got ${result.response.status}${describeError(result.body)}`)
  }
  if (result.body?.error?.code !== code) {
    throw new Error(`${label}: expected error code ${code}, got ${result.body?.error?.code ?? "none"}`)
  }
}

function describeError(body) {
  const error = body?.error
  if (!error) return ""
  return `${error.code ? ` ${error.code}` : ""}${error.message ? `: ${error.message}` : ""}`
}

function sameBytes(left, right) {
  return left.length === right.length && left.every((byte, index) => byte === right[index])
}

function sameTags(actual, expected) {
  if (!Array.isArray(actual) || actual.length !== expected.length) return false
  return actual.every((tag, index) => tag === expected[index])
}

function assertSafeBaseUrl(raw, allowRemote) {
  let url
  try {
    url = new URL(raw)
  } catch {
    throw new Error("base URL must be an absolute http(s) URL")
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new Error("base URL must use http or https")
  if (url.username || url.password) throw new Error("base URL must not include credentials")
  if (!allowRemote && !isLoopback(url.hostname)) {
    throw new Error(`refusing non-loopback base URL ${url.origin}; set FILE_API_ALLOW_REMOTE=1 to opt in`)
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/"
  return url
}

function isLoopback(hostname) {
  const host = hostname.toLowerCase().replace(/^\[/, "").replace(/\]$/, "")
  return host === "localhost" || host.endsWith(".localhost") || host === "::1" || /^127(?:\.\d{1,3}){3}$/.test(host)
}

async function main() {
  let config
  try {
    config = configFromEnv()
  } catch (error) {
    console.error(`smoke not run: ${error.message}`)
    process.exitCode = 1
    return
  }

  try {
    const result = await runSmoke({...config, log: message => console.log(message)})
    console.log(`smoke passed: ${result.checks.length} checks${result.revokedChecked ? " including revoked key" : ""}`)
  } catch (error) {
    console.error(`smoke failed: ${error.message}`)
    process.exitCode = 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main()
}
