/**
	Inline markup literals as Haxe 4.3.7 reads them. The lexer takes the text from `<` to the
	matching close tag, and the parser gives `@:markup "<text>"`.
**/
class Main {
	static function forms():Array<String> {
		return [
			Markup.text(<p></p>),
			Markup.text(<p class="a"> text </p>),
			Markup.text(<div><div></div></div>),
			Markup.text(<div><span></div>),
			Markup.text(<br/>),
			Markup.text(<img src="x" />),
			Markup.text(<ul><li /></ul>),
			Markup.text(<my-tag></my-tag>),
			Markup.text(<svg:rect></svg:rect>),
			Markup.text(<a.B_c-1:d></a.B_c-1:d>),
			Markup.text(<:x></:x>),
			Markup.text(<></>),
			Markup.text(<>fragment</>),
			Markup.text(<Upper></Upper>),
			Markup.text(<$name>$value ${1 + 2}</$name>)
		];
	}

	static function unbalanced():Array<String> {
		return [
			Markup.text(<q title=" </q>),
			Markup.text(<q title=' </q>),
			Markup.text(<q a=// </q>),
			Markup.text(<q a=/* </q>),
			Markup.text(<q a=~/ </q>)
		];
	}

	static function multiline():String {
		return Markup.text(<pre>
  first line
  second line
</pre>);
	}

	static function block():String {
		return Markup.text({ <A></A><b /> });
	}

	static function blockWithSemicolons():String {
		return Markup.text({ <A></A>; <b />; });
	}

	static function main() {
		for (text in forms().concat(unbalanced()))
			Sys.println(text);
		Sys.println(multiline());
		Sys.println(block());
		Sys.println(blockWithSemicolons());
		Sys.println(Fields.plain + " " + Fields.after);
	}
}

/** A markup literal field initializer needs no semicolon. */
@:build(Markup.fields())
class Fields {
	public static var plain:String = <field kind="static"></field>
	public static var after:String = <after/>;
}
