defmodule OddJob.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(name) when is_atom(name) do
    start_link(name, [])
  end

  def start_link(name, opts) when is_atom(name) and is_list(opts) do
    Supervisor.start_link(__MODULE__, [name, opts], name: id(name))
  end

  @impl true
  def init([name, opts]) do
    pool_opts = %{id: pool_id(name), pool: name}

    children = [
      {OddJob.Pool, pool_opts},
      {OddJob.Pool.Supervisor, [name, opts]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def child_spec(name) when is_atom(name), do: child_spec(name, [])
  def child_spec({name, opts}) when is_atom(name) and is_list(opts), do: child_spec(name, opts)

  def child_spec(opts) when is_list(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    child_spec(name, opts)
  end

  defp child_spec(name, opts) do
    %{
      id: id(name),
      start: {__MODULE__, :start_link, [name, opts]},
      type: :supervisor
    }
  end

  @spec pool_id(atom | binary) :: atom
  def pool_id(name) when is_atom(name) or is_binary(name), do: :"#{name}_pool"

  defp id(name), do: :"#{name}_sup"
end
