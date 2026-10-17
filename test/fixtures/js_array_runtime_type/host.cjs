// Each compiled program receives the same host values and must request each once, in order.
const vm = require('node:vm')
const originalArray = Array
function Replacement() {}
const values = [[], vm.runInNewContext('[1]'), { 0: 'item', length: 1 }, 'array', null, Array, Object.create(Array.prototype), [7], { __class__: { __hx_interfaces: [Array] } }]
let next = 0
let observations = 0
global.Probe = Object.freeze({
  value(slot) {
    if (slot !== next++) throw Error('runtime operand was repeated or reordered')
    if (slot === 9) {
      global.Array = Replacement
      return new Replacement()
    }
    return values[slot]
  },
  observe(value) {
    if (typeof value !== 'boolean') throw Error('array check did not return Bool')
    observations++
    console.log(value)
  },
  sameType(value) {
    return value === Array
  },
  done() {
    global.Array = originalArray
    if (next !== values.length + 1 || observations !== 13) throw Error('runtime observations were omitted')
  }
})
require(process.argv[2])
