package backend.cpp;

/** Exactly one executable projection owns the facts; only nested functions have environment symbols. */
typedef CppManagedLocalAccessInput = {
	final ?projection:TypedBackendFunctionProjection;
	final ?initializer:TypedBackendFieldInitializerProjection;
	final plan:CppManagedBodyStorage;
	final owner:CppManagedFunctionOwner;
	final parameters:Array<String>;
	final temporaryPrefix:String;
	final ?environmentName:String;
	final ?environmentSymbol:String;
	final ?receiverSymbol:String;
}

/** A copied common Value expression accompanied by its authoritative source type. */
private typedef CppManagedLocalValue = {
	final code:String;
	final type:TyType;
}

/**
	Resolve parameter and captured-cell reads through the exact executable catalog.
	Projected names select declarations only; lexical capture/parameter identities
	then select storage. Child closures read the same mutable cell as their creator.
	Reads copy common Values and contain no collecting operations. The consumer must
	root a managed result before evaluating any later collecting expression.
	Ordinary initialized declarations use CppManagedLocalStorage. Compound expressions
	and other creation events require explicit storage and sequencing support.
	Field-owned closures use initializer catalogs. They cannot borrow method receiver
	or constructor authority from the surrounding construction call.
 */
class CppManagedLocalAccess {
	final projection:Null<TypedBackendFunctionProjection>;
	final initializer:Null<TypedBackendFieldInitializerProjection>;

	public final plan:CppManagedBodyStorage;
	public final owner:CppManagedFunctionOwner;

	final environment:Null<CppManagedEnvironmentEmitter>;
	final environmentSymbol:Null<String>;

	public final parameters:CppManagedParameterEmitter;
	public final locals:CppManagedLocalStorage;
	public final receiver:Null<CppManagedReceiverStorage>;

	public function new(input:CppManagedLocalAccessInput) {
		if (input == null || (input.projection == null) == (input.initializer == null) || input.plan == null)
			throw "managed local access requires exact projection and storage owners";
		input.plan.requireFunction(input.owner);
		projection = input.projection;
		initializer = input.initializer;
		plan = input.plan;
		owner = input.owner;
		environmentSymbol = input.environmentSymbol;
		environment = switch owner {
			case Root(selected):
				if (projection == null || selected != projection || input.environmentName != null || input.environmentSymbol != null)
					throw "managed root access requires its exact projection without a closure environment";
				null;
			case Closure(expression):
				captureCatalog().require(expression);
				if (environmentSymbol == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(environmentSymbol))
					throw "managed local access requires a stable environment symbol";
				new CppManagedEnvironmentEmitter(plan, expression, input.environmentName);
		};
		parameters = new CppManagedParameterEmitter(plan, owner, input.parameters, input.temporaryPrefix);
		locals = new CppManagedLocalStorage(plan, owner, "hxhx_locals_" + input.temporaryPrefix);
		receiver = switch owner {
			case Root(_) if (input.receiverSymbol != null):
				new CppManagedReceiverStorage(projection, plan, input.receiverSymbol, "hxhx_receiver_" + input.temporaryPrefix);
			case _:
				if (input.receiverSymbol != null)
					throw "managed closure must obtain its receiver from the environment";
				null;
		};
	}

	/** Method-only operations cannot borrow the constructor surrounding an initializer closure. */
	function requireMethod():TypedBackendFunctionProjection {
		if (projection == null)
			throw "initializer closure has no method receiver or constructor authority";
		return projection;
	}

	function captureCatalog():TypedBackendCaptureCatalog
		return projection == null ? initializer.requireCaptureCatalog() : projection.requireCaptureCatalog();

	/** Adapt only the transport requested by the shared control renderer, using semantic source types. */
	public function render(value:HxExpr, expectedNativeType:String):String {
		final selected = read(value);
		final abi = plan.requireFunction(owner).abi;
		if (expectedNativeType == "bool") {
			if (selected.type.getSemanticKey() != "primitive:Bool")
				throw "managed condition requires a typed Boolean local";
			return CppManagedLeaf.read(selected.type, selected.code);
		}
		if (expectedNativeType == "hxhx::managed::Value" && abi.result == RootedResult)
			return selected.code;
		if (abi.result != DirectResult
			|| expectedNativeType != abi.nativeReturnType()
			|| selected.type.getSemanticKey() != abi.signature.getFunctionReturn().getSemanticKey())
			throw "managed local return requires an explicit typed conversion";
		return CppManagedLeaf.read(selected.type, selected.code);
	}

