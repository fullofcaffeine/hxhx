/** Restricted access remains typed and applies only to the annotated source expression. */
class M14PrivateAccessTest {
	static final provider = "class Other { public var value(null,default):Int; public function new() { value=7; } } ";

	static function typed(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function reject(body:String, message:String, ?declaration:String):Void {
		try {
			typed((declaration == null ? provider : declaration)
				+ "class Main { static function main() { final o=new Other(); "
				+ body
				+ " } }");
		} catch (error:TyperError) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "privateAccess accepted invalid source: " + body;
	}

	/** Compare body permission and generic forwarding with upstream and both executable backends. */
	static function bodyMetadataRuntime(source:String):Void {
		final root = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(root + "/Main.hx", source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != "7\n")
			throw "upstream body metadata differs: " + output + errors;
		final module = typed(source);
		JsRuntimeFixture.assertRuntime(module, "Main", "7\n");
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([module], []), root + "/ocaml", true);
		final native = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable]);
		final nativeOutput = native.stdout.readAll().toString();
		final nativeErrors = native.stderr.readAll().toString();
		final nativeCode = native.exitCode();
		native.close();
		if (nativeCode != 0 || nativeOutput != "7\n")
			throw "native body metadata differs: " + nativeOutput + nativeErrors;
		Sys.println("BODY_METADATA_RUNTIME:PASS");
	}

	static function main():Void {
		// Local initializer mismatches are diagnostics in the strict compiler lane.
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		final bodyMetadataSource = "class Other { public static var value(null,default):Int=7; } "
			+ "class Main { static function read():Int@:privateAccess { return Other.value; } "
			+ "static function identity<T>(value:T):T@:privateAccess { return value; } "
			+ "static function forward<T>(value:T):T { return identity(value); } "
			+ "static function main() { Sys.println(forward(read())); } }";
		bodyMetadataRuntime(bodyMetadataSource);
		try {
			typed(StringTools.replace(bodyMetadataSource, "return identity(value);", "var denied=Other.value; return identity(value);"));
			throw "body permission leaked into the following method";
		} catch (error:TyperError) {
			if (error.message.indexOf("cannot be accessed for reading") < 0)
				throw error;
		}
		for (body in [
			"var a=(@:privateAccess o.value);",
			"@:privateAccess { var a=o.value; }",
			"@:privateAccess var a:Int=o.value; var b:Int=a;",
			"@:privateAccess o.value=o.value+1;",
			"@:privateAccess o.value+=o.value;",
			"@:privateAccess @:privateAccess o.value=true ? o.value : 0;",
			"++@:privateAccess o.value;",
			"@:privateAccess o.value++;",
			"var a=(@:privateAccess (@:privateAccess o.value));",
			"var f=function():Int { return @:privateAccess o.value; }; var a:Int=f();"
		])
			typed(provider + "class Main { static function main() { final o=new Other(); " + body + " } }");
		typed(provider
			+
			"class Main { static var seed:Int=(@:privateAccess new Other().value); static function read(o:Other):Int { @:privateAccess return o.value; } static function main() {} }");
		final quoted = typed("class Main { static function main() { var syntax=macro @:privateAccess value; } }");
		var keptQuote = false;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == MacroExpr) {
				if (node.getExpressions()[0].getTag() != PrivateAccess)
					throw "property lowering erased quoted permission";
				keptQuote = true;
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in quoted.getTypedClasses())
			for (fn in owner.getFunctions())
				for (node in fn.getBody().getStatements())
					statement(node);
		if (!keptQuote)
			throw "typed module lost its quoted source";
		reject("var a=o.value;", "cannot be accessed for reading");
		reject("var a=(@privateAccess o.value);", "cannot be accessed for reading");
		reject("@privateAccess var a=o.value;", "cannot be accessed for reading");
		reject("var a=(@:privateAccess o.value); var b=o.value;", "cannot be accessed for reading");
		reject("var a=@:privateAccess o.value+o.value;", "cannot be accessed for reading");
		reject("(@:privateAccess o.value)=4;", "Invalid assign");
		reject("var a:String=(@:privateAccess o.value);", "String");
		var rejectedRecord = false;
		try {
			typed("class Main { static function consume(v:{value:Int}):Void {} static function main() { consume(@:privateAccess {value:1, extra:2}); } }");
		} catch (error:TyperError) {
			rejectedRecord = true;
		}
		if (!rejectedRecord)
			throw "privateAccess disabled fresh object literal checking";
		reject("@:privateAccess o.value=4;", "cannot be accessed for writing",
			"class Other { public var value(default,never):Int=7; public function new() {} } ");
		reject("var a=(@:privateAccess o.value);", "cannot be accessed for reading",
			"class Other { public var value(never,default):Int; public function new() { value=7; } } ");
		Sys.println("PRIVATE_ACCESS:PASS");
	}
}
