# Downcasts from values that do not fix the source type

`Std.downcast` is declared as `downcast<T:{}, S:T>(value:T, c:Class<S>):S`. The
bound `S:T` names another method type parameter. When `value` is `Dynamic`,
`Any`, `null`, or the class argument is an unchecked `cast null`, the arguments
do not fix `T`. Upstream Haxe 4.3.7 then lets the `S:T` check bind `T` instead
of failing, so `Std.downcast(dynamicValue, Sub)` is accepted.

Real violations must still fail with upstream's message:

| Module | Call | Diagnostic |
| --- | --- | --- |
| `InvalidSibling` | `Std.downcast(new Sibling(), Sub)` | `Constraint check failure for downcast.S` |
| `InvalidDynamicBound` | `pick<T:String, S:T>(dynamicValue, 5)` | `Constraint check failure for pick.T` |
| `InvalidCastBound` | `pick<T:Int, S:T>(cast null, "text")` | `Constraint check failure for pick.T` |

In the last two rows the open `T` is closed to `S` (Int or String), and then
`T`'s own bound fails. `Main` holds the accepted calls, including a user method
with the same dependent shape and an `Any` argument for an `Int` bound.

Run the typer regression, which also checks each module with upstream Haxe:

```sh
haxe test/m14_downcast_dynamic_constraint_test.hxml
```

Check the upstream behavior directly:

```sh
haxe -cp test/oracle/downcast_dynamic_seed -main Main --interp
haxe -cp test/oracle/downcast_dynamic_seed -main InvalidDynamicBound --no-output
```
