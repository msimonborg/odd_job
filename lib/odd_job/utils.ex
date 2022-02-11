defmodule OddJob.Utils do
  @moduledoc """
  Internal utilities for working with OddJob processes.

  To avoid unexpected behavior, it's recommended that developers do not interact
  directly with OddJob processes. See `OddJob` for the public API.
  """
  @moduledoc since: "0.4.0"

  import OddJob.Registry, only: [via: 2]

  @type name :: OddJob.Registry.name()

  @doc """
  Links and monitors the `pid` and returns the tuple `{pid, monitor_ref}`.

  ## Example

      iex> {pid, ref} = OddJob.Utils.link_and_monitor(spawn(fn -> :hello end))
      iex> receive do
      ...>   {:DOWN, ^ref, :process, ^pid, :normal} -> :received
      ...> end
      :received
  """
  @spec link_and_monitor(pid) :: {pid, reference}
  def link_and_monitor(pid) do
    Process.link(pid)
    {pid, Process.monitor(pid)}
  end

  @doc """
  Extracts the `pid` from an `{:ok, pid}` tuple.

      iex> pid = spawn_link(fn -> :hello end)
      iex> pid == OddJob.Utils.extract_pid({:ok, pid})
      true
  """
  @spec extract_pid({:ok, pid}) :: pid
  def extract_pid({:ok, pid}), do: pid

  @doc """
  Returns the `OddJob.Scheduler.Supervisor` name in :via for the given `name`.

      iex> OddJob.Utils.scheduler_sup_name(:job)
      {:via, Registry, {OddJob.Registry, {:job, :scheduler_sup}}}
  """
  @spec scheduler_sup_name(term) :: name
  def scheduler_sup_name(name), do: via(name, :scheduler_sup)

  @doc """
  Returns the `OddJob.Queue` name in :via for the given `name`.

      iex> OddJob.Utils.queue_name(:job)
      {:via, Registry, {OddJob.Registry, {:job, :queue}}}
  """
  @spec queue_name(term) :: name
  def queue_name(name), do: via(name, :queue)

  @doc """
  Returns the `OddJob.Pool.Supervisor` name in :via for the given `name`.

      iex> OddJob.Utils.pool_supervisor_name(:job)
      {:via, Registry, {OddJob.Registry, {:job, :pool_sup}}}
  """
  @spec pool_supervisor_name(term) :: name
  def pool_supervisor_name(name), do: via(name, :pool_sup)

  @doc """
  Returns the `OddJob.Async.ProxySupervisor` name in :via for the given `name`.

      iex> OddJob.Utils.proxy_sup_name(:job)
      {:via, Registry, {OddJob.Registry, {:job, :proxy_sup}}}
  """
  @spec proxy_sup_name(term) :: name
  def proxy_sup_name(name), do: via(name, :proxy_sup)

  @doc """
  Returns the `OddJob.Pool.Worker` name in :via for the given `name` and `id`.

      iex> OddJob.Utils.worker_name(:job, 1)
      {:via, Registry, {OddJob.Registry, {:job, {:worker, 1}}}}
  """
  @spec worker_name(term, non_neg_integer) :: name
  def worker_name(name, id), do: via(name, {:worker, id})
end
