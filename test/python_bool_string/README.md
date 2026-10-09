# Python Boolean string conversion

`Std.string` must produce Haxe text for Boolean and null values: `true`, `false`, and `null`.
Python normally spells these values `True`, `False`, and `None`.

Run `npm run test:m14:python-bool-string` from the repository root.
The test compares an authored expectation with upstream Haxe and generated Python at runtime.
It checks literal and nullable Booleans, null, and an effectful call that must run once per conversion.
Integer values `0` and `1` must remain distinct from Booleans, and the string `True` must retain its case.

Failures retain generated files under `.tmp/python_bool_string_*`.
Numeric formatting and complete `Std.string` behavior for other value types remain outside this contract.
