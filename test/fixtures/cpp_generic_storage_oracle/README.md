# Generic storage reference behavior

This fixture runs through upstream Haxe 4.3.7 and hxcpp 4.3.2. It specifies behavior that managed C++ must preserve. It does not prove that hxhx implements that behavior.

`Box<Int>` and `Box<String>` share the public class value `Box`. Their fields retain their declared generic behavior. An unset `T` field is null inside the generic class, including when a caller uses `Box<Int>`.

Native C++ converts that null to zero when the caller stores the field or method result in an `Int` local. An ordinary declared `Int` field also starts at zero. The interpreter instead retains null for these observations, so the fixture has separate expected outputs.

The fixture also checks reads after writes, class values for a concrete leaf, runtime membership in its generic ancestor, and the immediate superclass value.

The same runner then compiles and executes [the generic field contract](../cpp_generic_field_seed/README.md) and [the generic method contract](../cpp_generic_method_seed/README.md) with upstream C++. These programs assert Int/Bool conversion, retained generic nulls, inherited access, aliasing, callbacks, and reference values. Their interpreter behavior is not used as the scalar-default reference.

Use an existing isolated haxelib repository with hxcpp 4.3.2, or create one as described in [the startup reference](../cpp_static_startup_oracle/README.md). Set `HAXELIB_PATH` when that repository is outside the work directory. Then run:

```sh
HAXE_BIN="$(command -v haxe)" HAXELIB_BIN="$(command -v haxelib)" \
  taskpolicy -b nice -n 10 npm run test:m14:cpp-generic-storage-oracle
```

Use `nice -n 10` on hosts without `taskpolicy`. `HXHX_CPP_GENERIC_ORACLE_WORKDIR` selects the build directory. Do not run two copies against the same directory. The runner pins both versions, bounds native compilation and execution, uses two compile workers, and compares all outputs byte for byte. It saves the first program's outputs before reusing the native build directory for the field contract.

Task `haxe_ocaml-g85ze` owns implementation and native hxhx acceptance. Generic fields, method transport, applied storage identity, and public class identity must remain distinct during that work. README Goals status is unchanged.
