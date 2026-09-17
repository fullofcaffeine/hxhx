package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import haxe.macro.TypeTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlNativeEnumRepresentation.OcamlNativeEnumDescriptor;

/** Closed completion shapes investigated before native enum calls can be admitted. */
enum OcamlEnumResultShape {
	Constructor;
	Call;
	RetainedConstructor;
	RetainedCall;
}

/** Stable reasons why a declaration cannot supply a native enum result contract. */
enum OcamlEnumResultExclusion {
	UnsupportedDeclaration;
	UnsupportedResult;
	MissingBody;
	UnsupportedCompletion;
	DependencyNotClosed;
	Cycle;
}

/** A source candidate is descriptive evidence, not permission to change a value's carrier. */
typedef OcamlEnumResultCandidate = {
	final calleeId:String;
	final programRevision:String;
	final modelRevision:String;
	final isStatic:Bool;
	final descriptor:OcamlNativeEnumDescriptor;
	final sourceFingerprint:String;
	final shape:OcamlEnumResultShape;
	final dependency:Null<String>;
	final dependencySource:Null<OcamlLoweredSourceSpan>;
}

/**
	Classifies a small enum-result grammar and closes its dependency graph once.

	This first phase is deliberately disconnected from calls, local storage, and
	result emission. A later final-body comparison must establish correspondence
	before these candidates can become callable contracts. Every request clears
	positive and negative results; queries never scan a function or graph again.
**/
class OcamlNativeEnumResultAdmission {
	public static inline final MODEL = "ocaml-enum-result-source-v1";

	public var bodyScans(default, null):Int = 0;
	public var edgeVisits(default, null):Int = 0;

	var programRevision:String = "";
	var finished:Bool = false;
	final sources:Map<String, Null<OcamlEnumResultCandidate>> = [];
	final closed:Map<String, Bool> = [];
	final exclusions:Map<String, OcamlEnumResultExclusion> = [];

	public function new() {}

	/** Discard all source observations and graph outcomes at the request boundary. */
	public function beginProgram(revision:String):Void {
		if (revision.length == 0)
			throw "enum result classification requires a program revision";
		programRevision = revision;
		finished = false;
		sources.clear();
		closed.clear();
		exclusions.clear();
		bodyScans = 0;
		edgeVisits = 0;
	}

	/** Observe one declaration exactly once, before any graph query is published. */
	public function add(owner:ClassType, field:ClassField, isStatic:Bool, context:CompilationContext):Void {
		if (programRevision.length == 0 || finished)
			throw "enum result source observation is outside its preparation phase";
		final id = OcamlCallPlanner.calleeId(owner, field);
		if (sources.exists(id))
			throw "duplicate enum result source observation: " + id;
		#if reflaxe_ocaml_enum_result_test
		bodyScans++;
		#end
		sources.set(id, null);
		exclusions.set(id, UnsupportedDeclaration);
		if (owner.isExtern || owner.isInterface || owner.params.length != 0 || owner.superClass != null || owner.interfaces.length != 0 || field.isExtern
			|| field.params.length != 0 || field.overloads.get().length != 0 || !field.kind.match(FMethod(MethNormal)))
			return;
		final resultType = switch (TypeTools.follow(field.type)) {
			case TFun(_, result): result;
			case _: null;
		};
		final descriptor = resultType == null ? null : OcamlNativeEnumRepresentation.select(resultType, context);
		exclusions.set(id, UnsupportedResult);
		if (descriptor == null)
			return;
		final expression = field.expr();
		exclusions.set(id, MissingBody);
		if (expression == null)
			return;
		final body = switch (expression.expr) {
			case TFunction(fn): fn.expr;
			case _: null;
		};
		if (body == null)
			return;
		final selected = classify(body, owner, isStatic, descriptor, context);
		exclusions.set(id, UnsupportedCompletion);
		if (selected == null)
			return;
		sources.set(id, {
			calleeId: id,
			programRevision: programRevision,
			modelRevision: MODEL,
			isStatic: isStatic,
			descriptor: descriptor,
			sourceFingerprint: "sha256:" + Sha256.encode(MODEL + TypedExprTools.toString(body)),
			shape: selected.shape,
			dependency: selected.dependency,
			dependencySource: selected.dependencySource
		});
		exclusions.remove(id);
	}

	/** Memoize acyclic closure, excluding missing, unsupported, and cyclic producers. */
	public function finish():Void {
		if (programRevision.length == 0 || finished)
			throw "enum result graph preparation requires one open program";
		final active:Map<String, Bool> = [];
		function visit(id:String):Bool {
			if (closed.exists(id))
				return closed.get(id);
			if (active.exists(id)) {
				exclusions.set(id, Cycle);
				return false;
			}
			final source = sources.get(id);
			if (source == null) {
				closed.set(id, false);
				return false;
			}
			active.set(id, true);
			var valid = true;
			if (source.dependency != null) {
				#if reflaxe_ocaml_enum_result_test
				edgeVisits++;
				#end
				final dependency = sources.get(source.dependency);
				valid = dependency != null && dependency.descriptor.revision == source.descriptor.revision && visit(source.dependency);
			}
			active.remove(id);
			closed.set(id, valid);
			if (!valid && !exclusions.exists(id))
				exclusions.set(id, DependencyNotClosed);
			return valid;
		}
		final ids = [for (id in sources.keys()) id];
		ids.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		for (id in ids)
			visit(id);
		finished = true;
	}

