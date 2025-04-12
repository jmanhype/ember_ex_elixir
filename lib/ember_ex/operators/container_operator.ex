defmodule EmberEx.Operators.ContainerOperator do
  @moduledoc """
  An operator that contains and manages a pipeline of operators.
  
  The ContainerOperator provides a way to encapsulate a sequence of operators
  as a single operator, enabling hierarchical composition and reuse.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "Input transformer function type"
  @type input_transformer :: (map() -> map())
  
  @typedoc "Output transformer function type"
  @type output_transformer :: (map() -> map())
  
  @typedoc "ContainerOperator struct type"
  @type t :: %__MODULE__{
    operators: list(EmberEx.Operators.Operator.t()),
    input_transformers: %{optional(EmberEx.Operators.Operator.t()) => input_transformer()},
    output_transformers: %{optional(EmberEx.Operators.Operator.t()) => output_transformer()}
  }
  
  defstruct [:operators, :input_transformers, :output_transformers]
  
  @doc """
  Create a new ContainerOperator.
  
  ## Parameters
  
  - operators: A list of operators to execute in sequence
  - input_transformers: Optional map of functions to transform inputs for each operator
  - output_transformers: Optional map of functions to transform outputs from each operator
  
  ## Returns
  
  A new ContainerOperator struct
  
  ## Examples
  
      iex> # Create a pipeline that processes text through multiple steps
      iex> tokenizer = EmberEx.Operators.MapOperator.new(fn text -> %{tokens: String.split(text)} end)
      iex> counter = EmberEx.Operators.MapOperator.new(fn %{tokens: tokens} -> %{count: length(tokens)} end)
      iex> container = EmberEx.Operators.ContainerOperator.new([tokenizer, counter])
      iex> EmberEx.Operators.Operator.call(container, "Hello world")
      %{count: 2}
  """
  @spec new(
    list(EmberEx.Operators.Operator.t()),
    %{optional(EmberEx.Operators.Operator.t()) => input_transformer()},
    %{optional(EmberEx.Operators.Operator.t()) => output_transformer()}
  ) :: t()
  def new(operators, input_transformers \\ %{}, output_transformers \\ %{}) do
    %__MODULE__{
      operators: operators,
      input_transformers: input_transformers,
      output_transformers: output_transformers
    }
  end
  
  @doc """
  Create a new ContainerOperator with a name.
  
  ## Parameters
  
  - name: The name of the operator
  - operators: A list of operators to execute in sequence
  - input_transformers: Optional map of functions to transform inputs for each operator
  - output_transformers: Optional map of functions to transform outputs from each operator
  
  ## Returns
  
  A new ContainerOperator struct with the specified name
  """
  @spec new_with_name(
    String.t(),
    list(EmberEx.Operators.Operator.t()),
    %{optional(EmberEx.Operators.Operator.t()) => input_transformer()},
    %{optional(EmberEx.Operators.Operator.t()) => output_transformer()}
  ) :: t()
  def new_with_name(name, operators, input_transformers \\ %{}, output_transformers \\ %{}) do
    new(operators, input_transformers, output_transformers)
    |> EmberEx.Operators.BaseOperator.set_name(name)
  end
  
  @doc """
  Process inputs by executing operators in sequence.
  
  ## Parameters
  
  - operator: The ContainerOperator struct
  - inputs: A map of input values or direct input value
  
  ## Returns
  
  The output from the final operator in the sequence
  
  ## Examples
  
      iex> container = EmberEx.Operators.ContainerOperator.new([op1, op2, op3])
      iex> EmberEx.Operators.Operator.call(container, %{data: "input"})
      %{result: "processed"}
  """
  @impl true
  def forward(operator, inputs) do
    # Process operators in sequence, with optional transformations
    Enum.reduce(operator.operators, inputs, fn op, current_input ->
      # Apply input transformation if defined
      transformed_input = apply_transformation(
        current_input, 
        Map.get(operator.input_transformers, op),
        &identity/1
      )
      
      # Call the operator
      output = EmberEx.Operators.Operator.call(op, transformed_input)
      
      # Apply output transformation if defined
      apply_transformation(
        output,
        Map.get(operator.output_transformers, op),
        &identity/1
      )
    end)
  end
  
  @doc """
  Create a container with named transformations.
  
  This convenience function allows creating a container operator
  with transformations specified by operator names rather than
  operator instances.
  
  ## Parameters
  
  - operators: A list of {name, operator} tuples
  - input_transformers: Map of operator names to input transformer functions
  - output_transformers: Map of operator names to output transformer functions
  
  ## Returns
  
  A new ContainerOperator struct
  
  ## Examples
  
      iex> operators = [
      ...>   {:tokenize, tokenizer},
      ...>   {:count, counter},
      ...>   {:analyze, analyzer}
      ...> ]
      ...> input_transformers = %{
      ...>   analyze: fn input -> Map.put(input, :language, "en") end
      ...> }
      ...> container = EmberEx.Operators.ContainerOperator.named_pipeline(
      ...>   operators,
      ...>   input_transformers
      ...> )
  """
  @spec named_pipeline(
    list({atom(), EmberEx.Operators.Operator.t()}),
    %{optional(atom()) => input_transformer()},
    %{optional(atom()) => output_transformer()}
  ) :: t()
  def named_pipeline(operators, input_transformers \\ %{}, output_transformers \\ %{}) do
    # Extract operators from tuples
    operator_list = Enum.map(operators, fn {_name, op} -> op end)
    
    # Create mappings from operator instances to transformers
    op_map = Enum.into(operators, %{})
    
    input_trans_map = Enum.reduce(input_transformers, %{}, fn {name, trans_fn}, acc ->
      if op = op_map[name] do
        Map.put(acc, op, trans_fn)
      else
        acc
      end
    end)
    
    output_trans_map = Enum.reduce(output_transformers, %{}, fn {name, trans_fn}, acc ->
      if op = op_map[name] do
        Map.put(acc, op, trans_fn)
      else
        acc
      end
    end)
    
    new(operator_list, input_trans_map, output_trans_map)
  end
  
  @doc """
  Create a container that merges outputs from intermediate steps.
  
  This specialized container collects outputs from all operators
  and merges them into a single result map.
  
  ## Parameters
  
  - operators: A list of operators to execute in sequence
  - collect_keys: Optional list of keys to collect in the result
  
  ## Returns
  
  A new ContainerOperator struct configured to merge outputs
  
  ## Examples
  
      iex> container = EmberEx.Operators.ContainerOperator.collecting([op1, op2, op3])
      iex> EmberEx.Operators.Operator.call(container, "input")
      %{
      ...>   op1_result: "value1",
      ...>   op2_result: "value2", 
      ...>   op3_result: "value3"
      ...> }
  """
  @spec collecting(list(EmberEx.Operators.Operator.t()), list(atom()) | nil) :: t()
  def collecting(operators, collect_keys \\ nil) do
    # Create output transformers that merge results
    output_transformers = operators
    |> Enum.zip(1..length(operators))
    |> Enum.map(fn {op, index} ->
      # Define a function that merges this operator's output with the accumulated result
      transformer = fn output ->
        # If the output is a map, merge it
        # Otherwise, wrap it in a map with a key based on the operator's name or index
        case output do
          output when is_map(output) and is_nil(collect_keys) ->
            # Include all keys from the output
            output
            
          output when is_map(output) and is_list(collect_keys) ->
            # Include only specific keys from the output
            output
            |> Map.take(collect_keys)
            
          output ->
            # For non-map outputs, use the operator's name or a default key
            key = case EmberEx.Operators.BaseOperator.get_name(op) do
              nil -> :"step_#{index}_result"
              name -> String.to_atom("#{name}_result")
            end
            
            %{key => output}
        end
      end
      
      {op, transformer}
    end)
    |> Map.new()
    
    # Custom forward implementation that accumulates results
    forward_fn = fn operator, inputs ->
      # Process operators in sequence, accumulating outputs
      {_, final_result} = Enum.reduce(operator.operators, {inputs, %{}}, fn op, {current_input, acc_result} ->
        # Apply input transformation if defined
        transformed_input = apply_transformation(
          current_input,
          Map.get(operator.input_transformers, op),
          &identity/1
        )
        
        # Call the operator
        output = EmberEx.Operators.Operator.call(op, transformed_input)
        
        # Apply output transformation if defined
        transformed_output = apply_transformation(
          output,
          Map.get(operator.output_transformers, op),
          &identity/1
        )
        
        # Merge transformed output with accumulated result
        merged_result = if is_map(transformed_output) do
          Map.merge(acc_result, transformed_output)
        else
          key = case EmberEx.Operators.BaseOperator.get_name(op) do
            nil -> :result
            name -> String.to_atom("#{name}_result")
          end
          
          Map.put(acc_result, key, transformed_output)
        end
        
        # Pass output to next operator and update accumulated result
        {transformed_output, merged_result}
      end)
      
      final_result
    end
    
    operator = new(operators, %{}, output_transformers)
    
    # Override the forward function for this specific instance
    # This is a bit of a hack, but allows us to customize the behavior
    # without changing the core implementation
    Map.put(operator, :__forward_fn__, forward_fn)
  end
  
  # Helper functions
  
  defp apply_transformation(value, nil, default_fn), do: default_fn.(value)
  defp apply_transformation(value, transformer, _default_fn) when is_function(transformer), do: transformer.(value)
  
  defp identity(x), do: x
end
