defmodule EmberEx.Operators.MapReduceOperator do
  @moduledoc """
  An operator that applies a map function to inputs, processes in parallel, and reduces results.
  
  The MapReduceOperator implements the MapReduce pattern for distributed processing,
  where inputs are mapped to intermediate results, processed in parallel, and then
  reduced to a final output.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "MapReduceOperator struct type"
  @type t :: %__MODULE__{
    map_fn: (any() -> any()),
    processing_operator: EmberEx.Operators.Operator.t(),
    reduce_fn: (list(any()) -> any()),
    max_concurrency: pos_integer() | :infinity
  }
  
  defstruct [:map_fn, :processing_operator, :reduce_fn, :max_concurrency]
  
  @doc """
  Create a new MapReduceOperator.
  
  ## Parameters
  
  - map_fn: Function to map inputs to intermediate values
  - processing_operator: Operator to process each mapped value
  - reduce_fn: Function to reduce processed results to a final output
  - max_concurrency: Maximum number of concurrent processing tasks (default: System scheduler_cores * 2)
  
  ## Returns
  
  A new MapReduceOperator struct
  
  ## Examples
  
      iex> # Create a MapReduce that processes multiple documents in parallel
      iex> map_fn = fn documents -> Enum.map(documents, &%{text: &1}) end
      iex> reduce_fn = fn results -> %{summary: Enum.map_join(results, " ", &Map.get(&1, :key_points)) end
      iex> map_reduce = EmberEx.Operators.MapReduceOperator.new(
      ...>   map_fn,
      ...>   text_analyzer, 
      ...>   reduce_fn
      ...> )
  """
  @spec new(
    (any() -> any()),
    EmberEx.Operators.Operator.t(),
    (list(any()) -> any()),
    pos_integer() | :infinity
  ) :: t()
  def new(map_fn, processing_operator, reduce_fn, max_concurrency \\ nil) do
    # Default max_concurrency to scheduler_cores * 2 if not specified
    default_concurrency = System.schedulers_online() * 2
    
    %__MODULE__{
      map_fn: map_fn,
      processing_operator: processing_operator,
      reduce_fn: reduce_fn,
      max_concurrency: max_concurrency || default_concurrency
    }
  end
  
  @doc """
  Create a new MapReduceOperator with a name.
  
  ## Parameters
  
  - name: The name of the operator
  - map_fn: Function to map inputs to intermediate values
  - processing_operator: Operator to process each mapped value
  - reduce_fn: Function to reduce processed results to a final output
  - max_concurrency: Maximum number of concurrent processing tasks
  
  ## Returns
  
  A new MapReduceOperator struct with the specified name
  """
  @spec new_with_name(
    String.t(),
    (any() -> any()),
    EmberEx.Operators.Operator.t(),
    (list(any()) -> any()),
    pos_integer() | :infinity
  ) :: t()
  def new_with_name(name, map_fn, processing_operator, reduce_fn, max_concurrency \\ nil) do
    new(map_fn, processing_operator, reduce_fn, max_concurrency)
    |> EmberEx.Operators.BaseOperator.set_name(name)
  end
  
  @doc """
  Process inputs using the MapReduce pattern.
  
  ## Parameters
  
  - operator: The MapReduceOperator struct
  - inputs: Input value to be mapped, processed, and reduced
  
  ## Returns
  
  The reduced result
  
  ## Examples
  
      iex> map_reduce = EmberEx.Operators.MapReduceOperator.new(
      ...>   &String.split/1,
      ...>   length_counter,
      ...>   &Enum.sum/1
      ...> )
      iex> EmberEx.Operators.Operator.call(map_reduce, "Hello world foo bar")
      16
  """
  @impl true
  def forward(operator, inputs) do
    # Map inputs to intermediate values
    intermediate_values = operator.map_fn.(inputs)
    
    # Process intermediate values in parallel with max concurrency
    processed_results = 
      intermediate_values
      |> Task.async_stream(
        fn value -> 
          EmberEx.Operators.Operator.call(operator.processing_operator, value)
        end,
        max_concurrency: operator.max_concurrency,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Reduce processed results to final output
    operator.reduce_fn.(processed_results)
  end
  
  @doc """
  Create a MapReduceOperator for batch processing a collection.
  
  This is a convenience function for creating a MapReduceOperator that
  processes a collection of items in parallel.
  
  ## Parameters
  
  - processing_operator: Operator to process each item
  - reduce_fn: Function to combine results (defaults to returning the list of results)
  - max_concurrency: Maximum number of concurrent tasks
  
  ## Returns
  
  A new MapReduceOperator configured for batch processing
  
  ## Examples
  
      iex> batch_processor = EmberEx.Operators.MapReduceOperator.batch(
      ...>   text_analyzer,
      ...>   &%{results: &1}
      ...> )
      iex> EmberEx.Operators.Operator.call(batch_processor, ["doc1", "doc2", "doc3"])
      %{results: [%{analysis: "doc1 analysis"}, %{analysis: "doc2 analysis"}, %{analysis: "doc3 analysis"}]}
  """
  @spec batch(
    EmberEx.Operators.Operator.t(),
    (list(any()) -> any()) | nil,
    pos_integer() | :infinity
  ) :: t()
  def batch(processing_operator, reduce_fn \\ &(&1), max_concurrency \\ nil) do
    # For batch processing, the map function is identity (process each item as is)
    map_fn = &(&1)
    
    new(map_fn, processing_operator, reduce_fn, max_concurrency)
  end
  
  @doc """
  Create a MapReduceOperator for chunked processing of a large input.
  
  This is useful for processing large inputs that need to be broken down
  into smaller chunks for efficient parallel processing.
  
  ## Parameters
  
  - chunk_fn: Function to split input into chunks
  - processing_operator: Operator to process each chunk
  - reduce_fn: Function to combine results
  - max_concurrency: Maximum number of concurrent tasks
  
  ## Returns
  
  A new MapReduceOperator configured for chunked processing
  
  ## Examples
  
      iex> # Process a large document by splitting it into paragraphs
      iex> chunked_processor = EmberEx.Operators.MapReduceOperator.chunked(
      ...>   &String.split(&1, "\\n\\n"),
      ...>   paragraph_analyzer,
      ...>   &%{paragraphs: &1}
      ...> )
      iex> EmberEx.Operators.Operator.call(chunked_processor, long_document)
      %{paragraphs: [analysis1, analysis2, ...]}
  """
  @spec chunked(
    (any() -> list(any())),
    EmberEx.Operators.Operator.t(),
    (list(any()) -> any()),
    pos_integer() | :infinity
  ) :: t()
  def chunked(chunk_fn, processing_operator, reduce_fn, max_concurrency \\ nil) do
    new(chunk_fn, processing_operator, reduce_fn, max_concurrency)
  end
end
