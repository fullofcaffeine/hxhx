# Abstract overload syntax

Haxe 4.3.7 keeps every `extern overload` declaration of an abstract as its own field, as `haxe.ds.Vector` does with its two constructors.

hxhx reads abstract members with the declaration scanner, which returns both overloads. `ParserStage` merged the scanned members by name and kept only the first one. Authored parsing (the parse oracle) now keeps every overload. The compile path still keeps the first one only, because the frozen Stage3 OCaml backend rejects an abstract with two constructor bodies (haxe_ocaml-95co6). `../abstract_overload_native` checks that the compile path still builds an overloaded abstract.

`expected.bodies.json` lists the bodies that upstream's parse recorder printed for `Cells`, in declaration order. Run `node_modules/.bin/haxe test/m14_abstract_overload_syntax_test.hxml`.
