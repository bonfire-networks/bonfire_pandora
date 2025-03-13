defmodule Bonfire.PanDoRa.Web.SearchViewLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils
  @behaviour Bonfire.UI.Common.LiveHandler

  # Keep your existing extension declarations
  declare_extension("Federated Archives",
    icon: "mingcute:microscope-fill",
    emoji: "🔬",
    description: "Federated archives alliance",
    default_nav: [__MODULE__]
  )

  declare_nav_link("Search archive",
    page: "home",
    href: "/pandora",
    icon: "carbon:document"
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:force_live, true)
     |> assign(:page_title, "Search in your archive")
     |> assign(:without_secondary_widgets, true)
     |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
     |> assign(:term, nil)}
  end

  # Keep your existing handle_params implementation
  def handle_params(%{"term" => term}, _, socket) do
    {:noreply, assign(socket, term: term)}
  end

  def handle_params(_, _, socket), do: {:noreply, socket}
end
