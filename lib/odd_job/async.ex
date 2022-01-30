defmodule OddJob.Async do
  @moduledoc false
  alias OddJob.Job

  @type job :: OddJob.Job.t()

  @supervisor OddJob.Async.ProxySupervisor
  @server OddJob.Async.ProxyServer

  @spec perform(atom, fun) :: job
  def perform(pool, fun) when is_atom(pool) and is_function(fun) do
    {:ok, pid} = DynamicSupervisor.start_child(@supervisor, @server)
    Process.link(pid)
    ref = Process.monitor(pid)
    job = %Job{ref: ref, function: fun, owner: self(), proxy: pid, async: true}
    GenServer.call(pid, {:run, pool, job})
  end

  @spec await(job, timeout) :: any
  def await(%Job{ref: ref} = job, timeout) do
    receive do
      {^ref, results} ->
        Process.demonitor(ref, [:flush])
        results

      {:DOWN, ^ref, _, pid, reason} ->
        exit({reason(reason, pid), {__MODULE__, :await, [job, timeout]}})
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit({:timeout, {__MODULE__, :await, [job, timeout]}})
    end
  end

  # The following private functions were taken from the Task module in Elixir's standard library,
  # in the hope that exit behavior mimics that of the Task module.

  defp reason(:noconnection, proc), do: {:nodedown, monitor_node(proc)}
  defp reason(reason, _), do: reason

  defp monitor_node(pid) when is_pid(pid), do: node(pid)
  defp monitor_node({_, node}), do: node
end
