import TyCallAlignment.TyCallArgumentSlot;
import TyCallAlignment.TyCallOperandKind;

/**
	Keep a method candidate's selected source-to-parameter order during inference.

	Ranking needs parameter order; constraints and conversions need authored source
	order. This trial record translates between them without moving expressions.
	It is not a published typed call: declaration identity, final types, conversions,
	and revision ownership still belong to the selected call's publication boundary.
**/
class TyMethodArgumentOrder {
	final slots:Array<TyCallArgumentSlot>;
	final sourceCount:Int;

	function new(slots:Array<TyCallArgumentSlot>, sourceCount:Int) {
		this.slots = slots;
		this.sourceCount = sourceCount;
	}

	/** Publication receives a defensive copy of the winning slots, without repeating candidate selection. */
	public function getSlots():Array<TyCallArgumentSlot>
		return [
			for (slot in slots)
				switch slot {
					case RestElements(indices):
						RestElements(indices.copy());
					case _:
						slot;
				}
		];

	/** An extension receiver is supplied separately by its callee; its first slot cannot be omitted or reordered. */
	public function withoutReceiver():TyMethodArgumentOrder {
		if (sourceCount == 0 || slots.length == 0 || !slots[0].match(Supplied(0)))
			throw "extension argument order requires its supplied first receiver";
		return new TyMethodArgumentOrder([
			for (slot in slots.slice(1))
				switch slot {
					case Omitted:
						Omitted;
					case Supplied(source):
						Supplied(source - 1);
					case RestSpread(source):
						RestSpread(source - 1);
					case RestElements(sources):
						RestElements([for (source in sources) source - 1]);
				}
		], sourceCount - 1);
	}

	/** Shared alignment owns optional skipping; the caller supplies its existing candidate compatibility rule. */
	public static function select(signature:TyFunSig, sources:Array<HxExpr>,
			compatible:(Int, Int, Bool) -> TyCallArgumentCompatibility):Null<TyMethodArgumentOrder> {
		final parameters = [
			for (index in 0...signature.getArgs().length)
				TyCallableSignature.argumentParameter(signature, index)
		];
		final kinds:Array<TyCallOperandKind> = [
			for (source in sources)
				source.match(ECall(EIdent("__hxhx_spread"), [_])) ? Spread : Value
		];
		return switch TyCallAlignment.align(parameters, kinds, compatible) {
			case Aligned(selected): new TyMethodArgumentOrder(selected, sources.length);
			case Rejected(_): null;
		};
	}

	/**
		Rank each supplied value against its parameter. A checked spread contributes
		its container's element type because the parameter view exposes rest elements.
		Null here records omission, not an expression or a generic type argument.
	 */
	public function rankedTypes(types:Array<TyType>):Array<TyType> {
		if (types.length != sourceCount)
			throw "method argument order has a stale source count";
		final result = new Array<TyType>();
		for (slot in slots)
			switch slot {
				case Omitted:
					result.push(TyType.fromHintText("Null"));
				case Supplied(source):
					result.push(types[source]);
				case RestSpread(source):
					final container = types[source];
					final elements = container.getTypeArguments();
					result.push(container.isDynamic() || elements.length != 1 ? container : elements[0]);
				case RestElements(sources):
					for (source in sources)
						result.push(types[source]);
			}
		return result;
	}

	/** Select the exact declared destination for one authored operand without rerunning alignment. */
	public function parameterIndex(source:Int):Int {
		if (source < 0 || source >= sourceCount)
			throw "method argument order has a foreign source index";
		for (index in 0...slots.length)
			switch slots[index] {
				case Supplied(selected) | RestSpread(selected) if (selected == source):
					return index;
				case RestElements(sources) if (sources.indexOf(source) >= 0):
					return index;
				case _:
			}
		throw "method argument order omitted a supplied source";
	}

	/** Project specialized declaration contexts back to original operands, including rest element destinations. */
	public function sourceContexts(parameters:Array<TyType>):Array<TyType> {
		if (parameters.length != slots.length)
			throw "method argument contexts differ from the selected parameters";
		final result = [for (_ in 0...sourceCount) TyType.unknown()];
		for (index in 0...slots.length)
			switch slots[index] {
				case Supplied(source) | RestSpread(source):
					result[source] = parameters[index];
				case RestElements(sources):
					final elements = parameters[index].getTypeArguments();
					final element = parameters[index].isUnknown() ? TyType.unknown() : elements.length == 1 ? elements[0] : null;
					if (element == null)
						throw "method rest context requires its declared container";
					for (source in sources)
						result[source] = element;
				case Omitted:
			}
		return result;
	}
}
