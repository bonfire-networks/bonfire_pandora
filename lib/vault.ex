defmodule Bonfire.PanDoRa.Vault do
  use Cloak.Vault, otp_app: :bonfire_pandora
  use Untangle

  @key_var "PANDORA_CLOAK_KEY"

  @impl GenServer
  def init(config) do
    config =
      case System.fetch_env(@key_var) do
        {:ok, value} ->
          Keyword.put(config, :ciphers,
            default:
              {Cloak.Ciphers.AES.GCM,
               tag: "AES.GCM.V1", iv_length: 12, key: Base.decode64!(value)}
          )

        :error ->
          error(@key_var, "Environment variable not set, skipping Vault setup")
          config
      end

    {:ok, config}
  end
end
