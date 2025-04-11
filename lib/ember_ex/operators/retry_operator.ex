defmodule EmberEx.Operators.RetryOperator do
  @moduledoc """
  An operator that retries execution until success or max attempts.
  
  The RetryOperator wraps another operator and attempts to execute it
  multiple times until it succeeds or reaches a maximum number of attempts.
  This is useful for handling transient failures in LLM calls or other
  operations that may occasionally fail.
  
  Features:
  * Configurable maximum attempts and retry delay
  * Exponential backoff with jitter for retry timing
  * Selective retry based on error type
  * Detailed error tracking and reporting
  * Customizable retry conditions
  """
  
  use EmberEx.Operators.BaseOperator
  
  require Logger
  
  @typedoc "Error information tracking structure"
  @type error_info :: %{
    attempt: pos_integer(),
    error: Exception.t(),
    timestamp: DateTime.t(),
    stacktrace: list()
  }
  
  @typedoc "RetryOperator struct type"
  @type t :: %__MODULE__{
    operator: EmberEx.Operators.Operator.t(),
    max_attempts: pos_integer(),
    retry_delay_ms: non_neg_integer(),
    should_retry_fn: (Exception.t() -> boolean()),
    backoff_type: :linear | :exponential | :fibonacci,
    jitter: boolean(),
    error_details: boolean()
  }
  
  defstruct [
    :operator,
    :max_attempts,
    :retry_delay_ms,
    :should_retry_fn,
    :backoff_type,
    :jitter,
    :error_details
  ]
  
  @doc """
  Create a new RetryOperator with the given parameters.
  
  ## Parameters
  
  - operator: The operator to retry
  - opts: Keyword list of options
    - max_attempts: Maximum number of attempts (default: 3)
    - retry_delay_ms: Delay between retries in milliseconds (default: 1000)
    - should_retry_fn: Function that determines if an error should trigger a retry (default: retry all errors)
    - backoff_type: Type of backoff strategy to use (:linear, :exponential, or :fibonacci, default: :exponential)
    - jitter: Whether to add randomized jitter to retry delays (default: true)
    - error_details: Whether to include detailed error information in the result (default: true)
  
  ## Returns
  
  A new RetryOperator struct
  
  ## Examples
  
      iex> # Retry LLM calls up to 5 times with exponential backoff
      iex> retry_op = EmberEx.Operators.RetryOperator.new(
      ...>   llm_operator,
      ...>   max_attempts: 5,
      ...>   retry_delay_ms: 1000,
      ...>   should_retry_fn: fn error -> 
      ...>     String.contains?(inspect(error), "rate limit") 
      ...>   end
      ...> )
      
      iex> # Use linear backoff with no jitter for predictable retries
      iex> retry_op = EmberEx.Operators.RetryOperator.new(
      ...>   api_operator,
      ...>   backoff_type: :linear,
      ...>   jitter: false
      ...> )
  """
  @spec new(EmberEx.Operators.Operator.t(), keyword()) :: t()
  def new(operator, opts \\ []) do
    %__MODULE__{
      operator: operator,
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, 1000),
      should_retry_fn: Keyword.get(opts, :should_retry_fn, fn _ -> true end),
      backoff_type: Keyword.get(opts, :backoff_type, :exponential),
      jitter: Keyword.get(opts, :jitter, true),
      error_details: Keyword.get(opts, :error_details, true)
    }
  end
  
  @doc """
  Process inputs by attempting to execute the wrapped operator with retries.
  
  ## Parameters
  
  - operator: The RetryOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  The output from the wrapped operator if successful
  
  ## Raises
  
  - RuntimeError: If all retry attempts fail
  """
  @impl true
  def forward(operator, inputs) do
    # We'll track the attempts and errors via a process dictionary item
    # to ensure they're preserved across function calls
    Process.put(:retry_attempt_count, 1)
    Process.put(:retry_errors, [])
    
    # Call the recursive retry function
    result = attempt_with_retry(operator, inputs)
    
    # Get the final attempt count and errors
    attempts = Process.get(:retry_attempt_count)
    errors = Process.get(:retry_errors) || []
    
    # Add retry information to the result if it's a map
    case result do
      %{} -> 
        result = Map.put(result, :attempts, attempts)
        
        # Add detailed error information if requested
        if operator.error_details && length(errors) > 0 do
          Map.put(result, :retry_errors, errors)
        else
          result
        end
      other -> other # Return as is if not a map
    end
  end
  
  # Helper function for recursive retry logic
  defp attempt_with_retry(operator, inputs) do
    # Get the current attempt count
    attempt = Process.get(:retry_attempt_count)
    errors = Process.get(:retry_errors) || []
    
    try do
      # Attempt to execute the wrapped operator
      result = EmberEx.Operators.Operator.call(operator.operator, inputs)
      
      # Success - return the result directly
      result
    rescue
      error ->
        # Track error information
        error_info = %{
          attempt: attempt,
          error: error,
          timestamp: DateTime.utc_now(),
          stacktrace: __STACKTRACE__
        }
        
        # Update the errors list
        Process.put(:retry_errors, [error_info | errors])
        
        # Check if we should retry and have attempts remaining
        if attempt < operator.max_attempts && operator.should_retry_fn.(error) do
          # Log the retry attempt
          Logger.warning("Retry attempt #{attempt}/#{operator.max_attempts} failed: #{inspect(error)}")
          
          # Wait before retrying with appropriate backoff strategy
          delay = calculate_delay(operator.retry_delay_ms, attempt, operator.backoff_type, operator.jitter)
          Process.sleep(delay)
          
          # Increment the attempt counter for the next try
          Process.put(:retry_attempt_count, attempt + 1)
          
          # Retry
          attempt_with_retry(operator, inputs)
        else
          # Re-raise the error if we've exhausted retries or shouldn't retry
          reraise error, __STACKTRACE__
        end
    end
  end
  
  # Calculate delay based on the backoff strategy
  @spec calculate_delay(non_neg_integer(), pos_integer(), atom(), boolean()) :: non_neg_integer()
  defp calculate_delay(base_delay, attempt, backoff_type, add_jitter?) do
    delay = case backoff_type do
      :linear -> 
        # Linear backoff: base_delay * attempt
        base_delay * attempt
        
      :fibonacci -> 
        # Fibonacci backoff: base_delay * fibonacci(attempt)
        base_delay * fibonacci(attempt + 1)
        
      _exponential -> 
        # Exponential backoff: base_delay * 2^(attempt-1)
        base_delay * :math.pow(2, attempt - 1)
    end
    
    # Add jitter if requested (between 0.8x and 1.2x)
    if add_jitter? do
      jitter_factor = 0.8 + :rand.uniform() * 0.4
      round(delay * jitter_factor)
    else
      round(delay)
    end
  end
  
  # Fibonacci sequence calculation for fibonacci backoff
  @spec fibonacci(non_neg_integer()) :: non_neg_integer()
  defp fibonacci(0), do: 0
  defp fibonacci(1), do: 1
  defp fibonacci(n) when n > 1 do
    # Use process dictionary for memoization
    case Process.get({:fib, n}) do
      nil -> 
        result = fibonacci(n - 1) + fibonacci(n - 2)
        Process.put({:fib, n}, result)
        result
      result -> 
        result
    end
  end
  
  @doc """
  Get the specification for this operator.
  
  The RetryOperator inherits its specification from the wrapped operator.
  
  ## Returns
  
  The specification of the wrapped operator
  """
  @spec specification() :: EmberEx.Specifications.Specification.t() | nil
  def specification do
    # In a real implementation, we would return the specification
    # of the wrapped operator
    nil
  end
  
  @doc """
  Creates a new retry operator with predefined configurations for common error types.
  
  ## Parameters
  
  - operator: The operator to retry
  - error_type: The type of error to handle (:rate_limit, :timeout, :network, :all)
  - opts: Additional options to pass to new/2
  
  ## Returns
  
  A new RetryOperator configured for the specified error type
  
  ## Examples
  
      iex> retry_op = EmberEx.Operators.RetryOperator.for_error_type(llm_operator, :rate_limit)
  """
  @spec for_error_type(EmberEx.Operators.Operator.t(), atom(), keyword()) :: t()
  def for_error_type(operator, error_type, opts \\ []) do
    {should_retry_fn, default_opts} = case error_type do
      :rate_limit ->
        {fn error -> String.contains?(inspect(error), ["rate limit", "Rate limit", "429"]) end,
         [max_attempts: 5, retry_delay_ms: 2000, backoff_type: :exponential]}
         
      :timeout ->
        {fn error -> String.contains?(inspect(error), ["timeout", "timed out", "408"]) end,
         [max_attempts: 3, retry_delay_ms: 5000, backoff_type: :linear]}
         
      :network ->
        {fn error -> 
           error_str = inspect(error)
           String.contains?(error_str, ["network", "connection", "unreachable", "DNS"]) 
         end,
         [max_attempts: 4, retry_delay_ms: 1000, backoff_type: :fibonacci]}
         
      _all ->
        {fn _ -> true end,
         [max_attempts: 3, retry_delay_ms: 1000, backoff_type: :exponential]}
    end
    
    # Merge default options with user options, giving precedence to user options
    merged_opts = Keyword.merge(default_opts, opts)
    
    # Only set should_retry_fn if not explicitly provided in opts
    final_opts = if Keyword.has_key?(opts, :should_retry_fn) do
      merged_opts
    else
      Keyword.put(merged_opts, :should_retry_fn, should_retry_fn)
    end
    
    new(operator, final_opts)
  end
end
