import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;

/** A retained provider whose constructor and method prove the dynamic resolver path ran. */
@:keep
class NativeProvider implements ITargetBackendProvider {
	public static var constructions:Int = 0;
	public static var calls:Int = 0;

	var padding:String;

	public function new() {
		padding = "native provider";
		constructions++;
	}

	public function registrations():Array<BackendRegistrationSpec> {
		if (padding != "native provider")
			throw "provider lost its receiver";
		calls++;
		return [];
	}
}
