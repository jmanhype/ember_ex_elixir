defmodule EmberEx.XCS.JIT.Strategies.LLMStrategy do
  @moduledoc """
  LLM-specific JIT optimization strategy.
  
  This strategy is specialized for Language Model operations, focusing on:
  1. Optimizing prompt construction and template rendering
  2. Efficiently handling pre/post-processing while preserving stochastic LLM calls
  3. Partial caching of computation graphs around LLM nodes
  4. Parallel execution optimizations for batch requests
  """
  
  @behaviour EmberEx.XCS.JIT.Strategies.BaseStrategy
  use EmberEx.XCS.JIT.Strategies.JITFallbackMixin
  
  require Logger
  alias EmberEx.XCS.JIT.Cache
  alias EmberEx.XCS.JIT.Strategies.BaseStrategy
  alias EmberEx.XCS.Graph.LLMGraphBuilder
  
  # Define struct
  defstruct [:graph_builder, :llm_detector, :batch_size]
  
  # Define type for the struct
  @type t :: %__MODULE__{
    graph_builder: any(),
    llm_detector: module(),
    batch_size: pos_integer()
  }
  
  @doc """
  Initializes a new LLM strategy.
  
  ## Parameters
  
  - opts: Configuration options for the LLM strategy
    - `:batch_size` - Default batch size for parallel requests (default: 4)
    - `:llm_detector` - Module to detect LLM operators (default: EmberEx.XCS.JIT.LLMDetector)
  
  ## Returns
  
  A new LLMStrategy struct
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    # Set default batch size (could be configured)
    batch_size = Keyword.get(opts, :batch_size, 4)
    
    # Default LLM detector module (could be replaced with a more sophisticated detector)
    llm_detector = Keyword.get(
      opts, 
      :llm_detector, 
      EmberEx.XCS.JIT.LLMDetector
    )
    
    %__MODULE__{
      graph_builder: LLMGraphBuilder.new(batch_size: batch_size),
      llm_detector: llm_detector,
      batch_size: batch_size
    }
  end
  
  @impl BaseStrategy
  @doc """
  Scores a target to determine how suitable it is for LLM-specific JIT optimization.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to analyze
  - options: Optional parameters for scoring
  
  ## Returns
  
  Map with analysis results, including a score and rationale
  """
  @spec score_target(t(), any(), keyword()) :: %{score: number(), rationale: String.t(), features: map()}
  def score_target(%__MODULE__{llm_detector: detector} = _strategy, target, _options) do
    # Extract basic features
    features = BaseStrategy.extract_common_features(target)
    
    # First, determine if this is an LLM-related operator
    llm_score = if detector.is_llm_operator?(target) do
      100
    else
      # Look for LLM-related patterns
      pattern_score = detect_llm_patterns(target, features)
      
      # Check for prompt template features
      prompt_score = if has_prompt_template_features?(target, features) do
        40
      else
        0
      end
      
      # Check for post-processing features
      postproc_score = if has_postprocessing_features?(target, features) do
        30
      else
        0
      end
      
      pattern_score + prompt_score + postproc_score
    end
    
    # Calculate final score - we want this to be high only for LLM ops
    # and their directly related processing functions
    final_score = if llm_score > 30 do
      llm_score
    else
      0
    end
    
    rationale_items = []
    
    # Build rationale based on detected features
    rationale_items = if detector.is_llm_operator?(target) do
      ["Direct LLM operator detected" | rationale_items]
    else
      rationale_items
    end
    
    rationale_items = if has_prompt_template_features?(target, features) do
      ["Contains prompt template features" | rationale_items]
    else
      rationale_items
    end
    
    rationale_items = if has_postprocessing_features?(target, features) do
      ["Contains LLM post-processing patterns" | rationale_items]
    else
      rationale_items
    end
    
    # Final score and rationale
    %{
      score: final_score,
      rationale: Enum.join(rationale_items, "; "),
      features: Map.put(features, :llm_score, llm_score)
    }
  end
  
  @impl BaseStrategy
  @doc """
  Compiles a function or operator using LLM-specific JIT optimizations.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to compile
  - options: Compilation options including standard JIT options plus:
    - `:preserve_llm_call` - Always executes LLM call directly (default: true)
    - `:optimize_prompt` - Optimize prompt construction (default: true)
    - `:optimize_postprocess` - Optimize output processing (default: true)
    - `:parallel_requests` - Enable parallel batch processing (default: true)
  
  ## Returns
  
  Compiled function that behaves like the original but with LLM-specific optimizations
  """
  @spec compile(t(), any(), keyword()) :: function()
  def compile(%__MODULE__{llm_detector: detector, batch_size: default_batch_size} = strategy, target, options) do
    # Extract options with default values
    preserve_llm_call = Keyword.get(options, :preserve_llm_call, true)
    optimize_prompt = Keyword.get(options, :optimize_prompt, true)
    optimize_postprocess = Keyword.get(options, :optimize_postprocess, true)
    parallel_requests = Keyword.get(options, :parallel_requests, true)
    batch_size = Keyword.get(options, :batch_size, default_batch_size)
    
    # Standard JIT options
    _sample_input = Keyword.get(options, :sample_input)
    force_trace = Keyword.get(options, :force_trace, false)
    recursive = Keyword.get(options, :recursive, true)
    preserve_stochasticity = Keyword.get(options, :preserve_stochasticity, true)
    _cache_module = BaseStrategy.get_cache(Keyword.get(options, :cache))
    
    # Create a closure that will handle the JIT compilation and execution
    fn inputs when is_map(inputs) ->
      # Check if this is a batch request (inputs with multiple items)
      is_batch = is_batch_request?(inputs)
      
      # Handle batch requests with parallelization if enabled
      if is_batch and parallel_requests do
        handle_batch_request(strategy, target, inputs, batch_size, options)
      else
        # For single requests, apply LLM-specific optimizations
        
        # For direct LLM call operators, we may want to preserve the original call
        is_llm_op = detector.is_llm_operator?(target)
        
        if is_llm_op and preserve_llm_call do
          # Just execute the LLM call directly to preserve stochasticity
          execute_original(target, inputs)
        else
          # Apply partial graph optimizations by detecting LLM boundaries
          
          # For everything else, we can build an optimized graph
          # that preserves stochastic components
          
          # First, check if we can reuse a cached graph
          graph_signature = compute_graph_signature(target, inputs)
          
          # Try to get cached graph if not forcing trace
          graph = if force_trace, do: nil, else: Cache.get_with_state(target, graph_signature)
          
          if graph != nil do
            # Execute cached graph
            try do
              EmberEx.XCS.JIT.ExecutionUtils.execute_compiled_graph(graph, inputs, target)
            rescue
              e ->
                Logger.warning("Error executing LLM graph: #{inspect(e)}. Falling back to direct execution.")
                build_and_execute_llm_graph(strategy, target, inputs, graph_signature, recursive, optimize_prompt, optimize_postprocess, preserve_stochasticity)
            end
          else
            # Build and execute optimized LLM graph
            build_and_execute_llm_graph(strategy, target, inputs, graph_signature, recursive, optimize_prompt, optimize_postprocess, preserve_stochasticity)
          end
        end
      end
    end
  end
  
  # Private helper functions
  
  # Detects if target has LLM-related patterns (prompt formatting, token counting, etc.)
  defp detect_llm_patterns(target, features) do
    base_score = 0
    
    # Look for LLM-related keywords in function or module name
    name_str = cond do
      is_atom(target) -> to_string(target)
      is_function(target) -> inspect(target)
      true -> ""
    end
    
    name_patterns = [
      ~r/llm/i,
      ~r/language_model/i,
      ~r/prompt/i,
      ~r/chat/i,
      ~r/completion/i,
      ~r/token/i,
      ~r/embedding/i
    ]
    
    name_score = if Enum.any?(name_patterns, fn pattern -> 
      String.match?(name_str, pattern) 
    end) do
      20
    else
      0
    end
    
    # Give extra points if it's a known function type that often works with LLMs
    function_score = cond do
      features.is_class && features.has_call_method -> 10
      features.is_function -> 5
      true -> 0
    end
    
    base_score + name_score + function_score
  end
  
  # Detects if target has features related to prompt templates
  defp has_prompt_template_features?(target, features) do
    # This is a simple heuristic detection and could be made more sophisticated
    
    # Check if it's a module with template-related function names
    if is_atom(target) do
      prompt_functions = [
        :format_prompt,
        :render_template,
        :prepare_prompt,
        :build_prompt,
        :generate_prompt
      ]
      
      Enum.any?(prompt_functions, fn func ->
        function_exported?(target, func, 1) || function_exported?(target, func, 2)
      end)
    else
      # For functions, check if naming suggests prompt handling
      func_str = inspect(target)
      
      String.contains?(func_str, "prompt") || 
      String.contains?(func_str, "template") ||
      String.contains?(func_str, "format")
    end
  end
  
  # Detects if target has features related to LLM output post-processing
  defp has_postprocessing_features?(target, features) do
    # Check if it's a module with post-processing function names
    if is_atom(target) do
      postproc_functions = [
        :process_response,
        :parse_completion,
        :extract_response,
        :parse_json,
        :postprocess
      ]
      
      Enum.any?(postproc_functions, fn func ->
        function_exported?(target, func, 1) || function_exported?(target, func, 2)
      end)
    else
      # For functions, check if naming suggests post-processing
      func_str = inspect(target)
      
      String.contains?(func_str, "process") || 
      String.contains?(func_str, "parse") ||
      String.contains?(func_str, "extract") ||
      String.contains?(func_str, "response")
    end
  end
  
  # Determines if inputs represent a batch request
  defp is_batch_request?(inputs) do
    # Check for common batch patterns in input
    cond do
      # Direct batch field
      Map.has_key?(inputs, :batch) -> true
      
      # Array of inputs
      Map.has_key?(inputs, :inputs) && is_list(inputs.inputs) && length(inputs.inputs) > 1 -> true
      
      # Common batch field names
      Map.has_key?(inputs, :requests) || Map.has_key?(inputs, :prompts) || Map.has_key?(inputs, :batch_inputs) -> true
      
      # Default: not a batch
      true -> false
    end
  end
  
  # Handles parallel processing of batch requests
  defp handle_batch_request(strategy, target, batch_inputs, batch_size, options) do
    # Extract the list of individual inputs
    individual_inputs = extract_batch_items(batch_inputs)
    
    # Process in parallel batches
    results = individual_inputs
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      # Process each batch in parallel
      batch
      |> Task.async_stream(
        fn input -> 
          # Create individual input map
          single_input = prepare_single_input(input, batch_inputs)
          
          # Execute with LLM optimization but disable parallel to avoid recursion
          opts = Keyword.put(options, :parallel_requests, false)
          optimized_fn = compile(strategy, target, opts)
          optimized_fn.(single_input)
        end,
        timeout: 60_000  # 60 second timeout
      )
      |> Enum.map(fn {:ok, result} -> result end)
    end)
    
    # Combine results based on the expected output format
    combine_batch_results(results, batch_inputs)
  end
  
  # Extracts individual items from a batch request
  defp extract_batch_items(batch_inputs) do
    cond do
      Map.has_key?(batch_inputs, :batch) -> 
        batch_inputs.batch
        
      Map.has_key?(batch_inputs, :inputs) -> 
        batch_inputs.inputs
        
      Map.has_key?(batch_inputs, :requests) -> 
        batch_inputs.requests
        
      Map.has_key?(batch_inputs, :prompts) -> 
        batch_inputs.prompts
        
      Map.has_key?(batch_inputs, :batch_inputs) -> 
        batch_inputs.batch_inputs
        
      true -> 
        # Fallback, treat the entire input as a single item
        [batch_inputs]
    end
  end
  
  # Prepares a single input from a batch item
  defp prepare_single_input(item, batch_inputs) do
    # Preserve any global settings from the batch request
    global_fields = Map.drop(
      batch_inputs, 
      [:batch, :inputs, :requests, :prompts, :batch_inputs]
    )
    
    # If item is a map, merge with globals; otherwise wrap it
    if is_map(item) do
      Map.merge(global_fields, item)
    else
      # Try to determine the appropriate key based on batch type
      item_key = cond do
        Map.has_key?(batch_inputs, :batch) -> :item
        Map.has_key?(batch_inputs, :inputs) -> :input
        Map.has_key?(batch_inputs, :requests) -> :request
        Map.has_key?(batch_inputs, :prompts) -> :prompt
        true -> :item
      end
      
      Map.put(global_fields, item_key, item)
    end
  end
  
  # Combines individual results into a batch response
  defp combine_batch_results(results, original_batch) do
    # Determine result format based on input format
    cond do
      Map.has_key?(original_batch, :batch) ->
        Map.put(original_batch, :results, results)
        
      Map.has_key?(original_batch, :inputs) ->
        Map.put(original_batch, :outputs, results)
        
      Map.has_key?(original_batch, :requests) ->
        Map.put(original_batch, :responses, results)
        
      Map.has_key?(original_batch, :prompts) ->
        Map.put(original_batch, :completions, results)
        
      Map.has_key?(original_batch, :batch_inputs) ->
        Map.put(original_batch, :batch_outputs, results)
        
      true ->
        # Just return the array of results
        %{results: results}
    end
  end
  
  # Computes a signature for partial graph caching
  defp compute_graph_signature(target, inputs) do
    # For LLM operations, we want to cache based on the structure and
    # prompt template, but not the specific content that would affect randomness
    
    # Extract structure of inputs without variable content
    structure = extract_structure_signature(inputs)
    
    # Create a combined signature
    {:llm_graph, target, structure}
  end
  
  # Extracts a stable structure signature without variable content
  defp extract_structure_signature(inputs) when is_map(inputs) do
    # Convert the map to a list of key-value pairs
    inputs
    |> Enum.map(fn {k, v} -> {k, extract_structure_signature(v)} end)
    |> Enum.sort()
  end
  
  defp extract_structure_signature(inputs) when is_list(inputs) do
    if Enum.empty?(inputs) do
      []
    else
      # For lists, we'll just take the type of the first item to represent structure
      # This is a simplification - a more robust approach would analyze all items
      [extract_structure_signature(hd(inputs))]
    end
  end
  
  defp extract_structure_signature(value) when is_binary(value) do
    # For strings, we don't include the content, just the fact it's a string
    # and a general length category to better match similar prompts
    size_category = cond do
      String.length(value) < 10 -> :tiny
      String.length(value) < 100 -> :small
      String.length(value) < 1000 -> :medium
      String.length(value) < 10000 -> :large
      true -> :xlarge
    end
    
    {:string, size_category}
  end
  
  defp extract_structure_signature(value) do
    # For other values, use their type as the signature
    cond do
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_atom(value) -> :atom
      is_pid(value) -> :pid
      is_reference(value) -> :reference
      is_function(value) -> :function
      is_tuple(value) -> :tuple
      true -> :unknown
    end
  end
  
  # Builds and executes an optimized LLM graph
  defp build_and_execute_llm_graph(strategy, target, inputs, graph_signature, recursive, optimize_prompt, optimize_postprocess, preserve_stochasticity) do
    # Record compilation start time for metrics
    compilation_start = :os.system_time(:millisecond) / 1000
    
    # Analyze the target to identify LLM call boundaries
    {llm_graph, llm_nodes} = analyze_llm_boundaries(strategy, target, inputs)
    
    # Build partial optimization graph preserving LLM calls
    {result, optimized_graph} = LLMGraphBuilder.build_graph(
      llm_graph,
      inputs,
      llm_nodes: llm_nodes,
      recursive: recursive,
      optimize_prompt: optimize_prompt,
      optimize_postprocess: optimize_postprocess,
      preserve_stochasticity: preserve_stochasticity
    )
    
    compilation_duration = :os.system_time(:millisecond) / 1000 - compilation_start
    Cache.record_compilation(target, compilation_duration)
    
    # Cache the compiled graph with LLM signature
    # Only cache if we're not preserving stochasticity entirely
    unless preserve_stochasticity do
      Cache.set_with_state(target, optimized_graph, graph_signature)
    end
    
    # Return the execution result
    result
  end
  
  # Analyzes target to identify LLM call boundaries for partial optimization
  defp analyze_llm_boundaries(strategy, target, inputs) do
    # This is where we'd perform sophisticated analysis to determine
    # which parts of the computation are LLM calls that should be preserved
    # and which parts can be optimized
    
    # For now, we'll use a simple approach that treats the whole target
    # as a graph and marks any detected LLM operations as boundaries
    
    # In a full implementation, we would:
    # 1. Trace execution to build a complete graph
    # 2. Analyze each node to determine if it's an LLM operation
    # 3. Mark LLM ops as boundaries that shouldn't be optimized
    
    # Placeholder - this would need actual implementation based on the framework
    {target, []}
  end
  
  # Default execution function for the original target
  defp execute_original(target, inputs) when is_atom(target) do
    # Handle module-based operators
    target.call(inputs)
  end
  
  defp execute_original(target, inputs) when is_function(target) do
    # Handle function operators
    target.(inputs)
  end
end
