defmodule OddJob.Async do
  @moduledoc false
  @moduledoc since: "0.1.0"

  alias OddJob.{Async.ProxySupervisor, Job, Queue, Utils}

  @type job :: Job.t()
  @type queue :: Queue.queue()

  @doc since: "0.1.0"
  @spec perform(atom, queue, fun) :: job
  def perform(pool, queue, fun) when is_atom(pool) and is_function(fun) do
    pool
    |> ProxySupervisor.start_child()
    |> Utils.link_and_monitor()
    |> build_job(fun)
    |> tap(fn job -> Queue.perform(queue, job) end)
  end

  @spec perform_many(atom, queue, list | map, function) :: [job]
  def perform_many(pool, queue, collection, fun) do
    for item <- collection do
      pool
      |> ProxySupervisor.start_child()
      |> Utils.link_and_monitor()
      |> build_job(fn -> fun.(item) end)
    end
    |> tap(fn jobs -> Queue.perform_many(queue, jobs) end)
  end

  @spec build_job({pid, reference}, function) :: job
  defp build_job({pid, ref}, function) do
    %Job{
      ref: ref,
      function: function,
      owner: self(),
      proxy: pid,
      async: true
    }
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

  defp reason(:noconnection, proc), do: {:nodedown, monitor_node(proc)}
  defp reason(reason, _), do: reason

  defp monitor_node(pid) when is_pid(pid), do: node(pid)
  defp monitor_node({_, node}), do: node

  defp invalid_owner_error(job) do
    "job #{inspect(job)} must be queried from the owner but was queried from #{inspect(self())}"
  end
end
