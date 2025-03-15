defmodule Bonfire.PanDoRa do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  import Untangle

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Vault for encryption
      Bonfire.PanDoRa.Vault
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for more information about supervision trees
    opts = [strategy: :one_for_one, name: Bonfire.PanDoRa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def repo, do: Config.repo()
end
