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
  def await(%Job{ref: ref} = _job, timeout) do
    receive do
      %Job{ref: ^ref, results: results} -> results
    after
      timeout -> exit(:timeout)
    end
  end
end
