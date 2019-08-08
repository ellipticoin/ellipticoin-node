defmodule Ellipticoind.Models.Block do
  use Ecto.Schema
  use CborEncodable
  require Logger
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias Ellipticoind.{Repo, Miner}
  alias Ellipticoind.Models.Transaction
  alias Ellipticoind.Models.Block.Validations
  alias Ellipticoind.TransactionProcessor

  @primary_key false
  schema "blocks" do
    field(:hash, :binary, default: <<0::256>>, primary_key: true)

    belongs_to(:parent, __MODULE__,
      source: :parent_hash,
      foreign_key: :hash,
      type: :binary,
      define_field: false
    )

    has_many(:transactions, Transaction, references: :hash, foreign_key: :block_hash)
    field(:number, :integer, default: 0)
    field(:total_burned, :integer, default: 0)
    field(:winner, :binary, default: <<0::256>>)
    field(:memory_changeset_hash, :binary, default: Crypto.hash(<<>>))
    field(:storage_changeset_hash, :binary, default: Crypto.hash(<<>>))
    field(:proof_of_work_value, :integer)
  end

  def next_block_params() do
    best_block = best()

    if best_block do
      %{
        number: next_block_number(),
        parent: best_block
      }
    else
      %{
        number: 0
      }
    end
    |> Map.merge(%{
      winner: Configuration.public_key()
    })
  end

  def next_block_number() do
    best_block = best()

    if best_block do
      best_block.number + 1
    else
      0
    end
  end

  def best(query \\ __MODULE__),
    do:
      from(q in query, order_by: [desc: q.number])
      |> Ecto.Query.first()
      |> Repo.one()

  def latest(query \\ __MODULE__, count),
    do: from(q in query, order_by: [desc: q.number], limit: ^count)

  def changeset(block, params \\ %{}) do
    block_hash = hash(params)
    params = Map.put(params, :hash, block_hash)

    block
    |> cast(params, [
      :hash,
      :number,
      :memory_changeset_hash,
      :storage_changeset_hash,
      :proof_of_work_value,
      :winner
    ])
    |> unique_constraint(:hash)
    |> cast_assoc(:transactions)
    |> validate_required([
      :hash,
      :memory_changeset_hash,
      :storage_changeset_hash,
      :number,
      :proof_of_work_value,
      :winner
    ])
  end

  def as_map(block) do
    fields = __schema__(:fields)

    Map.take(block, fields)
    |> Map.put(:transactions, transactions_as_map(block.transactions))
    |> Map.put(:parent_hash, parent_hash(block))
  end

  defp transactions_as_map(transactions),
    do:
      if(Ecto.assoc_loaded?(transactions),
        do: transactions |> Enum.map(&Transaction.as_map/1),
        else: []
      )

  defp parent_hash(block),
    do:
      if(Map.has_key?(block, :parent) && Ecto.assoc_loaded?(block.parent),
        do: block.parent.hash
      )

  def apply(block) do
    if Validations.valid_next_block?(block) do
      Miner.stop()
      TransactionProcessor.process(block)
      Repo.insert!(block)
      Miner.cast_mine_next_block()
      WebsocketHandler.broadcast(:blocks, block)
      Logger.info("Applied block #{block.number}")
    else
      Logger.info("Received invalid block ##{block.number}")
    end
  end

  def as_binary_pre_pow(block),
    do:
      block
      |> as_map()
      |> Map.drop([
        :proof_of_work_value,
        :parent_hash,
        :parent,
        :hash,
        :total_burned
      ])
      |> Map.update!(:transactions, (fn transactions ->
        Enum.map(transactions, (fn transaction ->
          Map.drop(transaction, [
            :block_hash,
            :hash,
            :signature,
            :id,
          ])
        end))
      end))
      |> Cbor.encode()
end
