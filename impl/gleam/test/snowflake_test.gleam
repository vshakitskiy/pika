import gleeunit/should
import pika_id/snowflake

pub fn gen_creation_test() {
  snowflake.create_snowflake()
  |> snowflake.start_snowflake()
  |> should.be_ok()
}

pub fn gen_creation_with_custom_epoch_test() {
  snowflake.create_snowflake()
  |> snowflake.with_epoch(1_650_153_600_000)
  |> snowflake.start_snowflake()
  |> should.be_ok()
}

pub fn id_generation_test() {
  let assert Ok(snowflake_gen) =
    snowflake.create_snowflake()
    |> snowflake.with_epoch(1_650_153_600_000)
    |> snowflake.start_snowflake()

  snowflake.generate(snowflake_gen)
}

pub fn id_deconstruction_test() {
  let epoch = 1_650_153_600_000
  let node_id = 628

  let assert Ok(snowflake_gen) =
    snowflake.create_snowflake()
    |> snowflake.with_epoch(epoch)
    |> snowflake.with_node_id(node_id)
    |> snowflake.start_snowflake()

  let snowflake_id = snowflake.generate(snowflake_gen)
  let snowflake_dec =
    snowflake.deconstruct_snowflake_id(snowflake_gen, snowflake_id)

  snowflake_dec.epoch |> should.equal(epoch)
  snowflake_dec.node_id |> should.equal(node_id)
  snowflake_dec.id |> should.equal(snowflake_id)
}
