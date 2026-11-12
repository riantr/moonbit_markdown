///|
/// The module's entry point: the command line tool lives in src/mdcli, and
/// this package is only the executable that runs it.
///|
async fn main {
  @mdcli.run(@env.args())
}