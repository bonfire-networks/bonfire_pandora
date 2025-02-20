defmodule Bonfire.PanDoRa.Components.CategoryFilterLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias PanDoRa.API.Client

  prop category_title, :string, default: "Category"
  prop category_list, :list, default: []
  prop selected_list, :list, default: []
  prop loading, :boolean, default: false
  prop filter_event, :string, required: true
  prop item_display_key, :string, default: "name"
  prop count_display_key, :string, default: "items"
end
