# Optional field nullable read

Reading an optional structure field (`?crc:Int`) yields `Null<Int>` in Haxe 4.3.7: an absent field reads as `null`.

Run `node_modules/.bin/haxe test/m14_optional_field_nullable_read_test.hxml`. The upstream observer strips `Null<T>` from parameter types, so the test also reads the result types of `Reads.crcOf` and `Reads.labelOf` (`Null<Int>`, `Null<String>`, as upstream `$type` shows) and runs the native output.
