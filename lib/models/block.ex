defmodule Models.Block do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias Blacksmith.Repo

  schema "blocks" do
    belongs_to(:parent, __MODULE__)
    field(:number, :integer)
    field(:total_burned, :integer)
    field(:winner, :binary)
    field(:changeset_hash, :binary)
    field(:block_hash, :binary)
    timestamps()
  end

  def best_block(query \\ __MODULE__),
    do:
      from(q in query, order_by: q.total_burned)
      |> Ecto.Query.first()

  def latest(query \\ __MODULE__, count), do: from(q in query, order_by: q.number, limit: ^count)

  def changeset(user, params \\ %{}) do
    user
    |> cast(params, [:number])
    |> validate_required([
      :number,
      :changeset_hash,
      :block_hash,
      :winner
    ])
  end

  def hash(block), do: Crypto.hash(to_binary(block))
  def as_map(%{
    parent: parent,
    number: number,
    block_hash: block_hash,
    total_burned: total_burned,
    winner: winner,
    changeset_hash: changeset_hash
  }), do:
  %{
    parent_hash: (if Ecto.assoc_loaded?(parent), do: (parent.block_hash || <<0::256>>), else: <<0::256>>),
    block_hash: block_hash,
    total_burned: total_burned || <<0::256>>,
    number: number,
    winner: winner,
    changeset_hash: changeset_hash
  }

  def as_cbor(block), do: Cbor.encode(as_map(block))

  def forge(winner) do
    TransactionProcessor.proccess_transactions(1)
    TransactionProcessor.wait_until_done()
    {:ok, changeset} = Redis.fetch("changeset", <<>>)

    parent = best_block() |> Repo.one()
    Redis.delete("changeset")

    block = %__MODULE__{
      parent: parent,
      winner: winner,
      number: 0,
      changeset_hash: Crypto.hash(changeset)
    }

    block = Map.put(block, :block_hash, hash(block))

    Repo.insert(block)
  end

  defp to_binary(%{
         number: number,
         winner: winner,
         changeset_hash: changeset_hash
       }) do
    <<number::size(256)>> <> winner <> changeset_hash
  end
end
