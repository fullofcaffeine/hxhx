/** A retained named-call mapping cannot be borrowed or changed by a later tree rewrite. */
class M14NamedCallBindingTest {
	static function call():TypedExpr {
		final source = 'class Main { static function take(value:Int=4, tail:String):Int return value; static function main():Void { take("tail"); } }';
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var found:Null<TypedExpr> = null;
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Call && value.getDeclaration() != null && value.getDeclaration().getSignature().getName() == "take")
				found = value;
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (value in fn.getBody().getStatements())
					statement(value);
		if (found == null)
			throw "named binding fixture lost its call";
		return found;
	}

	static function rejects(run:Void->Void, expected:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "named binding accepted invalid input: " + expected;
	}

	/** A call on the current generic receiver retains its owner's binder through publication. */
	static function ownerParameter():Void {
		final source = 'class Box<T> { public var value:T; public function new(value:T) { fill(value); } function fill(value:T):Void { this.value=value; } }'
			+ 'class Main { static function main():Void { Sys.println(new Box("stored").value); } }';
		final path = ".tmp/named-call-owner-parameter/Main.hx";
		sys.FileSystem.createDirectory(haxe.io.Path.directory(path));
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", haxe.io.Path.directory(path), "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != "stored\n")
			throw "upstream owner-parameter contract differs: " + output + errors;
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var calls = 0;
		function expression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == "fill") {
				final binding = value.getNamedArguments();
				final expected = declaration.getSignature().getArgs()[0].getSemanticKey();
				if (binding == null
					|| binding.getArguments().getFunctionType().getFunctionArguments()[0].getSemanticKey() != expected
					|| value.getExpressions()[1].getType().getSemanticKey() != expected)
					throw "named call erased or replaced the current receiver's type parameter";
				calls++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (calls != 1)
			throw "owner-parameter fixture lost its exact call";
		JsRuntimeFixture.assertRuntime(typed, "Main", "stored\n");
	}

	static function main():Void {
		ownerParameter();
		final selected = call();
		final binding = selected.getNamedArguments();
		if (binding == null)
			throw "named call did not publish its mapping";
		final slots = binding.getArguments().getSlots();
		if (slots.length != 2 || !slots[0].match(Omitted) || !slots[1].match(Supplied(0)))
			throw "named call lost its skipped slot";
		final projected = TypedCallArgumentSource.types(binding.getArguments());
		if (projected.length != 2
			|| projected[0].getSemanticKey() != TyType.fromHintText("Null").getSemanticKey()
			|| projected[1].getSemanticKey() != TyType.fromHintText("String").getSemanticKey())
			throw "projected type facts differ from internal omission and supplied operand";
		if (binding.getArguments().getOperandTypes().length != 1)
			throw "projection changed authored operand facts";
		slots[0] = Supplied(0);
		if (!binding.getArguments().getSlots()[0].match(Omitted))
			throw "named slots exposed mutable storage";
		selected.withExpressions(selected.getExpressions()).assertArgumentBinding();
		final changed = selected.getExpressions();
		changed[1] = TypedExpr.intLiteral(7, TyType.fromHintText("Int"), null);
		rejects(() -> {
			selected.withExpressions(changed);
		}, "stale operand type");
		rejects(() -> {
			selected.withType(TyType.fromHintText("Bool"));
		}, "stale result type");
		rejects(() -> {
			call().withNamedArguments(binding);
		}, "another or changed declaration");
		Sys.println("NAMED_CALL_BINDING:PASS");
	}
}
