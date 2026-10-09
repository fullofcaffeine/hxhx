This fixture checks Haxe value conversion for PHP console output.

The authored program prints literal and computed Boolean values through `Sys.print` and `Sys.println`.
Two calls update a counter, so the expected output also detects repeated evaluation.
Equal and unequal enum payloads check Boolean values returned by the runtime.
String, integer, finite Float, and null cases check the surrounding conversion behavior.
The test compares the expected bytes with upstream Haxe's interpreter, upstream PHP output, and generated native PHP output.

`TraceValues` checks Boolean payloads through the same output path.
Upstream source-position prefixes are removed only for that comparison because this backend currently omits them.
This fixture does not claim complete trace behavior or numeric-formatting parity.

Run `haxe test/m14_php_console_output_integration_test.hxml`.
Without PHP, the test reports source-only coverage.
