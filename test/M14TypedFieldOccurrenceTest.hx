/** Resolved owners must survive qualified access, distinct classes, shadowing, and initializer projection. */
class M14TypedFieldOccurrenceTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function rejects(run:Void->Void, diagnostic:String):Void {
		try {
			run();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(diagnostic) >= 0)
				return;
			throw failure;
		}
		throw "field projection accepted invalid ownership";
	}

	static function main():Void {
		final text = "class Main { static var state:Int; static var copied:Int = Other.state;"
			+ " static function read():Int { return state + Other.state + Base.inherited; }"
			+ " static function shadow(state:Int):Int { return state; }"
			+ " static function receiver(Other:Box):Int { return Other.value; }"
			+ " static function closure():Void->Int { return function():Int { return Other.state; }; } }"
			+ " class Other { public static var state:Int; }"
			+ " class Base { public static var inherited:Int; }"
			+ " class Box { public var value:Int; }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(text, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final projection = typed.getBackendProjection();
		final main = projection.getClasses()[0];
		function method(name:String):TypedBackendFunctionProjection {
			for (fn in main.getFunctions())
				if (HxFunctionDecl.getName(fn.getDeclaration()) == name)
					return fn;
			throw "missing source method " + name;
		}
		function fields(fn:TypedBackendFunctionProjection):Array<TypedBackendFieldOccurrence> {
			final found = [];
			for (statement in fn.getBody())
				TypedBackendSourceWalk.statement(statement, expression -> {
					final occurrence = fn.findField(expression);
					if (occurrence != null)
						found.push(occurrence);
				}, _ -> {});
			return found;
		}
		final read = method("read");
		final selected = fields(read);
		check([for (entry in selected) entry.getField().getCanonicalKey()].join(",") == "Main#static#state,Main.Other#static#state,Main.Base#static#inherited",
			"qualified field owner changed: " + [for (entry in selected) entry.getField().getCanonicalKey()].join(","));
		check(selected[0].getReceiver() == ImplicitOwner
			&& selected[1].getReceiver() == TypeQualifier
			&& selected[2].getReceiver() == TypeQualifier,
			"type qualifier became a value receiver");
		for (entry in selected)
			check(entry.getType().getSemanticKey() == "primitive:Int", "field result type was lost");
		check(fields(method("shadow")).length == 0, "local shadowing acquired static ownership");
		final receiver = fields(method("receiver"));
		check(receiver.length == 1
			&& receiver[0].getField().getCanonicalKey() == "Main.Box#instance#value"
			&& receiver[0].getReceiver() == ValueReceiver,
			"local receiver effects were discarded");
		final closure = fields(method("closure"));
		check(closure.length == 1
			&& closure[0].getField().getCanonicalKey() == "Main.Other#static#state", "nested field identity was lost");
		final initializer = main.getFieldInitializers()[0];
		final initial = [];
		TypedBackendSourceWalk.expression(initializer.getExpression(), expression -> {
			final occurrence = initializer.findField(expression);
			if (occurrence != null)
				initial.push(occurrence);
		});
		check(initial.length == 1
			&& initial[0].getField().getCanonicalKey() == "Main.Other#static#state", "initializer dependency was lost");
		check(read.findField(initial[0].getExpression()) == null, "another executable's field was accepted");
		final copied:HxExpr = EField(EIdent("Other"), "state");
		check(read.findField(copied) == null, "copied source spelling acquired field facts");
		rejects(() -> selected[0].assertCurrent(read.getStableIdentity(), "wrong-revision"), "another executable or revision");
		final old = selected[0].getExpression();
		read.getBody().resize(0);
		rejects(() -> {
			read.findField(old);
		}, "absent from the current function");
		Sys.println("TYPED_FIELD_OCCURRENCE:PASS");
	}
}
