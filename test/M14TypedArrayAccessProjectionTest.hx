/** Exact indexed operations retain types without granting authority to copied or stale syntax. */
class M14TypedArrayAccessProjectionTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function rejected(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (error:String) {
			check(error.indexOf(expected) >= 0, "unexpected array ownership diagnostic: " + error);
			return;
		}
		throw "stale array occurrence retained authority";
	}

	static function main():Void {
		final typed = M14Stage3BoolStringTest.typeModule("ArrayAccessMain");
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final owner = typed.getTypedClasses()[0];
		var boolRead = false;
		var boolWrite = false;
		var intRead = false;
		var dynamicRead = false;
		var intCompound = false;
		for (fn in owner.getFunctions()) {
			final projection = TypedBodySource.functionProjection(fn);
			final foreign = TypedBodySource.functionProjection(fn);
			final entries = new Array<TypedBackendArrayAccess>();
			for (statement in projection.getBody())
				TypedBackendSourceWalk.statement(statement, expression -> {
					final entry = projection.findArrayAccess(expression);
					if (entry != null)
						entries.push(entry);
				}, _ -> {});
			for (entry in entries) {
				check(entry.indexType.getSemanticKey() == "primitive:Int", "array index lost its exact Int type");
				check(foreign.findArrayAccess(entry.expression) == null, "another body supplied array facts");
				check(projection.findArrayAccess(EArrayAccess(entry.receiver, entry.index)) == null, "copied array syntax borrowed facts");
				rejected(() -> entry.assertCurrent("foreign", projection.getBodyRevision()), "belongs to another executable");
				switch entry.kind {
					case Read:
						if (entry.resultType.getSemanticKey() == "primitive:Bool") {
							check(entry.receiverType.getNominalIdentity().getCanonicalName() == "Array"
								&& entry.receiverType.getTypeArguments()[0].getSemanticKey() == "primitive:Bool",
								"Boolean read lost its Array provider");
							boolRead = true;
						}
						intRead = intRead || entry.resultType.getSemanticKey() == "primitive:Int";
						dynamicRead = dynamicRead || (entry.receiverType.isDynamic() && entry.resultType.isDynamic());
					case Write:
						boolWrite = boolWrite || entry.valueType.getSemanticKey() == "primitive:Bool";
					case Compound(op):
						check(op == "+="
							&& entry.resultType.getSemanticKey() == "primitive:Int"
							&& entry.valueType.getSemanticKey() == "primitive:Int",
							"compound update lost its exact operation or types");
						intCompound = true;
				}
			}
			if (entries.length > 0) {
				projection.getBody().resize(0);
				rejected(() -> projection.findArrayAccess(entries[0].expression), "projection was mutated");
			}
		}
		check(boolRead && boolWrite && intRead && dynamicRead && intCompound, "indexed projection lost a required logical storage distinction");
		final projectedClass = TypedBodySource.classProjection(owner);
		var initializerRead = false;
		for (initializer in projectedClass.getFieldInitializers()) {
			TypedBackendSourceWalk.expression(initializer.getExpression(), expression -> {
				final entry = initializer.findArrayAccess(expression);
				if (entry == null)
					return;
				initializerRead = true;
				check(entry.resultType.getSemanticKey() == "primitive:Bool", "initializer indexed read lost Boolean type");
				rejected(() -> entry.assertCurrent("foreign", initializer.getBodyRevision()), "belongs to another executable");
				switch entry.receiver {
					case EArrayDecl(elements):
						elements.push(EBool(false));
						rejected(() -> initializer.findArrayAccess(expression), "projection was mutated");
						elements.pop();
					case _: throw "initializer receiver must retain the authored array";
				}
			});
		}
		check(initializerRead, "initializer array access was not observed");
		check(CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() == revision, "projection changed authored typed source");
		M14Stage3BoolStringTest.run("ArrayAccessMain", "array-access.expected.stdout");
		Sys.println("TYPED_ARRAY_ACCESS_PROJECTION:PASS");
	}
}
