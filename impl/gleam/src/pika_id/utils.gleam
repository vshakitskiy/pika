import gleam/erlang
import gleam/int
import gleam/list
import gleam/regex
import gleam/string

/// Get timestamp in millisec.
pub fn get_timestamp() -> Int {
  erlang.Millisecond |> erlang.system_time()
}

@external(erlang, "inet", "getifaddrs")
pub fn getifaddrs() -> Result(List(Interface), String)

pub type Interface =
  #(List(Int), List(Address))

pub type Address {
  Hwaddr(List(Int))
  Flags
  Addr
  Netmask
  Broadaddr
}

/// Get the mac address of the first available public interface on the device.
pub fn get_mac_address() -> String {
  let assert Ok(interfaces) = getifaddrs()

  let unfiltered_hwaddrs =
    interfaces
    |> list.map(fn(interface) {
      let #(_, addresses_list) = interface
      addresses_list
    })
    |> list.map(fn(addresses) {
      list.filter_map(addresses, fn(address) {
        case address {
          Hwaddr(_) -> Ok(address)
          _ -> Error(Nil)
        }
      })
    })
    |> list.flatten()
  let assert Hwaddr(mac_list) = filter_hwaddrs(unfiltered_hwaddrs)

  mac_list
  |> list.map(fn(num) { num |> int.to_base16 |> string.pad_left(2, "0") })
  |> string.join(":")
}

fn filter_hwaddrs(addresses: List(Address)) -> Address {
  let assert Ok(hwaddr) =
    list.find(addresses, fn(address) {
      case address {
        Hwaddr([0, 0, 0, 0, 0, 0]) -> False
        Hwaddr([_, _, _, _, _, _]) -> True
        _ -> False
      }
    })
  hwaddr
}

/// Compute the Node ID for the Snowflake gen.
pub fn compute_node_id() {
  let assert Ok(id) =
    get_mac_address() |> string.replace(":", "") |> int.base_parse(16)
  id % 1024
}

pub fn is_alphanumeric_list(str_list: List(String)) {
  let assert Ok(reg) = regex.from_string("^[0-9a-z]+$")
  str_list
  |> list.find(fn(str) { !regex.check(reg, str) })
}
