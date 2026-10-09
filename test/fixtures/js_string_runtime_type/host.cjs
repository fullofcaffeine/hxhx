const vm = require('node:vm')
const original = String
function Replacement() {}
const values = ['word', '', new String('word'), Object.create(String.prototype), null, String, vm.runInNewContext('new String("word")'), { __class__: { __hx_interfaces: [String] } }]
let next = 0
let observations = 0
global.Probe = {
  value(slot) {
    if (slot !== next++) throw Error('repeated or reordered operand')
    if (slot === 8) { global.String = Replacement; return new Replacement() }
    if (slot === 9) return 'word'
    return values[slot]
  },
  observe(value) { if(typeof value !== 'boolean')throw Error('not Bool'); observations++; console.log(value) },
  sameType(value) { return value === String },
  done() { global.String = original; if(next !== 10 || observations !== 14)throw Error('missing observation') }
}
require(process.argv[2])
