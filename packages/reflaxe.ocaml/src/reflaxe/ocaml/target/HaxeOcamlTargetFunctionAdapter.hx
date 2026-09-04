package reflaxe.ocaml.target;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr;
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature;
#end

/**
	Copies admitted original stock-Haxe functions before Reflaxe preprocessors.

	The internal metadata envelope is not semantic input. It makes every generic
	preprocessor prove that the separately stored target fact survived as the
	authoritative function body until target emission.
**/
class HaxeOcamlTargetFunctionAdapter {
	public static inline final MARKER_META = ":reflaxeOcamlTargetFunction";

	#if (macro || reflaxe_runtime)
	public static function captureModuleTypes(moduleTypes:Array<ModuleType>, catalog:OcamlTargetFunctionCatalog):Int {
		if (catalog == null)
			throw "stock Haxe target function capture requires a request catalog";
		catalog.beginRequest();
		var captured = 0;
		for (moduleType in moduleTypes)
			switch (moduleType) {
				case TClassDecl(reference):
					final classType = reference.get();
					if (classType.constructor != null && captureField(classType.constructor.get(), classType, false, catalog))
						captured++;
					for (field in classType.fields.get())
						if (captureField(field, classType, false, catalog))
							captured++;
					for (field in classType.statics.get())
						if (captureField(field, classType, true, catalog))
							captured++;
				case _:
			}
		return captured;
	}

	public static function fromSourceBeforePreprocessing(data:ClassFuncData):Null<OcamlTargetFunctionFact> {
		final body = data == null ? null : data.expr;
		if (data == null || body == null || !data.isStatic || data.args.length != 0)
			return null;
		final returnType = TypeTools.toString(data.ret);
		if (returnType != "Void")
			return null;
		final signature:OcamlTargetFunctionSignature = {
			moduleId: data.classType.module,
			sourceTypeName: data.classType.name,
			sourceFunctionName: data.field.name,
			role: OcamlTargetFunctionRole.StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: returnType
		};
		final targetIdentity = OcamlTargetFunctionFact.identityFor(signature);
		final targetBody = HaxeOcamlTargetExpressionAdapter.fromSourceBeforePreprocessing(targetIdentity, body);
		if (targetBody == null || targetBody.semanticTypeDisplay != returnType)
			return null;
		return new OcamlTargetFunctionFact(signature, targetBody);
	}

	/** Returns every target-function identity still carried by one final body. **/
	public static function markerIdentities(expression:Null<TypedExpr>):Array<String> {
		final identities = new Array<String>();
		if (expression != null)
			visitMarkers(expression, identities);
		return identities;
	}

	public static function hasFinalMarker(data:ClassFuncData, fact:OcamlTargetFunctionFact):Bool {
		if (data == null || fact == null)
			return false;
		final markers = markerIdentities(data.expr);
		return markers.length == 1 && markers[0] == fact.getCanonicalIdentity();
	}

	static function captureField(field:ClassField, classType:ClassType, isStatic:Bool, catalog:OcamlTargetFunctionCatalog):Bool {
		return switch (field.kind) {
			case FMethod(_):
				final data = ClassFieldHelper.findFuncData(field, classType, isStatic);
				final fact = data == null ? null : fromSourceBeforePreprocessing(data);
				if (data == null || fact == null) {
					false;
				} else {
					if (markerIdentities(data.expr).length != 0)
						throw 'stock Haxe function "${data.id}" already contains target-owned function metadata';
					catalog.register(data.id, fact);
					mark(data, fact);
					true;
				}
			case _:
				false;
		};
	}

	static function mark(data:ClassFuncData, fact:OcamlTargetFunctionFact):Void {
		final body = data.expr;
		if (body == null)
			throw "stock Haxe target function lost its body before marking";
		data.setExpr({expr: TMeta(metadata(fact.getCanonicalIdentity(), body.pos), body), pos: body.pos, t: body.t});
	}

	static function metadata(identity:String, position:Position):MetadataEntry {
		final value:Expr = {expr: EConst(CString(identity)), pos: position};
		return {name: MARKER_META, params: [value], pos: position};
	}

	static function visitMarkers(expression:TypedExpr, output:Array<String>):Void {
		switch (expression.expr) {
			case TMeta(metadata, child) if (metadata.name == MARKER_META):
				final identity = readMarker(metadata);
				if (identity == null)
					throw "stock Haxe target function metadata has an invalid identity";
				output.push(identity);
				TypedExprTools.iter(child, candidate -> visitMarkers(candidate, output));
			case _:
				TypedExprTools.iter(expression, candidate -> visitMarkers(candidate, output));
		}
	}

	static function readMarker(entry:MetadataEntry):Null<String> {
		return switch (entry.params) {
			case [{expr: EConst(CString(value, _))}]: value;
			case _: null;
		};
	}
	#end
}
