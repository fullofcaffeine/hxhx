/** Named inputs keep lexical identity, receiver use, and capture lists distinct. */
typedef TypedCaptureFunctionInput = {
	final identity:String;
	final parentIdentity:Null<String>;
	final occurrence:String;
	final controlTargetIdentity:Null<String>;
	final namedBinding:Null<TyLocalBinding>;
	final directCaptures:Array<TyLocalBinding>;
	final captures:Array<TyLocalBinding>;
	final directReceiver:Bool;
	final capturesReceiver:Bool;
}

/**
	Immutable capture dependencies for one executable function occurrence.
	Direct captures include reads and assignment targets. All captures additionally
	include locations needed to construct descendant closures after a creator exits.
	Function keys are scoped to the owning plan's exact checked body revision.
 */
class TypedCaptureFunction {
	public final identity:String;
	public final parentIdentity:Null<String>;
	public final occurrence:String;
	public final controlTargetIdentity:Null<String>;
	public final namedBinding:Null<TyLocalBinding>;
	public final directReceiver:Bool;
	public final capturesReceiver:Bool;

	final directCaptures:Array<TyLocalBinding>;
	final captures:Array<TyLocalBinding>;

	public function new(input:TypedCaptureFunctionInput) {
		identity = input.identity;
		parentIdentity = input.parentIdentity;
		occurrence = input.occurrence;
		controlTargetIdentity = input.controlTargetIdentity;
		namedBinding = input.namedBinding;
		directReceiver = input.directReceiver;
		capturesReceiver = input.capturesReceiver;
		directCaptures = input.directCaptures.copy();
		captures = input.captures.copy();
	}

	public function getDirectCaptures():Array<TyLocalBinding>
		return directCaptures.copy();

	public function getCaptures():Array<TyLocalBinding>
		return captures.copy();
}
