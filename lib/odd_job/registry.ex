defmodule OddJob.Registry do
  @moduledoc false
  @moduledoc since: "0.4.0"

  @type name :: {:via, Registry, {OddJob.Registry, {term, term}}}

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__, partitions: 2]
    |> Registry.child_spec()
  end

  @spec via(term, term) :: name
  def via(pool, role), do: {:via, Registry, {__MODULE__, {pool, role}}}
end
