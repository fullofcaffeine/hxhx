package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.data.ClassFuncData;

/** Identifies the typed root whose target plans are being prepared. */
enum abstract OcamlFunctionPreparationRootKind(String) to String {
	var Ordinary = "ordinary";
	var Nested = "nested";
	var Standalone = "standalone";
}

/** Identifies whether one preparation reached its sealed-plan boundary. */
enum abstract OcamlFunctionPreparationResult(String) to String {
	var Sealed = "sealed";
	var Failed = "failed";
}

private typedef OcamlFunctionPreparationPhaseTiming = {
	final name:String;
	final dtMs:Int;
}

/**
	Accumulates phase timings for one selected function without logging each phase.

	Why: a compiler process can be interrupted while one large function is still
	being prepared. A durable begin row identifies that function, while one end
	row reports completed phase durations without adding synchronous I/O to every
	typed-expression traversal.

	The session belongs to one preparation call. It does not retain typed
	expressions or survive a compiler request.
**/
class OcamlFunctionPreparationTelemetrySession {
	final logLine:String->Void;
	final count:Int;
	final className:String;
	final fieldName:String;
	final rootKind:OcamlFunctionPreparationRootKind;
	final functionId:String;
	final startS:Float;
	var phaseStartS:Float;
	var finished:Bool = false;
	final phases:Array<OcamlFunctionPreparationPhaseTiming> = [];

	public function new(logLine:String->Void, count:Int, className:String, fieldName:String, rootKind:OcamlFunctionPreparationRootKind, functionId:String,
			argumentCount:Int, hasBody:Bool) {
		this.logLine = logLine;
		this.count = count;
		this.className = className;
		this.fieldName = fieldName;
		this.rootKind = rootKind;
		this.functionId = functionId;
		startS = haxe.Timer.stamp();
		phaseStartS = startS;
		logLine("reflaxe.ocaml: function_prepare_begin count=" + Std.string(count) + " class=" + token(className) + " field=" + token(fieldName) + " root="
			+ rootKind + " function_id=" + token(functionId) + " args=" + Std.string(argumentCount) + " body=" + (hasBody ? "present" : "absent"));
	}

	/** Records one completed in-memory phase interval. */
	public function checkpoint(name:String):Void {
		if (finished)
			return;
		final now = haxe.Timer.stamp();
		phases.push({
			name: name,
			dtMs: elapsedMilliseconds(phaseStartS, now)
		});
		phaseStartS = now;
	}

	/** Flushes the only end row for this preparation. */
	public function finish(result:OcamlFunctionPreparationResult):Void {
		if (finished)
			return;
		checkpoint(result == OcamlFunctionPreparationResult.Sealed ? "finalize" : "interrupted");
		finished = true;
		final now = haxe.Timer.stamp();
		var message = "reflaxe.ocaml: function_prepare_end count=" + Std.string(count) + " class=" + token(className) + " field=" + token(fieldName)
			+ " root=" + rootKind + " function_id=" + token(functionId) + " result=" + result + " dt_ms=" + Std.string(elapsedMilliseconds(startS, now));
		for (phase in phases)
			message += " phase_" + phase.name + "_ms=" + Std.string(phase.dtMs);
		logLine(message);
	}

	static inline function elapsedMilliseconds(startS:Float, endS:Float):Int {
		return Std.int(Math.max(0, (endS - startS) * 1000));
	}

	static function token(value:String):String {
		return StringTools.replace(StringTools.replace(StringTools.replace(value, "%", "%25"), "\t", "%09"), " ", "%20");
	}
}

/**
	Selects ordinary function preparations for detailed target telemetry.

	Detailed preparation logging is intentionally admitted only with one exact
	class filter. This keeps output bounded for compiler-scale programs and makes
	the last unmatched begin row useful interruption evidence.
**/
class OcamlFunctionPreparationTelemetry {
	final logLine:String->Void;
	final classFilter:String;
	final fieldFilter:Null<String>;
	var count:Int = 0;

	public function new(logLine:String->Void, classFilter:String, fieldFilter:Null<String>) {
		this.logLine = logLine;
		this.classFilter = classFilter;
		this.fieldFilter = fieldFilter;
	}

	/** Starts telemetry only when the exact configured class and field match. */
	public function beginOrdinary(data:ClassFuncData):Null<OcamlFunctionPreparationTelemetrySession> {
		final className = (data.classType.pack ?? []).concat([data.classType.name]).join(".");
		if (className != classFilter)
			return null;
		if (fieldFilter != null && fieldFilter.length > 0 && data.field.name != fieldFilter)
			return null;
		count++;
		return new OcamlFunctionPreparationTelemetrySession(logLine, count, className, data.field.name, OcamlFunctionPreparationRootKind.Ordinary, data.id,
			data.args.length, data.expr != null);
	}
}
#end
