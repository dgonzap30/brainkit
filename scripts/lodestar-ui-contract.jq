def pattern_name:
  if ._kind == "pattern_named" then
    .name.base_name.name
  elif ._kind == "pattern_typed" then
    .sub_pattern | pattern_name
  else
    null
  end;

def container_members($container):
  .items[]?
  | select(
      ._kind == "enum_decl"
      and .name.base_name.name == $container
    )
  | .members[]?;

def has_public_static_let($container; $name):
  any(
    container_members($container);
    ._kind == "var_decl"
    and .name.base_name.name == $name
    and .let == true
    and .static == true
    and any(
      .attrs[]?;
      ._kind == "access_control_attr"
      and .access_level == "public"
    )
  );

def binding_initializers($container; $name):
  container_members($container)
  | select(._kind == "pattern_binding_decl")
  | .pattern_entries[]?
  | select((.pattern | pattern_name) == $name)
  | .original_init;

def has_color_initializer($container; $name; $value):
  any(
    binding_initializers($container; $name);
    ._kind == "call_expr"
    and .fn._kind == "unresolved_decl_ref_expr"
    and .fn.name == "Color"
    and .args.labels == "lodestarHex:"
    and (.args.args | length) == 1
    and .args.args[0].label == "lodestarHex"
    and .args.args[0].expr._kind == "integer_literal_expr"
    and .args.args[0].expr.value == $value
  );

def has_integer_initializer($container; $name; $value):
  any(
    binding_initializers($container; $name);
    ._kind == "integer_literal_expr"
    and .value == $value
  );

if $contract == "color" then
  has_public_static_let($container; $name)
  and has_color_initializer($container; $name; $value)
elif $contract == "integer" then
  has_public_static_let($container; $name)
  and has_integer_initializer($container; $name; $value)
else
  error("unknown LodestarUI contract kind: \($contract)")
end
