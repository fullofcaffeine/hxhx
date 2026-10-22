# Runtime meta-type categories

Dynamic matches non-null values. Class matches class descriptors, while Enum
matches enum descriptors. A descriptor is the value that names a type at runtime;
it is distinct from an instance created from that type.

The fixture also checks the Neko roles of primitive descriptors, ordinary enum
instance membership, type-operand syntax, and explicit untyped replacement and
restoration of the three meta bindings. The untyped operations are intentional
source-language compatibility inputs. They do not authorize untyped compiler code.

Run `haxe test/m14_neko_runtime_meta_test.hxml`. The observer loads real standard
providers, checks upstream Neko against the authored output, and compares both
the single-file and split native layouts. A failure remains a failing contract.
