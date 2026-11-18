import Shapes.Shape;
import Shapes.Marker;

class Main {
	static function main() {
		// The enums travel as Dynamic, so construction goes through the runtime type registry
		// instead of being lowered at compile time. Both enums declare a constructor named Same.
		final shapeEnum:Dynamic = Shape;
		final markerEnum:Dynamic = Marker;
		final shape:Dynamic = Type.createEnum(shapeEnum, "Same", [4, 5]);
		final marker:Dynamic = Type.createEnum(markerEnum, "Same", [9]);
		// The registry must build each value with its own enum's constructor: Shape.Same takes two
		// arguments and Marker.Same one. Printing the values is haxe_ocaml-b07mo.
		Sys.println("shape arguments=" + Type.enumParameters(shape).length);
		Sys.println("marker arguments=" + Type.enumParameters(marker).length);
	}
}
