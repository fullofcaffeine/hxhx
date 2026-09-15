# Python entry-class static members

Run `npm run test:m14:python-entry-members` from the repository root.
The test requires Haxe 4.3.7 and Python 3.

The fixture calls static methods through their class and through bare names.
Both forms share static state. Local variables named `calls` and `next` must
keep their own values. The fixture also saves the entry function during static
initialization, calls `Main.main()` again, and calls another class's `main`.
That secondary class also uses bare static calls and fields. Its Haxe module
path must resolve to the class that Python actually emits.

The harness compares an authored expectation with upstream Haxe output.
It then loads and types the same source with hxhx, generates Python, and runs it.
Failed output remains under `.tmp/python_entry_members_*` for inspection.

This focused compiler test runs under upstream Haxe's interpreter. It does
not prove a fresh standalone hxhx build or upstream-suite compatibility.
The README Goals status remains unchanged.
