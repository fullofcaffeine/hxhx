package reflaxe.ocaml.ast;

using StringTools;

/** One exact authored-text or typed-argument position in a raw OCaml template. */
enum OcamlRawInterpolationPlanPart {
	AuthoredText(value:String);
	TypedArgument(index:Int);
}

/** The checked placeholder layout or a source-facing reason it is unsafe. */
enum OcamlRawInterpolationPlanResult {
	Planned(parts:Array<OcamlRawInterpolationPlanPart>);
	Invalid(message:String);
}

/**
	Checks how typed Haxe expressions are inserted into an authored OCaml template.

	Each supplied argument must appear exactly once. This keeps evaluation and
	compiler-owned runtime-use provenance one-to-one: a template cannot silently
	drop a typed expression or duplicate it after its semantic checks have run.
**/
class OcamlRawInterpolationPlan {
	/** Builds the deterministic placeholder plan without compiling any argument expression. */
	public static function create(template:String, argumentCount:Int):OcamlRawInterpolationPlanResult {
		if (template == null)
			template = "";
		if (argumentCount < 0)
			return Invalid("raw __ocaml__ interpolation received a negative typed-argument count");

		final counts = [for (_ in 0...argumentCount) 0];
		final parts:Array<OcamlRawInterpolationPlanPart> = [];
		var lastPosition = 0;
		var invalidReason:Null<String> = null;
		~/{(\d+)}/g.map(template, function(ereg) {
			final matchPosition = ereg.matchedPos();
			if (matchPosition.pos > lastPosition)
				parts.push(AuthoredText(template.substring(lastPosition, matchPosition.pos)));

			final beforeIsIdentifier = matchPosition.pos > 0
				&& OcamlCodeIdentifierScanner.isIdentifierPartCode(template.fastCodeAt(matchPosition.pos - 1));
			final afterPosition = matchPosition.pos + matchPosition.len;
			final afterIsIdentifier = afterPosition < template.length
				&& OcamlCodeIdentifierScanner.isIdentifierPartCode(template.fastCodeAt(afterPosition));
			final argumentIndex = Std.parseInt(ereg.matched(1));
			if (beforeIsIdentifier || afterIsIdentifier) {
				if (invalidReason == null)
					invalidReason = 'raw __ocaml__ interpolation placeholder ${ereg.matched(0)} must be separated from authored identifier text';
			} else if (argumentIndex == null || argumentIndex < 0 || argumentIndex >= argumentCount) {
				if (invalidReason == null)
					invalidReason = 'raw __ocaml__ interpolation placeholder ${ereg.matched(0)} has no matching typed argument';
			} else {
				counts[argumentIndex]++;
				parts.push(TypedArgument(argumentIndex));
			}
			lastPosition = matchPosition.pos + matchPosition.len;
			return "";
		});
		if (lastPosition < template.length)
			parts.push(AuthoredText(template.substring(lastPosition)));

		if (invalidReason != null)
			return Invalid(invalidReason);
		for (index in 0...counts.length) {
			if (counts[index] != 1)
				return Invalid('raw __ocaml__ typed argument $index must appear exactly once; found ${counts[index]} placeholders');
		}
		return Planned(parts);
	}
}
