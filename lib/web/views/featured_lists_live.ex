defmodule Bonfire.PanDoRa.Web.FeaturedListsLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Auth

  @behaviour Bonfire.UI.Common.LiveHandler

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    # Fetch lists immediately in mount
    lists_result = fetch_lists(current_user: current_user(socket))

    socket =
      socket
      |> assign(:back, true)
      |> assign(:page_title, "Featured lists")
      # |> assign(:page_header_aside, [
      #   {Bonfire.PanDoRa.Components.CreateNewListLive, [id: "create_new_list", myself: @myself]}
      # ])
      |> handle_lists_result(lists_result)
      |> assign_pandora_urls()

    {:ok, socket}
  end

  defp assign_pandora_urls(socket) do
    socket
    |> assign(:pandora_token, Auth.pandora_token(current_user: socket.assigns[:current_user]))
    |> assign(:pandora_base_url, String.trim_trailing(Client.get_pandora_url() || "", "/"))
  end

  # Handle successful list fetch
  defp handle_lists_result(socket, {:ok, %{items: lists}}) do
    # IO.inspect(lists, label: "Fetched lists")

    socket
    |> assign(:lists, lists)
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  # Handle failed list fetch
  defp handle_lists_result(socket, {:error, error}) do
    # IO.inspect(error, label: "Error fetching lists")

    socket
    |> assign(:lists, [])
    |> assign(:loading, false)
    |> assign(:error, error)
  end

  # Fetch lists for the current user
  defp fetch_lists(opts) do
    Client.find_lists(
      [
        keys: ["id", "description", "poster_frames", "posterFrames", "editable", "name", "status"],
        sort: [%{key: "name", operator: "+"}],
        type: :featured
      ] ++ opts
    )
  end

  def handle_info(msg, socket) do
    {:noreply, socket}
  end
end
