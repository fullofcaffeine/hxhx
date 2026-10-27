#if macro
import haxe.macro.Context;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.reuse.OcamlTargetReuseContract;

/** Checks whether a real request observes the source identity needed for replay. */
@:access(reflaxe.ocaml.OcamlCompiler)
class TargetRevisionObservationFixture {
	public static function check():Void {
		final compiler = new OcamlCompiler();
		final observation = compiler.captureTargetReuseObservation();
		final enabled = Context.defined("reflaxe_ocaml_target_reuse");
		if (observation.reuseEnabled != enabled)
			throw "Target reuse observation lost the request opt-in";
		if ((observation.targetImplementationRevision != null) != enabled)
			throw "Only opted-in requests should observe the complete target implementation";
		if (!~/^sha256:[0-9a-f]{64}$/.match(observation.runtimeInputRevision))
			throw "Runtime source integrity must remain checked in both modes";
		final components = OcamlTargetReuseContract.revisionComponents(observation);
		final expectedName = enabled ? "target-implementation" : "target-implementation-candidate";
		if (components.filter(component -> component.name == expectedName).length != 1)
			throw "Target revision components do not describe the observed authority";
		final blockers = OcamlTargetReuseContract.blockers(observation);
		for (reason in [
			"reflaxe.ocaml:target-reuse-disabled",
			"reflaxe.ocaml:target-implementation-authority-incomplete"
		])
			if (blockers.contains(reason) == enabled)
				throw "Target replay blockers disagree with the observed authority: " + reason;
		Sys.println("TARGET_REVISION_OBSERVATION:" + (enabled ? "enabled" : "disabled") + ":PASS");
	}
}
#end
