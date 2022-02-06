defmodule OddJob.Supervisor do
  @moduledoc """
  The `OddJob.Supervisor` is the supervisor at the top of a pool supervision tree, and is
  responsible for starting and supervising the `OddJob.Pool` and `OddJob.Pool.Worker`s.

  All of this module's public functions can be called using the `OddJob` namespace. See
  the `OddJob` documentation for usage.
  """
  @moduledoc since: "0.1.0"
  use Supervisor

  @type start_arg :: atom | [start_option]
  @type start_option ::
          {:name, atom}
          | {:pool_size, non_neg_integer}
          | {:max_restarts, non_neg_integer}
          | {:max_seconds, non_neg_integer}
  @type child_spec :: %{
          id: atom,
          start: {OddJob.Supervisor, :start_link, [start_option]},
          type: :supervisor
        }

  @doc false
  @spec start_link(start_arg) :: Supervisor.on_start()
  def start_link(start_arg)

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
      {DynamicSupervisor, strategy: :one_for_one, name: pool_id(name) |> proxy_sup_name()},
      {DynamicSupervisor, strategy: :one_for_one, name: scheduler_sup_name(name)},
      {OddJob.Pool, pool_opts},
      {OddJob.Pool.Supervisor, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  @spec child_spec(start_arg | {atom, [start_option]}) :: child_spec
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

  @doc false
  @spec pool_id(atom | binary) :: atom
  def pool_id(name) when is_atom(name) or is_binary(name), do: :"#{name}_pool"
  @doc false
  @spec proxy_sup_name(any) :: atom
  def proxy_sup_name(name), do: :"#{name}_proxy_sup"
  @doc false
  @spec scheduler_sup_name(any) :: atom
  def scheduler_sup_name(name), do: :"#{name}_scheduler_sup"

  defp id(name), do: :"#{name}_sup"
end
