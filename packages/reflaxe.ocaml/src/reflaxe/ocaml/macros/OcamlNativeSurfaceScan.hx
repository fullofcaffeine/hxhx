package reflaxe.ocaml.macros;

#if macro
import haxe.macro.Type;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery.NativeSurfaceCapture;

/**
	Checks expressions from one already-decoded compiler field body.

	A class reference denotes that final class's static type surface. Repeated
	class references can reuse a completed result within this body, until any
	query observes a lazy type, monomorph, or unknown declaration. The query
	notifies this owner before a later result can use the old entry. Diagnostics
	remain owned by the caller and run at every expression, including cache hits.
	Completed typedef and abstract bodies share this lifetime, with exact depth
	and mask keys. Their actual arguments are still visited before every lookup.

	Create a fresh scan after each field.expr() call. Between find calls the caller
	may only traverse that decoded AST and report diagnostics. Strict checking can
	force types independently, so its caller must disable reuse. Never keep
	this object across field reads, typing callbacks, compiler requests, or builds.
	Discard the scan if a query throws; callers must not resume a failed body scan.
	The capture callback stays deferred until the first actual native-type check.
**/
class OcamlNativeSurfaceScan {
	static inline final DEPTH = 16;

	final getCapture:Void->NativeSurfaceCapture;
	final allowReuse:Bool;
	final completedClasses:Map<String, Int> = [];
	final completedBodies:Map<String, Int> = [];
	var query:Null<OcamlNativeSurfaceQuery>;
	var expressionBarrier = false;

	/** Counts for this body, retained across invalidation for progress diagnostics. */
	public var classHits(default, null) = 0;

	public var classQueries(default, null) = 0;

	public function new(getCapture:Void->NativeSurfaceCapture, allowReuse:Bool) {
		this.getCapture = getCapture;
		this.allowReuse = allowReuse;
	}

	/** Discards completed results before any caller-supplied callback can perform type work. */
	public function invalidate():Void {
		completedClasses.clear();
		completedBodies.clear();
		expressionBarrier = true;
	}

	function getQuery():OcamlNativeSurfaceQuery {
		if (query == null)
			query = new OcamlNativeSurfaceQuery(getCapture(), invalidate);
		return query;
	}

	/** Queries the result type and the same expression-owned types as the ordered validator. */
	public function find(expression:TypedExpr, requested:Int):Int {
		if (requested == 0)
			return 0;
		expressionBarrier = false;
		final current = getQuery();
		var key:Null<String> = null;
		if (allowReuse) {
			switch expression.expr {
				case TTypeExpr(TClassDecl(_)):
					final identity = current.capturedClassIdentity(expression);
					if (identity == null) {
						invalidate();
					} else {
						key = identity + ":" + DEPTH + ":" + requested;
						final previous = completedClasses.get(key);
						if (previous != null) {
							classHits++;
							return previous;
						}
						classQueries++;
					}
				case _:
			}
		}
		var found = allowReuse ? current.findBodyExpression(expression, DEPTH, requested,
			completedBodies) : current.findExpression(expression, DEPTH, requested);
		final remaining = requested & ~found;
		if (remaining != 0) {
			found |= switch expression.expr {
				case TTypeExpr(moduleType): current.findModule(moduleType) & remaining;
				case TVar(variable, _): findType(current, variable.t, remaining);
				case TFunction(fn):
					var arguments = 0;
					for (argument in fn.args) {
						arguments |= findType(current, argument.v.t, remaining & ~arguments);
						if (arguments == remaining)
							break;
					}
					arguments;
				case _: 0;
			};
		}
		if (key != null && !expressionBarrier)
			completedClasses.set(key, found);
		return found;
	}

	/** Applies the same reuse permission to expression-owned variable and function argument types. */
	function findType(current:OcamlNativeSurfaceQuery, type:Type, requested:Int):Int {
		return allowReuse ? current.findBodyType(type, DEPTH, requested, completedBodies) : current.find(type, DEPTH, requested);
	}
}
#end
