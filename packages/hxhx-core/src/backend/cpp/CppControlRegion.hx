package backend.cpp;

/** Native return transport is separate from the source function's control destination. */
enum CppControlFunctionResult {
	NoValue;
	DirectValue(nativeType:String);
	RootedValue(destination:String);
}

/** C++ spelling for shared executable regions; control decisions remain in typed lowering. */
typedef CppControlRegionServices = {
	final statement:(statement:HxStmt, indent:String) -> Array<String>;
	final returnValue:(value:HxExpr, expectedType:String) -> String;

	/** Direct results can require collecting calls before the native return statement. */
	final directReturn:(value:HxExpr, nativeType:String, indent:String) -> Array<String>;

	/** Statement-based emission keeps allocating expressions rooted through result publication. */
	final rootedValue:(value:HxExpr, destination:String, indent:String) -> Array<String>;

	final forLoop:(binding:HxForBinding, iterable:HxExpr, indent:String, renderBody:String->Array<String>) -> Array<String>;
	final switchArms:(scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, indent:String, renderBody:(Int, String) -> Array<String>) -> Array<String>;
}

/** Identify an actual lowered function body before selecting an expression renderer. */
function isFunctionBody(body:HxExpr):Bool
	return switch body {
		case ELoweredControl(FunctionBody, _, _, _): true;
		case _: false;
	};

/** Roots and closures must validate the same selected native return transport. */
private function validateResult(result:CppControlFunctionResult):Void {
	switch result {
		case RootedValue(destination):
			if (destination == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(destination))
				throw "C++ rooted return requires a stable destination symbol";
		case DirectValue(nativeType):
			if (nativeType == null || nativeType.length == 0 || nativeType == "void")
				throw "C++ direct return requires a value type";
		case NoValue:
	}
}

/** Render a lowered closure region; each return must name its exact function destination. */
function renderFunction(body:HxExpr, result:CppControlFunctionResult, scope:Null<CppRenderScope>, services:CppControlRegionServices):String {
	validateResult(result);
	return switch body {
		case ELoweredControl(FunctionBody, target, entries, _):
			if (target.length == 0)
				throw "C++ function control region has no return destination";
			renderEntries(entries, target, result, "  ", scope, services).join("\n");
		case _:
			throw "C++ statement function requires a shared function region";
	};
}

/**
	Render the checked method statement view with the same return services as closures.
	Expressions retain their exact cataloged objects. Ordinary returns inherit the
	method's typed destination; nested callable bodies establish their own elsewhere.
	Loop and catch statements need their exact control/binding projection before admission.
 */
function renderRoot(projection:TypedBackendFunctionProjection, result:CppControlFunctionResult, scope:Null<CppRenderScope>,
		services:CppControlRegionServices):String {
	validateResult(result);
	final target = projection.requireRootControlIdentity();
	return renderRootStatements(projection, projection.getBody(), target, result, "  ", scope, services).join("\n");
}

/**
	Run a field's lowered effects before publishing its final value into a root.
	An initializer has no function return destination. Its final operand stays in
	the same lexical scope as its declarations, and abrupt completion skips publication.
 */
function renderInitializer(projection:TypedBackendFieldInitializerProjection, destination:String, indent:String,
		services:CppControlRegionServices):Array<String> {
	projection.assertCurrent();
	validateResult(RootedValue(destination));
	final body = projection.getExpression();
	final lines = switch body {
		case ELoweredControl(Initializer(hasValue), owner, entries, _):
			if (owner != projection.getStableIdentity() || (hasValue && entries.length == 0))
				throw "C++ initializer differs from its exact field owner";
			final count = entries.length - (hasValue ? 1 : 0);
			final emitted = renderEntries(entries.slice(0, count), "", NoValue, indent, null, services);
			if (hasValue)
				for (line in services.rootedValue(entries[count], destination, indent))
					emitted.push(line);
			emitted;
		case ELoweredControl(_, _, _, _):
			throw "C++ initializer requires its shared initializer region";
		case _:
			services.rootedValue(body, destination, indent);
	};
	projection.assertCurrent();
	return lines;
}

