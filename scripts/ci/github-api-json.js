#!/usr/bin/env node
/**
 * Read JSON from the GitHub API with a small, bounded transport retry policy.
 *
 * This helper retries only idempotent reads that fail because GitHub is rate
 * limiting or temporarily unavailable. Callers still own the meaning of the
 * returned data, and ordinary client errors fail immediately so retries can
 * never turn missing or unauthorized evidence into a passing result.
 */

const retryableStatuses = new Set([429, 502, 503, 504])
const defaultRetryOptions = Object.freeze({
  maxAttempts: 4,
  baseDelayMs: 1000,
  maxDelayMs: 8000
})

function sleep(delayMs) {
  return new Promise(resolve => setTimeout(resolve, delayMs))
}

function parseRetryAfterMs(value, nowMs) {
  if (typeof value !== 'string' || value.trim() === '') return null
  const trimmed = value.trim()
  if (/^\d+(?:\.\d+)?$/.test(trimmed)) {
    return Math.max(0, Math.ceil(Number(trimmed) * 1000))
  }
  const retryAt = Date.parse(trimmed)
  if (Number.isNaN(retryAt)) return null
  return Math.max(0, retryAt - nowMs)
}

function safeNetworkClass(error) {
  const candidate = error && (error.code || (error.cause && error.cause.code) || error.name)
  const safe = String(candidate || 'error').replace(/[^A-Za-z0-9_-]/g, '-').slice(0, 48)
  return `network-${safe || 'error'}`
}

function formatHistory(history) {
  return history.map(entry => {
    const outcome = entry.retryable ? 'retryable' : 'final'
    const wait = entry.delayMs === null ? '' : `, wait=${entry.delayMs}ms`
    return `attempt ${entry.attempt}: ${entry.responseClass} (${outcome}${wait})`
  }).join('; ')
}

function readError(url, maxAttempts, history, startedAt, now) {
  const last = history[history.length - 1]
  const attempts = last ? last.attempt : 0
  const elapsedMs = Math.max(0, now() - startedAt)
  return new Error(
    `GitHub API read failed: endpoint=${url}; response=${last ? last.responseClass : 'unknown'}; `
      + `attempts=${attempts}/${maxAttempts}; elapsedRetryMs=${elapsedMs}; `
      + `history=[${formatHistory(history)}]`
  )
}

function validateOptions(options) {
  for (const key of ['maxAttempts', 'baseDelayMs', 'maxDelayMs']) {
    if (!Number.isInteger(options[key]) || options[key] < (key === 'maxAttempts' ? 1 : 0)) {
      throw new Error(`${key} must be ${key === 'maxAttempts' ? 'a positive' : 'a non-negative'} integer`)
    }
  }
}

/**
 * Fetch one GitHub API endpoint and decode its JSON response.
 *
 * Tests may inject fetch, sleep, and clock implementations. Production calls
 * use four total attempts and cap every delay at eight seconds, keeping the
 * workflow-level ten-minute timeout as the final upper bound.
 */
async function githubJson(url, token, overrides = {}) {
  const options = {
    ...defaultRetryOptions,
    ...overrides
  }
  validateOptions(options)
  const fetchImpl = options.fetchImpl || globalThis.fetch
  const sleepImpl = options.sleepImpl || sleep
  const now = options.now || Date.now
  if (typeof fetchImpl !== 'function') throw new Error('fetchImpl must be a function')
  if (typeof sleepImpl !== 'function') throw new Error('sleepImpl must be a function')
  if (typeof now !== 'function') throw new Error('now must be a function')

  const startedAt = now()
  const history = []
  for (let attempt = 1; attempt <= options.maxAttempts; attempt++) {
    let response
    try {
      response = await fetchImpl(url, {
        headers: {
          Accept: 'application/vnd.github+json',
          Authorization: `Bearer ${token}`,
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'hxhx-ci-evidence-ownership'
        }
      })
    } catch (error) {
      const retryable = attempt < options.maxAttempts
      const delayMs = retryable
        ? Math.min(options.maxDelayMs, options.baseDelayMs * (2 ** (attempt - 1)))
        : null
      history.push({
        attempt,
        responseClass: safeNetworkClass(error),
        retryable,
        delayMs
      })
      if (!retryable) throw readError(url, options.maxAttempts, history, startedAt, now)
      await sleepImpl(delayMs)
      continue
    }

    if (response.ok) {
      try {
        return await response.json()
      } catch (error) {
        history.push({
          attempt,
          responseClass: 'invalid-json',
          retryable: false,
          delayMs: null
        })
        throw readError(url, options.maxAttempts, history, startedAt, now)
      }
    }

    const canRetry = retryableStatuses.has(response.status) && attempt < options.maxAttempts
    let delayMs = null
    if (canRetry) {
      const retryAfter = response.headers && typeof response.headers.get === 'function'
        ? parseRetryAfterMs(response.headers.get('retry-after'), now())
        : null
      const fallback = options.baseDelayMs * (2 ** (attempt - 1))
      delayMs = Math.min(options.maxDelayMs, retryAfter === null ? fallback : retryAfter)
    }
    history.push({
      attempt,
      responseClass: `http-${response.status}`,
      retryable: canRetry,
      delayMs
    })
    if (!canRetry) throw readError(url, options.maxAttempts, history, startedAt, now)
    await sleepImpl(delayMs)
  }

  throw readError(url, options.maxAttempts, history, startedAt, now)
}

module.exports = {
  defaultRetryOptions,
  githubJson,
  parseRetryAfterMs,
  retryableStatuses
}
