#!/usr/bin/env node
/**
 * Deterministic transport fixtures for bounded GitHub API read retries.
 */

const {
  githubJson,
  parseRetryAfterMs,
  retryableStatuses
} = require('./github-api-json')

function fail(message) {
  console.error(`[github-api-json-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function assert(condition, message) {
  if (!condition) fail(message)
}

function headers(values = {}) {
  const normalized = new Map(Object.entries(values).map(([key, value]) => [key.toLowerCase(), value]))
  return {
    get(name) {
      return normalized.get(String(name).toLowerCase()) || null
    }
  }
}

function response(status, body = {}, headerValues = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: headers(headerValues),
    async json() {
      return body
    }
  }
}

function createHarness(outcomes, options = {}) {
  let nowMs = options.nowMs || Date.parse('2026-07-20T00:00:00Z')
  const waits = []
  const requests = []
  return {
    waits,
    requests,
    options: {
      maxAttempts: options.maxAttempts || 4,
      baseDelayMs: options.baseDelayMs === undefined ? 1000 : options.baseDelayMs,
      maxDelayMs: options.maxDelayMs === undefined ? 8000 : options.maxDelayMs,
      now: () => nowMs,
      sleepImpl: async delayMs => {
        waits.push(delayMs)
        nowMs += delayMs
      },
      fetchImpl: async (url, init) => {
        requests.push({ url, init })
        if (outcomes.length === 0) throw new Error('fixture ran out of outcomes')
        const outcome = outcomes.shift()
        if (outcome instanceof Error) throw outcome
        return outcome
      }
    }
  }
}

async function expectFailure(promise, snippets, label) {
  try {
    await promise
    fail(`${label} unexpectedly passed`)
  } catch (error) {
    for (const snippet of snippets) {
      assert(error.message.includes(snippet), `${label} did not report ${JSON.stringify(snippet)}\n${error.message}`)
    }
    return error
  }
}

async function main() {
  const endpoint = 'https://api.github.com/repos/example/hxhx/actions/runs'
  const token = 'fixture-secret-token'

  for (const status of retryableStatuses) {
    const harness = createHarness([response(status), response(200, { status })])
    const result = await githubJson(endpoint, token, harness.options)
    assert(result.status === status, `${status} retry did not return the eventual payload`)
    assert(harness.requests.length === 2, `${status} retry used the wrong attempt count`)
    assert(harness.waits.join(',') === '1000', `${status} retry used the wrong backoff`)
  }

  const retryAfter = createHarness([
    response(429, {}, { 'Retry-After': '3' }),
    response(200, { ok: true })
  ])
  await githubJson(endpoint, token, retryAfter.options)
  assert(retryAfter.waits.join(',') === '3000', 'Retry-After seconds were not honored')

  const retryDate = new Date(Date.parse('2026-07-20T00:00:00Z') + 4500).toUTCString()
  const dateRetry = createHarness([
    response(503, {}, { 'Retry-After': retryDate }),
    response(200, { ok: true })
  ])
  await githubJson(endpoint, token, dateRetry.options)
  assert(dateRetry.waits.join(',') === '4000', 'Retry-After HTTP date was not honored')

  const cappedRetry = createHarness([
    response(503, {}, { 'Retry-After': '60' }),
    response(200, { ok: true })
  ])
  await githubJson(endpoint, token, cappedRetry.options)
  assert(cappedRetry.waits.join(',') === '8000', 'Retry-After did not respect the bounded delay cap')

  const networkError = new Error('socket reset while fixture token was nearby')
  networkError.code = 'ECONNRESET'
  const network = createHarness([networkError, response(200, { ok: true })])
  await githubJson(endpoint, token, network.options)
  assert(network.waits.join(',') === '1000', 'network failure did not use bounded backoff')

  const exhausted = createHarness([
    response(503),
    response(503),
    response(503),
    response(503)
  ])
  const exhaustedError = await expectFailure(
    githubJson(endpoint, token, exhausted.options),
    [
      `endpoint=${endpoint}`,
      'response=http-503',
      'attempts=4/4',
      'elapsedRetryMs=7000',
      'attempt 1: http-503',
      'attempt 4: http-503'
    ],
    'retry exhaustion'
  )
  assert(!exhaustedError.message.includes(token), 'retry exhaustion leaked the GitHub token')

  const unauthorized = createHarness([response(401)])
  const unauthorizedError = await expectFailure(
    githubJson(endpoint, token, unauthorized.options),
    ['response=http-401', 'attempts=1/4', 'elapsedRetryMs=0'],
    'non-retryable authentication failure'
  )
  assert(unauthorized.requests.length === 1, 'non-retryable 401 was retried')
  assert(unauthorized.waits.length === 0, 'non-retryable 401 slept before failing')
  assert(!unauthorizedError.message.includes(token), 'authentication failure leaked the GitHub token')

  assert(parseRetryAfterMs('2', 0) === 2000, 'numeric Retry-After parsing changed')
  assert(parseRetryAfterMs('not-a-date', 0) === null, 'invalid Retry-After should be ignored')
  console.log('[ci:guards] OK: GitHub API reads retry only bounded transport failures')
  console.log('GITHUB_API_JSON_RETRY:PASS')
}

main().catch(error => fail(error.stack || error.message))
