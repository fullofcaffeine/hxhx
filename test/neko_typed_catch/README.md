# Typed Neko catches

Run `haxe test/m14_neko_typed_catch_integration_test.hxml`.
The harness compares upstream Haxe 4.3.7 with both generated Neko layouts.

A thrown string reaches the real Exception conversion helper in statement and
expression catches. Dynamic receives the original carrier. An integer skips
the earlier String handler and reaches the Int handler.

The companion value-view and numeric fixtures cover more matching categories.
These checks do not establish native stack-origin parity or static initialization.
