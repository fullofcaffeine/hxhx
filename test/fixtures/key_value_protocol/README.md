# Typed key/value protocol regression

Run `./node_modules/.bin/haxe test/m14_key_value_protocol_test.hxml`.
This standalone regression runs upstream JavaScript first, then checks exact Int loop bindings
and candidate execution. It observes acquisition, hasNext and next call counts, a single iterable
evaluation, empty iteration, and break/continue destinations using framework-neutral classes.
It also checks direct-iterator precedence, factory fallback, and returns from ordinary and local
functions. Required inline calls reuse the same iterator function at two call sites and check
that argument evaluation and protocol acquisition occur once.
Run `./node_modules/.bin/haxe test/m14_key_value_protocol_diagnostics_test.hxml`
to compare invalid protocols with upstream and require source-positioned candidate errors.
The regular `npm run test:m14:js-stmt-key-value-for` command also runs protocol ownership,
custom comprehension, and mutable iteration capture checks before the full-provider runtime fixture.
Focused evidence does not replace that command's combined acceptance.
