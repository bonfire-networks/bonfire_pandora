defmodule Bonfire.PanDoRa.Web.WidgetMovieInfoLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  defdelegate to_attr(v), to: Utils
  defdelegate extra_metadata(movie), to: Utils

  prop links, :any, default: []
  prop widget_title, :string, default: nil
  prop movie, :any, default: nil

  def mount(socket) do
    {:ok, socket}
  end

  def is_long_summary?(movie) do
    summary = e(movie, "summary", "")
    String.length(summary) >= 240
  end

  def get_summary(movie, show_all \\ false) do
    summary = e(movie, "summary", "")

    if show_all || !is_long_summary?(movie) do
      summary
    else
      String.slice(summary, 0, 240) <> "..."
    end
  end
end
