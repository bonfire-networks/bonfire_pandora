defmodule Bonfire.PanDoRa.Components.MoviePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils
  prop movie_id, :string, required: true
  prop event_target, :string, required: true
  prop movie, :map, required: true
  # New prop to support the optimized image approach
  prop image_src, :string, default: nil
end
