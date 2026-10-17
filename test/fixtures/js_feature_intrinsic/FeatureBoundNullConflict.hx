import FeatureBoundNull.NullBoundBase;

/** A later null operand must not hide an earlier concrete argument that violates a method bound. */
class FeatureBoundNullConflict {
	static function select<T:NullBoundBase>(first:T, second:T):T {
		return second;
	}

	static function main():Void {
		select(7, null);
	}
}
