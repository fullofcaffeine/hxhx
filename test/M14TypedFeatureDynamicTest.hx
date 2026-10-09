import haxe.io.Path;
import sys.io.File;

/** Dynamic replacement and bound receiver values must retain exact method contributions and runtime behavior. */
class M14TypedFeatureDynamicTest {
	static function main():Void {
		check("FeatureRecordCallback", "callback:on\nreceiver:on\ntrue\ntrue\ntrue\n");
		check("FeatureBoundEmptyObject", "true\nobject\ntext\n");
		check("FeatureBoundOptional", "1\nfirst\n2\nsecond\n1\nthird\ntrue\n7\nfalse\n9\n");
		checkGenericConflict("FeatureBoundOptionalMissing", "FeatureBoundOptional", "captured callback argument count differs");
		checkGenericConflict("FeatureBoundOptionalExtra", "FeatureBoundOptional", "captured callback argument count differs");
		check("FeatureBoundUnused", "called\ncalled\ndone\n");
		check("FeatureBoundNull", "true\ntrue\ntrue\nchild\ntrue\ntrue\nchild\n");
		checkDirectConstraint("FeatureBoundNullConflict", "FeatureBoundNull", "Constraint check failure for select.T");
		check("FeatureBoundCompound", "compound\n");
		checkDirectConstraint("FeatureBoundCompoundMissingInterface", "FeatureBoundCompound");
		checkDirectConstraint("FeatureBoundCompoundMissingBase", "FeatureBoundCompound");
		check("FeatureBoundInterface", "interface\n");
		checkDirectConstraint("FeatureBoundInterfaceConflict", "FeatureBoundInterface");
		checkDirectConstraint("FeatureBoundInterfaceUndeclared", "FeatureBoundInterface");
		check("FeatureBoundApplied", "child\nchild\n");
		checkDirectConstraint("FeatureBoundAppliedConflict", "FeatureBoundApplied", "Constraint check failure for echo.U");
		checkDirectConstraint("FeatureBoundConstraintDirect");
		checkDirectConstraint("foreign.FeatureBoundConstraintForeign");
		check("FeatureBoundConstraint", "child\nchild\n");
		check("FeatureBoundConstraintCapture", "7\n");
		check("FeatureBoundSubtype", "child\n");
		check("FeatureBoundExpected", "written\nargument\nclass\n9\n");
		checkGenericConflict("FeatureBoundMethodGenericConflict");
		checkGenericConflict("FeatureBoundMethodGenericAliasConflict");
		check("FeatureBoundMethodGeneric", "text\n7\ndirect\nwrapped\n");
		check("FeatureDynamic", "original:on\nreplacement:on\nreplacement:called\n");
		check("FeatureBoundMethod", "bound:on\nmake:first\nmake:second\nfirst\nsecond\nchanged\ntrue\nfalse\nmake:temporary\ntemporary\n");
		check("FeatureBoundContexts", "static\ninstance\nconstructor\nlocal\nlocal\nshadow\nold:changed\nreplacement\nfalse\ntrue\n");
		check("FeatureBoundInheritance", "child:initial\nchild:initial\ntrue\nchild:changed\nchild:changed\n");
		check("FeatureBoundGeneric", "text\n7\ninherited\nimplicit\n");
		Sys.println("TYPED_FEATURE_DYNAMIC:PASS");
	}

