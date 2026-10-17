/** Shared recursive edges expose repeated validation of one named body. */
typedef RecursiveRecord = {
	final a:RecursiveRecord;
	final b:RecursiveRecord;
	final c:RecursiveRecord;
	final d:RecursiveRecord;
	final e:RecursiveRecord;
	final f:RecursiveRecord;
};

typedef RecursiveNative = {
	final next:RecursiveNative;
	final native:ocaml.SurfaceMarker;
};

typedef GenericRecord<T> = {final value:T;};
typedef EffectBody = Int;

/** Enum parameters and abstract bodies retain their separate traversal rules. */
enum ParameterEnum<T> {
	Value(value:T);
}

abstract SurfaceAbstract(ocaml.SurfaceMarker) {}
