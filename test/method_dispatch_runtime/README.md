# Checked native method entries

Run `haxe test/reflaxe_ocaml_method_dispatch_runtime_test.hxml` from the repository root.

The observer compiles the manifest-verified production runtime. It checks receiver state across different concrete record layouts, closure lifetime, and mixed anonymous/class consumers. It also checks concurrent registration, signature mismatches, conflicting layouts, failed registration, absent methods, and invalid receiver representations.

The native registry treats contract keys and revisions as opaque identifiers. Haxe must select the methods, prove their signatures, and generate the typed binders. These tests cover storage and lookup only. The authored Haxe fixture `anonymous_structural_interface` must separately prove compiler generation, identity, inheritance, and initialization behavior.
