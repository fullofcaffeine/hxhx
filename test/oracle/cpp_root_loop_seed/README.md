# Ordinary method loops

RootLoops checks null Array elements, integer Array keys, nested loops, escaped
iteration captures, once-only range bounds, while/do-while exits, and early returns.
The range capture case changes the bound variable inside the loop. The original
bound still controls iteration, and escaped closures retain separate values.
The independently written native observer forces collection at every allocation.
Both optimization levels use address and undefined-behavior sanitizers.

Run the upstream expectation with:

```sh
haxe -cp test/oracle/cpp_root_loop_seed -main Main --interp
```

Compare stdout with expected.stdout. Run the managed native observer with
`haxe test/m14_cpp_root_loop_test.hxml`. Its typing uses the real Array provider.
The focused ownership check is `haxe test/m14_statement_control_projection_test.hxml`.
It rejects copied, foreign, changed-source, and wrong-revision control facts.

The original directory retains the complete null-storage program that first
exposed the ordinary Array-loop failure. Its assertions produce no output on
success. Run it with `haxe test/m14_cpp_root_loop_program_test.hxml`.
Neither program substitutes a closure or hand-expanded statements for its loops.
