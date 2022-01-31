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

  # The rest of this module, covering implementation of the `await` and `await_many` functions,
  # was copied and adapted from the analogous functions in the Elixir standard library's `Task` module.
  # The intention of these functions is to mimic the expected behavior of the `Task` functions.
  @spec await(job, timeout) :: any
  def await(%Job{ref: ref, owner: owner} = job, timeout \\ 5000) do
    if owner != self() do
      raise ArgumentError, invalid_owner_error(job)
    end

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

  @spec await_many([job], timeout) :: [any]
  def await_many(jobs, timeout \\ 5000)
      when timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
    awaiting =
      for job <- jobs, into: %{} do
        %Job{ref: ref, owner: owner} = job

        if owner != self() do
          raise ArgumentError, invalid_owner_error(job)
        end

        {ref, true}
      end

    timeout_ref = make_ref()

    timer_ref =
      if timeout != :infinity do
        Process.send_after(self(), timeout_ref, timeout)
      end

    try do
      await_many(jobs, timeout, awaiting, %{}, timeout_ref)
    after
      timer_ref && Process.cancel_timer(timer_ref)
      receive do: (^timeout_ref -> :ok), after: (0 -> :ok)
    end
  end

  defp await_many(jobs, _timeout, awaiting, replies, _timeout_ref)
       when map_size(awaiting) == 0 do
    for %{ref: ref} <- jobs, do: Map.fetch!(replies, ref)
  end

  defp await_many(jobs, timeout, awaiting, replies, timeout_ref) do
    receive do
      ^timeout_ref ->
        demonitor_pending_jobs(awaiting)
        exit({:timeout, {__MODULE__, :await_many, [jobs, timeout]}})

      {:DOWN, ref, _, proc, reason} when is_map_key(awaiting, ref) ->
        demonitor_pending_jobs(awaiting)
        exit({reason(reason, proc), {__MODULE__, :await_many, [jobs, timeout]}})

      {ref, reply} when is_map_key(awaiting, ref) ->
        Process.demonitor(ref, [:flush])

        await_many(
          jobs,
          timeout,
          Map.delete(awaiting, ref),
          Map.put(replies, ref, reply),
          timeout_ref
        )
    end
  end

  defp demonitor_pending_jobs(awaiting) do
    Enum.each(awaiting, fn {ref, _} ->
      Process.demonitor(ref, [:flush])
    end)
  end

  # The following private functions were taken from the Task module in Elixir's standard library,
  # in the hope that exit behavior mimics that of the Task module.

  defp reason(:noconnection, proc), do: {:nodedown, monitor_node(proc)}
  defp reason(reason, _), do: reason

  defp monitor_node(pid) when is_pid(pid), do: node(pid)
  defp monitor_node({_, node}), do: node

  defp invalid_owner_error(job) do
    "job #{inspect(job)} must be queried from the owner but was queried from #{inspect(self())}"
  end
end
