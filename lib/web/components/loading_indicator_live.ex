defmodule Bonfire.PanDoRa.Components.LoadingIndicator do
  use Bonfire.UI.Common.Web, :stateless_component

  def render(assigns) do
    ~F"""
    <div class="animate-pulse flex space-x-4 mt-4">
      <div class="flex-1 space-y-6 py-1">
        <div class="h-2 bg-slate-200 rounded" />
        <div class="space-y-3">
          <div class="grid grid-cols-3 gap-4">
            <div class="h-2 bg-slate-200 rounded col-span-2" />
            <div class="h-2 bg-slate-200 rounded col-span-1" />
          </div>
          <div class="h-2 bg-slate-200 rounded" />
        </div>
      </div>
    </div>
    """
  end
end
