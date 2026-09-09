/** Recursive generic bodies require real parameter ownership before reuse is safe. */
typedef GenericTree<T> = {
	final value:T;
	final left:GenericTree<T>;
	final right:GenericTree<T>;
};

/** Static method type parameters belong to their individual methods. */
class PureStatics<T:OwnedConstraint> {
	public static function first<T>(value:GenericTree<T>):GenericTree<T>
		return value;

	public static function second<T>(value:GenericTree<T>):GenericTree<T>
		return value;
}

/** A build callback detects unexpected constraint work during parameter recognition. */
@:build(NativeSurfaceOwnedFixture.buildConstraint())
interface OwnedConstraint {
	public function marker():Int;
}

/** A normal package can still expose native types through its static fields. */
class NativeStatics {
	public static function native():ocaml.SurfaceMarker
		return null;

	public static function atomic():haxe.atomic.SurfaceMarker
		return null;
}

/** A secondary enum declaration checks module paths and generic arguments. */
enum PlainEnum<T> {
	Value(value:T);
}

/** Class references expose enum packages and enum arguments in static signatures. */
class EnumStatics {
	public static function native(value:ocaml.SurfaceEnum<String>):Int
		return 0;

	public static function atomic(value:haxe.atomic.SurfaceEnum<String>):Int
		return 0;

	public static function parameter(value:PlainEnum<ocaml.SurfaceMarker>):Int
		return 0;
}

/** A secondary enum must retain native arguments even when its own package is ordinary. */
class EnumParameterStatics {
	public static function parameter(value:PlainEnum<ocaml.SurfaceMarker>):Int
		return 0;
}

/** A pure secondary enum proves that its module-qualified identity is recognized. */
class PureEnumStatics {
	public static function parameter(value:PlainEnum<String>):Int
		return 0;
}

/** Constructor signatures remain part of enum-value surface validation. */
enum NativeConstructors {
	Native(value:ocaml.SurfaceMarker);
	Atomic(value:haxe.atomic.SurfaceMarker);
}

/** Abstract values also expose their static method result types. */
abstract NativeAbstractStatics(Int) {
	public static function native():ocaml.SurfaceMarker
		return null;

	public static function atomic():haxe.atomic.SurfaceMarker
		return null;
}

/** A pure abstract class-value wrapper exposes an uncaptured owner only at the module read. */
abstract PureAbstractStatics(Int) {
	public static function value():Int
		return 0;
}
