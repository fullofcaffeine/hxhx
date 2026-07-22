/**
	Result of comparing two complete dependency observations.

	This report does not skip compiler work. It exists so clean compilations can
	prove whether the future cache would have invalidated every affected module.
**/
class CompilerDependencyComparison {
	final publicInterfaceChanges:Array<String>;
	final implementationChanges:Array<String>;
	final invalidations:Array<CompilerDependencyInvalidation>;

	public function new(publicInterfaceChanges:Array<String>, implementationChanges:Array<String>, invalidations:Array<CompilerDependencyInvalidation>) {
		this.publicInterfaceChanges = sortedCopy(publicInterfaceChanges);
		this.implementationChanges = sortedCopy(implementationChanges);
		this.invalidations = invalidations == null ? [] : invalidations.copy();
		this.invalidations.sort(compareInvalidations);
	}

	public function getPublicInterfaceChanges():Array<String>
		return publicInterfaceChanges.copy();

	public function getImplementationChanges():Array<String>
		return implementationChanges.copy();

	public function getInvalidations():Array<CompilerDependencyInvalidation>
		return invalidations.copy();

	public function isAffected(modulePath:String):Bool {
		for (invalidation in invalidations)
			if (invalidation.modulePath == modulePath)
				return true;
		return false;
	}

	public function reasonFor(modulePath:String):Null<CompilerDependencyInvalidation> {
		for (invalidation in invalidations)
			if (invalidation.modulePath == modulePath)
				return invalidation;
		return null;
	}

	static function sortedCopy(values:Array<String>):Array<String> {
		final out = values == null ? [] : values.copy();
		out.sort(compareText);
		return out;
	}

	static function compareInvalidations(left:CompilerDependencyInvalidation, right:CompilerDependencyInvalidation):Int
		return compareText(left.modulePath, right.modulePath);

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
