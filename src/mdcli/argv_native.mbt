///|
/// The index of the first user argument.
///
/// The program itself is the first entry, so the user arguments start at the
/// second one. Every target but js hands the arguments over that way.

///|
fn user_arg_start(_args : Array[String]) -> Int32 {
  1
}
