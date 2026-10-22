# Custom key/value comprehension

Run `haxe test/m14_key_value_comprehension_test.hxml`.
The authored fixture requires three ordered array elements and exactly three cursor reads.
The test compares upstream and candidate JavaScript. It diagnoses whether custom iterator
lowering preserves the loop until the compiler selects each array append.
This regression is part of the unpublished iterator candidate, not readiness evidence.
