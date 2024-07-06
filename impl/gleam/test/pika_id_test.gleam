import gleam/int
import gleam/string
import gleeunit
import gleeunit/should
import pika_id.{
  Prefix, WithEpoch, WithNodeId, pika_custom_init, pika_gen, pika_init,
}

pub fn main() {
  gleeunit.main()
}

pub fn pika_init_test() {
  pika_init([Prefix("user", "User ID", False)])
  |> should.be_ok()

  pika_custom_init([Prefix("user", "User ID", False)], [])
  |> should.be_ok()

  pika_custom_init([Prefix("user", "User ID", False)], [
    WithEpoch(1_000_000_000),
    WithNodeId(600),
  ])
  |> should.be_ok()
}

pub fn pika_init_empty_test() {
  pika_init([])
  |> should.be_error()
  |> should.equal(
    "Unable to initialize pika: \"You must specify at least one prefix.\"",
  )

  pika_custom_init([], [])
  |> should.be_error()
  |> should.equal(
    "Unable to initialize pika: \"You must specify at least one prefix.\"",
  )
}

pub fn pika_init_invalid_names_test() {
  pika_init([
    Prefix("u!ser", "User ID", False),
    Prefix("s/k", "Secret key", True),
  ])
  |> should.be_error()
  |> should.equal(
    "Unable to initialize pika: \"One of the prefixes is invalid (prefix 'u!ser' must be Alphanumeric)\"",
  )

  pika_init([
    Prefix("user", "User ID", False),
    Prefix("s_k", "Secret key", True),
  ])
  |> should.be_error()
  |> should.equal(
    "Unable to initialize pika: \"One of the prefixes is invalid (prefix 's_k' must be Alphanumeric)\"",
  )

  pika_init([Prefix("user", "User ID", False), Prefix("sk", "Secret key", True)])
  |> should.be_ok()
}

pub fn pika_gen_test() {
  let assert Ok(pika) =
    pika_init([
      Prefix("user", "User ID", False),
      Prefix("sk", "Secret key", True),
    ])
  pika.gen("user")
  |> should.be_ok
  |> string.starts_with("user_")
  |> should.equal(True)
  pika
  |> pika_gen("user")
  |> should.be_ok
  |> string.starts_with("user_")
  |> should.equal(True)
  pika.gen("sk")
  |> should.be_ok
  |> string.starts_with("sk_")
  |> should.equal(True)
  pika
  |> pika_gen("sk")
  |> should.be_ok
  |> string.starts_with("sk_")
  |> should.equal(True)

  pika.gen("task")
  |> should.be_error
  |> should.equal("Prefix is undefined")
  pika
  |> pika_gen("task")
  |> should.be_error
  |> should.equal("Prefix is undefined")
}

pub fn pika_deconstruct_test() {
  let assert Ok(pika) =
    pika_custom_init(
      [Prefix("user", "User ID", False), Prefix("sk", "Secret key", True)],
      [WithEpoch(1_000_000_000), WithNodeId(1000)],
    )

  let assert Ok(id) = pika.gen("user")
  let pika_id_meta = id |> pika.deconstruct() |> should.be_ok()
  should.equal(pika_id_meta.id, id)
  should.equal(pika_id_meta.prefix, "user")
  should.equal(pika_id_meta.description, "User ID")
  should.equal(pika_id_meta.secure, False)
  should.equal(
    pika_id_meta.decoded_tail,
    pika_id_meta.snowflake |> int.to_string(),
  )
  should.equal(pika_id_meta.epoch, 1_000_000_000)
  should.equal(pika_id_meta.node_id, 1000)

  let assert Ok(id) = pika.gen("sk")
  let pika_id_meta = id |> pika.deconstruct() |> should.be_ok()
  should.equal(pika_id_meta.secure, True)
  should.not_equal(
    pika_id_meta.decoded_tail,
    pika_id_meta.snowflake |> int.to_string(),
  )
}

pub fn pika_deconstruct_invalid_test() {
  let assert Ok(pika) =
    pika_custom_init(
      [Prefix("user", "User ID", False), Prefix("sk", "Secret key", True)],
      [WithEpoch(1_000_000_000), WithNodeId(1000)],
    )

  pika.deconstruct("userNzIxMTEyMTU4MzQ1OTMwMzQyNQ")
  |> should.be_error
  |> should.equal("Invalid Pika ID")

  pika.deconstruct("us_er")
  |> should.be_error
  |> should.equal("Prefix is undefined")

  pika.deconstruct("user_")
  |> should.be_error
  |> should.equal("Invalid Pika ID")

  // bm90c25vd2ZsYWtlaWQ from Base64 - "notsnowflakeid"
  pika.deconstruct("user_bm90c25vd2ZsYWtlaWQ")
  |> should.be_error
  |> should.equal("Invalid Pika ID")
}