	/** Common transport for an immediately rooted value, independent of the enclosing return convention. */
	public function value(expression:HxExpr):String
		return read(expression).code;

	/** Equal nominal type names cannot attach another program's descriptor policy to this body. */
	public function assertClassStorage(classes:CppManagedClassStorage):Void {
		if (projection == null)
			classes.assertInitializer(initializer);
		else
			classes.assertFunction(projection);
	}

	/** Aggregate layout comes from typed projection, with the same lexical boundary as calls. */
	public function aggregate(expression:HxExpr):TypedBackendAggregateOccurrence {
		requireExpression(expression);
		return projection == null ? initializer.requireAggregate(expression) : projection.requireAggregate(expression);
	}

	/** Runtime tests retain exact occurrence identity within the current lexical body. */
	public function runtimeType(expression:HxExpr):TypedBackendRuntimeTypeOccurrence {
		requireExpression(expression);
		return projection == null ? initializer.requireRuntimeType(expression) : projection.requireRuntimeType(expression);
	}

	/** Native instance bindings require an exact call in this lexical body. */
	public function instanceCall(expression:HxExpr):Null<TypedBackendInstanceCallOccurrence> {
		final call = projection == null ? initializer.findInstanceCall(expression) : projection.findInstanceCall(expression);
		if (call != null)
			requireExpression(expression);
		return call;
	}

	/** Cast facts remain attached to this exact lexical expression, including nested closures. */
	public function findCast(expression:HxExpr):Null<TypedBackendCastOccurrence> {
		final occurrence = projection == null ? initializer.findCast(expression) : projection.findCast(expression);
		if (occurrence != null)
			requireExpression(expression);
		return occurrence;
	}

	/** Exact field reads keep lexical ownership, including when nested in a closure. */
	public function field(expression:HxExpr, storage:Null<CppManagedStaticStorage>, classes:Null<CppManagedClassStorage>):Null<TypedBackendFieldOccurrence> {
		final field = projection == null ? initializer.findField(expression) : projection.findField(expression);
		if (field == null)
			return null;
		requireExpression(expression);
		if (field.getField().getIsStatic()) {
			if (storage == null)
				throw 'managed static field requires program storage';
			if (projection == null)
				storage.assertInitializer(initializer);
			else
				storage.assertFunction(projection);
			if (field.getField().getIsInline())
				storage.inlineInitializer(field);
			else
				storage.member(field);
		} else {
			if (classes == null)
				throw 'managed instance field requires program storage';
			assertClassStorage(classes);
			if (CppManagedArrayLength.selects(field))
				CppManagedArrayLength.require(field);
		}
		return field;
	}

	/** Constructor facts must belong to this lexical body and this exact program. */
	public function constructor(expression:HxExpr, classes:CppManagedClassStorage):TypedBackendConstructorOccurrence {
		requireExpression(expression);
		assertClassStorage(classes);
		return projection == null ? initializer.requireConstructor(expression) : projection.requireConstructor(expression);
	}

	/** Bare instance fields retain the checked receiver dependency without fabricating a this node. */
	public function implicitReceiverType(field:TypedBackendFieldOccurrence, classes:CppManagedClassStorage):TyType {
		requireExpression(field.getExpression());
		final facts = plan.requireFunction(owner).facts;
		if (!facts.directReceiver)
			throw "managed implicit field receiver lacks its exact typed capture facts";
		return plan.resolveType(classes.implicitFieldReceiverType(requireMethod(), field));
	}

	/** Read the same receiver selected by the field's exact lexical capture facts. */
	public function implicitReceiverValue(field:TypedBackendFieldOccurrence, classes:CppManagedClassStorage):String {
		requireExpression(field.getExpression());
		if (field.getReceiver() != ImplicitOwner || !plan.requireFunction(owner).facts.directReceiver || classes == null)
			throw 'managed implicit field receiver lacks its exact lexical owner';
		classes.assertImplicitFieldReceiver(requireMethod(), field);
		return receiver == null ? receiverReference() + '->read()' : receiver.value();
	}

