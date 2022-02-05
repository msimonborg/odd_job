defmodule OddJob.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(name) when is_atom(name) do
    start_link(name: name)
  end

  def start_link(opts) when is_list(opts) do
    Supervisor.start_link(__MODULE__, opts, name: id(opts[:name]))
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name)
    pool_opts = %{id: pool_id(name), pool: name}

    children = [
      {OddJob.Pool, pool_opts},
      {OddJob.Pool.Supervisor, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def child_spec(name) when is_atom(name), do: child_spec(name: name)

  def child_spec({name, opts}) when is_atom(name) and is_list(opts) do
    opts
    |> Keyword.put(:name, name)
    |> child_spec()
  end

  def child_spec(opts) when is_list(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: id(opts[:name]))
  end

  @spec pool_id(atom | binary) :: atom
  def pool_id(name) when is_atom(name) or is_binary(name), do: :"#{name}_pool"

  defp id(name), do: :"#{name}_sup"
end
