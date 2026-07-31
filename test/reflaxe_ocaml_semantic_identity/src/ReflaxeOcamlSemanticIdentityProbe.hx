#if macro
import haxe.crypto.Sha256;
import haxe.macro.Context;
import haxe.macro.TypedExprTools;
import sys.io.File;
#end

/**
	Perturbs Haxe's temporary local-variable allocator for semantic-ID tests.

	The probe records Haxe's raw typed-expression rendering, not a stable
	Reflaxe artifact. The test requires that this raw value changes while the
	standalone target's complete generated evidence remains byte-identical.
**/
class ReflaxeOcamlSemanticIdentityProbe {
	#if macro
	/**
		Registers one post-initialization probe before the user program is typed.

		Environment variables control the test so both compiler invocations use
		the same Haxe defines and target configuration.
	**/
	public static function run():Void {
		Context.onAfterInitMacros(() -> {
			final outputPath = Sys.getEnv("REFLAXE_OCAML_IDENTITY_PROBE_PATH");
			if (outputPath == null || outputPath.length == 0)
				Context.fatalError("REFLAXE_OCAML_IDENTITY_PROBE_PATH is required.", Context.currentPos());

			if (Sys.getEnv("REFLAXE_OCAML_IDENTITY_PERTURB") == "1") {
				Context.typeExpr(macro {
					var unrelatedFirst = 1;
					unrelatedFirst + 1;
				});
				Context.typeExpr(macro {
					var unrelatedSecond = 2;
					unrelatedSecond + 1;
				});
			}

			final probe = Context.typeExpr(macro {
				var observed = 7;
				observed + 1;
			});
			File.saveContent(outputPath, Sha256.encode(TypedExprTools.toString(probe)) + "\n");
		});
	}
	#end
}
