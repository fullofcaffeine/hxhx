This fixture checks optional calls inside parentheses, type annotations, casts,
and an explicit untyped expression. Each call evaluates its argument once and
uses the default value 23, producing 30. Exactly five argument markers precede
the five results, so the observer detects omitted or repeated evaluation.

Run `haxe test/m14_stage3_virtual_optional_calls_test.hxml`. The test compares
upstream execution with native output from a module supplied in memory. Its
virtual source path prevents a file-reparse fallback from hiding lost call facts.
