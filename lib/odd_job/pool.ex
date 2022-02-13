defmodule OddJob.Pool do
  @external_resource readme = Path.join([__DIR__, "../../README.md"])

  @usingdoc readme
            |> File.read!()
            |> String.split("<!-- USINGDOC -->")
            |> Enum.fetch!(1)

  @moduledoc """
  ## The `OddJob.Pool` process

  The `OddJob.Pool` is the supervisor at the top of a pool supervision tree, and is
  responsible for starting and supervising the `OddJob.Pool.Supervisor`, `OddJob.Queue`,
  `OddJob.Async.ProxySupervisor`, and `OddJob.Scheduler.Supervisor`. When you add a
  `OddJob.child_spec/1` to your list of supervised children, or call `OddJob.start_link/1`,
  you are adding an `OddJob.Pool` to your application.

  ## Public functions

  This module defines the public functions `start_link/1` and `child_spec/1`. It is recommended
  that you call these functions from the `OddJob` module namespace instead. See `OddJob` for
  documentation and usage.

  #{@usingdoc}
  """
  @moduledoc since: "0.1.0"

  use Supervisor

  @type name :: atom
  @type options :: [{:name, name} | start_option]
  @type child_spec :: Supervisor.child_spec()
  @type start_option ::
          {:pool_size, non_neg_integer}
          | {:max_restarts, non_neg_integer}
          | {:max_seconds, non_neg_integer}

  @doc false
  @spec child_spec(options) :: child_spec
  def child_spec(opts) when is_list(opts) do
    opts = Keyword.merge([name: __MODULE__], opts)

    opts
    |> super()
    |> Supervisor.child_spec(id: opts[:name])
  end

  @doc false
  @spec start_link(options) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop!(opts, :name)
    Supervisor.start_link(__MODULE__, [name, init_opts], name: name)
  end

  @impl Supervisor
  def init([name, _opts] = args) do
    children = [
      {OddJob.Async.ProxySupervisor, name},
      {OddJob.Scheduler.Supervisor, name},
      {OddJob.Queue, name},
      {OddJob.Pool.Supervisor, args}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  @doc since: "0.4.0"
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Returns a specification to start this module under a supervisor.
        See `Supervisor`.
        """
      end

      def child_spec(arg) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]},
          type: :supervisor
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Starts an OddJob supervision tree linked to the current process.
        See `OddJob.start_link/2`.
        """
      end

      def start_link([]), do: OddJob.start_link(name: __MODULE__)

      def start_link(arg) do
        IO.warn("""
        Your initial argument was ignored because you have not defined a custom
        `start_link/1` in #{__MODULE__}.
        """)

        start_link([])
      end

      defoverridable child_spec: 1, start_link: 1
    end
  end
end
