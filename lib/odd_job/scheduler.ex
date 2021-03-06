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

  import OddJob.Guards

  alias OddJob.Scheduler.Supervisor, as: SchedulerSup

  @name __MODULE__
  @registry OddJob.Registry

  @typedoc false
  @type timer :: non_neg_integer
  @type pool :: atom

  # <---- Client API ---->

  @doc false
  @spec perform(timer, pool, function) :: reference
  def perform(timer, pool, function) when is_timer(timer) do
    pool
    |> SchedulerSup.start_child()
    |> GenServer.call({:schedule_perform, timer, {pool, function}})
  end

  @spec perform_many(timer, pool, list | map, function) :: reference
  def perform_many(timer, pool, collection, function) do
    pool
    |> SchedulerSup.start_child()
    |> GenServer.call({:schedule_perform, timer, {pool, collection, function}})
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

  @doc false
  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(@name, [])
  end

  # <---- Callbacks ---->

  @impl GenServer
  @spec init([]) :: {:ok, []}
  def init([]) do
    {:ok, []}
  end

  @impl GenServer
  def handle_call({:schedule_perform, timer, dispatch}, _, state) do
    timer_ref =
      timer
      |> set_timer(dispatch)
      |> register()

    timeout = Process.read_timer(timer_ref) + 1
    {:reply, timer_ref, state, timeout}
  end

  defp set_timer(timer, dispatch) do
    Process.send_after(self(), {:perform, dispatch}, timer)
  end

  defp register(timer_ref) do
    Registry.register(@registry, timer_ref, :timer)
    timer_ref
  end

  @impl GenServer
  def handle_cast(:abort, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:perform, {pool, fun}}, state) do
    OddJob.perform(pool, fun)
    {:stop, :normal, state}
  end

  def handle_info({:perform, {pool, collection, function}}, state) do
    OddJob.perform_many(pool, collection, function)
    {:stop, :normal, state}
  end

  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end
end
