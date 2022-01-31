defmodule OddJob.Scheduler do
  @moduledoc false

  use GenServer

  @name __MODULE__

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([]) do
    GenServer.start_link(@name, [], name: @name)
  end

  @spec perform_after(integer, atom, function) :: reference
  def perform_after(time, pool, fun) do
    GenServer.call(@name, {:perform_after, time, pool, fun})
  end

  @impl true
  @spec init([]) :: {:ok, []}
  def init([]) do
    {:ok, []}
  end

  @impl true
  def handle_call({:perform_after, time, pool, fun}, _, state) do
    timer_ref = Process.send_after(self(), {:perform, pool, fun}, time)
    {:reply, timer_ref, state}
  end

  @impl true
  def handle_info({:perform, pool, fun}, state) do
    OddJob.perform(pool, fun)
    {:noreply, state}
  end
end