	/** Final initialization belongs to the root constructor and its own this receiver. */
	public function allowsFinalFieldWrite(field:TypedBackendFieldOccurrence):Bool {
		requireExpression(field.getExpression());
		switch owner {
			case Root(_):
			case _:
				return false;
		}
		final declaration = requireMethod().requireSemanticDeclaration();
		if (declaration.getIsStatic()
			|| declaration.getSignature().getName() != 'new'
			|| !declaration.getOwner().equals(field.getField().getOwner()))
			return false;
		return field.getReceiver() == ImplicitOwner || switch field.getExpression() {
			case EField(EThis, _): true;
			case _: false;
		};
	}

	/** Resolve the existing mutable location when constructing a descendant environment. */
	public function cellReference(binding:TyLocalBinding):String {
		final captured = capturedCell(binding);
		return captured != null ? captured : locals.owns(binding) ? locals.cellReference(binding) : parameters.cellReference(binding);
	}

	/** Resolve mutable storage without evaluating or copying its current contents. */
	public function place(binding:TyLocalBinding):CppManagedPlace {
		if (binding != null && binding.getKind() == NamedFunction)
			throw "named function storage cannot be reassigned";
		final captured = capturedCell(binding);
		return captured != null ? Cell(captured) : locals.owns(binding) ? locals.place(binding) : parameters.place(binding);
	}

	/** Static markers must occur in this function, not a copied expression or nested child's body. */
	public function requireExpression(expression:HxExpr):Void {
		plan.requireFunction(owner);
		requireLexicalExpression(expression);
	}

	/**
		Check membership within the already selected lexical owner during emission.
		The function emitter validates the complete plan before and after emission.
		This narrower check keeps repeated type queries from hashing the whole body;
		it does not replace revision validation at those emission boundaries.
	 */
	public function requireLexicalExpression(expression:HxExpr):Void {
		var found = false;
		switch owner {
			case Root(_):
				for (argument in HxFunctionDecl.getArgs(requireMethod().getDeclaration()))
					switch HxFunctionArg.getDefaultValue(argument) {
						case NoDefault:
						case Default(value):
							if (expressionContains(value, expression)) found = true;
					}
				for (statement in requireMethod().getBody())
					if (statementContains(statement, expression))
						found = true;
			case Closure(ELambda(_, body)):
				found = expressionContains(body, expression);
			case _:
				throw "managed expression owner is not an executable function";
		}
		if (!found)
			throw "managed call is not an exact expression in its projection";
	}

	static function statementContains(statement:HxStmt, target:HxExpr):Bool {
		var found = false;
		TypedBackendSourceWalk.statementChildren(statement, value -> {
			if (expressionContains(value, target))
				found = true;
		}, child -> {
			if (statementContains(child, target))
				found = true;
		});
		return found;
	}

	/** A loop's binding and iterable must occur together in this exact lexical owner. */
	public function requireLoop(binding:HxForBinding, iterable:HxExpr):Void {
		plan.requireFunction(owner);
		var found = false;
		function visit(value:HxExpr):Void {
			switch value {
				case ELoweredControl(For(selected), _, children, _) if (selected == binding && children.length == 2 && children[0] == iterable):
					found = true;
				case ELambda(_, _):
					return;
				case _:
			}
			TypedBackendSourceWalk.expressionChildren(value, visit);
		}
		function statement(value:HxStmt):Void {
			switch value {
				case SForIn(_, selected, _, _) | SForKeyValue(_, _, selected, _, _) if (selected == iterable):
					if (requireMethod().requireStatementControl(value).binding == binding)
						found = true;
				case _:
			}
			TypedBackendSourceWalk.statementChildren(value, visit, statement);
		}
		switch owner {
			case Root(_):
				for (value in requireMethod().getBody())
					statement(value);
			case Closure(ELambda(_, body)):
				visit(body);
			case _:
				throw "managed loop owner is not executable";
		}
		if (!found)
			throw "managed loop requires its exact projected occurrence";
	}

