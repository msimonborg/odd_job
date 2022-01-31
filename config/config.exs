import Config

# Configure jobs to supervise under the OddJob application tree
# config :odd_job,
#   supervise: [:work],
#   pool_size: 10 # Defaults to 5

if Mix.env() == :test, do: import_config("test.exs")
