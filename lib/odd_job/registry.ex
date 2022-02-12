defmodule OddJob.Registry do
  @moduledoc """
  The `OddJob` process registry.
  """
  @moduledoc since: "0.4.0"

  @type pool :: atom
  @type role :: atom
  @type name :: {:via, Registry, {OddJob.Registry, {pool, role}}}

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__, partitions: 2]
    |> Registry.child_spec()
  end

  @doc """
  Returns the name in `:via` that can be used to lookup an OddJob process.

  The first argument is the atom that was used to name the `pool`. The second
  argument is the `role` as an atom, or the tuple `{:worker, id}`.

  ## Roles

    * `:queue` - the `pool` process, a `GenServer` that receives jobs and assigns them to
    the workers

    * `:pool_sup` - the supervisor responsible for starting and stopping the workers in
    the pool

    * `:proxy_sup` - the supervisor responsible for starting the proxy processes that link
    the calling process to the worker during execution of an async job

    * `:scheduler_sup` - the supervisor responsible for starting job scheduling processes

  ## Example

      iex> OddJob.Registry.via(ViaTest, :sup)
      {:via, Registry, {OddJob.Registry, {ViaTest, :sup}}}

  See `OddJob.Utils` for helper functions that encapsulate each role.
  """
  @spec via(pool, role) :: name
  def via(pool, role), do: {:via, Registry, {__MODULE__, {pool, role}}}
end
