defmodule OddJob.Scheduler do
  @moduledoc """
  The `OddJob.Scheduler` is responsible for execution of scheduled jobs.

  Each scheduler is a dynamically supervised process that is created to manage a single timer
  and a job or collection of jobs to send to a pool when the timer expires. After the jobs are
  delivered to the pool the scheduler shuts itself down. The scheduler process will also
  automatically shutdown if a timer is cancelled with `OddJob.cancel_timer/1`. If a timer is
  cancelled with `Process.cancel_timer/1` then the scheduler will eventually timeout and shutdown
  one second after the timer would have expired.
  """
  @moduledoc since: "0.2.0"

  @doc false
  use GenServer, restart: :temporary
  alias OddJob.Utils

  @name __MODULE__
  @registry OddJob.SchedulerRegistry

  @typedoc false
  @type time :: Time.t() | DateTime.t()

  @doc false
  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(@name, [])
  end

  @doc false
  @spec perform_after(integer, atom, function) :: reference
  def perform_after(timer, pool, fun) do
    pool
    |> Utils.scheduler_sup_name()
    |> DynamicSupervisor.start_child(@name)
    |> Utils.extract_pid()
    |> GenServer.call({:perform_after, timer, pool, fun})
  end

  @doc false
  @spec perform_at(time, atom, function) :: reference
  def perform_at(time, pool, fun) do
    pool
    |> Utils.scheduler_sup_name()
    |> DynamicSupervisor.start_child(@name)
    |> Utils.extract_pid()
    |> GenServer.call({:perform_at, time, pool, fun})
  end

  @doc false
  @spec cancel_timer(reference) :: non_neg_integer | false
  def cancel_timer(timer_ref) when is_reference(timer_ref) do
    result = Process.cancel_timer(timer_ref)

    case lookup(timer_ref) do
      [{pid, :timer}] -> GenServer.cast(pid, :abort)
      [] -> :noop
    end

    result
  end

  defp lookup(timer_ref), do: Registry.lookup(@registry, timer_ref)

  @impl GenServer
  @spec init([]) :: {:ok, []}
  def init([]) do
    {:ok, []}
  end

  @impl GenServer
  def handle_call({:perform_after, timer, pool, fun}, _, state) do
    timer_ref =
      timer
      |> set_timer(:perform, pool, fun)
      |> register()
      |> set_timeout()

    {:reply, timer_ref, state}
  end

  def handle_call({:perform_at, time, pool, fun}, _, state) when is_struct(time, Time) do
    timer_ref =
      Time.utc_now()
      |> Time.diff(time, :millisecond)
      |> abs()
      |> set_timer(:perform, pool, fun)
      |> register()
      |> set_timeout()

    {:reply, timer_ref, state}
  end

  def handle_call({:perform_at, time, pool, fun}, _, state) when is_struct(time, DateTime) do
    timer_ref =
      DateTime.utc_now()
      |> DateTime.diff(time, :millisecond)
      |> abs()
      |> set_timer(:perform, pool, fun)
      |> register()
      |> set_timeout()

    {:reply, timer_ref, state}
  end

  defp set_timer(timer, dispatch, pool, fun) do
    Process.send_after(self(), {dispatch, pool, fun}, timer)
  end

  defp register(timer_ref) do
    Registry.register(@registry, timer_ref, :timer)
    timer_ref
  end

  defp set_timeout(timer_ref) do
    time_remaining = Process.read_timer(timer_ref)
    Process.send_after(self(), :timeout, time_remaining + 1000)
    timer_ref
  end

  @impl GenServer
  def handle_cast(:abort, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:perform, pool, fun}, state) do
    OddJob.perform(pool, fun)
    {:stop, :normal, state}
  end

  def handle_info(:timeout, state) do
    {:stop, :timeout, state}
  end
end
