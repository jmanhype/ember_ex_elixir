defmodule EmberEx.Operators.MapOperator do
  @moduledoc """
  Applies a function to each input.
  
  This operator takes an input value, applies a function to it,
  and returns the result as an output value.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "MapOperator struct type"
  @type t :: %__MODULE__{
    function: (any() -> any()),
    input_key: atom() | String.t(),
    output_key: atom() | String.t()
  }
  
  defstruct [:function, :input_key, :output_key]
  
  @doc """
  Create a new MapOperator with just a function.
  
  ## Parameters
  
  - function: The function to apply to the input
  
  ## Returns
  
  A new MapOperator struct
  
  ## Examples
  
      iex> operator = EmberEx.Operators.MapOperator.new(&String.upcase/1)
      iex> EmberEx.Operators.Operator.call(operator, "hello")
      "HELLO"
  """
  @spec new((any() -> any())) :: t()
  def new(function) when is_function(function) do
    %__MODULE__{
      function: function,
      input_key: nil,  # Will use the entire input
      output_key: nil  # Will return the entire output
    }
  end
  
  @doc """
  Create a new MapOperator.
  
  ## Parameters
  
  - function: The function to apply to the input
  - input_key: The key to extract from the input map
  - output_key: The key to use for the output map
  
  ## Returns
  
  A new MapOperator struct
  
  ## Examples
  
      iex> operator = EmberEx.Operators.MapOperator.new(&String.upcase/1, :text, :uppercase_text)
      iex> EmberEx.Operators.Operator.call(operator, %{text: "hello"})
      %{uppercase_text: "HELLO"}
  """
  @spec new((any() -> any()), atom() | String.t(), atom() | String.t()) :: t()
  def new(function, input_key, output_key) do
    %__MODULE__{
      function: function,
      input_key: input_key,
      output_key: output_key
    }
  end
  
  @doc """
  Create a new MapOperator with a name and optional specification.
  
  This version is used when you need to name the operator for use in a graph
  but don't need to specify input/output keys.
  
  ## Parameters
  
  - name: The name of the operator (used for identification in graphs)
  - spec: Optional specification for validation (can be nil)
  - function: The function to apply to the input
  
  ## Returns
  
  A new MapOperator struct
  
  ## Examples
  
      iex> operator = EmberEx.Operators.MapOperator.new_with_name("uppercase", nil, &String.upcase/1)
      iex> EmberEx.Operators.Operator.call(operator, "hello")
      "HELLO"
  """
  @spec new_with_name(String.t(), any(), (any() -> any())) :: t()
  def new_with_name(name, spec, function) when is_binary(name) do
    %__MODULE__{
      function: function,
      input_key: nil,  # Will use the entire input
      output_key: nil  # Will return the entire output
    }
    |> EmberEx.Operators.BaseOperator.set_name(name)
    |> EmberEx.Operators.BaseOperator.set_spec(spec)
  end
  
  @doc """
  Process inputs and return outputs.
  
  ## Parameters
  
  - operator: The MapOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  A map of output values
  """
  @impl true
  def forward(%__MODULE__{} = operator, inputs) do
    # Handle the case where input_key is nil (use entire inputs)
    input_value = if operator.input_key do
      Map.get(inputs, operator.input_key)
    else
      inputs
    end
    
    # Apply the function to the input
    output_value = operator.function.(input_value)
    
    # Handle the case where output_key is nil (return raw output)
    if operator.output_key do
      %{operator.output_key => output_value}
    else
      output_value
    end
  end
end

defmodule EmberEx.Operators.SequenceOperator do
  @moduledoc """
  Executes a sequence of operators.
  
  This operator takes a list of operators and executes them in sequence,
  passing the accumulated outputs from one operator to the next.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "SequenceOperator struct type"
  @type t :: %__MODULE__{
    operators: list(EmberEx.Operators.Operator.t())
  }
  
  defstruct [:operators]
  
  @doc """
  Create a new SequenceOperator.
  
  ## Parameters
  
  - operators: A list of operators to execute in sequence
  
  ## Returns
  
  A new SequenceOperator struct
  
  ## Examples
  
      iex> op1 = EmberEx.Operators.MapOperator.new(&String.upcase/1, :text, :uppercase)
      iex> op2 = EmberEx.Operators.MapOperator.new(&String.reverse/1, :uppercase, :reversed)
      iex> seq = EmberEx.Operators.SequenceOperator.new([op1, op2])
      iex> EmberEx.Operators.Operator.call(seq, %{text: "hello"})
      %{text: "hello", uppercase: "HELLO", reversed: "OLLEH"}
  """
  @spec new(list(EmberEx.Operators.Operator.t())) :: t()
  def new(operators) do
    %__MODULE__{operators: operators}
  end
  
  @doc """
  Process inputs and return outputs.
  
  ## Parameters
  
  - operator: The SequenceOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  A map of output values
  """
  @impl true
  def forward(%__MODULE__{} = operator, inputs) do
    Enum.reduce(operator.operators, inputs, fn op, acc ->
      outputs = EmberEx.Operators.Operator.call(op, acc)
      Map.merge(acc, outputs)
    end)
  end
