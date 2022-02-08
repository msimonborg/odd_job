defmodule OddJob.Registry do
  @moduledoc """
  The `OddJob` process registry.
  """
  @moduledoc since: "0.4.0"

  @type name :: {:via, Registry, {OddJob.Registry, {term, term}}}
  @type pool :: term
  @type role :: String.t()

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__, partitions: 2]
    |> Registry.child_spec()
  end

  @doc """
  Returns the name in `:via` that can be used to lookup an OddJob process.

  The first argument is the term that was used to name the `pool`. The second
  argument is the `role` as a string.

  ## Roles

    * `"sup"` - the supervisor at the top of the `pool` tree

    * `"pool"` - the `pool` process, a `GenServer` that receives jobs and assigns them to
    the workers

    * `"pool_sup"` - the supervisor responsible for starting and stopping the workers in
    the pool

    * `"proxy_sup"` - the supervisor responsible for starting the proxy processes that link
    the calling process to the worker during execution of an async job

    * `"scheduler_sup"` - the supervisor responsible for starting job scheduling processes

  ## Example

      iex> OddJob.Registry.via(ViaTest, "sup")
      {:via, Registry, {OddJob.Registry, {ViaTest, "sup"}}}
  """
  @spec via(pool, role) :: name
  def via(pool, role), do: {:via, Registry, {__MODULE__, {pool, role}}}
end
