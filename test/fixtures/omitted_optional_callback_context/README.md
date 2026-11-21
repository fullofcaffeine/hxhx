# Omitted optional callback context

A callback argument keeps its expected type when a later optional argument is left out, as in Haxe 4.3.7: `timer.start(() -> Counter.add(2), ms)` for `start(callback:() -> Void, ms:Int, ?repeat:Int)`.

Run `node_modules/.bin/haxe test/m14_omitted_optional_callback_context_test.hxml`. The observed class `Ops` has inputs that hxhx infers from the call.
