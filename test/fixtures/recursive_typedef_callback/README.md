# Recursive typedef callback

`d.params.map(show)` over `typedef Decl = {var name:String; var ?params:Array<Decl>;}` passes a method whose parameter is the expanded structure where `map` expects a function over `Decl`. Upstream Haxe 4.3.7 accepts it because both are the same type.

Run `node_modules/.bin/haxe test/m14_recursive_typedef_callback_test.hxml`. `Shapes` holds the recursive typedef; the observed class `Ops` takes simple inputs, because upstream and hxhx display typedef parameters differently.
