package backend.ocaml;

import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlGenericCallEmitter.convertView;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.runtimeHelpers;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/**
	Own callback layout selection for one native compilation request.

	The source scan rejects a connected group when any consumer cannot use callback
	views. This owner then binds selected functions to their exact current typed
	declarations and projections. A new request gets a new target registry. Source
	or projection mutation invalidates the selection before it can emit syntax.
**/
class Stage3OcamlCallableProgram {
	final modules:Array<TypedModule>;
	final revision:String;
	final registry:OcamlRepresentationRegistry;
	final selected:Map<String, TypedFunction> = [];

	public final externs:Stage3OcamlExternBindings;
	public final generics:Stage3OcamlGenericMethods;

	public function new(modules:Array<TypedModule>) {
		this.modules = modules.copy();
		externs = new Stage3OcamlExternBindings(modules);
		generics = new Stage3OcamlGenericMethods(modules);
		revision = currentRevision();
		registry = new OcamlRepresentationRegistry();
		registry.beginProgram(revision);
		final admitted = Stage3OcamlCallableSelection.select(modules);
		for (module in modules)
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (Lambda.exists(admitted, method -> method.calleeId == fn.getStableIdentity()))
						selected.set(fn.getStableIdentity(), fn);
	}

	/** The whole consumer graph, including rejected observers, belongs to this selection. */
	public function assertCurrent():Void {
		if (currentRevision() != revision)
			throw "Native callback program changed after selection";
	}

	function currentRevision():String {
		return CompilerCacheIdentity.encode([
			for (module in modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		]);
	}

	/** Equal names and revisions from a separately typed program cannot borrow declaration ownership. */
	public function bind(projection:TypedBackendFunctionProjection, names:Stage3OcamlLocalNames):Null<Stage3OcamlCallableFunction> {
		final fn = selected.get(projection.getStableIdentity());
		if (fn == null)
			return null;
		assertCurrent();
		if (projection.requireSemanticDeclaration() != fn.getDeclaration()
			|| projection.getBodyRevision() != CompilerTypedTreeRevision.functionBody(fn))
			throw "Native callback projection belongs to another typed owner";
		projection.requireCaptureCatalog();
		names.requireOwner(projection.getLocalCatalog());
		return new Stage3OcamlCallableFunction(this, projection, names);
	}

	/** Resolve the shared target's registered layout, never a locally invented arrow or identity pair. */
	public function carrier(shape:OcamlGenericValueShape):String {
		final selected = registry.selectCallableView(shape, InternalValue);
		final descriptor = registry.requireCallableView(selected.id, selected.revision, revision);
		return new OcamlASTPrinter().printType(reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.typeExpr(descriptor));
	}
}

/**
	Materialize callback operations from one selected function's exact expressions.

	The legacy emitter supplies rendered operands. Each becomes a real native local
	before the shared target builds structured syntax around it. This preserves
	source evaluation order without treating target source text as an identifier or
	changing the shared callback conversion and identity rules.
**/
@:allow(backend.ocaml.Stage3OcamlCallableProgram)
class Stage3OcamlCallableFunction {
	final program:Stage3OcamlCallableProgram;
	final projection:TypedBackendFunctionProjection;
	final catalog:TypedBackendCaptureCatalog;
	final names:Stage3OcamlLocalNames;
	final printer = new OcamlASTPrinter();
	final generated:Map<String, Bool> = [];
	var next = 0;

	function new(program:Stage3OcamlCallableProgram, projection:TypedBackendFunctionProjection, names:Stage3OcamlLocalNames) {
		this.program = program;
		this.projection = projection;
		catalog = projection.requireCaptureCatalog();
		this.names = names;
	}

	function current():Void {
		program.assertCurrent();
		catalog.assertCurrent();
	}

	function fresh(role:String):String {
		var name:String;
		do {
			name = names.internalName("__hx_view_" + role + "_" + next++);
		} while (generated.exists(name));
		generated.set(name, true);
		return name;
	}

	function source(expression:HxExpr):Null<TypedExpr> {
		program.assertCurrent();
		// The catalog validates every lookup. Reuse its identity without performing
		// the same full validation once in the getter and again in the lookup.
		return catalog.findCallableExpression(expression);
	}

