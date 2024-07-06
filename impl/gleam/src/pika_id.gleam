import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/regex
import gleam/result
import gleam/string
import pika_id/snowflake.{type SnowflakeGen}

/// When creating a pika ID, you must specify the prefix to be prepended - the general rule of thumb should be to use a different prefix for each object type (e.g. user, team, post, etc).
/// Type prefixes should be lowercase, short, alphanumeric strings.
/// 
/// ## Examples
/// ```gleam
/// Prefix("user", "User ID", False) // Correct
/// Prefix("sk", "Secret key", True) // Correct
/// Prefix("conn_acc", "ID for connected accounts", False) 
/// // -> "One of the prefixes is invalid (prefix 'conn_acc' must be Alphanumeric)"
/// Prefix("pa$$word", "password id here", False) 
/// // -> "One of the prefixes is invalid (prefix 'pa$$word' must be Alphanumeric)"
/// ```
pub type Prefix {
  Prefix(name: String, description: String, secure: Bool)
}

/// Options for pika ID setup.
/// - WithEpoch: customize the epoch (millis) that IDs are derived from - by default, this is 1640995200000 (Jan 1 2022)
/// - WithNodeId: by default, Node IDs are calculated by finding the MAC address of the first public network interface device, then calculating the modulo against 1024
pub type PikaOption {
  WithEpoch(Int)
  WithNodeId(Int)
}

/// Deconstructed format of a Pika ID. 
/// Contains metas from ID's prefix and snowflake.
pub type PikaIdMetadata {
  PikaIdMetadata(
    id: String,
    prefix: String,
    description: String,
    secure: Bool,
    tail: String,
    decoded_tail: String,
    snowflake: Int,
    timestamp: Int,
    epoch: Int,
    node_id: Int,
    seq: Int,
  )
}

/// Pika generator type.
pub type Pika {
  Pika(
    gen: fn(String) -> Result(String, String),
    deconstruct: fn(String) -> Result(PikaIdMetadata, String),
  )
}

fn pika_setup(snowflake_gen: SnowflakeGen, prefixes: List(Prefix)) -> Pika {
  Pika(gen(snowflake_gen, prefixes, _), deconstruct(snowflake_gen, prefixes, _))
}

