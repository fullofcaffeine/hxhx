/**
	Semantic surface for a Haxe abstract declaration.

	An abstract remains its own Haxe type even when the generated program stores
	its values as a simpler type such as `Int`. This record keeps that distinction,
	plus the conversions declared in headers such as `from Int to Float`, so the
	shared typer can decide which operations are legal before a backend chooses a
	target-language representation. Operator declarations are cataloged by source
	token without assigning mutation or writeback rules.
**/
class TyAbstractInfo extends TyNominalInfo {
	final underlyingType:TyType;
	final typeParameters:Array<String>;
	final implicitFromTypes:Array<TyType>;
	final implicitToTypes:Array<TyType>;
	final unaryOperators:haxe.ds.StringMap<Array<TyAbstractOperatorInfo>>;
	final binaryOperators:haxe.ds.StringMap<Array<TyAbstractBinaryOperatorInfo>>;

	public function new(identity:TyNominalTypeId, shortName:String, modulePath:String, fields:haxe.ds.StringMap<TyFieldInfo>,
			properties:haxe.ds.StringMap<TyPropertyInfo>, staticMethods:haxe.ds.StringMap<TyFunSig>, instanceMethods:haxe.ds.StringMap<TyFunSig>,
			staticMethodLists:haxe.ds.StringMap<Array<TyFunSig>>, instanceMethodLists:haxe.ds.StringMap<Array<TyFunSig>>,
			declarations:Array<TyDeclarationInfo>, underlyingType:TyType, typeParameters:Array<String>, implicitFromTypes:Array<TyType>,
			implicitToTypes:Array<TyType>) {
		super(identity, shortName, modulePath, fields, properties, staticMethods, instanceMethods, staticMethodLists, instanceMethodLists, declarations);
		this.underlyingType = underlyingType;
		this.typeParameters = typeParameters == null ? [] : typeParameters.copy();
		this.implicitFromTypes = implicitFromTypes == null ? [] : implicitFromTypes.copy();
		this.implicitToTypes = implicitToTypes == null ? [] : implicitToTypes.copy();
		this.unaryOperators = new haxe.ds.StringMap();
		this.binaryOperators = new haxe.ds.StringMap();
	}

	static function unaryKey(op:HxUnaryOperator, fixity:HxUnaryFixity):String {
		return HxUnaryOperatorTools.sourceToken(op) + "|" + (fixity == HxUnaryFixity.Prefix ? "prefix" : "postfix");
	}

	public function getUnderlyingType():TyType
		return underlyingType;

	public function getTypeParameters():Array<String>
		return typeParameters;

	/** Types that Haxe may convert into this abstract through its header `from` declarations. **/
	public function getImplicitFromTypes():Array<TyType>
		return implicitFromTypes.copy();

	/** Types that Haxe may obtain from this abstract through its header `to` declarations. **/
	public function getImplicitToTypes():Array<TyType>
		return implicitToTypes.copy();

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

	public function addBinaryOperator(info:TyAbstractBinaryOperatorInfo):Void {
		final key = info.getOperator();
		final candidates = binaryOperators.exists(key) ? binaryOperators.get(key) : [];
		candidates.push(info);
		binaryOperators.set(key, candidates);
	}

	public function getBinaryOperators(op:String):Array<TyAbstractBinaryOperatorInfo>
		return binaryOperators.exists(op) ? binaryOperators.get(op) : [];

	public function getAllBinaryOperators():Array<TyAbstractBinaryOperatorInfo> {
		final out = new Array<TyAbstractBinaryOperatorInfo>();
		for (candidates in binaryOperators)
			for (candidate in candidates)
				out.push(candidate);
		return out;
	}
}
