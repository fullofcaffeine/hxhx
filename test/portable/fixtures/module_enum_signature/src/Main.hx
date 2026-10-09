/** A recursive module group must retain an ordinary enum parameter's type. */
class Main {
	static function main():Void {
		Sys.println(First.accept(Token.Label("hello")));
		Sys.println(First.accept(Token.Items(["a", "b"])));
		Sys.println(First.maybe(null));
		Sys.println(First.maybe(Token.Label("nullable")));
		Sys.println(First.maybe(First.nullable(null)));
		final values = ["x"];
		final original:Null<Token> = Token.Items(values);
		final returned = First.nullable(original);
		values.push("y");
		Sys.println(First.maybe(returned));
		Sys.println(First.optional());
		Sys.println(First.optional(null));
		Sys.println(First.optional(Token.Label("supplied")));
	}
}
