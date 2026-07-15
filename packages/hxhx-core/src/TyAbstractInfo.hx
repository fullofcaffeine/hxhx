/**
	Semantic surface for a Haxe abstract declaration.

	The abstract keeps its own nominal identity even when its underlying type is
	a primitive target carrier. Unary declarations are cataloged by source token
	and fixity without assigning mutation or prefix/postfix result semantics.
**/
class TyAbstractInfo extends TyNominalInfo {
	final underlyingType:TyType;
	final typeParameters:Array<String>;
	final unaryOperators:haxe.ds.StringMap<Array<TyAbstractOperatorInfo>>;

	public function new(identity:TyNominalTypeId, shortName:String, modulePath:String, fields:haxe.ds.StringMap<TyType>,
			staticMethods:haxe.ds.StringMap<TyFunSig>, instanceMethods:haxe.ds.StringMap<TyFunSig>, staticMethodLists:haxe.ds.StringMap<Array<TyFunSig>>,
			instanceMethodLists:haxe.ds.StringMap<Array<TyFunSig>>, declarations:Array<TyDeclarationInfo>, underlyingType:TyType,
			typeParameters:Array<String>) {
		super(identity, shortName, modulePath, fields, staticMethods, instanceMethods, staticMethodLists, instanceMethodLists, declarations);
		this.underlyingType = underlyingType;
		this.typeParameters = typeParameters == null ? [] : typeParameters.copy();
		this.unaryOperators = new haxe.ds.StringMap();
	}

	static function unaryKey(op:HxUnaryOperator, fixity:HxUnaryFixity):String {
		return HxUnaryOperatorTools.sourceToken(op) + "|" + (fixity == HxUnaryFixity.Prefix ? "prefix" : "postfix");
	}

	public function getUnderlyingType():TyType
		return underlyingType;

	public function getTypeParameters():Array<String>
		return typeParameters;

	public function addUnaryOperator(info:TyAbstractOperatorInfo):Void {
		final key = unaryKey(info.getOperator(), info.getFixity());
		final candidates = unaryOperators.exists(key) ? unaryOperators.get(key) : [];
		candidates.push(info);
		unaryOperators.set(key, candidates);
	}

	public function getUnaryOperators(op:HxUnaryOperator, fixity:HxUnaryFixity):Array<TyAbstractOperatorInfo> {
		final key = unaryKey(op, fixity);
		return unaryOperators.exists(key) ? unaryOperators.get(key) : [];
	}

	public function getAllUnaryOperators():Array<TyAbstractOperatorInfo> {
		final out = new Array<TyAbstractOperatorInfo>();
		for (candidates in unaryOperators)
			for (candidate in candidates)
				out.push(candidate);
		return out;
	}
}
