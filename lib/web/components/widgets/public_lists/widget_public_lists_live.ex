defmodule Bonfire.PanDoRa.Web.WidgetPublicListsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client

  prop user, :any, default: nil

  def update(assigns, socket) do
    lists_result = Client.my_lists(current_user: current_user(socket))

    socket =
      socket
      |> assign(assigns)
      |> handle_lists_result(lists_result)

    {:ok, socket}
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
