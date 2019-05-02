use redis::Commands;
extern crate redis;
use db::DB;
use serialize::hex::ToHex;

fn full_key(block_number: u64, key: &[u8]) -> Vec<u8> {
    [
        unsafe { std::intrinsics::transmute::<u64, [u8; 8]>(block_number) }.to_vec(),
        key.to_vec(),
    ]
    .concat()
}
fn memory_key(key: &[u8]) -> Vec<u8> {
    ["memory:".as_bytes().to_vec(), key.to_vec()].concat()
}
fn hash_key(block_number: u64, key: &[u8]) -> Vec<u8> {
    [
        unsafe { std::intrinsics::transmute::<u64, [u8; 8]>(block_number) }.to_vec(),
        key.to_vec(),
    ]
    .concat()
}

fn get_memory_by_hash_key(conn: &redis::Connection, hash_key: &[u8]) -> Vec<u8> {
    let value: Vec<u8> = conn.hget("memory_hash", hash_key.to_vec()).unwrap();
    value
}

impl DB for redis::Connection {
    fn write(&self, block_number: u64, key: &[u8], value: &[u8]) {
        let _: () = redis::pipe()
            .atomic()
            .cmd("ZREM")
            .arg(memory_key(key))
            .arg(hash_key(block_number, key))
            .ignore()
            .cmd("ZADD")
            .arg(memory_key(key))
            .arg(block_number)
            .arg(hash_key(block_number, key))
            .ignore()
            .cmd("HSET")
            .arg("memory_hash")
            .arg(hash_key(block_number, key))
            .arg(value)
            .ignore()
            .query(self)
            .unwrap();
    }

    fn read(&self, block_number: u64, key: &[u8]) -> Vec<u8> {
        let latest_hash_keys = self
            .zrevrangebyscore_limit::<_, _, _, Vec<Vec<u8>>>(memory_key(key), "+inf", "-inf", 0, 1)
            .unwrap();

        match latest_hash_keys.as_slice() {
            [hash_key] => get_memory_by_hash_key(self, hash_key),
            _ => vec![],
        }
    }

    fn get_block_data(&self) -> Vec<u8> {
        let elements: Vec<Vec<u8>> = self.lrange("current_block", 0, -1).unwrap();
        elements.concat()
    }
}
