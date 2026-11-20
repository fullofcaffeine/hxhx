# Switch array branch inference

A switch expression whose branches mix complete arrays with an empty literal (`default: []`) has the complete element type, as in Haxe 4.3.7.

Run `node_modules/.bin/haxe test/m14_switch_array_branch_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`; the hxhx check types them with an empty `main`.