	static function expressionContains(expression:HxExpr, target:HxExpr):Bool {
		if (expression == target)
			return true;
		switch expression {
			case ELambda(_, _):
				return false;
			case _:
		}
		var found = false;
		TypedBackendSourceWalk.expressionChildren(expression, value -> {
			if (expressionContains(value, target))
				found = true;
		});
		return found;
	}

	/** A projected name selects an exact binding; it never supplies type or lifetime policy. */
	public function binding(name:String):TyLocalBinding {
		plan.requireFunction(owner);
		final local = (projection == null ? initializer.getLocalCatalog() : projection.getLocalCatalog()).findByProjectedName(name);
		if (local == null)
			throw "managed local read is absent from its executable catalog";
		return local.getBinding();
	}

	/** Receiver forwarding retains the same binding cell as the current environment. */
	public function receiverReference():String {
		plan.requireFunction(owner);
		if (receiver != null)
			return receiver.reference();
		if (environment == null)
			throw "managed root receiver requires explicit transport";
		return environmentSymbol + ".as<" + environment.nativeName + ">()->" + environment.receiverField();
	}

	/** This reads use their checked lexical receiver type, including applied type parameters. */
	public function receiverType(expression:HxExpr):TyType {
		requireExpression(expression);
		switch expression {
			case EThis:
			case _:
				throw "managed receiver read requires this";
		}
		final facts = plan.requireFunction(owner).facts;
		final type = captureCatalog().getPlan().receiverType;
		if (!facts.directReceiver || type == null)
			throw "managed receiver read lacks its exact typed capture facts";
		CppManagedClosureAbi.assertComplete(type);
		return plan.resolveType(type);
	}

	public function receiverValue(expression:HxExpr):String {
		receiverType(expression);
		return receiver == null ? receiverReference() + "->read()" : receiver.value();
	}

	/** Parent initialization belongs to the root constructor and keeps its existing allocated receiver. */
	public function superReceiverValue(occurrence:TypedBackendConstructorOccurrence, classes:CppManagedClassStorage):String {
		requireExpression(occurrence.getExpression());
		switch owner {
			case Root(selected) if (selected == projection):
			case _:
				throw "parent constructor call requires its root constructor";
		}
		classes.assertSuperConstructor(requireMethod(), occurrence);
		if (receiver == null || plan.abstractReceiverType != null)
			throw "parent constructor call requires an ordinary receiver";
		return receiver.value();
	}

	/** Explicit parent method selection retains this invocation's receiver, including its allocated class. */
	public function superMethodReceiverValue(call:TypedBackendInstanceCallOccurrence, classes:CppManagedClassStorage):String {
		requireExpression(call.getExpression());
		classes.methods.assertSuperMethod(requireMethod(), call);
		if (plan.abstractReceiverType != null)
			throw "super method requires an ordinary class receiver";
		return receiver == null ? receiverReference() + "->read()" : receiver.value();
	}

	/** Only the exact abstract constructor and its lexical descendants may replace this binding. */
	public function writableReceiver(expression:HxExpr):String {
		final type = receiverType(expression);
		if (plan.abstractReceiverType == null || type.getSemanticKey() != plan.abstractReceiverType.getSemanticKey())
			throw 'managed receiver assignment requires its exact abstract constructor backing';
		return receiverReference();
	}

	function capturedCell(binding:TyLocalBinding):Null<String> {
		for (cell in plan.requireFunction(owner).getCells())
			if (binding != null && cell.source.binding.getCanonicalIdentity() == binding.getCanonicalIdentity()) {
				if (environment == null)
					throw "captured storage requires its closure environment";
				return environmentSymbol + ".as<" + environment.nativeName + ">()->" + environment.cellField(binding);
			}
		return null;
	}

	function read(value:HxExpr):CppManagedLocalValue {
		plan.requireFunction(owner);
		final name = switch value {
			case EIdent(name): name;
			case _: throw "managed local access requires a projected local read";
		};
		final binding = this.binding(name);
		final captured = capturedCell(binding);
		if (captured != null)
			return {code: captured + "->read()", type: plan.resolveType(binding.getType())};
		if (locals.owns(binding))
			return {code: locals.value(binding), type: plan.resolveType(binding.getType())};
		return {code: parameters.value(binding), type: plan.resolveType(binding.getType())};
	}
}
