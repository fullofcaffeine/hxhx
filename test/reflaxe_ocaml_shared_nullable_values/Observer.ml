(* Independent consumer of the existing nullable-integer ABI.
   Obj.repr boxes known OCaml integers here; no unchecked value is unboxed. *)
let () =
  assert (Main.direct true = 3);
  assert (Main.direct false = 9);
  assert (Main.recover HxRuntime.hx_null = 9);
  assert (HxRuntime.is_null (Main.select false 0));
  assert (not (HxRuntime.is_null (Main.select true 0)));
  assert (HxRuntime.is_null (Main.retained HxRuntime.hx_null));
  List.iter (fun value ->
    assert (Main.recover (Obj.repr value) = value);
    assert (Main.recover (Main.select true value) = value);
    assert (Main.recover (Main.retained (Main.select true value)) = value);
    assert (Main.recover (Main.retained (Main.select false value)) = 9)
  ) [0; -7; 41; 2147483647; -2147483648]
