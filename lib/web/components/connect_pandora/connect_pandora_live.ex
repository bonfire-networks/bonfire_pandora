defmodule Bonfire.PanDoRa.Components.ConnectPandoraLive do
  @moduledoc """
  Settings widget for the manual Pandora sync/recovery flow.

  It opens a password form and submits to `/archive/connect`, where the backend
  will try signin first and fall back to signup+signin if the Pandora shadow
  user does not exist yet.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  declare_settings_component("Sync Pandora access",
    description: l(
      "Manual sync/recovery tool for the Pandora shadow account used by this Bonfire user."
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
