# Stage3 StringTools.replace

`Main.hx` calls `StringTools.replace(s, sub, by)` with a single match,
several matches, overlapping matches (`"aaaa"` with `"aa"`), a missing match,
an empty replacement, an empty input, an empty `sub`, and a whole-string
match. It uses both the static form and the `using StringTools` form
(`text.replace("one", "1")`). One call takes each argument from a function
that logs its position, so the output also shows that every argument runs
once, left to right.

Before the fix, the native program printed an empty string for every call.
The Stage3 emitter had an early bring-up case that replaced any
`StringTools.replace` call with `""`, so the arguments were never evaluated.
The call now reaches the generated `StringTools.replace`, whose body comes
from the standard library (`s.split(sub).join(by)`).

`npm run test:m14:stage3-string-methods` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text.
