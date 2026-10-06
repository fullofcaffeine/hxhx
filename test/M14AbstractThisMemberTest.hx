/** Explicit this inside an abstract selects its storage members, with exact generic arguments. */
class M14AbstractThisMemberTest {
	static function main():Void {
		final root = ".tmp/abstract_this_member";
		sys.FileSystem.createDirectory(root);
		final source = 'class Storage<T> {public var value:T;public function new(value:T){this.value=value;} public function duplicate():Storage<T> {return new Storage<T>(value);}}'
			+
			'abstract Wrapper<T>(Storage<T>) {public function new(value:T){this=new Storage<T>(value);} public function duplicate<U>():Wrapper<U> {return cast null;} public function extract():Storage<T> {return this.duplicate();} public function parenthesized():Storage<T> {return (this).duplicate();} public function read():T {return this.value;} public function captured():Storage<T> {var method=this.duplicate;return method();}}'
			+
			'class Main {static function main(){var box=new Wrapper<Int>(7);if(box.extract().value!=7) throw "direct";if(box.parenthesized().value!=7) throw "parenthesized";if(box.read()!=7) throw "field";if(box.captured().value!=7) throw "method value";}}';
		sys.io.File.saveContent(root + "/Main.hx", source);
		observe("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final resolved = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		var calls = 0;
		function inspect(expr:TypedExpr):Void {
			final declaration = expr.getDeclaration();
			if (expr.getTag() == Call && declaration != null && declaration.getSignature().getName() == "duplicate") {
				calls++;
				if (declaration.getOwner().getCanonicalName() != "Main.Storage"
					|| expr.getType().getNominalIdentity().getCanonicalName() != "Main.Storage"
					|| expr.getType()
						.getTypeArguments()[0].getTypeParameterIdentity()
						.getCanonicalKey() != TyNominalApplication.parameterIds(index.getByFullName("Main.Wrapper"))[0].getCanonicalKey())
					throw "abstract this lost its storage declaration or generic binding";
			}
			for (child in expr.getExpressions())
				inspect(child);
		}
		function statements(values:Array<TypedStmt>):Void {
			for (statement in values) {
				for (expr in statement.getExpressions())
					inspect(expr);
				statements(statement.getStatements());
			}
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				statements(fn.getBody().getStatements());
		if (calls != 2)
			throw "abstract this fixture lost a call";
		final script = root + "/main.js";
		new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(root, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		observe("node", ["--check", script]);
		observe("node", [script]);
		Sys.println("ABSTRACT_THIS_MEMBER:PASS");
	}

	/** Runtime assertions are authored independently and run through both compilers. */
	static function observe(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "")
			throw command + " abstract this observer failed: " + stdout + stderr;
	}
}
