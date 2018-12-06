use Mix.Config

config :blacksmith, base_contracts_path: "./base_contracts"
config :blacksmith, port: String.to_integer(System.get_env("PORT") || "4045")

config :blacksmith,
  staking_contract_address:
    (System.get_env("STAKING_CONTRACT_ADDRESS") || "") |> Base.decode16!(case: :mixed)

config :ethereumex, :web3_url, System.get_env("WEB3_URL")
config :ethereumex, :client_type, :websocket

config :blacksmith, Blacksmith.Repo,
  username: System.get_env("DATABASE_USER"),
  password: System.get_env("DATABASE_PASS"),
  database: System.get_env("DATABASE_NAME"),
  hostname: System.get_env("DATABASE_HOST"),
  pool_size: 15
