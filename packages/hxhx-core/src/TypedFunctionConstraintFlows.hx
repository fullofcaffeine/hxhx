/**
	Find the flows of one typed node. Tags that only read or call a value cannot
	store one. Every other tag whose own type names `Function` while a child is
	a function value counts as a flow, so a new expression form is refused until
	a target handles it.
**/
class TypedFunctionConstraintFlows {
	/** The flows of `node`, whose enclosing function returns `returnType`. */
	public static function ofNode(node:TypedExpr, returnType:Null<TyType>):Array<TypedBackendFunctionConstraintFlow> {
		final flows = new Array<TypedBackendFunctionConstraintFlow>();
		final position = node.getPosition();
		function add(site:String):Void
			flows.push({site: site, position: position});
		final children = node.getExpressions();
		switch node.getTag() {
			case Call if (children.length > 0 && children[0].getTag() == SuperValue):
				// `super(...)` is projected as a constructor occurrence and has no call-argument facts.
				final application = node.getConstructorApplication();
				final parameters = application == null ? [] : application.getParameterTypes();
				for (index in 1...children.length)
					if (index - 1 < parameters.length && TyFunctionConstraint.reaches(parameters[index - 1], children[index].getType()))
						add("constructor argument");
			case Call if (node.getExtensionProvider() != null):
				// A `using` call keeps its receiver under the callee, and its parameters only in the named binding.
				final named = node.getNamedArguments();
				final parameters = named == null ? [] : named.getDeclaration().getSignature().getArgs();
				final values = children[0].getExpressions().concat(children.slice(1));
				for (value in values)
					if (Lambda.exists(parameters, parameter -> TyFunctionConstraint.reaches(parameter, value.getType())))
						add("extension method argument");
			case Call | TraceCall | Lambda | FieldRead | NullSafeFieldRead | ArrayAccess | LocalRead | NameRead | VariableDeclarations:
			case NewValue:
				final application = node.getConstructorApplication();
				final parameters = application == null ? [] : application.getParameterTypes();
				for (index in 0...children.length)
					if (index < parameters.length && TyFunctionConstraint.reaches(parameters[index], children[index].getType()))
						add("constructor argument");
			case VariableDeclaration:
				final bindings = node.getLocalBindings();
				if (children.length == 1 && bindings.length == 1 && localFlow(bindings[0].getType(), children[0].getType()))
					add("local variable");
			case Assign:
				final target = children[0];
				if (TyFunctionConstraint.reaches(target.getType(), children[1].getType())
					&& !(target.getTag() == LocalRead && TyFunctionConstraint.isFunctionConstraint(target.getType())))
					add(switch target.getTag() {
						case FieldRead | NameRead: "field";
						case ArrayAccess: "array element";
						case _: "assignment target";
					});
			case ReturnExpr:
				if (children.length == 1 && TyFunctionConstraint.reaches(returnType, children[0].getType()))
					add("function result");
			case Anonymous:
				final names = node.getTexts();
				final type = node.getType().unwrapNull();
				final fieldNames = type.getAnonymousFieldNames();
				final fieldTypes = type.getAnonymousFieldTypes();
				for (index in 0...children.length) {
					final at = index < names.length ? fieldNames.indexOf(names[index]) : -1;
					if (at >= 0 && TyFunctionConstraint.reaches(fieldTypes[at], children[index].getType()))
						add("structure field");
				}
			case ArrayDecl if (isExactFunctionArray(node.getType())):
			case ArrayDecl | ArrayComprehension | ArrayAppend | MapInsert:
				var mentioned = TyFunctionConstraint.mentions(node.getType());
				var hasFunction = false;
				for (child in children) {
					mentioned = mentioned || TyFunctionConstraint.mentions(child.getType());
					hasFunction = hasFunction || TyFunctionConstraint.isFunctionValue(child.getType());
				}
				if (mentioned && hasFunction)
					add("collection element");
			case Binary if (node.getTexts()[0] != "??"):
				// Other operators read their operands; they do not store them.
			case _:
				// A `??`, conditional or switch can mix a `Function` operand with a plain function value.
				var hasConstraint = false;
				var hasFunction = false;
				var reached = false;
				for (child in children) {
					reached = reached || TyFunctionConstraint.reaches(node.getType(), child.getType());
					hasConstraint = hasConstraint || TyFunctionConstraint.isFunctionConstraint(child.getType());
					hasFunction = hasFunction || TyFunctionConstraint.isFunctionValue(child.getType());
				}
				if (reached || (hasConstraint && hasFunction))
					add("expression result");
		}
		return flows;
	}

	/** A local of exactly `Function` is adapted by its target; any other local that receives a function value is a flow. */
	public static function localFlow(destination:Null<TyType>, value:Null<TyType>):Bool
		return TyFunctionConstraint.reaches(destination, value) && !TyFunctionConstraint.isFunctionConstraint(destination);

	static function isExactFunctionArray(type:TyType):Bool {
		final concrete = type.unwrapNull();
		final identity = concrete.getNominalIdentity();
		final arguments = concrete.getTypeArguments();
		return identity != null
			&& identity.getCanonicalName() == "Array"
			&& arguments.length == 1
			&& TyFunctionConstraint.isFunctionConstraint(arguments[0]);
	}
}
