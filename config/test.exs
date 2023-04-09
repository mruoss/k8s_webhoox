import Config

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :info],
    [library: :k8s],
    [library: :bonny]
  ]
