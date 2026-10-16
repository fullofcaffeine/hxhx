package backend.ocaml;

/**
	One native helper executes a class's own fields in Haxe 4.3.7 initialization order.
	Each field retains its exact typed executable and local catalog. Construction
	chooses when to call this helper; it never absorbs an ancestor's initializers.
	The helper participates in ordinary OCaml function ordering, including recursion.
 */
class Stage3OcamlInstanceInitializers {
	final projection:TypedBackendClassProjection;
	final owner:String;
	final fields:Array<TypedBackendFieldInitializerProjection>;
	final name:String;

	/** Class storage admits exact stored fields before this helper can render them. */
	@:allow(backend.ocaml.Stage3OcamlClassStorage)
	private function new(input:{projection:TypedBackendClassProjection, owner:String, fields:Array<TypedBackendFieldInitializerProjection>}) {
		projection = input.projection;
		owner = input.owner;
		fields = input.fields.copy();
		// Upstream 4.3.7 runs a class's initialized fields in reverse declaration
		// order. The existing C++ initializer contract observes the same order.
		fields.reverse();
		// This lowercase spelling is emitted verbatim. Avoid authored methods and
		// static fields, which share the module's OCaml value namespace.
		final reserved = [
			for (fn in projection.getFunctions())
				HxFunctionDecl.getName(fn.getDeclaration())
		];
		for (field in HxClassDecl.getFields(projection.getDeclaration()))
			reserved.push(HxFieldDecl.getName(field));
		var selected = "__hx_initialize_instance_fields";
		while (reserved.indexOf(selected) >= 0)
			selected += "_";
		name = selected;
	}

	public function getName():String
		return name;

	public function hasFields():Bool
		return fields.length != 0;

	/** A separately typed class cannot borrow these executable field occurrences. */
	public function assertOwner(owner:TypedBackendClassProjection):Void {
		if (owner != projection)
			throw "native instance initialization requires its exact class projection";
		for (field in fields)
			field.assertCurrent();
	}

	public function getFields():Array<TypedBackendFieldInitializerProjection> {
		assertOwner(projection);
		return fields.copy();
	}

	/** Exact callable declarations supply dependencies even for saved function values. */
	public function methodDependencies():Array<String> {
		final result = new Array<String>();
		for (field in getFields()) {
			TypedBackendSourceWalk.expression(field.getExpression(), expression -> {
				final call = TypedExactStaticCallSource.decode(expression);
				if (call != null && call.owner == owner && result.indexOf(call.method) < 0)
					result.push(call.method);
			});
			for (callable in field.requireCaptureCatalog().getCallableExpressions()) {
				final declaration = callable.source.getDeclaration();
				if (declaration != null && declaration.getOwner().getCanonicalName() == owner) {
					final method = declaration.getSignature().getName();
					if (result.indexOf(method) < 0)
						result.push(method);
				}
			}
		}
		return result;
	}

	/** Static-value dependencies keep the helper after those values during module initialization. */
	public function referencesOwnStatics():Bool {
		var found = false;
		for (field in getFields())
			TypedBackendSourceWalk.expression(field.getExpression(), expression -> {
				final read = field.findField(expression);
				if (read != null && read.getField().getIsStatic() && read.getField().getOwner().getCanonicalName() == owner)
					found = true;
			});
		return found;
	}

	/** Evaluate each field once, then commit its converted value through the existing object storage. */
	public function render(emit:TypedBackendFieldInitializerProjection->String, quote:String->String):String {
		return "(" + [
			for (field in getFields())
				"HxAnon.set (Obj.repr this_) " + quote(field.getField().getName()) + " (" + emit(field) + "); "
		].join("") + "())";
	}
}
