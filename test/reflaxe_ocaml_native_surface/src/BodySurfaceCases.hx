/** Repeated static calls provide distinct expressions with the same class surface. */
class BodySurfaceCases {
	public static function enumValue():OwnedSurfaceCases.PlainEnum<ocaml.SurfaceMarker> {
		final ordinary:OwnedSurfaceCases.PlainEnum<String> = OwnedSurfaceCases.PlainEnum.Value("value");
		final native:OwnedSurfaceCases.PlainEnum<ocaml.SurfaceMarker> = OwnedSurfaceCases.PlainEnum.Value(null);
		return ordinary == null ? native : native;
	}

	public static function nativeEnumValue():ocaml.SurfaceEnum<String>
		return ocaml.SurfaceEnum.Value("value");

	public static function first():Int
		return SurfaceOwner.ping() + SurfaceOwner.ping() + SurfaceOwner.ping();

	public static function second():Int
		return SurfaceOwner.ping() + SurfaceOwner.ping();

	public static function converted():Class<SurfaceOwner> {
		final owner:Class<SurfaceOwner> = SurfaceOwner;
		final nested = () -> SurfaceOwner;
		return nested() == owner ? SurfaceOwner : owner;
	}
}

/** Private members and inside/outside references must agree on the class-value surface. */
class SurfaceOwner {
	public static function ping():Int
		return 1;

	static function nativeMarker():ocaml.SurfaceMarker
		return null;

	public static function inside():Class<SurfaceOwner> {
		final owner:Class<SurfaceOwner> = SurfaceOwner;
		return ping() > 0 ? SurfaceOwner : owner;
	}
}
