defmodule OddJob.Supervisor do
  @moduledoc """
  The `OddJob.Supervisor` is the supervisor at the top of a pool supervision tree, and is
  responsible for starting and supervising the `OddJob.Pool` and `OddJob.Pool.Worker`s.

  All of this module's public functions can be called using the `OddJob` namespace. See
  the `OddJob` documentation for usage.
  """
  @moduledoc since: "0.1.0"
  use Supervisor
  import OddJob.Utils

  @doc false
  defmacro __using__(opts) do
    keys = [:name, :pool_size, :max_restarts, :max_seconds]
    {sup_opts, start_opts} = Keyword.split(opts, keys)

    quote location: :keep, bind_quoted: [sup_opts: sup_opts, start_opts: start_opts] do
      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Returns a specification to start this module under a supervisor.
        See `Supervisor`.
        """
      end

      def child_spec(arg) when is_atom(arg), do: child_spec(name: arg)

      def child_spec(arg) when is_list(arg) do
        Keyword.merge([name: __MODULE__], unquote(Macro.escape(sup_opts)))
        |> Keyword.merge(arg)
        |> OddJob.child_spec()
        |> Supervisor.child_spec(unquote(Macro.escape(start_opts)))
      end

      defoverridable child_spec: 1
    end
  end

  @type start_arg :: atom | [{:name, atom} | start_option]
  @type child_spec :: Supervisor.child_spec()
  @type start_option ::
          {:pool_size, non_neg_integer}
          | {:max_restarts, non_neg_integer}
          | {:max_seconds, non_neg_integer}

  @doc false
  @spec start_link(atom, [start_option]) :: Supervisor.on_start()
  def start_link(name, opts \\ []) when is_atom(name) and is_list(opts) do
    opts = Keyword.delete(opts, :name)
    name = to_snakecase(name)
    Supervisor.start_link(__MODULE__, [name, opts], name: supervisor_name(name))
  end

  @impl Supervisor
  def init([name, _opts] = args) do
    pool_opts = [id: pool_name(name), pool: name]

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: proxy_sup_name(name)},
      {DynamicSupervisor, strategy: :one_for_one, name: scheduler_sup_name(name)},
      {OddJob.Pool, pool_opts},
      {OddJob.Pool.Supervisor, args}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  @spec child_spec(start_arg) :: child_spec
  def child_spec(name) when is_atom(name), do: child_spec(name: name)

  def child_spec(opts) when is_list(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    name = to_snakecase(name)

    opts
    |> super()
    |> Supervisor.child_spec(
      id: supervisor_name(name),
      start: {__MODULE__, :start_link, [name, opts]}
    )
  end
end
