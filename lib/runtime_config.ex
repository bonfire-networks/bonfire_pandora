defmodule Bonfire.PanDoRa.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  NOTE: you can override this default config in your app's `runtime.exs`, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs()` line
  """
  def config do
    import Config

    # config :bonfire_pandora,
    #   modularity: :disabled

    config :bonfire_pandora,
      pandora_url: System.get_env("PANDORA_URL")

    config :bonfire_pandora, PanDoRa.API.Client,
      username: System.get_env("PANDORA_USER"),
      password: System.get_env("PANDORA_PW")
  end
end
