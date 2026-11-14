///|
/// The index of the first user argument.
///
/// The js backend runs under node, and node's own arguments come first: the
/// node binary, and then the script that was run. The user arguments start
/// after those two, so the offset is two rather than one.

///|
fn user_arg_start(_args : Array[String]) -> Int32 {
  2
}
