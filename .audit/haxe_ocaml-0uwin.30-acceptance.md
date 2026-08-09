1. Portable raw text that names a compiler-private `Hx...` helper fails with a clear source diagnostic.
2. Ordinary raw OCaml that does not forge the private namespace keeps its existing behavior.
3. Metal continues to reject raw injection under its stricter contract.
4. Structured interpolation cannot discard occurrence provenance or manufacture a private runtime use.
5. An inventory of real raw consumers records whether checked private-runtime placeholders are necessary; absence of a consumer means they remain deferred.
6. Positive, negative, interpolation, and clean-repeat fixtures pass without broadening README claims.
