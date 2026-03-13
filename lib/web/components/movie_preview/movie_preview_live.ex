defmodule Bonfire.PanDoRa.Components.MoviePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  prop movie_id, :string, required: true
  # nil when used inside a LiveView (events routed to LV); pass @myself when inside a LiveComponent
  prop event_target, :any, default: nil
  prop movie, :map, required: true
  prop image_src, :string, default: nil
  prop media_url, :string, default: nil

  defdelegate to_attr(v), to: Bonfire.PanDoRa.Utils
  defdelegate extra_metadata(movie), to: Bonfire.PanDoRa.Utils
end