	function shape(type:TyType):OcamlGenericValueShape {
		final selected = Stage3OcamlCallableSelection.valueShape(type);
		if (selected == null)
			throw "Native callback occurrence has an unsupported value type: " + type.getSemanticKey();
		if (selected.match(FunctionValue(_, _)))
			program.carrier(selected);
		return selected;
	}

	/** Function annotations change only inside the selected connected component. */
	public function type(type:TyType):Null<String> {
		current();
		return TyAliasExpansion.reveal(type).isFunction() ? program.carrier(shape(type)) : null;
	}

	function convert(actual:TyType, expected:TyType, value:OcamlExpr):OcamlExpr {
		// A typed null literal is already the emitter's canonical Obj.t null sentinel.
		// It can enter Dynamic unchanged; it does not authorize a nullable callback.
		if (actual.isNullLiteral() && expected.isDynamic())
			return value;
		final conversion = crossing(shape(actual), shape(expected));
		if (conversion == null)
			throw "Native callback occurrence lacks a selected conversion";
		final helpers = runtimeHelpers(conversion, "native-callback");
		return convertView(conversion, value, "native-callback", fresh, (role, symbol) -> {
			if (!Lambda.exists(helpers, helper -> helper.role == role && helper.symbol == symbol))
				throw "Native callback syntax requested an unplanned runtime helper";
			return EIdent(symbol);
		});
	}

	/** Bind the legacy operand once, then let shared target syntax own the selected operation. */
	function bindValues(values:Array<String>, body:Array<OcamlExpr>->OcamlExpr):String {
		final locals = [for (_ in values) fresh("operand")];
		var output = printer.printExpr(body([for (name in locals) EIdent(name)]));
		var index = values.length;
		while (index-- > 0)
			output = "(let " + locals[index] + " = (" + values[index] + ") in " + output + ")";
		return output;
	}

	/** A local conversion requires the original destination and initializer, not just the destination type. */
	public function local(name:String, expression:HxExpr, rendered:String):Null<String> {
		final destination = names.findType(name);
		if (destination == null || !TyAliasExpansion.reveal(destination).isFunction())
			return null;
		current();
		final write = projection.requireLocalWrite(name, expression);
		return bindValues([rendered], values -> convert(write.sourceType, write.binding.getType(), values[0]));
	}

	/** Root method returns are converted before entering the method's return exception. */
	public function returned(statement:HxStmt, rendered:String):Null<String> {
		if (!TyAliasExpansion.reveal(projection.getReturnType()).isFunction())
			return null;
		current();
		var present = false;
		function visit(value:HxStmt):Void {
			if (value == statement)
				present = true;
			// Expression children can contain another function and therefore another return owner.
			TypedBackendSourceWalk.statementChildren(value, _ -> {}, visit);
		}
		for (value in projection.getBody())
			visit(value);
		if (!present)
			throw "Native callback return belongs to another statement owner";
		final expression = switch statement {
			case SReturn(value, _): value;
			case _: throw "Native callback return requires a value return";
		};
		final fact = source(expression);
		if (fact == null)
			throw "Native callback return lacks its exact typed occurrence";
		return bindValues([rendered], values -> convert(fact.getType(), projection.getReturnType(), values[0]));
	}

	/** The direct-return route still requires a return owned by this exact method body. */
	public function returnedExpression(expression:HxExpr, rendered:String):Null<String> {
		if (!TyAliasExpansion.reveal(projection.getReturnType()).isFunction())
			return null;
		current();
		var found:Null<HxStmt> = null;
		function visit(statement:HxStmt):Void {
			switch statement {
				case SReturn(value, _) if (value == expression):
					found = statement;
				case _:
			}
			TypedBackendSourceWalk.statementChildren(statement, _ -> {}, visit);
		}
		for (statement in projection.getBody())
			visit(statement);
		if (found == null)
			throw "Native callback return belongs to another expression owner";
		return returned(found, rendered);
	}

	/** Grouping a direct method call retains its declaration closure, not its stored callback view. */
	public function staticCallee(expression:HxExpr):Null<TyDeclarationInfo> {
		var fact = source(expression);
		while (fact != null && (fact.getTag() == Parenthesized || fact.getTag() == CheckType))
			fact = fact.getExpressions()[0];
		final declaration = fact == null ? null : fact.getDeclaration();
		return fact != null
			&& (fact.getTag() == NameRead || fact.getTag() == FieldRead)
			&& declaration != null
			&& declaration.getIsStatic() ? declaration : null;
	}

