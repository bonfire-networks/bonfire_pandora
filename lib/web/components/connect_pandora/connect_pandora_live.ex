defmodule Bonfire.PanDoRa.Components.ConnectPandoraLive do
  @moduledoc """
  Widget for Settings: "Connect to Pandora" button opens a modal with a password form.
  Submits POST to /archive/connect. Registered as a SettingsModule component so it appears
  in the extension configure tab automatically.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  declare_settings_component("Connect to Pandora",
    description: l(
      "Connect your Bonfire account to a Pandora archive using your profile email and username."
    ),
    scope: :user
  )

  prop csrf_token, :string, default: nil

  def update(assigns, socket) do
    csrf = assigns[:csrf_token] || Plug.CSRFProtection.get_csrf_token()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:csrf_token, csrf)}
  end
end
