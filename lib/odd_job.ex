defmodule OddJob do
  defdelegate child_spec(name), to: OddJob.Supervisor
end
