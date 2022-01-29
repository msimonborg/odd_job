defmodule OddJob do
  defdelegate child_spec(name), to: OddJob.Supervisor

  def perform(job, fun) do
    GenServer.call(:"odd_job_#{job}_queue", {:perform, fun})
  end
end