end

defmodule EmberEx.Operators.ParallelOperator do
  @moduledoc """
  Executes multiple operators in parallel.
  
  This operator takes a list of operators and executes them in parallel,
  then merges their outputs.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "ParallelOperator struct type"
  @type t :: %__MODULE__{
    operators: list(EmberEx.Operators.Operator.t())
  }
  
  defstruct [:operators]
  
  @doc """
  Create a new ParallelOperator.
  
  ## Parameters
  
  - operators: A list of operators to execute in parallel
  
  ## Returns
  
  A new ParallelOperator struct
  
  ## Examples
  
      iex> op1 = EmberEx.Operators.MapOperator.new(&String.upcase/1, :text, :uppercase)
      iex> op2 = EmberEx.Operators.MapOperator.new(&String.reverse/1, :text, :reversed)
      iex> parallel = EmberEx.Operators.ParallelOperator.new([op1, op2])
      iex> EmberEx.Operators.Operator.call(parallel, %{text: "hello"})
      %{text: "hello", uppercase: "HELLO", reversed: "olleh"}
  """
  @spec new(list(EmberEx.Operators.Operator.t())) :: t()
  def new(operators) do
    %__MODULE__{operators: operators}
  end
  
  @doc """
  Process inputs and return outputs.
  
  ## Parameters
  
  - operator: The ParallelOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  A map of output values
  """
  @impl true
  @doc """
  Executes all sub-operators in parallel and merges their results into the input map.
  Waits up to 20 seconds for all tasks to complete (increased timeout for slow MCP servers).

  ## Parameters
  - operator: The ParallelOperator struct
  - inputs: Input map to be processed

  ## Returns
  - Map with merged outputs from all sub-operators
  """
  @spec forward(t(), map()) :: map()
  @doc """
  Executes all sub-operators in parallel and merges their results into the input map.
  Waits up to 60 seconds for all tasks to complete (increased timeout for slow MCP servers).
  Logs before and after each task, and before merging results.
  """
  def forward(%__MODULE__{} = operator, inputs) do
    require Logger
    # Execute all operators in parallel with logging
    tasks = Enum.map(operator.operators, fn op ->
      Logger.debug("[ParallelOperator] Spawning task for operator: #{inspect(op)} with inputs: #{inspect(inputs)}")
      Task.async(fn ->
        result = EmberEx.Operators.Operator.call(op, inputs)
        Logger.debug("[ParallelOperator] Task result for operator #{inspect(op)}: #{inspect(result)}")
        result
      end)
    end)

    # Wait for all tasks to complete, up to 60 seconds
    results = Task.await_many(tasks, 60_000)
    Logger.debug("[ParallelOperator] All task results: #{inspect(results)}")

    # Merge all results with the original inputs
    Enum.reduce(results, inputs, &Map.merge/2)
  end
end
