import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleam/result
import gleam/string
import pika_id/internal.{compute_node_id, get_timestamp}

/// The default epoch for the generator.
pub const default_epoch: Int = 1_640_995_200_000

/// The max number of seq that can be generated in a millisec.
pub const max_seq: Int = 4095

/// The messages that the generator can receive.
pub opaque type Message(snowflake) {
  Generate(reply_with: process.Subject(SnowflakeId))
  Get(reply_with: process.Subject(Snowflake))
  Shutdown
}

/// The Snowflake generator content.
/// Holds the state of the gen and is used to generate IDs.
pub opaque type Snowflake {
  Snowflake(node_id: Int, epoch: Int, seq: Int, last_seq_exhaustion: Int)
}

/// Type alias for the Snowflake ID
pub type SnowflakeId =
  Int

/// The deconstructed Snowflake ID content.
pub type DeconstructedSnowflake {
  DeconstructedSnowflake(
    id: Int,
    timestamp: Int,
    epoch: Int,
    node_id: Int,
    seq: Int,
  )
}

/// Type of the generator.
/// It holds the actor subject that is used to handle the generator state.
/// 
/// # Example
/// ```gleam
/// import pika_id/snowflake.{create_snowflake, start_snowflake}
///
/// pub fn main() {
///   let assert Ok(snowflake_gen) =
///     create_snowflake()
///     |> start_snowflake()
/// 
///   let id = snowflake_gen |> snowflake.generate
/// }
/// ```
pub opaque type SnowflakeGen {
  SnowflakeGen(actor: process.Subject(Message(Snowflake)))
}

/// Creates a new Snowflake generator with default settings.
pub fn create_snowflake() -> Snowflake {
  Snowflake(compute_node_id(), default_epoch, 0, 0)
}

/// Sets the epoch for the generator.
pub fn with_epoch(snowflake: Snowflake, epoch: Int) -> Snowflake {
  Snowflake(..snowflake, epoch: epoch)
}

/// Sets the Node ID for the generator.
pub fn with_node_id(snowflake: Snowflake, node_id: Int) -> Snowflake {
  Snowflake(..snowflake, node_id: node_id)
}

/// Starts the generator.
pub fn start_snowflake(snowflake: Snowflake) {
  case snowflake.epoch > get_timestamp() {
    True -> Error("epoch must be in the past")
    False -> {
      let snowflake =
        Snowflake(..snowflake, last_seq_exhaustion: get_timestamp())

      snowflake
      |> actor.start(handle_message)
      |> result.map_error(fn(err) {
        "could not start actor: " <> err |> string.inspect()
      })
      |> result.map(SnowflakeGen)
    }
  }
}

fn handle_message(
  message: Message(e),
  stack: Snowflake,
) -> actor.Next(Message(e), Snowflake) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    Generate(client) -> {
      let snowflake = stack |> update_snowflake
      let id = snowflake |> generate_id
      process.send(client, id)
      actor.continue(snowflake)
    }
    Get(client) -> {
      process.send(client, stack)
      actor.continue(stack)
    }
  }
}

/// Generates a new Snowflake ID.
///
/// # Examples
/// ```gleam
/// import pika_id/snowflake.{
///   create_snowflake, start_snowflake, with_epoch, with_node_id,
/// }
/// 
/// pub fn main() {
///   let epoch = 1_650_153_600_000
///   let node_id = 628
/// 
///   let assert Ok(snowflake_gen) =
///     create_snowflake()
///     |> with_epoch(epoch)
///     |> with_node_id(node_id)
///     |> start_snowflake()
/// 
///   let id = snowflake_gen |> snowflake.generate
/// }
/// ```
pub fn generate(snowflake_gen: SnowflakeGen) -> SnowflakeId {
  actor.call(snowflake_gen.actor, Generate, 10)
}

fn generate_id(snowflake: Snowflake) -> SnowflakeId {
  // seq >= max_seq??

  let since_epoch =
    int.bitwise_shift_left(snowflake.last_seq_exhaustion - snowflake.epoch, 22)
  let node_id = int.bitwise_shift_left(snowflake.node_id, 12)

  int.bitwise_or(since_epoch, node_id) |> int.bitwise_or(snowflake.seq)
}

fn update_snowflake(snowflake: Snowflake) -> Snowflake {
  let timestamp = get_timestamp()
  case snowflake {
    Snowflake(last_seq_exhaustion: lse, seq: s, ..)
      if lse == timestamp && s < max_seq
    -> Snowflake(..snowflake, seq: s + 1)
    Snowflake(last_seq_exhaustion: lse, ..) if lse == timestamp ->
      snowflake |> update_snowflake
    _ -> Snowflake(..snowflake, seq: 0, last_seq_exhaustion: timestamp)
  }
}

fn get_snowflake(snowflake_gen: SnowflakeGen) -> Snowflake {
  actor.call(snowflake_gen.actor, Get, 10)
}

/// Deconstruct the Snowflake ID. Recuires a Snowflake Gen for finding epoch.
/// # Examples
/// ```gleam
/// let id = snowflake_gen |> snowflake.generate
/// snowflake.deconstruct_snowflake_id(snowflake_gen, id)
/// |> io.debug 
/// // DeconstructedSnowflake(
/// //   id, 
/// //   timestamp, 
/// //   epoch, 
/// //   node_id, 
/// //   seq
/// // )
/// ```
pub fn deconstruct_snowflake_id(
  snowflake_gen: SnowflakeGen,
  snowflake_id: SnowflakeId,
) -> DeconstructedSnowflake {
  let epoch = get_snowflake(snowflake_gen).epoch
  let timestamp = int.bitwise_shift_right(snowflake_id, 22) + epoch
  let node_id =
    int.bitwise_shift_right(snowflake_id, 12) |> int.bitwise_and(0b11_1111_1111)
  let seq = int.bitwise_and(snowflake_id, 0b1111_1111_1111)
  DeconstructedSnowflake(snowflake_id, timestamp, epoch, node_id, seq)
}
