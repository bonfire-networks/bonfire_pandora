defmodule Bonfire.PanDoRa.Web.WidgetMovieInfoLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop links, :any, default: []
  prop widget_title, :string, default: nil
  prop movie, :any, default: nil
end
