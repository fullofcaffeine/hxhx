/** A resolved enum value, an unresolved enum value, or an ordinary runtime field. */
enum TyFieldConstantKind {
	Ordinary;
	Unresolved(reason:String);
	IntValue(value:Int);
	StringValue(value:String);
	BoolValue(value:Bool);
}

/**
	Immutable shared constant evidence attached to the exact field declaration.
	Reads retain the field identity for dependencies even when projection embeds
	a literal. An unresolved enum value must never become placeholder zero/null.
**/
class TyFieldConstant {
	final kind:TyFieldConstantKind;

	public function new(kind:TyFieldConstantKind) {
		this.kind = kind;
	}

	public function getKind():TyFieldConstantKind
		return kind;

	public function isEnumValue():Bool
		return !kind.match(Ordinary);

	/** Include both value and unresolved state in semantic revisions. */
	public function getCanonicalIdentity():String {
		return CompilerCacheIdentity.encode(switch (kind) {
			case Ordinary: ["ordinary-field"];
			case Unresolved(reason): ["unresolved-enum-value", reason];
			case IntValue(value): ["enum-int", Std.string(value)];
			case StringValue(value): ["enum-string", value];
			case BoolValue(value): ["enum-bool", value ? "true" : "false"];
		});
	}

	/** Project only shared resolved facts; ordinary fields keep their runtime read. */
	public function project():Null<HxExpr> {
		return switch (kind) {
			case Ordinary: null;
			case Unresolved(reason): throw "unresolved enum-abstract constant: " + reason;
			case IntValue(value): EInt(value);
			case StringValue(value): EString(value);
			case BoolValue(value): EBool(value);
		};
	}
}
