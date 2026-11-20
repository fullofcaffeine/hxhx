# Assigned container inference

An omitted input that receives a new container (`path = new Array()` or `path = []`) takes the element type from later uses such as `path.push("x")`, as in Haxe 4.3.7.

Run `node_modules/.bin/haxe test/m14_assigned_container_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`; the hxhx check types them with an empty `main`. The upstream observer reads `Main.Ops` and follows `Null<T>` to `T`.
