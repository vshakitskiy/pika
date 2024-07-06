# pika

> Gleam implementation of Pika

Combine Stripe IDs with Snowflakes you get Pika! The last ID system you'll ever need!
Combining pragmatism with functionality

[![Version](https://img.shields.io/hexpm/v/pika_id)](https://hex.pm/packages/pika_id)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pika_id)
![Erlang-compatible](https://img.shields.io/badge/target-erlang-b83998)

## Features

- Written using only official Gleam libs.
- Different client implementations.

## Installation

Add `pika_id` to your Gleam project.

```sh
gleam add pika_id
```

Further documentation can be found at: https://hexdocs.pm/pika_id

## Basic Usage

```gleam
import pika_id.{Prefix}

pub fn main() {
  let assert Ok(pika) =
    pika_id.pika_init([
      Prefix(name: "user", description: "User IDs", secure: False),
      Prefix(name: "post", description: "Post IDs", secure: False),
      Prefix(name: "sk", description: "Secret Keys", secure: True),
    ])
  // -> Pika

  pika.gen("user")
  // -> Ok("user_MzMyNTUyMDY3Mzc0MDcxODA4")

  pika.gen("sk")
  // -> Ok("sk_c19iOTJlMDVmZDU2NTY3YzA1MTBmOTBkOTZjOTdmNzgyNl8zMzI1NTIwNjczOTA4NDkwMjQ")

  pika
  |> pika_id.pika_deconstruct(
    "sk_c185NTBlNTI0YTc0NjZkNjc2NmVlMDdhMDBiYjliZTMyYV8zMzI1NTIzMDU0MzQzNzgyNDA",
  )
  // ->
  //   Ok(
  //     PikaIdMetadata(
  //       "sk_c185NTBlNTI0YTc0NjZkNjc2NmVlMDdhMDBiYjliZTMyYV8zMzI1NTIzMDU0MzQzNzgyNDA",
  //       "sk",
  //       "Secret Keys",
  //       True,
  //       "c185NTBlNTI0YTc0NjZkNjc2NmVlMDdhMDBiYjliZTMyYV8zMzI1NTIzMDU0MzQzNzgyNDA",
  //       "s_950e524a7466d6766ee07a00bb9be32a_332552305434378240",
  //       332552305434378240,
  //       1720281848138,
  //       1640995200000,
  //       628,
  //       0
  //     )
  //   )
}
```

## Node IDs

By default, Node IDs are calculated by finding the MAC address of the first public network interface device, then calculating the modulo against 1024.

This works well for smaller systems, but if you have a lot of nodes generating Snowflakes, then collision is possible. In this case, you should create an internal singleton service which keeps a rolling count of the assigned node IDs - from 1 to 1023. Then, services that generate Pikas should call this service to get assigned a node ID.

You can then pass in the node ID when initializing Pika like this:

```gleam
  let assert Ok(pika) =
    pika_custom_init(
      [
        Prefix(name: "user", description: "User IDs", secure: False),
        Prefix(name: "post", description: "Post IDs", secure: False),
        Prefix(name: "sk", description: "Secret Keys", secure: True),
      ],
      [WithNodeId(628)],
      // You can also specify Epoch: [WithNodeId(628), WithEpoch(1_000_000_000)]
    )
```
