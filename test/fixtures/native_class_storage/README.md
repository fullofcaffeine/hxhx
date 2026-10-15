# Native class storage

Distinct instances compare as different objects even when their fields match. Aliases, method results, constructor results, nullable values, and fields retain reference identity. A receiver with effects runs once before its declared field is read. String and Array length operations retain their native behavior.

Run `node_modules/.bin/haxe test/m14_native_class_storage_test.hxml`. The receiver-call integration command also includes this test. The runner compares upstream Haxe and native OCaml output with `expected.stdout`. It also rejects copied, removed, or foreign equality occurrences and foreign field declarations.
