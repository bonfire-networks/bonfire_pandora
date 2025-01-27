defmodule Bonfire.PanDoRa.Web.SearchLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Components.ResultsDisplay

  alias Bonfire.PanDoRa.Components.LoadingIndicator
  alias Bonfire.PanDoRa.Components.ResultsDisplay

  declare_extension(
    "Pan.do/ra",
    icon: "bi:app",
    description: l("An awesome extension")
    # default_nav: [
    #   Bonfire.PanDoRa.Web.SearchLive
    # ]
  )

  declare_nav_link(l("Search Pan.do/ra"), page: "home", icon: "ri:home-line", emoji: "🧩")

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  data results, :map, default: nil
  data loading, :boolean, default: false
  data search_term, :string, default: ""

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"term" => term}, _, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:search_term, term)

    handle_async(:fetch_data, search(term), socket)
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def handle_event("search", %{"term" => term}, socket) do
    {:noreply,
     socket
     |> assign(:loading, true)
     |> assign(:search_term, term)
     |> start_async(:fetch_data, fn ->
       search(term)
     end)}
  end

  def handle_event("validate", %{"term" => term}, socket) do
    {:noreply, assign(socket, :search_term, term)}
  end

  def handle_async(:fetch_data, {:ok, {:ok, results}}, socket) do
    handle_async(:fetch_data, {:ok, results}, socket)
  end

  def handle_async(:fetch_data, {:ok, results}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:results, results)}
  end

  def handle_async(:fetch_data, {:exit, error}, socket) do
    handle_async(:fetch_data, {:ok, {:error, error}}, socket)
  end

  def handle_async(:fetch_data, {:ok, {:error, error}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> put_flash(:error, error || l("An unexpected error occurred"))}
  end

  defp search(""), do: Client.find() |> debug()
  defp search(term), do: Client.find(search_term: term) |> debug()
end
