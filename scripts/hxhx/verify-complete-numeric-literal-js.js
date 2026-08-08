#!/usr/bin/env node

/**
 * Checks the numeric values stored in generated JavaScript class fields.
 *
 * Runtime output proves that the program behaves correctly. This check adds a
 * closer view of the compiler boundary. It catches a generator that truncates
 * a literal and later happens to repair the value at runtime.
 */

const fs = require('fs')

const file = process.argv[2]
if (!file) {
  throw new Error('Usage: verify-complete-numeric-literal-js.js <generated.js>')
}

const source = fs.readFileSync(file, 'utf8')

function readArray(field, expected) {
  const pattern = new RegExp(`\\.${field}\\s*=\\s*\\[([^\\]]*)\\]`)
  const match = source.match(pattern)
  if (!match) {
    throw new Error(`Generated JavaScript has no ${field} array assignment`)
  }

  const values = Function(`"use strict"; return [${match[1]}]`)()
  if (values.length !== expected.length || values.some((value, index) => !Object.is(value, expected[index]))) {
    throw new Error(`${field} lost numeric value data: expected ${expected}, found ${values}`)
  }
}

readArray('DECIMALS', [31, 28, -31, 1234567, 2147483647, -2147483648])
readArray('HEXADECIMALS', [31, 2147483647])
readArray('FLOATS', [0.69314718056, 1e-5, 3.14e2, 0.5, -0.125, 1e10, 0.69314718056])

console.log('HXHX_COMPLETE_NUMERIC_LITERAL_JS:PASS')
