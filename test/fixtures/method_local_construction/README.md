# Method-local construction

This source checks that local allocation and length variables remain in their method. A copy must allocate a distinct instance and preserve its fields.

Run `node_modules/.bin/haxe test/m14_method_local_construction_test.hxml`. The runner also parses the real Haxe standard-library Vector source and checks its local declarations. It compares upstream and native output and checks the projected field inventory. The receiver-call integration command includes this test.

This replaces a synthetic fixture that inserted locals as static fields and relied on module-name suppression. Native compilation rejects an unbound constructor receiver, while runtime output proves independent copied storage. This focused contract does not claim complete Vector or native compiler readiness.
