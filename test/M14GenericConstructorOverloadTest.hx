import sys.io.File;

/** Member overload selection must retain one exact declaration and reject conflicting receiver uses. */
class M14GenericConstructorOverloadTest {
	static final root = "test/fixtures/generic_constructor_context";

	/** Extern methods are a compile-time contract; no host implementation is needed. */
	static function upstream(module:String, accepts:Bool, diagnostic:String = "Int should be String"):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, [
			"60",
			"node_modules/.bin/haxe",
			"-cp",
			root,
			"-main",
			module,
			"--no-output",
			"-js",
			"/tmp/hxhx-generic-constructor-unused.js"
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepts || (!accepts && stderr.indexOf(diagnostic) < 0))
			throw "upstream constructor contract changed: " + module + ": " + stdout + stderr;
	}

	static function typeModule(module:String):TypedModule {
		final path = root + "/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function main():Void {
		upstream("OverloadCases", true);
		final typed = typeModule("OverloadCases");
		var calls = 0;
		var constructors = 0;
		function inspect(node:TypedExpr):Void {
			if (node.getTag() == NewValue) {
				constructors++;
				if (node.getType().getSemanticKey() != "nominal:OverloadCases.Box<primitive:String>")
					throw "selected overload lost its receiver constraint";
			}
			final declaration = node.getDeclaration();
			if (node.getTag() == Call && declaration != null && declaration.getSignature().getName() == "choose") {
				calls++;
				if (node.getType().getSemanticKey() != "primitive:Int"
					|| declaration.getSignature().getArgs()[1].getSemanticKey() != "primitive:Bool")
					throw "rejected overload replaced the selected member declaration or result";
			}
			for (child in node.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		if (constructors != 1 || calls != 1)
			throw "overload contract lost its constructor or selected call";
		for (owner in typed.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				fn.requireCaptureCatalog();
		Sys.println("GENERIC_CONSTRUCTOR_OVERLOAD:PASS");

		reject("ConflictCases");
		reject("ConstructorConflictCases");
		reject("ConstructorNumericConflictCases", "Int should be Float");
		Sys.println("GENERIC_CONSTRUCTOR_CONFLICT:PASS");
	}

	/** Inference and typed replay must choose the same original constructor declaration. */
	public static function checkConstructor():Void {
		upstream("ConstructorOverloadCases", true);
		final path = root + "/ConstructorOverloadCases.hx";
		final resolved = new ResolvedModule("ConstructorOverloadCases", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		if (index.getByFullName("ConstructorOverloadCases.Box").instanceMethodCandidates("new").length != 2)
			throw "constructor metadata did not retain both overload declarations";
		final typed = TyperStage.typeResolvedModule(resolved, index);
		var checked = 0;
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (expression in statement.getExpressions())
						if (expression.getTag() == NewValue) {
							checked++;
							final application = expression.getConstructorApplication();
							if (expression.getType().getSemanticKey() != "nominal:ConstructorOverloadCases.Box<primitive:String>"
								|| application == null
								|| application.getParameterTypes()[0].getSemanticKey() != "primitive:String"
								|| application.getDeclaration().getSignature().getArgs()[1].getSemanticKey() != "primitive:Bool")
								throw "constructor candidate inference did not preserve the selected applied declaration";
						}
		if (checked != 1)
			throw "constructor overload fixture lost its allocation";
		Sys.println("GENERIC_CONSTRUCTOR_CANDIDATE:PASS");
	}

	/** Both member and constructor contradictions must fail before typed publication. */
	public static function reject(module:String, diagnostic:String = "Int should be String"):Void {
		upstream(module, false, diagnostic);
		var rejected = false;
		try {
			typeModule(module);
		} catch (error:TyperError) {
			rejected = error.message.indexOf("generic constructor") >= 0;
		}
		if (!rejected)
			throw "conflicting generic use was not rejected during shared typing: " + module;
	}
}
