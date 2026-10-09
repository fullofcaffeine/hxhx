# Calls inside generic methods

The same authored `Box<T>.forward()` body calls `echo(read())` for several class arguments. Each invocation must use its own concrete types without changing the shared source facts.

Run `npm run test:m14:cpp-generic-method-context` for ownership checks and generated C++ execution at O0/O2 with sanitizers and forced collection. The fixture covers null-preserving Int/Bool results, String and reference values, inherited bodies, concrete overrides, and a receiver captured by a closure. The native observer checks retained and released allocations.

Run `npm run test:m14:cpp-generic-storage-oracle` with the isolated upstream toolchain described in `../cpp_generic_storage_oracle/README.md` for Haxe 4.3.7/hxcpp 4.3.2 behavior. Successful execution is silent.

Generic field initializer applications, method-owned generic inference, and overall integration acceptance remain separate requirements.
