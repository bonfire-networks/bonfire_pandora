defmodule Bonfire.PanDoRa.Vault do
  use Cloak.Vault, otp_app: :bonfire_pandora
  use Untangle

  @key_var "PANDORA_CLOAK_KEY"
  @fallback_var "SECRET_KEY_BASE"

  @impl GenServer
  def init(config) do
    raw =
      System.get_env(@key_var) ||
        derive_from_secret_key_base()

    config =
      if raw do
        key = decode_key(raw)

        Keyword.put(config, :ciphers,
          default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", iv_length: 12, key: key}
        )
      else
        error(
          @key_var,
          "Neither #{@key_var} nor #{@fallback_var} are set – Vault not initialised, credential storage will fail"
        )

        config
      end

    {:ok, config}
  end

  # Derive a 32-byte AES key from SECRET_KEY_BASE using SHA-256
  defp derive_from_secret_key_base do
    case System.fetch_env(@fallback_var) do
      {:ok, secret} ->
        :crypto.hash(:sha256, secret) |> Base.encode64()

      :error ->
        nil
    end
  end

  # Accept either a 32-byte base64 key or any string (hashed to 32 bytes)
  defp decode_key(value) do
    case Base.decode64(value) do
      {:ok, key} when byte_size(key) == 32 -> key
      _ -> :crypto.hash(:sha256, value)
    end
  end
end
