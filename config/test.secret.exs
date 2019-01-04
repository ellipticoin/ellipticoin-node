use Mix.Config

config :blacksmith, private_key: File.read!("test/support/private_key.pem")
# Ganache-cli generates a set of private keys based on a mnemonic
# For testing we use the following mnemonic:
# ganache-cli -m "theme recall skull maximum glance major nerve situate giant snake glide oblige"
config :blacksmith,
  ethereum_private_key:
    Base.decode16!("43622b10a1d41a3ba7b7ce4f26bffca0193c0f1c5ff497b04760e940fceff15d",
      case: :lower
    )

config :blacksmith,
       :testnet_private_keys,
       [
         "43622b10a1d41a3ba7b7ce4f26bffca0193c0f1c5ff497b04760e940fceff15d",
         "523f07ab029c8d9d1d0440703cd1da30c96bc7fb32f53721310f83dca42d57cf",
         "20b72edfdbad77bf1c10ebc2061a51297fd3da551f44887386bfc10c585baf9f"
       ]
       |> Enum.map(&Base.decode16!(&1, case: :lower))
