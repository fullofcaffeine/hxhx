/**
	Bind one selected declaration to its original executable pattern occurrence.
	Equal-looking patterns in another body cannot borrow this selection. The
	projection checks its typed revision and tree membership before returning it.
 */
class TypedBackendNamedPattern {
	public final pattern:HxSwitchPattern;
	public final selection:TypedNamedPattern;

	final owner:String;
	final revision:String;
	final identity:String;

	public function new(input:{
		owner:String,
		revision:String,
		pattern:HxSwitchPattern,
		selection:TypedNamedPattern
	}) {
		owner = input.owner;
		revision = input.revision;
		pattern = input.pattern;
		selection = input.selection;
		identity = TypedBodyFingerprint.exactExpression(ESwitch(ENull, [pattern], []));
	}

	public function assertCurrent(owner:String, revision:String):Void {
		if (this.owner != owner
			|| this.revision != revision
			|| identity != TypedBodyFingerprint.exactExpression(ESwitch(ENull, [pattern], [])))
			throw "named pattern belongs to another owner or revision";
	}

	/** Visit only case patterns; ordinary enum expressions cannot authorize a case. */
	public static function inExpression(expression:HxExpr, visit:HxSwitchPattern->Void):Void {
		switch expression {
			case ESwitch(_, patterns, _) | ELoweredControl(Switch(patterns, _), _, _, _):
				for (pattern in TypedSwitchPatterns.named(patterns))
					visit(pattern);
			case _:
		}
	}

	public static function inStatement(statement:HxStmt, visit:HxSwitchPattern->Void):Void {
		switch statement {
			case SSwitch(_, patterns, _, _):
				for (pattern in TypedSwitchPatterns.named(patterns))
					visit(pattern);
			case _:
		}
	}
}
