/**
	Prove that a single typed pattern cannot fall through on normal completion.

	A required record field can always be captured, while a literal or array length
	can fail. Reading a null record may throw; that abrupt path does not leave a
	switch result unassigned. This proof does not replace finite-domain coverage
	analysis. Name resolution must prove that a bare name introduces a capture,
	not a constant pattern. This analysis does not combine several individually refutable rows into a complete matrix.
 */
function proves(pattern:HxSwitchPattern, type:TyType, isCapture:String->Bool):Bool {
	return switch pattern {
		case PWildcard: true;
		case PBind(name): isCapture(name);
		case PCapture(_, inner): proves(inner, type, isCapture);
		case POr(alternatives): alternatives != null && alternatives.filter(item -> proves(item, type, isCapture)).length > 0;
		case PObject(names, patterns):
			var record = type;
			while (record != null && record.isNullable())
				record = record.unwrapNull();
			if (record == null || !record.isAnonymous() || names == null || patterns == null || names.length == 0 || names.length != patterns.length) {
				false;
			} else {
				final fields = record.getAnonymousFieldNames();
				final types = record.getAnonymousFieldTypes();
				var covered = true;
				for (i in 0...names.length) {
					final index = fields.indexOf(names[i]);
					if (index < 0 || !proves(patterns[i], types[index], isCapture))
						covered = false;
				}
				covered;
			}
		case _: false;
	};
}
