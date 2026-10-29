/** Verify exact bitwise facts before the shared runtime observer emits its program. */
class M14IntBitwiseProjectionTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function rejected(action:Void->Void):Void {
		try {
			action();
		} catch (_:String) {
			return;
		}
		throw "stale bitwise occurrence retained authority";
	}

	public static function verify(module:TypedModule):Void {
		final revision = CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity();
		var concrete = 0;
		var dynamicInput = 0;
		var initializerCount = 0;
		for (owner in module.getTypedClasses()) {
			for (fn in owner.getFunctions()) {
				final projection = TypedBodySource.functionProjection(fn);
				final foreign = TypedBodySource.functionProjection(fn);
				final entries = new Array<TypedBackendBitwiseOccurrence>();
				for (statement in projection.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final entry = projection.findBitwise(expression);
						if (entry != null)
							entries.push(entry);
					}, _ -> {});
				for (entry in entries) {
					check(foreign.findBitwise(entry.expression) == null, "foreign function supplied bitwise facts");
					check(projection.findBitwise(EBinop(entry.operation, entry.left, entry.right)) == null, "copied syntax borrowed bitwise facts");
					rejected(() -> entry.assertCurrent("foreign", projection.getBodyRevision()));
					if (entry.isConcreteInt())
						concrete++;
					else if (entry.leftType.isDynamic())
						dynamicInput++;
				}
				if (entries.length != 0) {
					projection.getBody().resize(0);
					rejected(() -> projection.findBitwise(entries[0].expression));
				}
			}
			final fields = TypedBodySource.classProjection(owner);
			final foreignFields = TypedBodySource.classProjection(owner).getFieldInitializers();
			for (field in fields.getFieldInitializers())
				TypedBackendSourceWalk.expression(field.getExpression(), expression -> {
					final entry = field.findBitwise(expression);
					if (entry == null)
						return;
					check(entry.isConcreteInt(), "initializer lost its concrete Int operation");
					for (foreign in foreignFields)
						check(foreign.findBitwise(expression) == null, "foreign initializer supplied bitwise facts");
					rejected(() -> entry.assertCurrent("foreign", field.getBodyRevision()));
					initializerCount++;
				});
		}
		check(concrete >= 6 && dynamicInput == 1 && initializerCount == 1, "bitwise observer lost a required operation category");
		check(CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity() == revision, "projection changed authored typed source");
		Sys.println("INT_BITWISE_PROJECTION:PASS");
	}
}
