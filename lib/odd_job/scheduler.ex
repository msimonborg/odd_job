defmodule OddJob.Scheduler do
  @moduledoc false

  use GenServer, restart: :temporary

  @name __MODULE__
  @supervisor OddJob.SchedulerSupervisor
  @registry OddJob.SchedulerRegistry

  @type time :: Time.t() | DateTime.t()

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(@name, [])
  end

  @spec perform_after(integer, atom, function) :: reference
  def perform_after(timer, pool, fun) do
    {:ok, pid} = DynamicSupervisor.start_child(@supervisor, @name)
    GenServer.call(pid, {:perform_after, timer, pool, fun})
  end

  @spec perform_at(time, atom, function) :: reference
  def perform_at(time, pool, fun) do
    {:ok, pid} = DynamicSupervisor.start_child(@supervisor, @name)
    GenServer.call(pid, {:perform_at, time, pool, fun})
  end

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

  @impl true
  @spec init([]) :: {:ok, []}
  def init([]) do
    {:ok, []}
  end

  @impl true
  def handle_call({:perform_after, timer, pool, fun}, _, state) do
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, timer)
    register(timer_ref)
    set_timeout(timer)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_call({:perform_at, time, pool, fun}, _, state) when is_struct(time, Time) do
    time_now = Time.utc_now()
    timer = Time.diff(time, time_now, :millisecond)
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, timer)
    register(timer_ref)
    set_timeout(timer)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_call({:perform_at, time, pool, fun}, _, state) when is_struct(time, DateTime) do
    time_now = DateTime.utc_now()
    timer = DateTime.diff(time, time_now, :millisecond)
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, timer)
    register(timer_ref)
    set_timeout(timer)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_cast(:abort, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:perform, pool, fun}, state) do
    OddJob.perform(pool, fun)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :timeout, state}
  end

  defp register(timer_ref), do: Registry.register(@registry, timer_ref, :timer)
  defp set_timeout(timer), do: Process.send_after(self(), :timeout, timer + 1000)
end
