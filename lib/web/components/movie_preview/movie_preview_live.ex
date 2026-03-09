defmodule Bonfire.PanDoRa.Components.MoviePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  prop movie_id, :string, required: true
  # nil when used inside a LiveView (events routed to LV); pass @myself when inside a LiveComponent
  prop event_target, :any, default: nil
  prop movie, :map, required: true
  prop image_src, :string, default: nil

  # Known fields handled explicitly in the template; the rest are rendered as generic badges
  @known_fields ~w(id title item_id public_id stable_id order duration director image)

  def known_fields, do: @known_fields

  @doc """
  Converts any Pandora field value to a safe string for HTML attributes.
  Lists are joined; nil becomes "".
  """
  def to_attr(nil), do: ""
  def to_attr(list) when is_list(list), do: list |> Enum.filter(&is_binary/1) |> Enum.join(", ")
  def to_attr(v), do: to_string(v)

  @doc "Returns extra metadata fields from a movie map (fields not in @known_fields with non-nil values)."
  def extra_metadata(movie) when is_map(movie) do
    movie
    |> Enum.reject(fn {k, v} -> k in @known_fields or is_nil(v) or v == "" end)
    |> Enum.map(fn {k, v} -> {k, to_attr(v)} end)
    |> Enum.reject(fn {_k, v} -> v == "" end)
  end

  def extra_metadata(_), do: []
end
