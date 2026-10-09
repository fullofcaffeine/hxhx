import haxe.macro.ExprTools;
import hxhxmacrohost.api.RuntimeMacroExprs;

/** Local generic syntax must survive immutable source facts, macro quotation, and typed quotation replay. */
class M14SourceGenericFunctionSyntaxTest {
	static function facts(source:HxExpr):HxSourceFunction {
		return switch source {
			case ESourceFunction(value, _, _, _): value;
			case _: throw "generic function lost its authored function node";
		};
	}

	static function main():Void {
		// Stored metadata has the same expression representation for quoted functions and runtime type information.
		final metadata = RuntimeMacroExprs.parseMetadataEntries(["ignored", '@:tag("first", [1, 2])', "@:flag", '@:tag("second")']);
		if (metadata.length != 3 || metadata[0].name != ":tag" || metadata[1].name != ":flag" || metadata[2].name != ":tag")
			throw "stored metadata lost order, duplicate names, or invalid-entry filtering";
		if (metadata[0].params.length != 2
			|| ExprTools.toString(metadata[0].params[0]) != '"first"'
			|| ExprTools.toString(metadata[0].params[1]) != "[1, 2]"
			|| metadata[1].params.length != 0
			|| ExprTools.toString(metadata[2].params[0]) != '"second"')
			throw "stored metadata arguments changed";
		for (entry in metadata) {
			final position = hxhxmacrohost.api.Context.getPosInfos(entry.pos);
			if (position.file != "<macro>" || position.min != 0 || position.max != 0)
				throw "stored metadata synthetic position changed";
		}
		if (RuntimeMacroExprs.parseMetadataEntries(null).length != 0 || RuntimeMacroExprs.parseMetadataEntries([]).length != 0)
			throw "absent metadata must remain empty";
		final text = 'function echo<@:localMarker("tag") T:Array<Int>>(value:T):T { return value; }';
		final source = HxParser.parseCompleteExprText(text);
		final generics = facts(source).getGenerics();
		final parameters = generics.getParameters();
		if (parameters.length != 1 || parameters[0].name != "T" || parameters[0].constraints.length != 1)
			throw "generic parameter or its bound was discarded";
		switch parameters[0].constraints[0].getKind() {
			case TypePath(["Array"], [inner]):
				switch inner.getKind() {
					case TypePath(["Int"], []):
					case _: throw "nested constraint argument changed";
				}
			case _:
				throw "generic constraint is not structured type syntax";
		}
		final constraint = parameters[0].constraints[0];
		if (text.substring(constraint.getPos().getIndex(), constraint.getEndPos().getIndex()) != "Array<Int>")
			throw "constraint span differs from its authored spelling";
		parameters[0].constraints.resize(0);
		parameters[0].metadata.resize(0);
		parameters.resize(0);
		if (generics.getParameters()[0].constraints.length != 1 || generics.getParameters()[0].metadata.length != 1)
			throw "generic syntax escaped through mutable array access";

		final expected = SourceGenericFunctionSyntaxOracle.parsed('function echo<@:localMarker("tag") T:Array<Int>>(value:T):T { return value; }');
		final actual = RuntimeMacroExprs.parse(text, null);
		switch actual.expr {
			case EFunction(_, fn):
				switch fn.params[0].constraints[0] {
					case TPath({pack: [], name: "Array", params: [TPType(TPath({pack: [], name: "Int", params: []}))]}):
					case _: throw "generic macro constraint flattened into a type name";
				}
			case _:
				throw "macro parser did not preserve a generic function";
		}
		if (ExprTools.toString(actual) != expected)
			throw "generic macro syntax differs from upstream: " + ExprTools.toString(actual) + "\nexpected: " + expected;
		final defaults = 'function echo<T=String>(value:T):T return value';
		if (facts(HxParser.parseCompleteExprText(defaults)).getGenerics().getParameters()[0].defaultType == null)
			throw "generic default was lost before executable-source validation";
		final expectedDefaults = SourceGenericFunctionSyntaxOracle.parsed('function echo<T=String>(value:T):T return value');
		if (ExprTools.toString(RuntimeMacroExprs.parse(defaults, null)) != expectedDefaults)
			throw "generic default syntax changed before semantic validation: "
				+ ExprTools.toString(RuntimeMacroExprs.parse(defaults, null))
				+ "\nexpected: "
				+ expectedDefaults;

		for (entry in [
			{
				text: 'function echo<T:Int & String & Bool>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:Int & String & Bool>(value:T):T return value')
			},
			{
				text: 'function echo<T:(Int & String)>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:(Int & String)>(value:T):T return value')
			},
			{
				text: 'function echo<T:Int & String -> Bool>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:Int & String -> Bool>(value:T):T return value')
			},
			{
				text: 'function echo<T:Int -> String & Bool>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:Int -> String & Bool>(value:T):T return value')
			},
			{
				text: 'function echo<T:{>Base, final id:Int; var ?name:String; var count(default,null):Int; function call<U>(value:U):U;}>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:{>Base, final id:Int; var ?name:String; var count(default,null):Int; function call<U>(value:U):U;}>(value:T):T return value')
			},
			{
				text: 'function echo<T:(value:Int, ?name:String)->String>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:(value:Int, ?name:String)->String>(value:T):T return value')
			},
			{
				text: 'function echo<T:(...values:Int)->Void>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:(...values:Int)->Void>(value:T):T return value')
			},
			{
				text: 'function echo<T:(?value:Int)->Void>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:(?value:Int)->Void>(value:T):T return value')
			},
			{
				text: 'function echo<T:{public var length:Int;}>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:{public var length:Int;}>(value:T):T return value')
			},
			{
				text: 'function echo<T:{var length:Int;}>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:{var length:Int;}>(value:T):T return value')
			},
			{
				text: 'function echo<T:(Int->String)>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:(Int->String)>(value:T):T return value')
			},
			{
				text: 'function echo<T:haxe.macro.Expr.TypeParamDecl>(value:T):T return value',
				expected: SourceGenericFunctionSyntaxOracle.parsed('function echo<T:haxe.macro.Expr.TypeParamDecl>(value:T):T return value')
			}
		]) {
			final rendered = ExprTools.toString(RuntimeMacroExprs.parse(entry.text, null));
			if (rendered != entry.expected)
				throw "structured constraint changed: " + rendered + "\nexpected: " + entry.expected;
		}
		final intersection = RuntimeMacroExprs.parse('function echo<T:Int & String & Bool>(value:T):T return value', null);
		switch intersection.expr {
			case EFunction(_, {params: [{constraints: [TIntersection([_, _, _])]}]}):
			case _:
				throw "intersection constraint was split into separate declarations";
		}
		final grouped = RuntimeMacroExprs.parse('function echo<T:(Int->String)>(value:T):T return value', null);
		switch grouped.expr {
			case EFunction(_, {params: [{constraints: [TParent(TFunction(_, _))]}]}):
			case _:
				throw "function constraint lost its grouping node";
		}
		final fingerprint = TypedBodyFingerprint.forExpression(source);
		for (changed in [
			StringTools.replace(text, "Array<Int>", "Array<String>"),
			StringTools.replace(text, "tag", "other")
		])
			if (TypedBodyFingerprint.forExpression(HxParser.parseCompleteExprText(changed)) == fingerprint)
				throw "generic syntax change reused a source fingerprint";
		final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(source, []), HxPos.unknown(), null).getExpressions()[0];
		if (TypedBodyFingerprint.forExpression(TypedSourceSyntax.expression(quoted)) != fingerprint)
			throw "typed quotation discarded generic source facts";
		Sys.println("SOURCE_GENERIC_FUNCTION_SYNTAX:PASS");
	}
}
