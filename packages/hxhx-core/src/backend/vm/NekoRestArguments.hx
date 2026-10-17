package backend.vm;

/**
	Pack rest elements only after the owning typed call selects their membership.
	A spread already supplies its Array, whereas an Array-valued rest element must
	be enclosed in a new Array. Reflection bypasses this source-call adaptation.
 */
class NekoRestArguments {
	final binding:TyCallArgumentBinding;
	final operands:Array<Null<HxExpr>>;
	final prefix:Array<HxExpr>;

	function new(binding:TyCallArgumentBinding, projected:Array<HxExpr>, prefix:Array<HxExpr>) {
		this.binding = binding;
		this.prefix = prefix.copy();
		operands = [for (_ in binding.getOperandTypes()) null];
		var cursor = 0;
		var omitted = 0;
		function retain(index:Int):Void {
			while (omitted > 0) {
				if (cursor >= projected.length || !projected[cursor].match(ENull))
					throw "Neko rest call lost an interior omitted parameter";
				cursor++;
				omitted--;
			}
			if (index < 0 || index >= operands.length || operands[index] != null || cursor >= projected.length)
				throw "Neko rest call changed its selected operands";
			operands[index] = projected[cursor++];
		}
		for (slot in binding.getSlots())
			switch slot {
				case Omitted:
					omitted++;
				case Supplied(index) | RestSpread(index):
					retain(index);
				case RestElements(indices):
					for (index in indices)
						retain(index);
			}
		if (cursor != projected.length || Lambda.exists(operands, value -> value == null))
			throw "Neko rest call changed its projected operand count";
	}

	/** Exact declaration flags cheaply exclude ordinary named calls before a full occurrence lookup. */
	public static function fromCall(context:NekoEmitContext, expression:HxExpr, arguments:Array<HxExpr>, ?selected:TyDeclarationInfo):Null<NekoRestArguments> {
		if (context == null || context.currentExecutable == null)
			return null;
		if (selected != null && !Lambda.exists(selected.getSignature().getArgRest(), value -> value))
			return null;
		switch expression {
			case ECall(_, _):
			case _:
				return null;
		}
		final source = switch context.currentExecutable {
			case FunctionBody(fn):
				final current = context.typedProgram.requireDeclaredFunction(fn.body.getDeclaration());
				if (current.body != fn.body || current.owner != fn.owner)
					throw "Neko rest call belongs to another function projection";
				fn.body.findCallableExpression(expression);
			case FieldInitializer(field):
				if (context.typedProgram.requireDeclaredInitializer(field.getDeclaration()) != field)
					throw "Neko rest call belongs to another initializer projection";
				field.findCallableExpression(expression);
			case null: null;
		};
		if (source == null || source.getTag() != Call) {
			if (selected != null)
				throw "Neko declared rest call lost its exact typed occurrence";
			return null;
		}
		source.assertArgumentBinding();
		final named = source.getNamedArguments();
		final binding = named == null ? source.getArgumentBinding() : named.getArguments();
		if (binding == null || !hasRest(binding))
			return null;
		final offset = source.getExtensionProvider() == null ? 0 : 1;
		return new NekoRestArguments(binding, arguments.slice(offset), arguments.slice(0, offset));
	}

	/** Constructor catalogs retain the original allocation and super-call operand mapping. */
	public static function fromConstructor(context:NekoEmitContext, expression:HxExpr, arguments:Array<HxExpr>):Null<NekoRestArguments> {
		final occurrence = switch context.currentExecutable {
			case FunctionBody(fn): fn.body.requireConstructor(expression);
			case FieldInitializer(field): field.requireConstructor(expression);
			case null: throw "Neko rest construction requires its executable owner";
		};
		final binding = occurrence.requireArgumentBinding();
		return hasRest(binding) ? new NekoRestArguments(binding, arguments, []) : null;
	}

	static function hasRest(binding:TyCallArgumentBinding):Bool
		return Lambda.exists(binding.getSlots(), slot -> switch slot {
			case RestElements(_) | RestSpread(_): true;
			case _: false;
		});

	/** Spreads retain an existing container; element groups require a fresh authored Array. */
	public function needsArrayFactory():Bool
		return Lambda.exists(binding.getSlots(), slot -> slot.match(RestElements(_)));

	public function render(context:NekoEmitContext, emit:HxExpr->String):Array<String> {
		final result = prefix.map(emit);
		final factory = needsArrayFactory() ? NekoArrayProvider.boundFactory(context) : null;
		for (slot in binding.getSlots())
			result.push(switch slot {
				case Omitted: "null";
				case Supplied(index): emit(operand(index));
				case RestSpread(index):
					switch operand(index) {
						case ECall(EIdent("__hxhx_spread"), [value]): emit(value);
						case _: throw "Neko rest spread lost its checked operand marker";
					}
				case RestElements(indices): NekoArrayProvider.fromValues(factory, [for (index in indices) emit(operand(index))]);
			});
		return result;
	}

	function operand(index:Int):HxExpr {
		final expression = operands[index];
		if (expression == null)
			throw "Neko rest call lost a supplied operand";
		return expression;
	}
}
