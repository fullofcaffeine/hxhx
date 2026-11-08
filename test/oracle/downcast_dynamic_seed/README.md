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
| `InvalidNullArrayBound` | `pick<T, S:Array<T>>(null, 5)` | `Constraint check failure for pick.S` |
| `InvalidNullBoundedArrayBound` | `pick<T:String, S:Array<T>>(null, 5)` | `Constraint check failure for pick.S` |
| `InvalidNullRecordBound` | `pick<T, S:{x:T}>(null, {y: 1})` | upstream: `{ y : Int } should be { x : Null<Unknown<0>> }`; hxhx: `Constraint check failure for pick.S` |
| `InvalidNullClassBound` | `pick<T, S:Class<T>>(null, 5)` | `Constraint check failure for pick.S` |
| `InvalidNullSharedBound` | `pick<T, S:Array<T>, U:Array<T>>(null, [5], ["a"])` | upstream: `String should be Int`; hxhx: `Constraint check failure for pick.U` |

In the `InvalidDynamicBound` and `InvalidCastBound` rows, the open `T` is closed
to `S` (Int or String), and then `T`'s own bound fails. In the `InvalidNull*`
rows, a `null` literal leaves `T` open. Upstream skips `T`'s own bound then, but
`T` only matches as a wildcard inside the bound on `S`, so a value of the wrong
shape still fails. A position that matched nothing concrete stays a wildcard,
so `arrayOf(null, [])`, `arrayOf(null, [null])` and `arrayOf(null, anyValue)` are
accepted. All bounds share what `T` matched, so `InvalidNullSharedBound` fails. `Main` holds the accepted calls, including a user method
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
