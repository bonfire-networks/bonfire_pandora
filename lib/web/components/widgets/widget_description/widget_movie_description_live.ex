defmodule Bonfire.PanDoRa.Web.WidgetMovieDescriptionLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop links, :any, default: []
  prop widget_title, :string, default: nil
  prop movie, :map, required: true

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
