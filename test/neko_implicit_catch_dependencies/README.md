# Implicit catch dependencies

Run `haxe test/m14_implicit_catch_use_integration_test.hxml` from the repository root.
The test loads this fixture through normal Neko project resolution and inspects
shared typed facts and dependency observations before backend emission.

String and Int catches require the real ValueException payload provider. A base
Exception catch requires the exact conversion helper. Dynamic and exception
subtype catches must not acquire eager conversion or payload unwrapping.
Handlers intentionally ignore their variables so ordinary reads cannot hide
missing implicit dependencies. Runtime catch dispatch is tested separately.

The test also edits a public payload provider and the private conversion helper
through request-local source views. Both edits must invalidate the consumer.
Private signatures use an explicit private-declaration dependency because they
are absent from the provider's public-interface revision.
