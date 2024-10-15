import Config

#### General configuration useful for tests, everything else should be in `bonfire_pan_do_ra.exs` or `Bonfire.PanDoRa.RuntimeConfig`

# You probably won't want to touch these. You might override some in
# other config files.

config :bonfire, :repo_module, Bonfire.Common.Repo

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mime, :types, %{
  "application/activity+json" => ["activity+json"]
}

config :bonfire_pan_do_ra, :otp_app, :bonfire_pan_do_ra
config :bonfire_common, :otp_app, :bonfire_pan_do_ra
config :bonfire_pan_do_ra, :repo_module, Bonfire.Common.Repo
config :bonfire_pan_do_ra, ecto_repos: [Bonfire.Common.Repo]
config :bonfire_pan_do_ra, :localisation_path, "priv/localisation"

config :bonfire_data_identity, Bonfire.Data.Identity.Credential, hasher_module: Argon2

import_config "bonfire_pan_do_ra.exs"
# import_config "#{Mix.env()}.exs"
