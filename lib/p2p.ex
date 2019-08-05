defmodule P2P do
  require Logger
  alias Ellipticoind.Models.{Block, Transaction}
  alias Ellipticoind.Miner
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_init_arg) do
    transport().subscribe(self())
    {:ok, %{}}
  end

  def broadcast(message),
    do: apply(transport(), :broadcast, [message])

  def subscribe(),
    do: apply(transport(), :subscribe)

  def receive(message) do
    case message.__struct__ do
      Block ->
        send(Process.whereis(Ellipticoind.Miner), :cancel)
        Block.apply(message)
        Miner.mine_next_block()

      Transaction ->
        Transaction.post(message)
    end
  end

  def handle_info(:cancel, state) do
    {:noreply, state}
  end

  def handle_info({:p2p, message}, state) do
    __MODULE__.receive(message)
    {:noreply, state}
  end

  defp transport(), do: Application.fetch_env!(:ellipticoind, :p2p_transport)
end
