# Dynamic Boolean control

This independently authored program checks all Boolean input combinations for
`&&` and `||`. Its output records operand order and proves that a skipped operand
has no effect. It also checks Dynamic conditions in branches, string
conditionals, while loops, and do-while loops, plus Dynamic-to-Bool local writes.

Run `haxe test/m14_dynamic_boolean_control_test.hxml` from the repository root.
The runner compares upstream Haxe and the compiled native OCaml executable with
`expected.stdout`. It also rejects condition facts from copied operands,
foreign executable bodies, and removed statements.

The normal `npm run test:m14:hih-dynamic-operators` command includes this test
before the existing operator and DateTools checks. These focused contracts do
not establish complete native compiler or standard-library compatibility.