	/** Invalid direct calls must report a source type error rather than fail in backend replay. */
	static function checkDirectConstraint(name:String, provider:String = "FeatureBoundConstraint",
			diagnostic:String = "Constraint check failure for echo.T"):Void {
		final root = "test/fixtures/js_feature_intrinsic/";
		final resolved = [
			for (module in [provider, name]) {
				final path = root + StringTools.replace(module, ".", "/") + ".hx";
				new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
			}
		];
		var rejected = false;
		try
			TyperStage.typeResolvedModule(resolved[1], TyperIndex.build(resolved))
		catch (error:TyperError) {
			if (error.getMessage() != diagnostic || error.getFilePath() != root + StringTools.replace(name, ".", "/") + ".hx")
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "invalid direct method constraint was accepted: " + name;
		Sys.println("TYPED_FEATURE_DIRECT_CONSTRAINT:" + name + ":PASS");
	}

	/** A copied callback shares its capture's inferred parameter, so conflicting calls must fail before emission. */
	static function checkGenericConflict(name:String, provider:String = "FeatureBoundMethodGeneric",
			diagnostic:String = "captured callback argument conflicts with its inferred type"):Void {
		final root = "test/fixtures/js_feature_intrinsic/";
		final resolved = [
			for (module in [provider, name]) {
				final path = root + module + ".hx";
				new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
			}
		];
		final index = TyperIndex.build(resolved);
		var rejected = false;
		try
			TyperStage.typeResolvedModule(resolved[1], index)
		catch (error:TyperError) {
			if (error.message != diagnostic || error.filePath != root + name + ".hx")
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "generic callback conflict was accepted: " + name;
		Sys.println("TYPED_FEATURE_GENERIC_CONFLICT:" + name + ":PASS");
	}

	static function check(name:String, expected:String):Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final resolution = new CompilerSourceProvider().resolveModule([root], name);
		final path = resolution.filePath;
		if (path == null)
			throw "dynamic fixture did not resolve: " + name;
		final resolved = new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path), resolution.toOrigin(name));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([module], false);
		final sources = new TypedFeatureSourceCatalog({program: program, classPaths: [root], standardRoot: root + "/origin_lib"});
		final entries = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main")
						fn
		];
		if (entries.length != 1)
			throw "dynamic fixture requires one entry point";
		if (name == "FeatureBoundEmptyObject") {
			final selected = entries[0].getEnvironment().getLocals().filter(local -> local.getName() == "selected");
			if (selected.length != 1 || selected[0].getType().getSemanticKey() != "nominal:FeatureBoundEmptyObject.EmptyObjectValue")
				throw "empty object bound erased the concrete inferred result";
		}
		if (name == "FeatureBoundUnused") {
			final callTypes = new Array<TyType>();
			function inspectUnused(node:TypedExpr):Void {
				final selected = node.getDeclaration();
				if (node.getTag() == Call && selected != null && selected.getSignature().getName() == "echo")
					callTypes.push(node.getType());
				for (child in node.getExpressions())
					inspectUnused(child);
			}
			for (statement in entries[0].getBody().getStatements())
				for (node in statement.getExpressions())
					inspectUnused(node);
			if (callTypes.length != 2
				|| !callTypes[0].isOpenMethodParameter()
				|| !callTypes[1].isOpenMethodParameter()
				|| callTypes[0].getSemanticKey() == callTypes[1].getSemanticKey())
				throw "unused calls must retain distinct immutable open method instances";
			final callbacks = [
				for (local in entries[0].getEnvironment().getLocals())
					if (local.getName() == "callback") local.getType()
			];
			if (callbacks.length != 1 || !callbacks[0].isFunction())
				throw "unused callback lost its callable type";
			final argument = callbacks[0].getFunctionArguments()[0];
			if (!argument.isOpenMethodParameter()
				|| argument.getSemanticKey() != callbacks[0].getFunctionReturn().getSemanticKey()
				|| callTypes.filter(type -> type.getSemanticKey() == argument.getSemanticKey()).length != 0)
				throw "unused callback must share its own argument/result identity only";
		}
		if (name == "FeatureBoundNull") {
			final expectedResults = [
				"nominal:FeatureBoundNull.NullBoundBase",
				"nominal:FeatureBoundNull.NullBoundChild",
				"primitive:Int",
				"nominal:FeatureBoundNull.NullBoundChild",
				"nominal:FeatureBoundNull.NullBoundBase"
			];
			final results = new Array<String>();
			function inspectNullCall(node:TypedExpr):Void {
				final selected = node.getDeclaration();
				if (node.getTag() == Call && selected != null && selected.getSignature().getName() == "echo")
					results.push(node.getType().getSemanticKey());
				for (child in node.getExpressions())
					inspectNullCall(child);
			}
			for (statement in entries[0].getBody().getStatements())
				for (node in statement.getExpressions())
					inspectNullCall(node);
			if (results.join("|") != expectedResults.join("|"))
				throw "null-only generic calls lost their contextual or later inferred results: " + results.join("|");
		}
		if (name == "FeatureBoundApplied") {
			var direct = 0;
			function inspectApplied(node:TypedExpr):Void {
				final selected = node.getDeclaration();
				if (node.getTag() == Call && selected != null && selected.getSignature().getName() == "echo") {
					if (node.getType().getSemanticKey() != "nominal:FeatureBoundApplied.AppliedChild")
						throw "applied bound lost the exact child result: " + node.getType().getSemanticKey();
					final methodParameter = selected.getTypeParameterIds()[0];
					final original = selected.getResolvedTypeParameterConstraints().get(methodParameter.getCanonicalKey())[0];
					if (!original.isTypeParameter() || original.getTypeParameterIdentity().equals(methodParameter))
						throw "receiver substitution mutated or confused the declaration binders";
					direct++;
				}
				for (child in node.getExpressions())
					inspectApplied(child);
			}
			for (statement in entries[0].getBody().getStatements())
				for (node in statement.getExpressions())
					inspectApplied(node);
			if (direct != 2)
				throw "explicit and inherited bound applications were not both inspected";
		}
		if (name == "FeatureBoundConstraint" || name == "FeatureBoundInterface" || name == "FeatureBoundCompound") {
			final resultKey = switch (name) {
				case "FeatureBoundInterface": "nominal:FeatureBoundInterface.InterfaceChild";
				case "FeatureBoundCompound": "nominal:FeatureBoundCompound.CompoundChild";
				case _: "nominal:FeatureBoundConstraint.ConstraintChild";
			};
			final boundKey = switch (name) {
				case "FeatureBoundInterface": "nominal:FeatureBoundInterface.BoundValue<primitive:String>";
				case "FeatureBoundCompound": "nominal:FeatureBoundCompound.CompoundBase&nominal:FeatureBoundCompound.CompoundNamed";
				case _: "nominal:FeatureBoundConstraint.ConstraintBase";
			};
			var direct = 0;
			function inspect(node:TypedExpr):Void {
				final selected = node.getDeclaration();
				if (node.getTag() == Call && selected != null && selected.getSignature().getName() == "echo") {
					if (node.getType().getSemanticKey() != resultKey)
						throw "constrained direct result lost its subtype";
					final key = selected.getTypeParameterIds()[0].getCanonicalKey();
					final constraints = selected.getResolvedTypeParameterConstraints();
					if (constraints.get(key).map(type -> type.getSemanticKey()).join("&") != boundKey)
						throw "constraint lost declaration scope";
					constraints.get(key).pop();
					if (selected.getResolvedTypeParameterConstraints()
						.get(key)
						.map(type -> type.getSemanticKey())
						.join("&") != boundKey)
						throw "caller mutated the declaration constraint list";
					constraints.set(key, [TyType.fromHintText("Int")]);
					if (selected.getResolvedTypeParameterConstraints()
						.get(key)
						.map(type -> type.getSemanticKey())
						.join("&") != boundKey)
						throw "caller mutated declaration constraints";
					direct++;
				}
				for (child in node.getExpressions())
					inspect(child);
			}
			for (statement in entries[0].getBody().getStatements())
				for (node in statement.getExpressions())
					inspect(node);
			if (direct != 1)
				throw "constraint fixture did not inspect its direct call";
		}
		if (name == "FeatureBoundExpected") {
			final observed = [
				for (local in entries[0].getEnvironment().getLocals())
					if (local.getName() == "text" || local.getName() == "alias" || local.getName() == "mixed") local.getType()
						.getFunctionArguments()
						.map(type -> type.getSemanticKey())
						.join(",") + "->"
						+ local.getType().getFunctionReturn().getSemanticKey()];
			if (observed.join(";") != "primitive:String->primitive:String;primitive:String->primitive:String;primitive:String,primitive:Int->primitive:Int")
				throw "expected callback contexts lost exact published types: " + observed.join(";");
		}
		if (name == "FeatureBoundMethodGeneric")
			checkMethodGenericResults(entries[0]);
		if (name == "FeatureBoundGeneric")
			checkGenericSignatures(entries[0]);
		for (mode in ["full", "std", "no"]) {
			final roots = TypedFeatureRoots.select({
				program: program,
				sources: sources,
				entryPoint: entries[0],
				mode: mode
			});
			final reachable = TypedFeatureMemberClosure.retain(roots);
			final names = new TypedFeatureDiscovery(reachable).namesFor(program);
			if (name == "FeatureBoundMethod" && names.indexOf("bound.method") < 0)
				throw "bound method lost its exact feature contribution";
			Sys.println("TYPED_FEATURE_DYNAMIC_DECISIONS:" + name + ":" + mode + ":PASS");
			final emitted = new TypedEmissionRetention({reachable: reachable, mode: mode}).apply(program);
			final selected = TypedFeatureSelection.lower(emitted, names);
			if (name == "FeatureBoundMethod")
				checkMethodOwnership(selected.getTypedModules()[0]);
			M14GenericConstructorArgumentTest.assertRuntime(selected.getTypedModules()[0], name, expected);
			Sys.println("TYPED_FEATURE_DYNAMIC:" + name + ":" + mode + ":PASS");
		}
	}

	/** A generic method's declaration binder must not escape as the result of calling a stored callback. */
	static function checkMethodGenericResults(main:TypedFunction):Void {
		final observed = new Array<String>();
		function expression(node:TypedExpr):Void {
			if (node.getTag() == Call) {
				final callee = node.getExpressions()[0];
				if (callee.getTag() == LocalRead && (callee.getTexts()[0] == "text" || callee.getTexts()[0] == "number"))
					observed.push(node.getType().getSemanticKey());
			}
			for (child in node.getExpressions())
				expression(child);
		}
		for (statement in main.getBody().getStatements())
			for (node in statement.getExpressions())
				expression(node);
		if (observed.join(";") != "primitive:String;primitive:Int")
			throw "generic callback results differ: " + observed.join(";");
	}

	/** Runtime erasure must not hide a lost generic parameter in the compiler's callable type. */
	static function checkGenericSignatures(main:TypedFunction):Void {
		final observed = new Array<String>();
		function expression(node:TypedExpr):Void {
			if (node.getTag() == FieldRead && node.getTexts()[0] == "echo") {
				final type = node.getType();
				if (node.getDeclaration() == null || !type.isFunction() || type.getFunctionArguments().length != 1)
					throw "generic method value lacks its selected declaration and callable signature";
				observed.push(type.getFunctionArguments()[0].getSemanticKey() + "->" + type.getFunctionReturn().getSemanticKey());
			}
			for (child in node.getExpressions())
				expression(child);
		}
		for (statement in main.getBody().getStatements())
			for (node in statement.getExpressions())
				expression(node);
		final expected = [
			"primitive:String->primitive:String",
			"primitive:Int->primitive:Int",
			"primitive:String->primitive:String"
		];
		if (observed.join(";") != expected.join(";"))
			throw "stored generic signatures differ: " + observed.join(";");
	}

	/** Copied syntax and changed receiver operands cannot borrow another occurrence's binding facts. */
	static function checkMethodOwnership(module:TypedModule):Void {
		final functions = [for (owner in module.getTypedClasses()) for (fn in owner.getFunctions()) fn];
		final main = [
			for (fn in functions)
				if (fn.getDeclaration().getSignature().getName() == "main") fn
		][0];
		final projection = TypedBodySource.functionProjection(main);
		final separate = TypedBodySource.functionProjection(main);
		final entries = new Array<TypedBackendMethodOccurrence>();
		for (statement in projection.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final entry = projection.findMethodUse(expression);
				if (entry != null)
					entries.push(entry);
			}, _ -> {});
		if (entries.length != 4)
			throw "expected four exact stored-method reads";
		var mutations = 0;
		for (entry in entries) {
			if (entry.getUse() != ValueRead)
				throw "stored method has another use role";
			final expression = entry.getExpression();
			if (separate.findMethodUse(expression) != null)
				throw "another projection accepted a foreign method occurrence";
			reject(() -> entry.assertCurrent("foreign-owner", projection.getBodyRevision()));
			reject(() -> entry.assertCurrent(projection.getStableIdentity(), "foreign-revision"));
			switch expression {
				case EField(receiver, name):
					if (projection.findMethodUse(EField(receiver, name)) != null)
						throw "copied syntax acquired binding facts";
					switch receiver {
						case ECall(_, arguments):
							final original = arguments[0];
							arguments[0] = EString("mutated");
							reject(() -> {
								projection.findMethodUse(expression);
							});
							arguments[0] = original;
							if (projection.findMethodUse(expression) != entry)
								throw "restored occurrence lost identity";
							mutations++;
						case _:
					}
				case _:
					throw "method occurrence lost its receiver field";
			}
		}
		if (mutations != 1)
			throw "temporary receiver mutation was not exercised";
	}

	static function reject(action:Void->Void):Void {
		var rejected = false;
		try
			action()
		catch (_:String)
			rejected = true;
		if (!rejected)
			throw "invalid method ownership was accepted";
	}
}
