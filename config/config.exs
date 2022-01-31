import Config

# Configure jobs to supervise under the OddJob application tree
config :odd_job,
  supervise: [:work]

# Configure pool size, defaults to 5
# pool_size: 10

if Mix.env() == :test, do: import_config("test.exs")
