defmodule Bonfire.PanDoRa.Web.WidgetPublicListsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Auth

  prop user, :any, default: nil

  def update(assigns, socket) do
    lists_result = Client.my_lists(current_user: current_user(socket), per_page: 200)

    socket =
      socket
      |> assign(assigns)
      |> assign_pandora_urls()
      |> handle_lists_result(lists_result)

    {:ok, socket}
  end

  defp assign_pandora_urls(socket) do
    socket
    |> assign(:pandora_token, Auth.pandora_token(current_user: socket.assigns[:current_user]))
    |> assign(:pandora_base_url, String.trim_trailing(Client.get_pandora_url() || "", "/"))
  end

  # Handle successful list fetch
  defp handle_lists_result(socket, {:ok, %{items: lists}}) do
    socket
    |> assign(:lists, lists)
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  # Handle failed list fetch
  defp handle_lists_result(socket, {:error, error}) do
    socket
    |> assign(:lists, [])
    |> assign(:loading, false)
    |> assign(:error, error)
  end
end
