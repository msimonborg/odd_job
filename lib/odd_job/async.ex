defmodule OddJob.Async do
  @moduledoc false
  @type job :: OddJob.Job.t()

  @supervisor OddJob.Async.ProxySupervisor
  @server OddJob.Async.ProxyServer

  @spec start_link(atom, fun) :: job
  def start_link(pool, fun) when is_atom(pool) and is_function(fun) do
    {:ok, pid} = DynamicSupervisor.start_child(@supervisor, @server)
    true = Process.link(pid)
    ref = Process.monitor(pid)
    GenServer.call(pid, {:run, ref, pool, fun})
  end
end
