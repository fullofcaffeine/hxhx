# Null default input inference

An omitted parameter with a `null` default (`?p = null` or `p = null`) is optional and nullable, and later uses choose its type, as in Haxe 4.3.7.

Run `node_modules/.bin/haxe test/m14_null_default_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`; the hxhx check types them with an empty `main`. The upstream observer reads `Main.Ops`. It follows `Null<T>` to `T`, so the test drops the `Null` wrapper on the hxhx side and ignores spaces.
