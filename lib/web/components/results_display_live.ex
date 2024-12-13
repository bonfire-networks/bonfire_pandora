defmodule Bonfire.PanDoRa.Components.ResultsDisplay do
  use Bonfire.UI.Common.Web, :stateless_component

  prop results, :map, required: true
  prop search_term, :string, required: true

  def render(assigns) do
    ~F"""
    <div class="mt-4">
      <h2 class="text-xl font-bold mb-2">{l("Results")}</h2>
      {#if is_map(@results) and map_size(@results) > 0}
        <div class="border rounded-lg overflow-hidden">
          <p :for={r <- e(@results, "items", nil)} class="p-4 overflow-x-auto">{e(r, "title", nil)}</p>
        </div>
      {#else}
        <p class="">{l("No results found")}</p>
      {/if}
    </div>
    """
  end
end
