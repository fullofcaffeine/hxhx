# Applied generic allocation

Run `haxe test/m14_cpp_generic_layout_test.hxml` to check applied layout facts and generated native allocation.

The source constructs `Box<Int>`, `Box<String>`, and a concrete leaf with a generic parent. The observer checks zero for the declared Int slot, null for the declared T slot, and false for the leaf's Bool slot. It also checks shared Box descriptor identity, the inherited field prefix, and collection after the static references are released.

The test uses forced collection and O0/O2 address and undefined-behavior sanitizers. It also executes the unchanged inherited-constructor fixture through native C++.

This proves allocation and layout selection. Generic field access, generic method transport, and generic field initializers remain required under `haxe_ocaml-g85ze`. The separate generic-storage reference specifies the full null and class-identity behavior.
