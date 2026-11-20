# Recursive local function inference

A named local function can call itself before its body has chosen a result. Upstream Haxe 4.3.7 gives the recursive call the function's own result, for example `Void` when the body has no `return`.

Run `node_modules/.bin/haxe test/m14_recursive_local_function_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`; the hxhx check types them with an empty `main`. The upstream observer reads `Main.Ops` and follows `Null<T>` to `T`.
