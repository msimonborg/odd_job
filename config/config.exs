import Config

# Configure jobs to supervise under the OddJob application tree
# config :odd_job,
#   default_pool: :email, # Defaults to `:job`
#   extra_pools: [:work], # Defaults to an empty list
#   pool_size: 10 # Defaults to 5

if Mix.env() == :test, do: import_config("test.exs")
