import Config

# Configure jobs to supervise under the OddJob application tree
config :odd_job,
  supervise: [:email, :task]
