class OcamlNativeMain {
	static function main() {
		var xs = ocaml.List.Cons(1, ocaml.List.Cons(2, ocaml.List.Nil));

		switch (xs) {
			case ocaml.List.Nil:
			case ocaml.List.Cons(h, t):
		}

		var o = ocaml.Option.Some(1);
		switch (o) {
			case ocaml.Option.None:
			case ocaml.Option.Some(v):
		}

		var r = ocaml.Result.Ok(1);
		switch (r) {
			case ocaml.Result.Ok(v):
			case ocaml.Result.Error(e):
		}
	}
}

