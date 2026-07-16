/**
	The immutable structural body for one source function.

	The source fingerprint seals the parsed revision used to construct the tree.
	It is checked before macro expansion and backend dispatch.
**/
class TypedFunctionBody {
	final statements:Array<TypedStmt>;
	final sourceFingerprint:String;

	public function new(statements:Array<TypedStmt>, sourceFingerprint:String) {
		this.statements = statements == null ? [] : statements.copy();
		this.sourceFingerprint = sourceFingerprint == null ? "" : sourceFingerprint;
	}

	public function getStatements():Array<TypedStmt>
		return statements.copy();

	public function getSourceFingerprint():String
		return sourceFingerprint;
}
