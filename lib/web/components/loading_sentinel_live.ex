# lib/bonfire/pan_do_ra/components/infinite_scroll_sentinel.ex
defmodule Bonfire.PanDoRa.Components.LoadingSentinelLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop loading, :boolean, default: false
  prop page, :integer, default: 0
  prop has_more, :boolean, default: false
end
