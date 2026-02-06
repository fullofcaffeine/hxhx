# 1 "out.ml"
let () =
  HxTypeRegistry.init ();
  ignore (Hxhxmacrohost_Main.main ())
