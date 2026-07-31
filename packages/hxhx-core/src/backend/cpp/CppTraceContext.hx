package backend.cpp;

/**
	Diagnostic trace settings owned by one C++ program render.

	The configuration is captured when the program lookup is created so later
	environment changes cannot alter an active render or a later request reuse
	settings from an earlier program. The phase buffer is mutable only while a
	nested measurement is collecting ordered diagnostic lines.
**/
class CppTraceContext {
	/** Whether this program records detailed C++ render timings. **/
	public final timingsEnabled:Bool;

	/** Optional `Owner.method` or method-only filter for statement timings. **/
	public final timingMethodFilter:String;

	/** Whether verbose C++ render-stage diagnostics are enabled. **/
	public final deepEnabled:Bool;

	/** Whether selected method timing includes lambda sub-phases. **/
	public final lambdaPhasesEnabled:Bool;

	/** Whether selected method timing includes call-argument sub-phases. **/
	public final callArgDetailPhasesEnabled:Bool;

	/** Whether helper classification emits one detail record per helper. **/
	public final helperClassificationDetailsEnabled:Bool;

	/** Current nested timing sink, restored after every measured callback. **/
	public var timingPhaseBuffer:Null<Array<String>>;

	public function new(timingsEnabled:Bool, timingMethodFilter:String, deepEnabled:Bool = false, lambdaPhasesEnabled:Bool = false,
			callArgDetailPhasesEnabled:Bool = false, helperClassificationDetailsEnabled:Bool = false) {
		this.timingsEnabled = timingsEnabled;
		this.timingMethodFilter = timingMethodFilter == null ? "" : StringTools.trim(timingMethodFilter);
		this.deepEnabled = deepEnabled;
		this.lambdaPhasesEnabled = lambdaPhasesEnabled;
		this.callArgDetailPhasesEnabled = callArgDetailPhasesEnabled;
		this.helperClassificationDetailsEnabled = helperClassificationDetailsEnabled;
		this.timingPhaseBuffer = null;
	}
}
