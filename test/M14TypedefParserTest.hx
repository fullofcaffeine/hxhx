/** Prove typedef syntax survives parsing without becoming a runtime class. */
class M14TypedefParserTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function declaration(source:String):HxTypedefDecl {
		final module = ParserStage.parse(source, "Alias.hx").getDecl();
		require(HxModuleDecl.getClasses(module).length == 0, "typedef-only source created a runtime class");
		final declarations = HxModuleDecl.getTypedefs(module);
		require(declarations.length == 1, "missing typedef declaration");
		return declarations[0];
	}

	static function main():Void {
		// Both spellings are accepted by Haxe 4.3.7; neither is an array parameter.
		for (hint in ["(...values:Int)->Int", "(...Int)->Int"]) {
			switch (declaration("typedef Alias = " + hint + ";").getTarget().getKind()) {
				case FunctionType(args, _):
					require(args.length == 1 && args[0].isRest && !args[0].isOptional, "rest argument facts disappeared");
				case _:
					throw "rest function type became grouping";
			}
		}
		final source = "@:keep private typedef Alias<T:{id:Int}=String> = Array<T>;";
		final alias = declaration(source);
		require(alias.getName() == "Alias" && alias.getVisibility() == Private, "typedef identity or visibility changed");
		require(alias.getMetadata()[0] == "@:keep", "typedef metadata disappeared");
		require(alias.getPos().getIndex() == source.indexOf("typedef") && alias.getEndPos().getIndex() == source.length,
			"typedef range must end after its semicolon");
		final parameters = alias.getParameters();
		require(parameters.length == 1
			&& parameters[0].name == "T"
			&& parameters[0].constraints.length == 1
			&& parameters[0].defaultType != null,
			"typedef binder lost its constraint or default");
		parameters[0].constraints.resize(0);
		require(alias.getParameters()[0].constraints.length == 1, "caller mutated stored parameter constraints");
		switch (alias.getTarget().getKind()) {
			case TypePath(segments, args):
				require(segments.join(".") == "Array" && args.length == 1, "generic target was flattened");
				segments.push("Changed");
				args.resize(0);
			case _:
				throw "generic target is not a type path";
		}
		switch (alias.getTarget().getKind()) {
			case TypePath(segments, args):
				require(segments.length == 1 && args.length == 1, "caller mutated stored target syntax");
			case _:
				throw "target kind changed";
		}
		final record = declaration("typedef Alias = {>Base, final id:Int; var ?name:String; var count(default,null):Int; function call<T>(value:T):T;};");
		switch (record.getTarget().getKind()) {
			case AnonymousType(fields, extensions):
				require(extensions.length == 1 && fields.length == 4 && fields[1].isOptional, "structural fields or extension disappeared");
				switch (fields[0].kind) {
					case Variable(_, true, "", ""):
					case _: throw "final structural field lost mutability";
				}
				switch (fields[2].kind) {
					case Variable(_, false, "default", "null"):
					case _: throw "structural accessors disappeared";
				}
				switch (fields[3].kind) {
					case Method(params, args, _): require(params.length == 1 && args[0].name == "value", "method signature disappeared");
					case _: throw "structural method became a variable";
				}
			case _:
				throw "structural alias lost its target";
		}
		switch (declaration("typedef Alias = (value:Int, ?name:String) -> String;").getTarget().getKind()) {
			case FunctionType(args, _):
				require(args.length == 2 && args[1].name == "name" && args[1].isOptional, "function arguments changed");
			case _:
				throw "function alias lost its target";
		}
		switch (declaration("typedef Alias = Int -> (String -> Bool);").getTarget().getKind()) {
			case ArrowType(_, result):
				switch (result.getKind()) {
					case GroupedType(_):
					case _: throw "function-result grouping disappeared";
				}
			case _:
				throw "legacy arrow syntax disappeared";
		}
		final mixed = ParserStage.parse("typedef Alias = Int; class Main {}", "Main.hx").getDecl();
		require(HxModuleDecl.getClasses(mixed).length == 1
			&& HxModuleDecl.getTypedefs(mixed).length == 1, "mixed module confused classes and aliases");
		for (source in [
			"typedef Alias = ;",
			"typedef Alias = Array<Int;",
			"typedef Alias = {value:};",
			"typedef Alias = (value:Int)->String->Bool;",
			"typedef Alias = ()->Int->Bool;",
			"typedef Alias = (?...values:Int)->Int;",
			"typedef Alias = (...?values:Int)->Int;"
		])
			try {
				declaration(source);
				throw "malformed typedef was accepted";
			} catch (error:HxParseError) {
				require(error.pos.getIndex() > 0, "malformed typedef has no source position");
			}
		function integrity(source:String):String {
			final parsed = ParserStage.parse(source, "Alias.hx");
			return ParsedModuleIntegrity.revision(new ParsedModule("same-source-control", parsed.getDecl(), "Alias.hx"));
		}
		require(integrity("typedef Alias=Int;") != integrity("typedef Alias=Bool;"), "typedef target is absent from parsed integrity");
		require(integrity("typedef Alias=(...x:Int)->Int;") != integrity("typedef Alias=(   x:Int)->Int;"), "rest marker is absent from parsed integrity");
		require(integrity("typedef Alias={var x:Int;};") != integrity("typedef Alias={final x:Int;};"), "field mutability is absent from integrity");
		Sys.println("TYPEDEF_PARSER:PASS");
	}
}
