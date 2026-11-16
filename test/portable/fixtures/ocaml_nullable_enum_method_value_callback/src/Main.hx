class Main {
	static function main() {
		final refs = new Refs(e -> switch (e) {
			case EInt(v): "int" + v;
			case _: null;
		});
		refs.expression(ECall(EIdent("f"), [EIdent("a"), EInt(3), ECall(EIdent("g"), [])]));
		refs.expression(null);
		Sys.println(refs.names.join(","));
		Sys.println(Walk.names(ECall(EIdent("h"), [EIdent("b")])));
	}
}
