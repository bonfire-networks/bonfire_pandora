defmodule Bonfire.PanDoRa.Components.ConnectPandoraLive do
  @moduledoc """
  Widget for Settings: "Connect to Pandora" button opens a modal with a password form.
  Submits POST to /archive/connect. Parent should pass csrf_token (e.g. from session in mount).
  """
  use Bonfire.UI.Common.Web, :stateful_component

  prop csrf_token, :string, default: nil

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end