fn validate_settings(
  prefixes: List(Prefix),
  options: List(PikaOption),
) -> Result(#(SnowflakeGen, List(Prefix)), String) {
  use prefixes <- result.try(case prefixes {
    [] -> Error("You must specify at least one prefix.")
    prefixes -> Ok(prefixes)
  })

  use prefixes <- result.try({
    let assert Ok(reg) = regex.from_string("^[0-9a-z]+$")
    let match =
      prefixes
      |> list.find(fn(prefix) { !regex.check(reg, prefix.name) })

    case match {
      Ok(prefix) ->
        Error(
          "One of the prefixes is invalid (prefix '"
          <> prefix.name
          <> "' must be Alphanumeric)",
        )
      Error(_) -> Ok(prefixes)
    }
  })

  let snowflake_ctx = snowflake.create_snowflake()
  let snowflake_ctx =
    list.fold(options, snowflake_ctx, fn(snowflake_ctx, option) {
      case option {
        WithEpoch(num) -> snowflake_ctx |> snowflake.with_epoch(num)
        WithNodeId(num) -> snowflake_ctx |> snowflake.with_node_id(num)
      }
    })

  case snowflake_ctx |> snowflake.start_snowflake() {
    Error(err) -> Error(err |> string.inspect())
    Ok(snowflake_gen) -> Ok(#(snowflake_gen, prefixes))
  }
}

//  let assert Ok(pika) =
/// Initialize Pika with default Epoch and Node ID.
/// 
/// `Pika.gen(String) | pika_gen(Pika, String)` - generate ID
/// 
/// `Pika.deconstruct(String) | pika_deconstruct(Pika, String)` - deconstruct ID
/// 
/// To guarantee that developers use the correct pre-defined prefix types for the right object types, pika requires you to "register" them before they're used to prevent warnings from being thrown. 
/// 
/// This is also where you define if a prefix type should be cryptographically secure or not.
/// 
/// ## Examples
/// 
/// ```gleam
/// let assert Ok(pika) =
///   pika_init([
///     Prefix("user", "User ID", False),
///     Prefix("sk", "Secret key", True),
///   ]) 
/// // -> Pika
/// 
/// let assert Ok(pika) =
///   pika_init([
///     Prefix("u!ser", "User ID", False),
///   ]) 
/// // -> "Unable to initialize pika: "One of the prefixes is invalid (prefix 'u!ser' must be Alphanumeric)""
/// ```
pub fn pika_init(prefixes: List(Prefix)) -> Result(Pika, String) {
  case validate_settings(prefixes, []) {
    Error(err) ->
      Error("Unable to initialize pika: " <> err |> string.inspect())
    Ok(#(snowflake_gen, prefixes)) -> Ok(pika_setup(snowflake_gen, prefixes))
  }
}

/// Initialize Pika with custom Epoch and/or Node ID. 
/// 
/// To guarantee that developers use the correct pre-defined prefix types for the right object types, pika requires you to "register" them before they're used to prevent warnings from being thrown.
///
/// This is also where you define if a prefix type should be cryptographically secure or not.
/// 
/// If you dont need to specify options, use `pika_init` instead. (or pass [] as options).
/// 
/// ## Examples
/// 
/// #### Options
/// ```gleam
/// let assert Ok(pika) =
///   pika_custom_init(
///     [
///       Prefix("user", "User ID", False), 
///       Prefix("sk", "Secret key", True)
///     ],
///     [WithEpoch(1_000_000_000), WithNodeId(640)],
///   ) 
/// // -> Pika
/// ```
/// 
/// #### No options
/// ```gleam
/// let assert Ok(pika) = pika_custom_init([
///   Prefix("user", "User ID", False), 
///   Prefix("sk", "Secret key", True)
/// ], []) 
/// // -> Pika
/// ```
pub fn pika_custom_init(
  prefixes: List(Prefix),
  options: List(PikaOption),
) -> Result(Pika, String) {
  case validate_settings(prefixes, options) {
    Error(err) ->
      Error("Unable to initialize pika: " <> err |> string.inspect())
    Ok(#(snowflake_gen, prefixes)) -> Ok(pika_setup(snowflake_gen, prefixes))
  }
}

fn gen(
  generator: SnowflakeGen,
  prefixes: List(Prefix),
  head: String,
) -> Result(String, String) {
  case list.find(prefixes, fn(prefix) { prefix.name == head }) {
    Error(_) -> Error("Prefix is undefined")
    Ok(prefix) -> {
      let snowflake_id = snowflake.generate(generator)
      Ok(head <> "_" <> gen_tail(snowflake_id, prefix.secure))
    }
  }
}

fn gen_tail(snowflake_id: Int, secure: Bool) -> String {
  let snowflake_str = int.to_string(snowflake_id)
  case secure {
    False ->
      snowflake_str
      |> bit_array.from_string()
      |> bit_array.base64_encode(False)
    True -> {
      {
        "s_"
        <> crypto.strong_random_bytes(16)
        |> bit_array.base16_encode()
        |> string.lowercase()
        <> "_"
        <> snowflake_str
      }
      |> bit_array.from_string()
      |> bit_array.base64_encode(False)
    }
  }
}

/// Generate a pika ID. 
/// Tail will be generated based on prefix secure status.
/// 
/// Example of a normal decoded tail: `129688685040889861`
/// 
/// Example of a cryptographically secure decoded tail: `s_387d0775128c383fa8fbf5fd9863b84aba216bcc6872a877_129688685040889861`
/// 
/// ## Examples
/// 
/// ```gleam
/// pika.gen("user")
/// // -> Ok("user_MzMyNTAwNTIwMDUzMTk0NzUy")
/// ```
/// 
/// ```gleam
/// pika |> pika_gen("user")
/// // -> Ok("user_MzMyNTAwNTIwMDQwNjExODQw")
/// ```
/// 
/// ```gleam
/// pika |> pika_gen("core")
/// // -> Error("Prefix is undefined")
/// ```
pub fn pika_gen(pika: Pika, prefix: String) -> Result(String, String) {
  pika.gen(prefix)
}

fn deconstruct(
  generator: SnowflakeGen,
  prefixes: List(Prefix),
  id: String,
) -> Result(PikaIdMetadata, String) {
  use #(head, tail) <- result.try(case string.contains(id, "_") {
    False -> Error("Invalid Pika ID")
    True ->
      case string.split(id, "_") {
        [] -> Error("Invalid Pika ID")
        [head, ..tail] -> Ok(#(head, tail))
      }
  })

  use prefix <- result.try(case
    list.find(prefixes, fn(prefix) { prefix.name == head })
  {
    Error(_) -> Error("Prefix is undefined")
    Ok(prefix) -> Ok(prefix)
  })

  use decoded_tail <- result.try(case tail {
    [""] | [] -> Error("Invalid Pika ID")
    rest -> {
      use tail_bit_array <- result.try(case
        string.join(rest, "_")
        |> bit_array.base64_decode()
      {
        Error(_) -> Error("Invalid Pika ID")
        Ok(decoded_tail) -> Ok(decoded_tail)
      })

      case tail_bit_array |> bit_array.to_string() {
        Error(_) -> Error("Invalid Pika ID")
        Ok(decoded_tail) -> Ok(decoded_tail)
      }
    }
  })

  use snowflake_id <- result.try(case prefix.secure {
    False -> {
      case int.parse(decoded_tail) {
        Error(_) -> Error("Invalid Pika ID")
        Ok(num) -> Ok(num)
      }
    }
    True -> {
      use str_snowflake_id <- result.try(case
        string.split(decoded_tail, "_")
        |> list.last
      {
        Error(_) -> Error("Invalid Pika ID")
        Ok(str_num) -> Ok(str_num)
      })

      case int.parse(str_snowflake_id) {
        Error(_) -> Error("Invalid Pika ID")
        Ok(num) -> Ok(num)
      }
    }
  })

  let snowflake_meta =
    snowflake.deconstruct_snowflake_id(generator, snowflake_id)

  Ok(PikaIdMetadata(
    id,
    prefix.name,
    prefix.description,
    prefix.secure,
    string.join(tail, "_"),
    decoded_tail,
    snowflake_meta.id,
    snowflake_meta.timestamp,
    snowflake_meta.epoch,
    snowflake_meta.node_id,
    snowflake_meta.seq,
  ))
}

/// Deconstruct a pika ID into metadata (`PikaIDMetadata`)
/// ## Examples
/// ```gleam
/// pika.deconstruct("user_MzMyNTAwNTIwMDQwNjExODQw")
/// // -> 
/// Ok(
///   PikaIdMetadata(
///     "user_MzMyNTAwNTIwMDQwNjExODQw",
///     "user",
///     "User ID",
///     False,
///     "MzMyNTAwNTIwMDQwNjExODQw",
///     "332500520040611840",
///     332500520040611840,
///     1720269501538,
///     1640995200000,
///     628,
///     0
///   )
/// )
/// ```
pub fn pika_deconstruct(
  pika: Pika,
  id: String,
) -> Result(PikaIdMetadata, String) {
  pika.deconstruct(id)
}
