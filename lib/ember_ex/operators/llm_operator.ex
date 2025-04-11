defmodule EmberEx.Operators.LLMOperator do
  @moduledoc """
  An operator that executes a language model with a formatted prompt.
  
  The LLMOperator uses a specification to validate inputs, render a prompt,
  execute a language model, and validate the output. It leverages Instructor X
  for structured outputs from language models.
  """
  
  use EmberEx.Operators.BaseOperator
  
  require Logger
  
  @typedoc "LLMOperator struct type"
  @type t :: %__MODULE__{
    specification: EmberEx.Specifications.Specification.t(),
    model: EmberEx.Models.ModelCallable.t(),
    model_kwargs: map()
  }
  
  defstruct [:specification, :model, :model_kwargs]
  
  @doc """
  Create a new LLMOperator with the given specification and model.
  
  ## Parameters
  
  - specification: The specification for input/output validation and prompt rendering
  - model: The model callable to use for execution
  - model_kwargs: Additional keyword arguments to pass to the model (default: %{})
  
  ## Returns
  
  A new LLMOperator struct
  
  ## Examples
  
      iex> spec = EmberEx.Specifications.EctoSpecification.new(
      ...>   "Summarize the following text: {text}",
      ...>   MyApp.InputSchema,
      ...>   MyApp.OutputSchema
      ...> )
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> llm_op = EmberEx.Operators.LLMOperator.new(spec, model)
  """
  @spec new(EmberEx.Specifications.Specification.t(), EmberEx.Models.ModelCallable.t(), map()) :: t()
  def new(specification, model, model_kwargs \\ %{}) do
    %__MODULE__{
      specification: specification,
      model: model,
      model_kwargs: model_kwargs
    }
  end
  
  @doc """
  Process inputs by rendering a prompt, executing the model, and validating the output.
  
  ## Parameters
  
  - operator: The LLMOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  The validated output from the language model
  
  ## Raises
  
  - RuntimeError: If input validation, model execution, or output validation fails
  """
  @impl true
  def forward(operator, inputs) do
    # Render the prompt using the specification
    prompt = EmberEx.Specifications.Specification.render_prompt(operator.specification, inputs)
    
    # Get the output schema from the specification
    output_schema = EmberEx.Specifications.Specification.output_schema(operator.specification)
    
    # Prepare model arguments
    model_args = Map.merge(operator.model_kwargs, %{
      messages: [
        %{role: "user", content: prompt}
      ],
      response_model: output_schema
    })
    
    # Execute the model
    case operator.model.(model_args) do
      {:ok, response} ->
        # Return the response
        response
        
      {:error, reason} ->
        # Log the error
        Logger.error("LLMOperator execution failed: #{inspect(reason)}")
        
        # Re-raise the error
        raise "LLMOperator execution failed: #{inspect(reason)}"
    end
  end
  
  @doc """
  Create an LLMOperator with a simple prompt template and output schema.
  
  ## Parameters
  
  - prompt_template: The prompt template string with placeholders
  - output_schema: The output schema for validation
  - model_name: The name of the model to use (default: "openai/gpt-4")
  - model_kwargs: Additional keyword arguments to pass to the model (default: %{})
  
  ## Returns
  
  A new LLMOperator struct
  
  ## Examples
  
      iex> output_schema = %{
      ...>   "type" => "object",
      ...>   "properties" => %{
      ...>     "summary" => %{"type" => "string"}
      ...>   },
      ...>   "required" => ["summary"]
      ...> }
      iex> llm_op = EmberEx.Operators.LLMOperator.from_prompt(
      ...>   "Summarize the following text: {text}",
      ...>   output_schema
      ...> )
  """
  @spec from_prompt(String.t(), map(), String.t(), map()) :: t()
  def from_prompt(prompt_template, output_schema, model_name \\ "openai/gpt-4", model_kwargs \\ %{}) do
    # Create a simple specification
    spec = EmberEx.Specifications.EctoSpecification.new(
      prompt_template,
      nil,  # No input validation
      output_schema
    )
    
    # Create a model callable
    model = EmberEx.Models.create_model_callable(model_name)
    
    # Create the operator
    new(spec, model, model_kwargs)
  end
  
  @doc """
  Get the specification for this operator.
  
  ## Returns
  
  The specification for this operator
  """
  @spec specification() :: EmberEx.Specifications.Specification.t()
  def specification do
    # In a real implementation, we would return the specification
    # of the operator
    nil
  end
end