private function renderRootStatements(projection:TypedBackendFunctionProjection, statements:Array<HxStmt>, target:String, result:CppControlFunctionResult,
		indent:String, scope:Null<CppRenderScope>, services:CppControlRegionServices, loop:String = ""):Array<String> {
	final lines = new Array<String>();
	for (statement in statements) {
		final emitted = switch statement {
			case SReturn(value, position): renderEntries([ELoweredControl(Return, target, [value], position)], target, result, indent, scope, services);
			case SReturnVoid(position): renderEntries([ELoweredControl(Return, target, [], position)], target, result, indent, scope, services);
			case SExpr(value, _): renderEntries([value], target, result, indent, scope, services, loop);
			case SVar(_, _, _, _, _): services.statement(statement, indent);
			case SThrow(_, _): services.statement(statement, indent);
			case SBlock(children, _):
				[indent + "{"].concat(CppLocalScope.isolate(scope,
					() -> renderRootStatements(projection, children, target, result, indent + "  ", scope, services, loop)))
					.concat([indent + "}"]);
			case SSwitch(scrutinee, patterns, bodies, _):
				if (patterns.length != bodies.length)
					throw "C++ root switch differs from its shared arm layout";
				services.switchArms(scrutinee, patterns, indent,
					(index,
							bodyIndent) -> CppLocalScope.isolate(scope,
							() -> renderRootStatements(projection, [bodies[index]], target, result, bodyIndent, scope, services, loop)));
			case SIf(condition, yes, no, _):
				final branch = [indent + "if (" + services.returnValue(condition, "bool") + ") {"];
				for (line in CppLocalScope.isolate(scope, () -> renderRootStatements(projection, [yes], target, result, indent + "  ", scope, services, loop)))
					branch.push(line);
				branch.push(indent + "}");
				if (no != null) {
					branch.push(indent + "else {");
					for (line in CppLocalScope.isolate(scope,
						() -> renderRootStatements(projection, [no], target, result, indent + "  ", scope, services, loop)))
						branch.push(line);
					branch.push(indent + "}");
				}
				branch;
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _):
				final control = projection.requireStatementControl(statement);
				if (control.binding == null)
					throw "C++ root for requires its exact binding";
				services.forLoop(control.binding, iterable, indent,
					bodyIndent -> CppLocalScope.isolate(scope,
						() -> renderRootStatements(projection, [body], target, result, bodyIndent, scope, services, control.destination)));
			case SWhile(condition, body, _) | SDoWhile(body, condition, _):
				final control = projection.requireStatementControl(statement);
				final isDo = switch statement {
					case SDoWhile(_, _, _): true;
					case _: false;
				};
				final test = services.returnValue(condition, "bool");
				final lines = [indent + (isDo ? "do {" : "while (" + test + ") {")];
				for (line in CppLocalScope.isolate(scope,
					() -> renderRootStatements(projection, [body], target, result, indent + "  ", scope, services, control.destination)))
					lines.push(line);
				lines.push(indent + (isDo ? "} while (" + test + ");" : "}"));
				lines;
			case SBreak(_) | SContinue(_):
				final control = projection.requireStatementControl(statement);
				if (loop.length == 0 || control.destination != loop)
					throw "C++ root loop exit differs from its exact destination";
				[
					indent + (switch statement {
						case SBreak(_): "break;";
						case _: "continue;";
					})
				];
			case _: throw "managed root statement requires exact control projection for " + Type.enumConstructor(statement);
		};
		for (line in emitted)
			lines.push(line);
	}
	return lines;
}