	/** Callback value reads get an identity; direct static invocations keep the declaration's calling convention. */
	public function render(expression:HxExpr, emit:HxExpr->String, raw:HxExpr->String, reference:TyDeclarationInfo->String):Null<String> {
		final fact = source(expression);
		if (fact == null)
			return null;
		final children = fact.getExpressions();
		switch fact.getTag() {
			case Lambda | SourceFunction:
				shape(fact.getType());
				return bindValues([raw(expression)], values -> reflaxe.ocaml.ast.OcamlCallableViewSyntax.produce(FreshLiteral, values[0], fresh));
			case NameRead | FieldRead if (TyAliasExpansion.reveal(fact.getType()).isFunction()):
				final declaration = fact.getDeclaration();
				if (declaration == null || !declaration.getIsStatic())
					throw "Native callback origin lacks its selected static declaration";
				shape(fact.getType());
				return bindValues([reference(declaration)],
					values -> reflaxe.ocaml.ast.OcamlCallableViewSyntax.produce(StaticDeclaration(declaration.getIdentity().getCanonicalKey()), values[0],
						fresh));
			case CheckType if (TyAliasExpansion.reveal(fact.getType()).isFunction()):
				final operand = switch expression {
					case ECheckType(inner, _): inner;
					case _: throw "Native callback annotation lost its projected operand";
				};
				return bindValues([emit(operand)], values -> convert(children[0].getType(), fact.getType(), values[0]));
			case Binary if (children.length == 2 && TyAliasExpansion.reveal(children[0].getType()).isFunction()):
				return switch expression {
					case EBinop(op, left, right) if (op == "==" || op == "!="):
						shape(children[0].getType());
						shape(children[1].getType());
						bindValues([emit(left), emit(right)],
							values -> reflaxe.ocaml.ast.OcamlCallableViewSyntax.compare(values[0], values[1],
								(left, right) -> EBinop(op == "==" ? PhysEq : PhysNeq, left, right), fresh));
					case _: throw "Native callback comparison lost its exact operands";
				};
			case Call:
				return call(expression, fact, emit, reference);
			case _:
				return null;
		}
	}

	function call(expression:HxExpr, fact:TypedExpr, emit:HxExpr->String, reference:TyDeclarationInfo->String):Null<String> {
		final children = fact.getExpressions();
		var callee = children[0];
		while (callee.getTag() == Parenthesized || callee.getTag() == CheckType)
			callee = callee.getExpressions()[0];
		final signature = TyAliasExpansion.reveal(callee.getType());
		if (!signature.isFunction())
			return null;
		final declaration = callee.getDeclaration();
		final direct = (callee.getTag() == NameRead || callee.getTag() == FieldRead) && declaration != null && declaration.getIsStatic();
		if (direct
			&& !reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.needsBoundary(Stage3OcamlCallableSelection.declarationShape(declaration)))
			return null;
		final exact = TypedExactStaticCallSource.decode(expression);
		final projected = if (exact != null) {
			{callee: exact.callee, arguments: exact.arguments};
		} else switch expression {
			case ECall(target, arguments): {callee: target, arguments: arguments};
			case _: throw "Native callback call lost its exact projected arguments";
		};
		final parameters = signature.getFunctionParameters();
		if (projected.arguments.length != parameters.length || children.length != parameters.length + 1)
			throw "Native callback call lost its fixed argument mapping";
		final operands = [direct ? reference(declaration) : emit(projected.callee)];
		for (argument in projected.arguments)
			operands.push(emit(argument));
		return bindValues(operands, values -> {
			final arguments = [
				for (index in 0...parameters.length)
					convert(children[index + 1].getType(), parameters[index].type, values[index + 1])
			];
			final argumentNames = [for (_ in arguments) fresh("argument")];
			final inputs:Array<OcamlExpr> = [for (name in argumentNames) EIdent(name)];
			if (inputs.length == 0)
				inputs.push(EConst(CUnit));
			final invocation = direct ? values[0] : reflaxe.ocaml.ast.OcamlCallableViewSyntax.invocation(values[0]);
			var output = convert(signature.getFunctionReturn(), fact.getType(), EApp(invocation, inputs));
			// Conversion helpers can have effects too; OCaml application order must not reorder them.
			var index = arguments.length;
			while (index-- > 0)
				output = ELet(argumentNames[index], arguments[index], output, false);
			return output;
		});
	}
}
