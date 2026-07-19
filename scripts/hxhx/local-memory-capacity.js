#!/usr/bin/env node
/**
 * Collect a platform-aware estimate of memory available to a heavy compiler.
 *
 * Raw free-page counts are not an admission signal on systems such as macOS,
 * where inactive and compressed pages remain reclaimable. Callers therefore
 * receive both the selected value and its provenance/reliability.
 */

'use strict'

const fs = require('fs')
const os = require('os')
const { execFileSync } = require('child_process')

const GIB = 1024 * 1024 * 1024
const DEFAULT_MIN_AVAILABLE_GIB = 4
const DEFAULT_MIN_AVAILABLE_FRACTION = 0.1

function parseMacOsAvailableMemory(output, totalMemoryBytes) {
  const match = output.match(/System-wide memory free percentage:\s*([0-9]+(?:\.[0-9]+)?)%/i)
  if (!match) throw new Error('memory_pressure did not report a free percentage')
  const fraction = Number(match[1]) / 100
  if (!Number.isFinite(fraction) || fraction < 0 || fraction > 1) {
    throw new Error(`memory_pressure returned invalid percentage ${match[1]}`)
  }
  return Math.round(totalMemoryBytes * fraction)
}

function parseLinuxAvailableMemory(text) {
  const match = text.match(/^MemAvailable:\s+(\d+)\s+kB$/m)
  if (!match) throw new Error('/proc/meminfo does not contain MemAvailable')
  return Number(match[1]) * 1024
}

function collectMacOsAvailableMemory(totalMemoryBytes) {
  try {
    const output = execFileSync('/usr/bin/memory_pressure', ['-Q'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    return {
      availableMemoryBytes: parseMacOsAvailableMemory(output, totalMemoryBytes),
      provenance: 'macos_memory_pressure',
      reliable: true,
      error: '',
    }
  } catch (error) {
    return {
      availableMemoryBytes: os.freemem(),
      provenance: 'node_raw_free_fallback',
      reliable: false,
      error: `macOS available-memory collection failed: ${error.message}`,
    }
  }
}

function collectLinuxAvailableMemory() {
  try {
    const text = fs.readFileSync('/proc/meminfo', 'utf8')
    return {
      availableMemoryBytes: parseLinuxAvailableMemory(text),
      provenance: 'linux_memavailable',
      reliable: true,
      error: '',
    }
  } catch (error) {
    return {
      availableMemoryBytes: os.freemem(),
      provenance: 'node_raw_free_fallback',
      reliable: false,
      error: `Linux available-memory collection failed: ${error.message}`,
    }
  }
}

function collectAvailableMemory(platform = process.platform, totalMemoryBytes = os.totalmem()) {
  if (platform === 'darwin') return collectMacOsAvailableMemory(totalMemoryBytes)
  if (platform === 'linux') return collectLinuxAvailableMemory()
  if (platform === 'win32') {
    return {
      availableMemoryBytes: os.freemem(),
      provenance: 'windows_available_physical',
      reliable: true,
      error: '',
    }
  }
  return {
    availableMemoryBytes: os.freemem(),
    provenance: 'node_raw_free_fallback',
    reliable: false,
    error: `no reviewed available-memory collector for platform ${platform}`,
  }
}

function memoryThresholdBytes(totalMemoryBytes, minimumGiB, minimumFraction) {
  return Math.max(minimumGiB * GIB, totalMemoryBytes * minimumFraction)
}

function assessMemoryCapacity(state, options) {
  const minimumGiB = Number.isFinite(options.minAvailableMemoryGiB)
    ? options.minAvailableMemoryGiB
    : DEFAULT_MIN_AVAILABLE_GIB
  const minimumFraction = Number.isFinite(options.minAvailableMemoryFraction)
    ? options.minAvailableMemoryFraction
    : DEFAULT_MIN_AVAILABLE_FRACTION
  const thresholdBytes = memoryThresholdBytes(
    state.totalMemoryBytes,
    minimumGiB,
    minimumFraction
  )
  const available = state.availableMemoryBytes
  const validAvailable = Number.isFinite(available) && available >= 0
  const reliable = state.availableMemoryReliable === true && validAvailable
  return {
    reliable,
    status: reliable ? (available < thresholdBytes ? 'pressured' : 'safe') : 'unavailable',
    availableMemoryBytes: validAvailable ? available : 0,
    availableMemoryGiB: validAvailable ? Math.round((available / GIB) * 1000) / 1000 : 0,
    availableFraction:
      validAvailable && state.totalMemoryBytes > 0
        ? Math.round((available / state.totalMemoryBytes) * 1000) / 1000
        : 0,
    provenance: state.availableMemoryProvenance || 'unavailable',
    thresholdBytes: Math.round(thresholdBytes),
    thresholdGiB: Math.round((thresholdBytes / GIB) * 1000) / 1000,
    minimumGiB,
    minimumFraction,
  }
}

module.exports = {
  DEFAULT_MIN_AVAILABLE_FRACTION,
  DEFAULT_MIN_AVAILABLE_GIB,
  GIB,
  assessMemoryCapacity,
  collectAvailableMemory,
  memoryThresholdBytes,
  parseLinuxAvailableMemory,
  parseMacOsAvailableMemory,
}
