defmodule OddJob.Supervisor do
  @moduledoc false
  use Supervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(name) do
    Supervisor.start_link(__MODULE__, name, name: id(name))
  end

  @impl true
  def init(name) do
    pool_opts = %{id: pool_id(name), pool: name}

    children = [
      {OddJob.Pool, pool_opts},
      {OddJob.Pool.Supervisor, name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def child_spec(name) do
    %{
      id: id(name),
      start: {__MODULE__, :start_link, [name]},
      type: :supervisor
    }
  end

  @spec pool_id(atom | binary) :: atom
  def pool_id(name) when is_atom(name) or is_binary(name), do: :"#{name}_pool"

  defp id(name), do: :"#{name}_sup"
end
