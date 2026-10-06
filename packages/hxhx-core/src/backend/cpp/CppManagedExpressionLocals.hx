package backend.cpp;

import backend.cpp.CppManagedRootedExpression.CppManagedExpressionOwner;

/**
	Dispatch local storage through its exact callable or field-initializer owner.
	Each owner applies its own generic arguments. Field locals retain their
	own declaration events and never borrow constructor catalogs.
	Nested closure construction shares these cells. Receiver and return transport
	remain operations of a real callable body, not of an initializer expression.
 */
class CppManagedExpressionLocals {
	final owner:CppManagedExpressionOwner;
	final prefix:String;
	final application:Null<CppManagedInitializerApplication>;
	var initializerLocals:Null<CppManagedInitializerLocals>;

	public function new(owner:CppManagedExpressionOwner, prefix:String, ?application:CppManagedInitializerApplication) {
		if (owner == null || prefix == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(prefix))
			throw "managed local access requires an owner and allocated prefix";
		this.owner = owner;
		this.prefix = prefix;
		this.application = application;
		if (application != null)
			switch owner {
				case FieldInitializer(projection) if (projection == application.projection):
					application.assertCurrent();
				case _:
					throw "initializer locals application belongs to another owner";
			}
	}

	function fieldLocals():CppManagedInitializerLocals {
		if (initializerLocals == null)
			switch owner {
				case FieldInitializer(projection):
					initializerLocals = new CppManagedInitializerLocals(projection, prefix + "local_", application);
				case _:
					throw "initializer storage requires a field owner";
			}
		return initializerLocals;
	}

	public function binding(name:String):TyLocalBinding
		return switch owner {
			case CallableBody(selected): selected.binding(name);
			case FieldInitializer(_): fieldLocals().binding(name);
		};

	public function value(expression:HxExpr):String
		return switch owner {
			case CallableBody(selected): selected.value(expression);
			case FieldInitializer(projection):
				projection.requireExpression(expression);
				switch expression {
					case EIdent(name): fieldLocals().value(binding(name));
					case _: throw "initializer local read requires its exact identifier";
				}
		};

	public function place(binding:TyLocalBinding):CppManagedPlace
		return switch owner {
			case CallableBody(selected): selected.place(binding);
			case FieldInitializer(_): fieldLocals().place(binding);
		};

	/** A nested callable keeps the capture facts of its actual lexical owner. */
	public function requireClosure(expression:HxExpr):backend.cpp.CppManagedStoragePlan.CppManagedFunctionPlan
		return switch owner {
			case CallableBody(selected): selected.plan.requireClosure(expression);
			case FieldInitializer(_): fieldLocals().captures.requireClosure(expression);
		};

	public function requireAscribedClosure(expression:HxExpr):HxExpr
		return switch owner {
			case CallableBody(selected): selected.plan.requireAscribedClosure(expression);
			case FieldInitializer(_): fieldLocals().captures.requireAscribedClosure(expression);
		};

	/** Only a direct lexical child can capture storage from the currently executing scope. */
	public function assertChild(expression:HxExpr):Void {
		final parent = switch owner {
			case CallableBody(selected): selected.plan.requireFunction(selected.owner).facts.identity;
			case FieldInitializer(projection): projection.requireCaptureCatalog().getPlan().getFunctions()[0].identity;
		};
		if (requireClosure(expression).facts.parentIdentity != parent)
			throw "managed function literal belongs to another lexical parent";
	}

	public function environment(expression:HxExpr, name:String):CppManagedEnvironmentEmitter
		return switch owner {
			case CallableBody(selected): new CppManagedEnvironmentEmitter(selected.plan, expression, name);
			case FieldInitializer(_): new CppManagedEnvironmentEmitter(fieldLocals().captures, expression, name);
		};

	public function cellReference(binding:TyLocalBinding):String
		return switch owner {
			case CallableBody(selected): selected.cellReference(binding);
			case FieldInitializer(_): fieldLocals().cellReference(binding);
		};

	/** Catch selection must publish through the storage owner of this exact lexical entry. */
	public function renderCatch(binding:TyLocalBinding, selectedRoot:String, heap:String, indent:String):Array<String>
		return switch owner {
			case CallableBody(selected): selected.locals.renderCatch(binding, selectedRoot, heap, indent);
			case FieldInitializer(_): fieldLocals().renderCatch(binding, selectedRoot, heap, indent);
		};

	/** Field locals resolve through their field application, independently of the constructor. */
	public function resolveType(type:TyType):TyType
		return switch owner {
			case CallableBody(selected): selected.plan.resolveType(type);
			case FieldInitializer(_): fieldLocals().captures.resolveType(type);
		};

	/** Validate the transfer before asking the selected storage owner to emit its declaration. */
	public function declare(input:{
		name:String,
		?casts:CppManagedCastPlan,
		initializer:Null<HxExpr>,
		heap:String,
		indent:String,
		accepts:(HxExpr, TyType) -> Bool,
		valueType:HxExpr->TyType,
		render:(HxExpr, TyType, String, String) -> Array<String>
	}):Array<String> {
		final selected = binding(input.name);
		final type = resolveType(selected.getType());
		final render = (value, root, indent) -> input.render(value, type, root, indent);
		return switch owner {
			case FieldInitializer(_): fieldLocals().declare(selected, input.initializer, input.heap, input.indent, render);
			case CallableBody(access):
				if (input.initializer != null) {
					final source = input.valueType(input.initializer);
					if (!input.accepts(input.initializer, type)
						&& !CppManagedValueTransfer.needsConversion(type, source, input.casts)
						&& !CppManagedArrayRecovery.selects(type, source))
						throw "managed local initialization requires an explicit typed conversion: "
							+ source.getSemanticKey()
							+ " -> "
							+ type.getSemanticKey();
				}
				access.locals.renderDeclaration(selected, input.initializer, input.heap, input.indent, render);
		};
	}
}
