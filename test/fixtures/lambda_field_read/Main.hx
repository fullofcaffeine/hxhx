/**
	A lambda parameter that the body only reads a field from types, as in upstream Haxe 4.3.7
	(haxe_ocaml-0pwiv): the field's value has no other use, so its type stays open upstream.
**/
class Main {
	static function each<T>(cb:T->Void):String
		return "each";

	static function apply<T>(value:T, cb:T->Void):Void
		cb(value);

	static function main() {
		Sys.println(each(function(res) res.error));
		apply({error: "e"}, function(res) Sys.println(res.error));
	}
}
