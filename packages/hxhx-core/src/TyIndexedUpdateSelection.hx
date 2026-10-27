/** Supported source forms; compound tokens are validated by the existing binary-operator owner. */
enum TyIndexedUpdateKind {
	Unary(op:HxUnaryOperator, fixity:HxUnaryFixity);
	Compound(op:String);
}

/** Source identities exist before candidate selection chooses any getter, operator, or setter. */
typedef TyIndexedUpdateQueryInput = {
	final owner:String;
	final source:HxExpr;
	final kind:TyIndexedUpdateKind;
	final getterSource:HxExpr;
	final computedSource:HxExpr;
	final setterSource:HxExpr;
}

/** Immutable query ownership does not imply that any helper or update operation is viable. */
class TyIndexedUpdateQuery {
	public final owner:String;
	public final source:HxExpr;
	public final kind:TyIndexedUpdateKind;
	public final getterSource:HxExpr;
	public final computedSource:HxExpr;
	public final setterSource:HxExpr;

	final fingerprints:Array<String>;

	public function new(input:TyIndexedUpdateQueryInput) {
		owner = input.owner;
		source = input.source;
		kind = input.kind;
		getterSource = input.getterSource;
		computedSource = input.computedSource;
		setterSource = input.setterSource;
		if (owner == null || owner.length == 0)
			throw "indexed update requires an owner";
		if (!matchesSource())
			throw "indexed update kind disagrees with its source";
		final queries = sources();
		for (index in 0...queries.length)
			for (prior in 0...index)
				if (queries[index] == queries[prior])
					throw "indexed update results require distinct source queries";
		fingerprints = queries.map(TypedBodyFingerprint.exactExpression);
	}

	function matchesSource():Bool {
		return switch kind {
			case Unary(op, fixity): (op == Increment || op == Decrement) && switch source {
					case EUnop(actual, actualFixity, EArrayAccess(_, _)): actual == op && actualFixity == fixity;
					case _: false;
				};
			case Compound(op): HxBinaryOperatorTools.isCompoundAssignment(op) && switch source {
					case EBinop(actual, EArrayAccess(_, _), _): actual == op;
					case _: false;
				};
		};
	}

	function sources():Array<HxExpr>
		return [source, getterSource, computedSource, setterSource];

	/** A different owner or a mutated original/query cannot borrow this candidate's facts. */
	public function validate(candidateOwner:String):Void {
		if (candidateOwner != owner)
			throw "indexed update query belongs to another owner";
		final queries = sources();
		for (index in 0...queries.length)
			if (fingerprints[index] != TypedBodyFingerprint.exactExpression(queries[index]))
				throw "indexed update source or query changed";
		if (!matchesSource())
			throw "indexed update kind disagrees with its source";
	}
}

/** All selected declarations become available only after the candidate has checked the complete operation. */
typedef TyIndexedUpdateSelectionInput = {
	final query:TyIndexedUpdateQuery;
	final getter:TyIndexedAccessBinding;
	final setter:TyIndexedAccessBinding;
	final ?binary:TyBoundAbstractBinaryOperator;
}

/**
	Retain a completed candidate's exact calls without publishing a partial selection.
	This fact authorizes inference replay only, never backing-value indexing or an invented operator.
 */
class TyIndexedUpdateSelection {
	public final query:TyIndexedUpdateQuery;
	public final getter:TyIndexedAccessBinding;
	public final setter:TyIndexedAccessBinding;
	public final binary:Null<TyBoundAbstractBinaryOperator>;

	final declarations:Array<TyDeclarationInfo>;
	final declarationKeys:Array<String>;

	public function new(input:TyIndexedUpdateSelectionInput) {
		query = input.query;
		getter = input.getter;
		setter = input.setter;
		binary = input.binary;
		if (getter.declaration == null || setter.declaration == null)
			throw "indexed update requires declared getter and setter calls";
		declarations = [getter.declaration, setter.declaration];
		if (binary != null)
			declarations.push(binary.getOperatorInfo().getDeclaration());
		declarationKeys = declarations.map(declaration -> declaration.getIdentity().getCanonicalKey());
		validate(query.owner);
	}

	/** Similar syntax or another selected declaration cannot stand in for the completed candidate. */
	public function validate(candidateOwner:String):Void {
		query.validate(candidateOwner);
		if (!getter.owns(query.getterSource) || !setter.owns(query.setterSource))
			throw "indexed update selected call belongs to another query";
		if (declarations[0] != getter.declaration
			|| declarations[1] != setter.declaration
			|| (binary != null && declarations[2] != binary.getOperatorInfo().getDeclaration()))
			throw "indexed update changed its selected declaration";
		for (index in 0...declarations.length)
			if (declarationKeys[index] != declarations[index].getIdentity().getCanonicalKey())
				throw "indexed update changed its selected declaration identity";
	}
}
