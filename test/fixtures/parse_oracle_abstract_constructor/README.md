# Parse oracle abstract constructor

Haxe 4.3.7 builds an abstract's constructor as `_new` before build macros run, and wraps the authored body in `var this:T; ...; return cast this;` (`typeloadFields.ml:265-298`). The parse oracle's upstream recorder removes exactly that wrapper and records the authored statements under `new`. The `hxhx` side prints an abstract's `new` as a block, because the wrapper loses the authored bracing. A plain class named like an implementation class (`Lookalike_Impl_`) keeps its authored `_new`.

Run `node_modules/.bin/haxe test/m14_parse_oracle_abstract_constructor_test.hxml`.
