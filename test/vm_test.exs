defmodule VMTest do
  @db Db.Redis
  @sender "509c3480af8118842da87369eb616eb7b158724927c212b676c41ce6430d334a"
          |> Base.decode16!(case: :lower)

  use ExUnit.Case

  setup_all do
    Forger.enable_auto_forging()

    on_exit(fn ->
      @db.reset()
      Forger.disable_auto_forging()
    end)
  end

  test "TransactionProccessor proccesses transactions" do
    counter_code = read_test_wasm("counter.wasm")

    TransactionPool.add(%{
      code: counter_code,
      env: %{
        sender: @sender,
        address: @sender,
        contract_name: :Counter
      },
      method: :increment_by,
      params: [
        1
      ]
    })

    Forger.wait_for_block(self())

    TransactionPool.add(%{
      code: counter_code,
      env: %{
        sender: @sender,
        address: @sender,
        contract_name: :Counter
      },
      method: :increment_by,
      params: [
        1
      ]
    })
    Forger.wait_for_block(self())

    assert VM.get(%{
      code: counter_code,
      env: %{
        sender: @sender,
        address: @sender,
        contract_name: :Counter
      },
      method: :get_count,
      params: []
    }) == {:ok, Cbor.encode(2)}
  end

  def read_test_wasm(file_name) do
    Path.join([test_support_dir(), "wasm", file_name])
    |> File.read!()
  end

  def test_support_dir() do
    Path.join([File.cwd!(), "test", "support"])
  end

  def deploy(contract_name, contract_code, sender, nonce) do
    TransactionPool.add(%{
      sender: sender,
      nonce: nonce,
      address: Constants.system_address(),
      contract_name: :UserContracts,
      method: :deploy,
      params: [
        contract_name,
        contract_code
      ]
    })

    TransactionPool.subscribe(sender, nonce, self())

    receive do
      {:transaction, :done, <<return_code::size(32), result::binary>>} -> {return_code, result}
      _ -> raise "Error deploying #{contract_name}"
    end
  end
end
