defmodule Bonfire.PanDoRa.PaginationContext do
  @doc """
  Convert page/per_page to range parameters
  """
  def to_range(page, per_page) do
    start_index = page * per_page
    [start_index, start_index + per_page - 1]
  end

  @doc """
  Check if we have more items based on returned results
  """
  def has_more?(items, per_page) when is_list(items) do
    length(items) >= per_page
  end
end
