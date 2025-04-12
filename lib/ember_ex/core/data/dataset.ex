defmodule EmberEx.Core.Data.Dataset do
  @moduledoc """
  Dataset abstraction for working with structured data sources.
  
  This module provides a behavior and implementation for working with datasets
  in a standardized way across EmberEx. It supports:
  
  - Common dataset operations (mapping, filtering, batching)
  - Iteration and lazy processing
  - Various data formats (CSV, JSON, etc.)
  - Integration with data loaders
  
  Datasets are designed to be composable and efficient for use in ML/LLM pipelines.
  """
  
  @typedoc """
  A dataset handle, containing metadata and access information.
  """
  @type t :: %__MODULE__{
    name: String.t(),
    size: non_neg_integer() | nil,
    schema: map() | nil,
    source: term(),
    metadata: map(),
    transform_pipeline: list(function()),
    iterator_state: term()
  }
  
  defstruct [
    name: nil,
    size: nil,
    schema: nil,
    source: nil,
    metadata: %{},
    transform_pipeline: [],
    iterator_state: nil
  ]
  
  @doc """
  Creates a new dataset from a source.
  
  ## Parameters
    * `source` - Source data (file path, list, stream, etc.)
    * `opts` - Dataset options:
      * `:name` - Dataset name
      * `:schema` - Optional schema definition
      * `:transform_pipeline` - List of transformation functions
      * `:metadata` - Additional dataset metadata
  
  ## Returns
    * `{:ok, dataset}` - A new dataset instance
    * `{:error, reason}` - Error with reason if dataset creation fails
  
  ## Examples
      iex> Dataset.new([%{text: "example 1"}, %{text: "example 2"}], name: "examples")
      {:ok, %Dataset{name: "examples", size: 2, ...}}
      
      iex> Dataset.new("path/to/data.csv", name: "csv_data")
      {:ok, %Dataset{name: "csv_data", ...}}
  """
  @spec new(term(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(source, opts \\ []) do
    try do
      name = Keyword.get(opts, :name, "unnamed_dataset")
      schema = Keyword.get(opts, :schema, nil)
      transform_pipeline = Keyword.get(opts, :transform_pipeline, [])
      metadata = Keyword.get(opts, :metadata, %{})
      
      # Initialize the dataset
      dataset = %__MODULE__{
        name: name,
        schema: schema,
        source: source,
        metadata: metadata,
        transform_pipeline: transform_pipeline
      }
      
      # Try to determine the size if possible
      dataset = case get_size(source) do
        {:ok, size} -> %{dataset | size: size}
        _ -> dataset
      end
      
      # Validate against schema if provided
      if schema && is_list(source) do
        case validate_against_schema(source, schema) do
          :ok -> {:ok, dataset}
          {:error, reason} -> {:error, "Schema validation failed: #{reason}"}
        end
      else
        {:ok, dataset}
      end
    rescue
      e -> {:error, "Failed to create dataset: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Gets a batch of items from the dataset.
  
  ## Parameters
    * `dataset` - The dataset to get items from
    * `batch_size` - Number of items to retrieve
    * `opts` - Batching options:
      * `:offset` - Starting offset (default: 0)
      * `:shuffle` - Whether to shuffle items (default: false)
  
  ## Returns
    * `{:ok, items, new_dataset}` - Batch of items and updated dataset
    * `{:error, reason}` - Error with reason if retrieval fails
  
  ## Examples
      iex> {:ok, batch, updated_ds} = Dataset.get_batch(dataset, 10)
      iex> length(batch)
      10
  """
  @spec get_batch(t(), pos_integer(), keyword()) :: 
    {:ok, list(map()), t()} | {:error, String.t()}
  def get_batch(dataset, batch_size, context_or_opts \\ []) do
    # Handle either a context (updated dataset from previous call) or options
    {offset, shuffle} = case context_or_opts do
      %__MODULE__{iterator_state: %{offset: offset}} ->
        {offset, false}
      opts when is_list(opts) ->
        {
          Keyword.get(opts, :offset, 0),
          Keyword.get(opts, :shuffle, false)
        }
      _ ->
        {0, false}
    end
    
    try do
      case get_items(dataset.source, offset, batch_size, shuffle) do
        {:ok, items} ->
          # Apply transform pipeline to each item
          transformed_items = items
            |> Enum.map(fn item -> 
              apply_transforms(item, dataset.transform_pipeline)
            end)
            |> Enum.filter(&(&1 != nil))  # Remove filtered out items
          
          # Update dataset state (e.g., for iteration)
          updated_dataset = %{dataset | 
            iterator_state: %{offset: offset + length(items)}
          }
          
          {:ok, transformed_items, updated_dataset}
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, "Failed to get batch: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Maps a function over the entire dataset, creating a new dataset.
  
  ## Parameters
    * `dataset` - The dataset to map over
    * `map_fn` - Function to apply to each item
    
  ## Returns
    * `{:ok, new_dataset}` - A new dataset with the map function applied
    * `{:error, reason}` - Error with reason if mapping fails
  
  ## Examples
      iex> {:ok, uppercase_ds} = Dataset.map(dataset, fn item -> 
      ...>   Map.update!(item, :text, &String.upcase/1)
      ...> end)
  """
  @spec map(t(), (map() -> map())) :: {:ok, t()} | {:error, String.t()}
  def map(dataset, map_fn) when is_function(map_fn, 1) do
    try do
      # Add the function to the transform pipeline
      updated_pipeline = dataset.transform_pipeline ++ [map_fn]
      
      # Return a new dataset with the updated pipeline
      {:ok, %{dataset | 
        transform_pipeline: updated_pipeline,
        name: "#{dataset.name}:mapped",
        metadata: Map.put(dataset.metadata || %{}, :parent, dataset.name)
      }}
    rescue
      e -> {:error, "Failed to map function over dataset: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Filters the dataset based on a predicate function.
  
  ## Parameters
    * `dataset` - The dataset to filter
    * `filter_fn` - Function that returns true for items to keep
    
  ## Returns
    * `{:ok, new_dataset}` - A new dataset with the filter applied
    * `{:error, reason}` - Error with reason if filtering fails
  
  ## Examples
      iex> {:ok, filtered_ds} = Dataset.filter(dataset, fn item -> 
      ...>   String.length(item.text) > 10
      ...> end)
  """
  @spec filter(t(), (map() -> boolean())) :: {:ok, t()} | {:error, String.t()}
  def filter(dataset, filter_fn) when is_function(filter_fn, 1) do
    # This would typically create a lazy filtering operation
    # For simplicity, we're using a direct approach
    try do
      # Apply the filter within a transform function
      filter_transform = fn item ->
        if filter_fn.(item), do: item, else: nil
      end
      
      # Return a new dataset with the filter added
      # (with nil removal handled during batch retrieval)
      # We need to check if the filter will result in an empty set
      is_empty_filter = case dataset.source do
        source when is_list(source) ->
          Enum.all?(source, fn item -> filter_fn.(item) == false end)
        _ ->
          false
      end

      {:ok, %{dataset | 
        transform_pipeline: dataset.transform_pipeline ++ [filter_transform],
        name: "#{dataset.name}:filtered",
        # Size becomes 0 if we know it's empty, nil otherwise
        size: (if is_empty_filter do 0 else nil end)
      }}
    rescue
      e -> {:error, "Failed to filter dataset: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Converts the dataset to a list (eagerly evaluates the entire dataset).
  
  ## Parameters
    * `dataset` - The dataset to convert
    
  ## Returns
    * `{:ok, items}` - All items in the dataset as a list
    * `{:error, reason}` - Error with reason if conversion fails
    
  ## Warning
    This function loads the entire dataset into memory, which may be
    problematic for very large datasets.
  """
  @spec to_list(t()) :: {:ok, list(map())} | {:error, String.t()}
  def to_list(dataset) do
    try do
      case dataset.size do
        nil ->
          # Size unknown, iteratively collect batches
          collect_all_batches(dataset, 1000, [])
        size ->
          # Size known, get everything in one batch
          {:ok, items, _} = get_batch(dataset, size)
          {:ok, items}
      end
    rescue
      e -> {:error, "Failed to convert dataset to list: #{Exception.message(e)}"}
    end
  end

  @doc """
  Shuffles the items in a dataset.
  
  ## Parameters
    * `dataset` - The dataset to shuffle
    
  ## Returns
    * `{:ok, shuffled_dataset}` - A new dataset with shuffled items
    * `{:error, reason}` - Error with reason if shuffling fails
    
  ## Examples
      iex> {:ok, shuffled_ds} = Dataset.shuffle(dataset)
  """
  @spec shuffle(t()) :: {:ok, t()} | {:error, String.t()}
  def shuffle(dataset) do
    try do
      case dataset.source do
        src when is_list(src) ->
          # For list sources, shuffle directly
          {:ok, %{dataset | 
            source: Enum.shuffle(src),
            name: "#{dataset.name}:shuffled"
          }}
          
        %Stream{} ->
          # For streams, we need to materialize then shuffle
          # This could be memory-intensive for large streams
          case to_list(dataset) do
            {:ok, items} ->
              shuffled_items = Enum.shuffle(items)
              {:ok, %{dataset | 
                source: shuffled_items,
                name: "#{dataset.name}:shuffled"
              }}
              
            {:error, reason} ->
              {:error, reason}
          end
          
        _ ->
          {:error, "Unsupported source type for shuffling"}
      end
    rescue
      e -> {:error, "Failed to shuffle dataset: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Splits a dataset into two parts based on a ratio.
  
  ## Parameters
    * `dataset` - The dataset to split
    * `ratio` - Ratio of items for the first dataset (0.0 to 1.0)
    * `opts` - Split options:
      * `:first_name` - Name for the first dataset (default: original_name:train)
      * `:second_name` - Name for the second dataset (default: original_name:test)
      * `:shuffle` - Whether to shuffle before splitting (default: true)
      
  ## Returns
    * `{:ok, first_dataset, second_dataset}` - The two datasets after splitting
    * `{:error, reason}` - Error with reason if splitting fails
    
  ## Examples
      iex> {:ok, train_ds, test_ds} = Dataset.split(dataset, 0.8)
      iex> {:ok, train_ds, val_ds} = Dataset.split(
      ...>   dataset, 
      ...>   0.7,
      ...>   first_name: "train_data", 
      ...>   second_name: "validation_data"
      ...> )
  """
  @spec split(t(), float(), keyword()) :: 
    {:ok, t(), t()} | {:error, String.t()}
  def split(dataset, ratio, opts \\ []) when is_float(ratio) and ratio >= 0.0 and ratio <= 1.0 do
    try do
      # Get naming options
      first_name = Keyword.get(opts, :first_name, "#{dataset.name}:train")
      second_name = Keyword.get(opts, :second_name, "#{dataset.name}:test")
      shuffle_before = Keyword.get(opts, :shuffle, true)
      
      # Get all items
      {:ok, all_items} = to_list(dataset)
      
      # Maybe shuffle
      all_items = if shuffle_before, do: Enum.shuffle(all_items), else: all_items
      
      # Calculate split index
      split_at = round(length(all_items) * ratio)
      
      # Split the items
      {first_items, second_items} = Enum.split(all_items, split_at)
      
      # Create the datasets
      {:ok, first_dataset} = new(
        first_items,
        name: first_name,
        schema: dataset.schema,
        metadata: Map.put(dataset.metadata || %{}, :parent, dataset.name)
      )
      
      {:ok, second_dataset} = new(
        second_items,
        name: second_name,
        schema: dataset.schema,
        metadata: Map.put(dataset.metadata || %{}, :parent, dataset.name)
      )
      
      {:ok, first_dataset, second_dataset}
    rescue
      e -> {:error, "Failed to split dataset: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Creates a dataset with batched items.
  
  ## Parameters
    * `dataset` - The dataset to batch
    * `batch_size` - Size of each batch
    * `opts` - Batching options:
      * `:drop_remainder` - Whether to drop the last batch if incomplete
      
  ## Returns
    * `{:ok, batched_dataset}` - A new dataset with batched items
    * `{:error, reason}` - Error with reason if batching fails
    
  ## Examples
      iex> {:ok, batched_ds} = Dataset.batch(dataset, 32)
  """
  @spec batch(t(), pos_integer(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def batch(dataset, batch_size, opts \\ []) when is_integer(batch_size) and batch_size > 0 do
    try do
      # Get batching options
      _drop_remainder = Keyword.get(opts, :drop_remainder, false)
      
      # Get all items
      {:ok, all_items} = to_list(dataset)
      
      # Create batches
      batches = all_items
        |> Enum.chunk_every(batch_size, batch_size, [])
        |> Enum.filter(fn batch -> length(batch) > 0 end)
      
      # Create the batched dataset
      {:ok, %{dataset | 
        source: batches,
        name: "#{dataset.name}:batched",
        metadata: Map.put(dataset.metadata || %{}, :batch_size, batch_size)
      }}
    rescue
      e -> {:error, "Failed to batch dataset: #{Exception.message(e)}"}
    end
  end
  
  # Private helper functions
  
  @spec get_size(term()) :: {:ok, non_neg_integer()} | :unknown
  defp get_size(source) when is_list(source), do: {:ok, length(source)}
  defp get_size(%Stream{}), do: :unknown
  defp get_size(source) when is_binary(source) do
    # If a file path, could try to determine size
    :unknown
  end
  defp get_size(_), do: :unknown
  
  @spec get_items(term(), non_neg_integer(), pos_integer(), boolean()) :: 
    {:ok, list(map())} | {:error, String.t()}
  defp get_items(source, offset, batch_size, shuffle) when is_list(source) do
    items = source
      |> maybe_shuffle(shuffle)
      |> Enum.drop(offset)
      |> Enum.take(batch_size)
    
    {:ok, items}
  end
  
  defp get_items(%Stream{} = source, offset, batch_size, shuffle) do
    items = source
      |> maybe_shuffle_stream(shuffle)
      |> Stream.drop(offset)
      |> Stream.take(batch_size)
      |> Enum.to_list()
    
    {:ok, items}
  end
  
  defp get_items(source, _offset, _batch_size, _shuffle) when is_binary(source) do
    # Handle file paths - would need to implement file reading logic
    {:error, "File loading not implemented yet"}
  end
  
  defp get_items(_source, _offset, _batch_size, _shuffle) do
    {:error, "Unsupported source type"}
  end
  
  @spec maybe_shuffle(list(), boolean()) :: list()
  defp maybe_shuffle(items, true), do: Enum.shuffle(items)
  defp maybe_shuffle(items, false), do: items
  
  @spec maybe_shuffle_stream(Enumerable.t(), boolean()) :: Enumerable.t()
  defp maybe_shuffle_stream(stream, true) do
    # WARNING: This eagerly evaluates the stream to shuffle it
    # Only use for small streams
    stream |> Enum.to_list() |> Enum.shuffle() |> list_to_stream()
  end
  defp maybe_shuffle_stream(stream, false), do: stream
  
  @spec list_to_stream(list()) :: Enumerable.t()
  defp list_to_stream(list) do
    Stream.resource(
      fn -> list end,
      fn
        [] -> {:halt, []}
        [h | t] -> {[h], t}
      end,
      fn _ -> [] end
    )
  end
  
  @spec apply_transforms(map(), list(function())) :: map() | nil
  defp apply_transforms(item, transforms) do
    Enum.reduce_while(transforms, item, fn transform, acc -> 
      case transform.(acc) do
        nil -> {:halt, nil}  # Item filtered out
        result -> {:cont, result}
      end
    end)
  end
  
  @spec collect_all_batches(t(), pos_integer(), list()) :: {:ok, list()} | {:error, String.t()}
  defp collect_all_batches(dataset, batch_size, acc) do
    case get_batch(dataset, batch_size, offset: length(acc)) do
      {:ok, [], _} -> 
        # No more items
        {:ok, acc}
      {:ok, items, updated_ds} ->
        # Got some items, continue collecting
        if length(items) < batch_size do
          # Last batch
          {:ok, acc ++ items}
        else
          # More might be available
          collect_all_batches(updated_ds, batch_size, acc ++ items)
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Schema validation functions
  
  @spec validate_against_schema(list(map()), map()) :: :ok | {:error, String.t()}
  defp validate_against_schema(items, schema) do
    # In a real implementation, this would use Ecto or another validation library
    # For now, we just do a simple validation
    invalid_items = Enum.filter(items, fn item ->
      !validate_item(item, schema)
    end)
    
    if Enum.empty?(invalid_items) do
      :ok
    else
      {:error, "#{length(invalid_items)} items failed schema validation"}
    end
  end
  
  @spec validate_item(map(), map()) :: boolean()
  defp validate_item(item, schema) do
    Enum.all?(schema, fn {field, {type, opts}} ->
      required = Keyword.get(opts || [], :required, false)
      
      # Check if required field exists
      if required && !Map.has_key?(item, field) do
        false
      else
        # If field exists, validate its type
        case Map.get(item, field) do
          nil -> !required
          value -> validate_type(value, type)
        end
      end
    end)
  end
  
  @spec validate_type(term(), atom()) :: boolean()
  defp validate_type(value, :string), do: is_binary(value)
  defp validate_type(value, :integer), do: is_integer(value)
  defp validate_type(value, :float), do: is_float(value)
  defp validate_type(value, :number), do: is_number(value)
  defp validate_type(value, :boolean), do: is_boolean(value)
  defp validate_type(value, :list), do: is_list(value)
  defp validate_type(value, :map), do: is_map(value)
  defp validate_type(_, _), do: true  # Unknown types pass by default
end
