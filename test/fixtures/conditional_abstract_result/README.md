# Conditional abstract results

A function returning `Int` can select between an Int-backed abstract and an
integer when the abstract declares a conversion. The shared typed tree must
retain that result and put the conversion inside the selected branch.

`Main.hx` checks a header conversion and an effectful `@:to` method. Ternary,
nested ternary, `if/else` initializers, and grouped branches must produce
`expected.stdout`. The conversion
counter proves that an unselected branch has no conversion effects.

Run the independent upstream observer:

```sh
haxe -cp test/fixtures/conditional_abstract_result -main Main --interp
```

Run the shared-tree, generated JavaScript, and native C++ regression:

```sh
npm run test:m14:conditional-abstract-result
```

The driver also checks that a missing output conversion cannot be inferred from
equal backing storage, and that Dynamic and nullable branches keep their facts.
It uses the existing `Sys.println` extern from `cpp_static_callable` to declare
the real console boundary. It does not substitute numeric library bodies.

This fixture proves declared conditional results. It does not establish full
Int64 compatibility or change project readiness.