private function renderEntries(entries:Array<HxExpr>, target:String, result:CppControlFunctionResult, indent:String, scope:Null<CppRenderScope>,
		services:CppControlRegionServices, loop:String = ""):Array<String> {
	final lines = new Array<String>();
	for (entry in entries) {
		switch entry {
			case ELoweredControl(Try(_), _, _, _):
				throw "C++ try regions require ordered typed catch emission (haxe_ocaml-qrk0u)";
			case ELoweredControl(Switch(patterns), destination, children, _):
				if (destination.length != 0 || children.length != patterns.length + 1)
					throw "C++ switch differs from its shared arm layout";
				for (index in 1...children.length)
					switch children[index] {
						case ELoweredControl(Scope, "", _, _):
						case _: throw "C++ switch arm requires a shared lexical scope";
					}
				for (line in services.switchArms(children[0], patterns, indent,
					(index, bodyIndent) -> renderEntries([children[index + 1]], target, result, bodyIndent, scope, services, loop)))
					lines.push(line);
			case ELoweredControl(For(binding), destination, children, _):
				if (destination.length == 0 || children.length != 2)
					throw "C++ for differs from its shared loop layout";
				final body = switch children[1] {
					case ELoweredControl(Scope, "", entries, _): entries;
					case _: throw "C++ for body requires a shared lexical scope";
				};
				for (line in services.forLoop(binding, children[0], indent,
					bodyIndent -> CppLocalScope.isolate(scope, () -> renderEntries(body, target, result, bodyIndent, scope, services, destination))))
					lines.push(line);
			case ELoweredControl(While(kind), destination, children, _):
				if (destination.length == 0 || children.length != 2)
					throw "C++ while differs from its shared loop layout";
				switch children[1] {
					case ELoweredControl(Scope, "", _, _):
					case _: throw "C++ while body requires a shared lexical scope";
				}
				final condition = services.returnValue(children[0], "bool");
				lines.push(indent + (kind == DoWhile ? "do" : "while (" + condition + ")"));
				for (line in renderEntries([children[1]], target, result, indent, scope, services, destination))
					lines.push(line);
				if (kind == DoWhile)
					lines.push(indent + "while (" + condition + ");");
			case ELoweredControl(Break, destination, children, _) | ELoweredControl(Continue, destination, children, _):
				if (loop.length == 0 || destination != loop || children.length != 0)
					throw "C++ loop exit differs from its shared loop destination";
				final spelling = switch entry {
					case ELoweredControl(Break, _, _, _): "break";
					case _: "continue";
				};
				lines.push(indent + spelling + ";");
			case ELoweredControl(Scope, scopeTarget, children, _):
				if (scopeTarget.length != 0)
					throw "C++ lexical scope cannot establish a function destination";
				lines.push(indent + "{");
				final nested = CppLocalScope.isolate(scope, () -> renderEntries(children, target, result, indent + "  ", scope, services, loop));
				for (line in nested)
					lines.push(line);
				lines.push(indent + "}");
			case ELoweredControl(Return, destination, values, _):
				if (target.length == 0 || destination != target || values.length > 1)
					throw "C++ return differs from its shared function destination";
				if (values.length == 0 && result != NoValue)
					throw "C++ value-returning function has a valueless return";
				switch result {
					case NoValue:
						lines.push(indent + (values.length == 0 ? "return;" : "return " + services.returnValue(values[0], "void") + ";"));
					case DirectValue(nativeType):
						for (line in services.directReturn(values[0], nativeType, indent))
							lines.push(line);
					case RootedValue(root):
						for (line in services.rootedValue(values[0], root, indent))
							lines.push(line);
						lines.push(indent + "return;");
				}
			case ELoweredControl(Branch, destination, children, _):
				if (destination.length != 0 || (children.length != 2 && children.length != 3))
					throw "C++ conditional differs from its shared branch layout";
				for (index in 1...children.length)
					switch children[index] {
						case ELoweredControl(Scope, "", _, _):
						case _: throw "C++ conditional branch requires a shared lexical scope";
					}
				lines.push(indent + "if (" + services.returnValue(children[0], "bool") + ")");
				for (line in renderEntries([children[1]], target, result, indent, scope, services, loop))
					lines.push(line);
				if (children.length == 3) {
					lines.push(indent + "else");
					for (line in renderEntries([children[2]], target, result, indent, scope, services, loop))
						lines.push(line);
				}
			case ELoweredControl(Throw, destination, values, position):
				if (destination.length != 0 || values.length != 1)
					throw "C++ throw differs from its shared operand layout";
				for (line in services.statement(SThrow(values[0], position), indent))
					lines.push(line);
			case ELoweredControl(FunctionBody, _, _, _):
				throw "C++ nested function region requires a callable value";
			case EVars(declarations):
				for (declaration in declarations) {
					if (HxExprVarDecl.getIsStatic(declaration))
						throw "source static locals require shared storage lowering";
					final statement = HxStmt.SVar(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration),
						HxExprVarDecl.getInitializer(declaration), HxExprVarDecl.getPosition(declaration));
					for (line in services.statement(statement, indent))
						lines.push(line);
				}
			case _:
				for (line in services.statement(SExpr(entry, HxPos.unknown()), indent))
					lines.push(line);
		}
	}
	return lines;
}
