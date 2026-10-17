# Startup in an uncalled class

Loading `Main.hx` also loads its sibling class, `Unused`. Haxe 4.3.7 runs
the sibling's static initializer before `Main.main`, even though main never
calls the sibling. The output must contain `unused` before `main`.

Run the independent reference from the repository root:

```sh
haxe -cp test/fixtures/cpp_managed_startup_seed -main Main --interp
```

Compare stdout with `expected.stdout`. Haxe 4.3.7 produces the same output
with `-dce full` and `-dce no`.

`M14CppManagedProgramPlanTest` requires the managed C++ target to reject this
program before publishing files while startup support remains incomplete.
That rejection prevents silent loss of the initializer. It does not prove
C++ startup support. Once implemented, the normal target must run this source
and match the reference output before the rejection check can be replaced.
