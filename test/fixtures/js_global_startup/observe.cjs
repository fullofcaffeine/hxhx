const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8');
const usesUid = process.argv[3] === 'uid';

for (const names of [['window', 'global', 'self'], ['global', 'self'], ['self'], []]) {
  for (const initial of [undefined, 41]) {
    const context = {marker: 'chosen', ids: []};
    let host = context;
    for (const [index, name] of names.entries()) {
      context[name] = {marker: index === 0 ? 'chosen' : 'wrong', ids: []};
      if (index === 0) host = context[name];
    }
    if (usesUid) {
      if (initial !== undefined) host.$haxeUID = initial;
    } else {
      Object.defineProperty(host, '$haxeUID', {
        get() { throw new Error('unused UID feature read global state'); },
        set() { throw new Error('unused UID feature wrote global state'); }
      });
    }
    vm.createContext(context);
    vm.runInContext(source, context, {timeout: 1000});
    vm.runInContext(source, context, {timeout: 1000});
    if (usesUid) {
      const first = initial === undefined ? 0 : initial;
      assert.deepEqual(host.ids, [first, first + 1]);
      assert.equal(host.$haxeUID, first + 2);
    }
  }
}
