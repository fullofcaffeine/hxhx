import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Explicit this preserves abstract storage, core String values, and ordinary generic class identity. */
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
		coreStringReceiver();
	}

	/** The real core provider receives a primitive value; a qualified class with the same short name does not. */
	static function coreStringReceiver():Void {
		final root = ".tmp/core_string_receiver";
		sys.FileSystem.createDirectory(root + "/custom");
		final custom = 'package custom;class String<T>{public function new(){}public function identity():custom.String<T>{return this;}}';
		final main = 'class Main{static function main():Void{'
			+ 'if("A".charCodeAt(0)!=65)throw "char code";if("hello".substr(1,3)!="ell")throw "substring";'
			+ 'var own=new custom.String<Int>();if(own.identity()!=own)throw "qualified identity";}}';
		sys.io.File.saveContent(root + "/custom/String.hx", custom);
		sys.io.File.saveContent(root + "/Main.hx", main);
		observe("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		observe("node", [root + "/upstream.js"]);
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final sources = [
			new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(main, root + "/Main.hx")),
			new ResolvedModule("custom.String", root + "/custom/String.hx", ParserStage.parse(custom, root + "/custom/String.hx"))
		];
		final index = TyperIndex.buildHeaders(sources);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index, null, true);
		loader.markResolvedAlready(sources);
		for (name in ["String", "HxOverrides"])
			if (loader.ensureTypeAvailable(name, "", []) == null)
				throw "missing real provider: " + name;
		final providers = loader.drainNewModules().filter(module -> ResolvedModule.getModulePath(module) == "String");
		if (providers.length != 1 || !sys.FileSystem.exists(ResolvedModule.getFilePath(providers[0])))
			throw "missing authentic String source";
		final provider = TyperStage.typeResolvedModule(providers[0], index, loader, true);
		var receivers = 0;
		var calls = 0;
		function inspect(expression:TypedExpr):Void {
			if (expression.getTag() == ThisValue) {
				receivers++;
				if (expression.getType().getSemanticKey() != "primitive:String")
					throw "core String this became an ordinary object";
			}
			final declaration = expression.getDeclaration();
			if (expression.getTag() == Call && declaration != null && declaration.getOwner().getCanonicalName() == "HxOverrides") {
				calls++;
				if (expression.getNamedArguments() == null)
					throw "String provider call has no selected argument binding";
			}
			for (child in expression.getExpressions())
				inspect(child);
		}
		for (owner in provider.getTypedClasses())
			for (method in owner.getFunctions())
				for (statement in method.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		if (receivers < 2 || calls < 2)
			throw "core String regression missed its provider bodies";
		final typed = sources.map(source -> TyperStage.typeResolvedModule(source, index, loader, true));
		var ordinaryReceivers = 0;
		function inspectOrdinary(expression:TypedExpr):Void {
			if (expression.getTag() == ThisValue) {
				ordinaryReceivers++;
				final type = expression.getType();
				final identity = type.getNominalIdentity();
				final binders = TyNominalApplication.parameterIds(index.getByFullName("custom.String"));
				if (identity == null
					|| identity.getCanonicalName() != "custom.String"
					|| type.getTypeArguments().length != 1
					|| !type.getTypeArguments()[0].getTypeParameterIdentity().equals(binders[0]))
					throw "qualified String receiver lost its class or generic identity";
			}
			for (child in expression.getExpressions())
				inspectOrdinary(child);
		}
		for (owner in typed[1].getTypedClasses())
			for (method in owner.getFunctions())
				for (statement in method.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspectOrdinary(expression);
		if (ordinaryReceivers != 1)
			throw "qualified String regression missed its receiver";
		final script = root + "/native.js";
		new backend.js.JsBackend().emit(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, index), false),
			new backend.BackendContext(root, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		observe("node", ["--check", script]);
		observe("node", [script]);
		Sys.println("CORE_STRING_THIS:PASS");
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
