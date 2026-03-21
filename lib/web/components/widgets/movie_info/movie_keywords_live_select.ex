defmodule Bonfire.PanDoRa.Web.MovieKeywordsLiveSelect do
  @moduledoc """
  LiveSelect for Pandora movie keywords: string options, free-text tags (`user_defined_options`),
  and option/tag slots that never call `Map` APIs on binary values (unlike the generic Bonfire integration).
  """
  use Bonfire.UI.Common.Web, :function_component

  def movie_keywords_live_select(assigns) do
    assigns =
      assigns
      |> Phoenix.Component.assign_new(:update_min_len, fn -> 1 end)
      |> Phoenix.Component.assign_new(:debounce, fn -> 200 end)
      |> Phoenix.Component.assign_new(:disabled, fn -> false end)
      |> Phoenix.Component.assign_new(:options, fn -> [] end)

    ~H"""
    <LiveSelect.live_select
      field={@form[@field]}
      mode={:tags}
      phx-target={@event_target}
      options={@options}
      value={@value}
      user_defined_options={true}
      allow_clear={true}
      keep_options_on_select={true}
      update_min_len={@update_min_len}
      debounce={@debounce}
      placeholder={@placeholder}
      disabled={@disabled}
      style={:daisyui}
      text_input_extra_class="input input-ghost bg-base-content/5 rounded-full w-full"
      container_extra_class="w-full flex flex-col"
      tag_class="badge badge-primary rounded-full badge-md gap-1.5 font-semibold"
      dropdown_extra_class="z-50 max-h-liveselect flex-nowrap border border-base-content/10 !bg-base-100 overflow-y-auto top-12"
      tags_container_class="flex flex-wrap gap-1.5"
      value_mapper={&keyword_value_mapper/1}
    >
      <:option :let={option}>
        <div class="flex p-0 gap-2 items-center">
          <p class="font-semibold text-base-content/70">{option.label}</p>
        </div>
      </:option>
      <:tag :let={option}>
        <div class="flex items-center gap-2">
          <p class="font-semibold text-sm">{option.label}</p>
        </div>
      </:tag>
    </LiveSelect.live_select>
    """
  end

  defp keyword_value_mapper(v) when is_binary(v), do: %{label: v, value: v}
  defp keyword_value_mapper(v), do: v
end
