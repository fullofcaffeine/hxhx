import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** Method linkage requires current caller ownership as well as the selected callee declaration. */
class M14CppManagedInstanceMethodTest {
	static function program():CppTypedProgramProjection {
		final source = 'class Main { static function main():Void { final value = new Box(7); value.read(); } }'
			+ ' abstract Box(Int) { public function new(value:Int) { this = value; } public function read():Int { return this; } }';
		final parsed = new ResolvedModule('Main', 'Main.hx', ParserStage.parse(source, 'Main.hx'));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]));
		return new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
	}

	static function rejected(action:Void->Void, diagnostic:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) < 0)
				throw error;
			return;
		}
		throw 'instance method ownership control unexpectedly passed';
	}

	public static function main():Void {
		final source = program();
		final classes = new CppManagedClassStorage(source);
		final main = source.requireClass(source.requireClassIdentity('Main')).getFunctions()[0];
		var selected:Null<TypedBackendInstanceCallOccurrence> = null;
		for (statement in main.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final found = main.findInstanceCall(expression);
				if (found != null)
					selected = found;
			}, _ -> {});
		if (selected == null)
			throw 'instance method fixture lost its exact call';
		final call = selected;
		rejected(() -> classes.methods.requireInstanceMethod(call), 'another program or occurrence');
		if (classes.methods.functionInstanceCall(main, call.getExpression()) != call)
			throw 'instance method registration replaced its occurrence';
		final target = classes.methods.requireInstanceMethod(call);
		if (target.requireSemanticDeclaration() != call.getDeclaration() || target.getReturnType().getSemanticKey() != 'primitive:Int')
			throw 'instance method selected another declaration or result';
		final other = new CppManagedClassStorage(program());
		rejected(() -> other.methods.requireInstanceMethod(call), 'another program or occurrence');
		rejected(() -> other.methods.functionInstanceCall(main, call.getExpression()), 'foreign function owner');
		Sys.println('CPP_MANAGED_INSTANCE_METHOD:PASS');
	}
}
