# Class source ranges

This source checks that native parsing retains the exact declaration range that
upstream Haxe reports. The range starts at the class or interface keyword and
ends immediately after its closing brace. Comments, metadata, modifiers and
trailing module functions stay outside that range.

Run the regression from the repository root:

```sh
haxe test/m14_class_source_range_test.hxml
```

The command runs through both eval and Neko. The macro observer reads positions
from upstream Haxe. The runtime test compares
native parser, typed-class and backend-projection facts with those positions.
The Unicode prefix and inactive conditional branch check that byte and
character offsets are not confused. Parsing reads the active branches but
counts positions in the original source.
Synthetic declarations must retain an absent source range.

The test also sends four requests through the production parser cache. It
checks an unchanged request, an inactive edit with identical filtered text,
and restoration of the original source. Only identical original and filtered
inputs can reuse a declaration. The retained original declaration stays intact.

These positions supply the source origin required by shared runtime class
markers. This regression does not establish native constructor execution.