	/** Return a copied closed candidate; no caller can publish or mutate this catalog. */
	public function candidate(id:String):Null<OcamlEnumResultCandidate> {
		if (!finished || closed.get(id) != true)
			return null;
		final source = sources.get(id);
		return source == null ? null : {
			calleeId: source.calleeId,
			programRevision: source.programRevision,
			modelRevision: source.modelRevision,
			isStatic: source.isStatic,
			descriptor: source.descriptor,
			sourceFingerprint: source.sourceFingerprint,
			shape: source.shape,
			dependency: source.dependency,
			dependencySource: source.dependencySource == null ? null : {
				file: source.dependencySource.file,
				min: source.dependencySource.min,
				max: source.dependencySource.max
			}
		};
	}

	/** Returns the recorded rejection without revisiting source or dependency edges. */
	public function exclusion(id:String):Null<OcamlEnumResultExclusion> {
		return finished ? exclusions.get(id) : null;
	}

	/**
		Checks the actual post-preprocessing body against its early producer grammar.

		This does not admit calls or locals. It rejects a changed owner, result,
		completion shape, or exact callee before a later phase may trust the catalog.
		Harmless wrappers and local renaming can change without changing that proof.
	**/
	public function requireFinal(data:ClassFuncData, context:CompilationContext):Void {
		if (!finished || data.programRevision != programRevision)
			throw "enum result final comparison requires the prepared program revision";
		final id = OcamlCallPlanner.calleeId(data.classType, data.field);
		final source = candidate(id);
		if (source == null)
			return;
		if (source.modelRevision != MODEL || data.isStatic != source.isStatic)
			throw "enum result final body changed its declaration kind: " + id;
		final descriptor = OcamlNativeEnumRepresentation.select(data.ret, context);
		if (descriptor == null || descriptor.revision != source.descriptor.revision || data.expr == null)
			throw "enum result final body lost its declared variant: " + id;
		final selected = classify(data.expr, data.classType, data.isStatic, descriptor, context);
		if (selected == null || selected.shape != source.shape || selected.dependency != source.dependency)
			throw "enum result final body changed its source completion: " + id;
	}

	/** Preserve casts and control flow as boundaries; only harmless source wrappers disappear. */
	static function unwrap(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TParenthesis(child) | TMeta(_, child): unwrap(child);
			case _: expression;
		};
	}

	static function classify(body:TypedExpr, owner:ClassType, isStatic:Bool, descriptor:OcamlNativeEnumDescriptor,
			context:CompilationContext):Null<{shape:OcamlEnumResultShape, dependency:Null<String>, dependencySource:Null<OcamlLoweredSourceSpan>}> {
		final statements = switch (unwrap(body).expr) {
			case TBlock(items): items;
			case _: [body];
		};
		if (statements.length == 0)
			return null;
		var completed = unwrap(statements[statements.length - 1]);
		switch (completed.expr) {
			case TReturn(value) if (value != null):
				completed = unwrap(value);
			case _:
		}
		var local:Null<TVar> = null;
		var producer = completed;
		var firstEffect = 0;
		if (statements.length > 1)
			switch (unwrap(statements[0]).expr) {
				case TVar(variable, initializer) if (initializer != null && !variable.capture && !variable.isStatic):
					switch (completed.expr) {
						case TLocal(returned) if (returned.id == variable.id):
							local = variable;
							producer = unwrap(initializer);
							firstEffect = 1;
						case _: return null;
					}
				case _:
			}
		for (index in firstEffect...statements.length - 1)
			if (!safeEffect(statements[index], local))
				return null;
		final direct = OcamlNativeEnumRepresentation.selectDirectConstructor(producer, context);
		if (direct != null && direct.revision == descriptor.revision)
			return {shape: local == null ? Constructor : RetainedConstructor, dependency: null, dependencySource: null};
		final dependency = switch (producer.expr) {
			case TCall(callee, _):
				switch (unwrap(callee).expr) {
					case TField(_, FStatic(reference, field)):
						OcamlCallPlanner.calleeId(reference.get(), field.get());
					case TField(receiver, FInstance(reference, parameters, field))
						if (!isStatic
							&& parameters.length == 0
							&& reference.get().module == owner.module
							&& reference.get().name == owner.name
							&& unwrap(receiver).expr.match(TConst(TThis))):
						OcamlCallPlanner.calleeId(reference.get(), field.get());
					case _: null;
				}
			case _: null;
		};
		return dependency == null ? null : {
			shape: local == null ? Call : RetainedCall,
			dependency: dependency,
			dependencySource: OcamlLoweredOrigin.sourceSpan(producer.pos)
		};
	}

	/** A supported intervening call cannot replace, capture, or expose the retained local. */
	static function safeEffect(expression:TypedExpr, local:Null<TVar>):Bool {
		if (!unwrap(expression).expr.match(TCall(_, _)))
			return false;
		var safe = true;
		function visit(value:TypedExpr):Void {
			switch (value.expr) {
				case TReturn(_) | TFunction(_) | TVar(_, _) | TBreak | TContinue:
					safe = false;
				case TLocal(variable) if (local != null && variable.id == local.id):
					safe = false;
				case _:
					TypedExprTools.iter(value, visit);
			}
		}
		visit(expression);
		return safe;
	}
}
#end
