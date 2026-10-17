# Native object string conversion

Run `haxe test/m14_neko_object_string_conversion_integration_test.hxml`.
The test compares upstream Haxe 4.3.7 with both generated Neko layouts.

Std.string and the raw VM string primitive must call the object's selected
toString method exactly once. The fixture observes receiver state and an
inherited override without using exception handling.

The raw primitive call is confined to one documented native boundary. Its
result becomes a Haxe String immediately. This fixture does not establish
anonymous-object formatting or complete reflection parity.
