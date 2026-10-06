import TyCallAlignment.TyCallArgumentSlot;
import TyCallAlignment.TyCallOperandKind;
import TyAssignmentCompatibility.TyAssignmentNullPolicy;

/**
	An immutable, checked mapping from source operands to callable parameters.

	Only successful shared validation can construct this component. It retains
	omissions and rest membership without creating placeholders or packed arrays.
	The full call binding must additionally own invocation, conversions, generic
	substitutions, and alias-use evidence; this component does not claim those facts.
 */
class TyCallArgumentBinding {
	final functionType:TyType;
	final operandTypes:Array<TyType>;
	final operandKinds:Array<TyCallOperandKind>;
	final slots:Array<TyCallArgumentSlot>;
	final nullPolicy:TyAssignmentNullPolicy;

	@:allow(TyCallbackArgumentContext)
	function new(signature:TyCallableSignature, types:Array<TyType>, kinds:Array<TyCallOperandKind>, slots:Array<TyCallArgumentSlot>,
			policy:TyAssignmentNullPolicy) {
		functionType = signature.getFunctionType();
		operandTypes = types.copy();
		operandKinds = kinds.copy();
		this.slots = copySlots(slots);
		nullPolicy = policy;
	}

	/** This internal publication boundary must receive operands already accepted by shared typing. */
	public static function require(signature:TyCallableSignature, types:Array<TyType>, kinds:Array<TyCallOperandKind>,
			policy:TyAssignmentNullPolicy):TyCallArgumentBinding {
		return switch (TyCallValidation.validate(signature, types, kinds, policy)) {
			case Aligned(slots): new TyCallArgumentBinding(signature, types, kinds, slots, policy);
			case Rejected(failure): throw "cannot publish call arguments: " + TyCallValidation.describeFailure(failure, signature, types, kinds);
		};
	}

	static function copySlots(values:Array<TyCallArgumentSlot>):Array<TyCallArgumentSlot>
		return [
			for (value in values)
				switch (value) {
					case RestElements(indices):
						RestElements(indices.copy());
					case _:
						value;
				}
		];

	public function getSlots():Array<TyCallArgumentSlot>
		return copySlots(slots);

	public function getFunctionType():TyType
		return functionType;

	public function getOperandTypes():Array<TyType>
		return operandTypes.copy();

	public function getOperandKinds():Array<TyCallOperandKind>
		return operandKinds.copy();

	/** A rewrite must preserve the callable signature, source count, types, and spread shape. */
	public function assertCurrent(calleeType:TyType, types:Array<TyType>, kinds:Array<TyCallOperandKind>):Void {
		if (calleeType.getSemanticKey() != functionType.getSemanticKey()
			|| types.length != operandTypes.length
			|| kinds.length != operandKinds.length)
			throw "call argument binding has a stale signature or operand count";
		for (index in 0...types.length)
			if (types[index].getSemanticKey() != operandTypes[index].getSemanticKey() || kinds[index] != operandKinds[index])
				throw "call argument binding has a stale operand type or spread shape";
	}

	/** Serialize semantic facts, including omission versus explicitly supplied null. */
	public function getSemanticKey():String {
		final facts:Array<Null<String>> = [
			"call-arguments-v1",
			functionType.getSemanticKey(),
			nullPolicy == Strict ? "strict" : "unchecked"
		];
		facts.push(Std.string(operandTypes.length));
		for (index in 0...operandTypes.length) {
			facts.push(operandTypes[index].getSemanticKey());
			facts.push(operandKinds[index] == Spread ? "spread" : "value");
		}
		for (slot in slots)
			switch (slot) {
				case Omitted:
					facts.push("omitted");
				case Supplied(index):
					facts.push("supplied");
					facts.push(Std.string(index));
				case RestSpread(index):
					facts.push("rest-spread");
					facts.push(Std.string(index));
				case RestElements(indices):
					facts.push("rest-elements");
					facts.push(Std.string(indices.length));
					for (index in indices)
						facts.push(Std.string(index));
			}
		return CompilerCacheIdentity.encode(facts);
	}
}
