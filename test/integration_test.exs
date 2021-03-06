defmodule Integration.MiningTest do
  import Test.Utils
  use NamedAccounts
  use ExUnit.Case, async: false
  alias Ellipticoind.Storage
  alias Ellipticoind.Models.{Block, Transaction}
  alias Ellipticoind.Miner
  use OK.Pipe

  setup do
    Redis.reset()
    checkout_repo()
    SystemContracts.deploy()

    on_exit(fn ->
      Redis.reset()
    end)

    :ok
  end

  test "mining a block" do
    P2P.Transport.Test.subscribe_to_test_broadcasts(self())
    base_reward = 640000
    mint_gas_cost = 80163
    transfer_gas_cost = 129378
    alices_initial_balance = 1000000
    bobs_initial_balance = 1000000

    set_balances(%{
      @alice => alices_initial_balance,
      @bob => bobs_initial_balance,
    })

    post(
      %{
        nonce: 2,
        gas_limit: 100000000,
        function: :transfer,
        arguments: [@bob, 50000],
      },
      @alices_private_key
    )

    Miner.mine_next_block()

    broadcasted_transaction =
      receive do
        {:p2p, nil, %Transaction{} = transaction} -> transaction
      end

    assert !is_nil(broadcasted_transaction)

    broadcasted_block =
      receive do
        {:p2p, nil, %Block{} = block} -> block
      end

    assert !is_nil(broadcasted_block)

    new_block = poll_for_block(0)
    assert Block.Validations.valid_proof_of_work_value?(broadcasted_block)
    assert new_block.number == 0

    assert new_block.transactions
           |> Enum.map(fn transaction ->
             Map.take(
               transaction,
               [
                 :arguments,
                 :contract_address,
                 :function,
                 :return_code,
                 :return_value,
                 :sender
               ]
             )
           end) ==
             [
               %{
                 arguments: [],
                 contract_address: <<0::256>> <> "BaseToken",
                 function: :mint,
                 return_code: 0,
                 return_value: nil,
                 sender: Configuration.public_key()
               },
               %{
                 arguments: [@bob, 50000],
                 contract_address: <<0::256>> <> "BaseToken",
                 function: :transfer,
                 return_code: 0,
                 return_value: nil,
                 sender: @alice
               }
             ]

    assert is_integer(new_block.proof_of_work_value)
    assert byte_size(new_block.hash) == 32
    assert byte_size(new_block.memory_changeset_hash) == 32
    assert byte_size(new_block.storage_changeset_hash) == 32
    refute new_block.hash == <<0::256>>
    refute Map.has_key?(new_block, :parent_hash)

    assert get_balance(@alice) == alices_initial_balance - transfer_gas_cost - 50000
    assert get_balance(Configuration.public_key()) == base_reward + transfer_gas_cost + mint_gas_cost
  end

  test "a new block is mined on the parent chain and another ellipticoind is the winner" do
    set_balances(%{
      @alice => 100,
      @bob => 100
    })

    transaction =
      %Transaction{
        block_hash: nil,
        nonce: 1,
        gas_limit: 100000000,
        contract_address: <<0::256>> <> "BaseToken",
        function: :transfer,
        return_code: 0,
        return_value: nil,
        arguments: [@bob, 50]
      }
      |> Transaction.sign(@alices_private_key)

    block = %Block{
      number: 0,
      hash: <<0::256>>,
      proof_of_work_value: 2,
      memory_changeset_hash:
        Base.decode16!("6CAD99E2AC8E9D4BACC64E8FC9DE852D7C5EA3E602882281CFDFE1C562967A79"),
      storage_changeset_hash:
        Base.decode16!("6CAD99E2AC8E9D4BACC64E8FC9DE852D7C5EA3E602882281CFDFE1C562967A79"),
      transactions: [transaction],
      winner: @bob
    }

    Block.apply(block)

    assert get_balance(@alice) == 50
    assert get_balance(@bob) == 150
  end

  test "creating a contract" do
    post(
      %{
        contract_address: <<0::256>> <> "system",
        nonce: 0,
        gas_limit: 100000000,
        function: :create_contract,
        arguments: [:test_contract, test_contract_code(:constructor), [<<1, 2, 3>>]]
      },
      @alices_private_key
    )

    Miner.mine_next_block()
    poll_for_block(0)
    :timer.sleep(100)

    key = Storage.to_key(@alice, :test_contract, "value")
    {:ok, %{body: body}} = http_get("/memory/#{Base.url_encode64(key)}")
    assert body == <<1, 2, 3>>
  end

  test "transaction runs out of gas" do
    P2P.Transport.Test.subscribe_to_test_broadcasts(self())
    alices_initial_balance = 100000
    bobs_initial_balance = 100000
    gas_cost = 31490

    set_balances(%{
      @alice => alices_initial_balance,
      @bob => bobs_initial_balance,
    })

    post(
      %{
        nonce: 2,
        gas_limit: gas_cost - 1,
        function: :transfer,
        arguments: [@bob, 50000],
      },
      @alices_private_key
    )

    Miner.mine_next_block()

    assert get_balance(@alice) == alices_initial_balance - (gas_cost - 1)
    assert get_balance(@bob) == bobs_initial_balance
  end
end
