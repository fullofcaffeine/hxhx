# Enum-abstract constant initialization

Run `npm run test:m14:enum-abstract-initializers` from the repository root.
The test compares upstream Haxe output with a compiled native Stage3 executable.
It includes integer, string, Boolean, and same-enum alias constants.

Each initializer keeps the declared enum-abstract type in the typed program.
A backing literal gets an explicit conversion that preserves its stored value.
An alias keeps its reference to the original constant declaration.

This permission belongs to the exact enum constant initializer.
An ordinary field or function cannot introduce `Signal` from an integer unless
its declaration permits that conversion. The test retains those negative controls
and rejects a string initializer for an integer-backed enum abstract.

The full enum-abstract switch diagnostic suite runs in the surrounding
`test:m14:typer-abstract-catalog` command. This fixture does not prove ordinary
enum payload construction. README Goals status remains unchanged.
