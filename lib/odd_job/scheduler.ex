defmodule OddJob.Scheduler do
  @moduledoc false

  use GenServer

  @name __MODULE__

  @type time :: Time.t() | DateTime.t()

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(@name, [], name: @name)
  end

  @spec perform_after(integer, atom, function) :: reference
  def perform_after(timer, pool, fun) do
    GenServer.call(@name, {:perform_after, timer, pool, fun})
  end

  @spec perform_at(time, atom, function) :: reference
  def perform_at(time, pool, fun) do
    GenServer.call(@name, {:perform_at, time, pool, fun})
  end

  @impl true
  @spec init([]) :: {:ok, []}
  def init([]) do
    {:ok, []}
  end

  @impl true
  def handle_call({:perform_after, timer, pool, fun}, _, state) do
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, timer)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_call({:perform_at, time, pool, fun}, _, state) when is_struct(time, Time) do
    time_now = Time.utc_now()
    timer = Time.diff(time, time_now, :millisecond)
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, timer)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_call({:perform_at, time, pool, fun}, _, state) when is_struct(time, DateTime) do
    time_now = DateTime.utc_now()
    timer = DateTime.diff(time, time_now, :millisecond)
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, timer)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_info({:perform, pool, fun}, state) do
    OddJob.perform(pool, fun)
    {:noreply, state}
  end
end
