/**
	Exact generated query occurrences belonging to one authored iterable occurrence.
	Inference and executable replay share these objects so solved callback/call facts
	are never looked up using freshly synthesized expressions with similar text.
 */
class TyKeyValueProtocolSource {
	final source:HxExpr;
	final owner:String;
	final fingerprint:String;

	public final acquire:HxExpr;
	public final condition:HxExpr;
	public final next:HxExpr;
	public final key:HxExpr;
	public final value:HxExpr;

	final queryFingerprint:String;

	public function new(source:HxExpr, owner:String, direct:Bool = false) {
		this.source = source;
		this.owner = owner;
		fingerprint = TypedBodyFingerprint.exactExpression(source);
		acquire = direct ? source : ECall(EField(source, "keyValueIterator"), []);
		condition = ECall(EField(acquire, "hasNext"), []);
		next = ECall(EField(acquire, "next"), []);
		key = EField(next, "key");
		value = EField(next, "value");
		queryFingerprint = queries();
	}

	/** One function's inference records cannot authorize another function's protocol replay. */
	public function assertOwner(candidate:String):Void {
		if (owner == null || owner.length == 0 || candidate != owner)
			throw "iterator protocol belongs to another inference owner";
	}

	function queries():String
		return [
			for (entry in [acquire, condition, next, key, value])
				TypedBodyFingerprint.exactExpression(entry)
		].join("|");

	/** Similar source text is not authority to reuse another occurrence's inferred facts. */
	public function owns(candidate:HxExpr):Bool {
		if (candidate != source)
			return false;
		if (TypedBodyFingerprint.exactExpression(source) != fingerprint || queries() != queryFingerprint)
			throw "iterator source or protocol queries changed after inference selection";
		return true;
	}
}
