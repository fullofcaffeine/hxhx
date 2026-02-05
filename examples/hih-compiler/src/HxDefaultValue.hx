/**
	Represents whether an argument has a default value.

	Why:
	- The OCaml backend treats `Null<T>` for non-nullable `T` as a special case
	  and may represent it as `Obj.t` during early bring-up.
	- For bootstrapping, we prefer explicit sum types over `Null<T>` to keep the
	  generated OCaml types precise.

	What:
	- Either no default, or an explicit expression.
**/
enum HxDefaultValue {
	NoDefault;
	Default(expr:HxExpr);
}

