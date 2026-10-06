package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/**
	Bind an exact enum call to its existing typed constructor body.
	The shared declaration inventory owns constructor order, identity and payload
	arity. Neko reuses that body and the normal static-function path; it does not
	repeat source-name lookup or invent a second enum representation.
 */
class NekoEnumConstructorPlan {
	public final selected:NekoProjectedFunction;

	final source:HxExpr;
	final fingerprint:String;
	final arguments:Array<HxExpr>;

	function new(selected:NekoProjectedFunction, source:HxExpr, arguments:Array<HxExpr>) {
		this.selected = selected;
		this.source = source;
		this.fingerprint = TypedBodyFingerprint.exactExpression(source);
		this.arguments = arguments.copy();
	}

	public function getArguments():Array<HxExpr> {
		if (TypedBodyFingerprint.exactExpression(source) != fingerprint)
			throw "Neko enum constructor call changed after selection";
		return arguments.copy();
	}

	/** Only declared constructor bodies and singleton initializers can tag a produced enum value. */
	public static function resultOwner(context:NekoEmitContext):Null<String> {
		return switch context.currentExecutable {
			case FunctionBody(selected):
				selected.body.requireSemanticDeclaration().getIsEnumConstructor() ? selected.owner.requireSemanticFacts().getClassIdentity() : null;
			case FieldInitializer(selected):
				final field = selected.getField();
				final owner = context.typedProgram.requireClass(field.getOwner().getCanonicalName()).requireSemanticFacts();
				var found:Null<String> = null;
				if (owner.getNominalKind().match(EnumValue))
					for (constructor in owner.copyEnumConstructors())
						switch constructor.member {
							case Singleton(declaration) if (declaration.canonicalIdentity == field.getCanonicalKey()):
								found = owner.getClassIdentity();
							case _:
						}
				found;
			case null: null;
		};
	}

	/** Ordinary calls remain ordinary; malformed reserved payloads fail before emission. */
	public static function fromExpression(program:NekoTypedProgramProjection, expression:HxExpr):Null<NekoEnumConstructorPlan> {
		final call = TypedExactEnumConstructorSource.decode(expression);
		if (call == null) {
			switch expression {
				case ECall(EUnsupported(marker), _) if (marker == TypedExactEnumConstructorSource.marker()):
					throw "Neko enum constructor contains a malformed typed payload";
				case _:
					return null;
			}
		}
		if (program == null)
			throw "Neko enum constructor requires its typed program";
		final selected = program.requireFunction(call.owner, call.declaration);
		final facts = selected.owner.requireSemanticFacts();
		final declaration = selected.body.requireSemanticDeclaration();
		if (!facts.getNominalKind().match(EnumValue)
			|| facts.getModuleIdentity() != call.modulePath
			|| !declaration.getIsEnumConstructor()
			|| !declaration.getIsStatic()
			|| declaration.getSignature().getName() != call.constructor)
			throw "Neko enum constructor conflicts with its exact declaration";
		for (constructor in facts.copyEnumConstructors())
			switch constructor.member {
				case Callable(method) if (method.canonicalIdentity == call.declaration && constructor.name == call.constructor):
					if (call.arguments.length > method.arguments.length)
						throw "Neko enum constructor payload arity changed";
					// Shared call binding keeps trailing omissions absent. The ordinary
					// Neko parameter adapter supplies null for those optional slots.
					for (index in call.arguments.length...method.arguments.length)
						if (!method.arguments[index].isOptional)
							throw "Neko enum constructor payload arity omits a required argument";
					return new NekoEnumConstructorPlan(selected, expression, call.arguments);
				case _:
			}
		throw "Neko enum constructor is absent from its declaration inventory";
	}
}
