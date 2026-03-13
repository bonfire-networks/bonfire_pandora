defmodule Bonfire.PanDoRa.Web.SearchLive do
  @moduledoc """
  Presentation component for archive search: form, active filter badges, results list.
  State and events are handled by SearchViewLive; filters are in the sidebar widget.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop term, :string
  prop current_user, :any
  prop filter_sections, :list, default: []
  prop active_filter_badges, :list, default: []
  prop selected_by_field, :map, default: %{}
  prop loading, :boolean, default: false
  prop page, :integer, default: 0
  prop has_more_items, :boolean, default: true
  prop current_count, :integer, default: 0
  prop pandora_token, :string, default: nil
  prop pandora_base_url, :string, default: nil
end
