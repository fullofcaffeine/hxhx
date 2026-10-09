/**
	Preserve the typed destination of an ordinary loop or jump in its projected
	statement view. Equal source text cannot lend another statement its authority.
	For-loop bindings are retained once so targets can validate the binding and
	iterable together without recovering a declaration from its source spelling.
 */
class TypedBackendStatementControl {
	public final statement:HxStmt;
	public final destination:String;
	public final binding:Null<HxForBinding>;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(owner:String, revision:String, source:TypedStmt, statement:HxStmt) {
		final target = source.getControlTarget();
		if (target == null || target.getKind() != Loop || target.getOwnerIdentity() != owner)
			throw "statement control requires its exact typed loop destination";
		this.owner = owner;
		this.revision = revision;
		this.statement = statement;
		destination = target.getCanonicalIdentity();
		binding = switch statement {
			case SForIn(name, _, _, _) if (source.getTag() == ForIn): Value(name);
			case SForKeyValue(key, value, _, _, _) if (source.getTag() == ForKeyValue): KeyValue(key, value);
			case SWhile(_, _, _) if (source.getTag() == While): null;
			case SDoWhile(_, _, _) if (source.getTag() == DoWhile): null;
			case SBreak(_) if (source.getTag() == Break): null;
			case SContinue(_) if (source.getTag() == Continue): null;
			case _: throw "statement control differs from its typed statement";
		};
		fingerprint = TypedBodyFingerprint.exactStatements([statement]);
	}

	/** Reject foreign revisions and changes to the loop body, operands, or bindings. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (this.owner != owner || this.revision != revision)
			throw "statement control belongs to another executable or revision";
		if (TypedBodyFingerprint.exactStatements([statement]) != fingerprint)
			throw "statement control changed after projection";
	}
}
