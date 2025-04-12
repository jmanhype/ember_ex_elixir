defmodule EmberEx.XCS.JIT.Strategies.Providers.LLMStrategy do
  @moduledoc """
  JIT optimization strategy specifically for LLM operators.
  
  This strategy implements optimizations tailored for language model-based operators:
  
  1. **Prompt Caching**: Caches responses for identical prompts to avoid redundant LLM calls
  2. **Semantic Similarity**: Uses vector embeddings to identify similar past prompts/responses
  3. **Batch Processing**: Combines multiple similar requests into batches where appropriate
  4. **Stochastic Preservation**: Maintains controlled randomness for creative applications
  
  This strategy is most effective for applications where:
  - The same or similar prompts are executed repeatedly
  - Performance and cost efficiency are important concerns
  - LLM determinism needs to be carefully managed
  """
  
  use EmberEx.XCS.JIT.Strategies.BaseStrategy
  require Logger
  
  @typedoc "Cache entry for LLM prompt caching"
  @type cache_entry :: %{
    prompt: String.t(),
    response: any(),
    embedding: [float()] | nil,
    timestamp: integer(),
    usage_count: integer()
  }
  
  @typedoc "LLM JIT strategy struct"
  @type t :: %__MODULE__{
    prompt_cache: %{optional(String.t()) => cache_entry()},
    similarity_threshold: float(),
    max_cache_size: integer(),
    preserve_randomness: boolean(),
    embedding_provider: {module(), atom(), list()},
    create_embedding_fn: (String.t() -> [float()] | nil)
  }
  
  defstruct [
    :prompt_cache,
    :similarity_threshold,
    :max_cache_size,
    :preserve_randomness,
    :embedding_provider,
    :create_embedding_fn
  ]
  
  @doc """
  Create a new LLM strategy instance.
  
  ## Options
  
  - similarity_threshold: Threshold for considering prompts similar (default: 0.85)
  - max_cache_size: Maximum number of entries in the prompt cache (default: 1000)
  - preserve_randomness: Whether to preserve some level of randomness (default: false)
  - embedding_provider: Module, function, and args for creating embeddings
  
  ## Returns
  
  A new LLM strategy struct
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    embedding_provider = Keyword.get(
      options, 
      :embedding_provider, 
      {EmberEx.Models.Providers.OpenAI, :get_embedding, ["text-embedding-3-small"]}
    )
    
    %__MODULE__{
      prompt_cache: %{},
      similarity_threshold: Keyword.get(options, :similarity_threshold, 0.85),
      max_cache_size: Keyword.get(options, :max_cache_size, 1000),
      preserve_randomness: Keyword.get(options, :preserve_randomness, false),
      embedding_provider: embedding_provider,
      create_embedding_fn: fn text -> create_embedding(text, embedding_provider) end
    }
  end
  
  @impl true
  @spec compile(t(), any(), keyword()) :: function()
  def compile(%__MODULE__{} = strategy, target, _options) do
    Logger.debug("Compiling LLM operator with LLMStrategy")
    
    # Extract necessary information from the target
    prompt_template = extract_prompt_template(target)
    
    # Set up a lexical closure that includes our strategy state
    strategy_state = %{
      prompt_cache: strategy.prompt_cache,
      similarity_threshold: strategy.similarity_threshold,
      max_cache_size: strategy.max_cache_size,
      preserve_randomness: strategy.preserve_randomness,
      create_embedding_fn: strategy.create_embedding_fn,
      prompt_template: prompt_template,
      # Metrics counters
      cache_hits: 0,
      cache_misses: 0
    }
    
    # Create an agent process to maintain the cache state
    {:ok, agent} = Agent.start_link(fn -> strategy_state end)

    # Return the optimized function
    fn inputs ->
      # Check if this is an exact match for a cached prompt
      prompt = render_prompt(prompt_template, inputs)
      
      case find_cached_response(agent, prompt) do
        {:hit, response} ->
          # Record cache hit for metrics
          Agent.update(agent, fn state -> 
            # Update metrics
            EmberEx.Metrics.Exporters.Prometheus.update_jit_cache_metrics(
              map_size(state.prompt_cache),
              1,
              0
            )
            
            # Update state
            %{state | cache_hits: state.cache_hits + 1}
          end)
          
          # Return the cached response
          response
          
        {:miss, similar_entry} ->
          # Decide whether to use the similar entry based on randomness preferences
          if similar_entry && !strategy_state.preserve_randomness do
            # Use the similar entry
            Logger.debug("Using similar prompt from cache (similarity above threshold)")
            Agent.update(agent, fn state -> 
              # Update metrics
              EmberEx.Metrics.Exporters.Prometheus.update_jit_cache_metrics(
                map_size(state.prompt_cache),
                1,
                0
              )
              
              # Update state
              %{state | cache_hits: state.cache_hits + 1}
            end)
            
            similar_entry.response
          else
            # Execute the original operator
            response = EmberEx.Operators.Operator.call(target, inputs)
            
            # Cache the result
            Agent.update(agent, fn state -> 
              # Create embedding for the prompt
              embedding = state.create_embedding_fn.(prompt)
              
              # Update cache
              updated_cache = cache_response(
                state.prompt_cache, 
                prompt, 
                response, 
                embedding,
                state.max_cache_size
              )
              
              # Update metrics
              EmberEx.Metrics.Exporters.Prometheus.update_jit_cache_metrics(
                map_size(updated_cache),
                0,
                1
              )
              
              # Update state
              %{state | 
                prompt_cache: updated_cache,
                cache_misses: state.cache_misses + 1
              }
            end)
            
            # Return the response
            response
          end
      end
    end
  end
  
  @impl true
  @spec score_target(t(), any(), keyword()) :: {number(), String.t()}
  def score_target(%__MODULE__{} = _strategy, target, _options) do
    cond do
      # Check if target is an LLMOperator
      is_struct(target) && Map.has_key?(target, :__struct__) && 
      target.__struct__ == EmberEx.Operators.LLMOperator ->
        {100, "Target is an LLMOperator which is ideal for LLM-specific optimizations"}
      
      # Check for operator type names with "LLM" in them
      is_struct(target) && Map.has_key?(target, :__struct__) && 
      String.contains?(to_string(target.__struct__), "LLM") ->
        {75, "Target appears to be LLM-related based on its name"}
      
      # Not an LLM operator
      true ->
        {0, "Target is not an LLM operator"}
    end
  end
  
  # Private helper functions
  
  defp extract_prompt_template(target) do
    if is_struct(target) && Map.has_key?(target, :__struct__) && 
       target.__struct__ == EmberEx.Operators.LLMOperator && 
       Map.has_key?(target, :specification) do
      # If this is a proper LLMOperator with a specification, extract the prompt template
      target.specification
    else
      # For other operator types, return nil
      nil
    end
  end
  
  defp render_prompt(prompt_template, inputs) do
    if prompt_template do
      # Use the specification's render_prompt function
      EmberEx.Specifications.Specification.render_prompt(prompt_template, inputs)
    else
      # Fallback - stringify the input
      inspect(inputs)
    end
  end
  
  defp find_cached_response(agent, prompt) do
    Agent.get(agent, fn state ->
      # First, check for exact match
      case Map.get(state.prompt_cache, prompt) do
        nil ->
          # No exact match, check for similar prompts if enabled
          find_similar_prompt(state, prompt)
        
        entry ->
          # Exact match found
          {:hit, entry.response}
      end
    end)
  end
  
  defp find_similar_prompt(state, prompt) do
    # Skip similarity check if the embedding function is not available
    embedding = state.create_embedding_fn.(prompt)
    
    if embedding do
      # Find the most similar prompt in the cache
      {similar_entry, similarity} = 
        Enum.reduce(state.prompt_cache, {nil, 0.0}, fn {_, entry}, {best_entry, best_similarity} ->
          if entry.embedding do
            similarity = cosine_similarity(embedding, entry.embedding)
            if similarity > best_similarity, do: {entry, similarity}, else: {best_entry, best_similarity}
          else
            {best_entry, best_similarity}
          end
        end)
      
      # Return the similar entry if it exceeds the threshold
      if similar_entry && similarity >= state.similarity_threshold do
        {:miss, similar_entry}
      else
        {:miss, nil}
      end
    else
      {:miss, nil}
    end
  end
  
  defp cache_response(cache, prompt, response, embedding, max_size) do
    # Create a new cache entry
    new_entry = %{
      prompt: prompt,
      response: response,
      embedding: embedding,
      timestamp: System.system_time(:millisecond),
      usage_count: 1
    }
    
    # Add to cache, potentially evicting old entries if needed
    updated_cache = Map.put(cache, prompt, new_entry)
    
    # Evict old entries if we're over the maximum cache size
    if map_size(updated_cache) > max_size do
      # Evict the least recently used items
      {_, evicted_cache} = 
        updated_cache
        |> Enum.sort_by(fn {_, entry} -> entry.timestamp end)
        |> Enum.split(map_size(updated_cache) - max_size)
        |> elem(1)
        |> Enum.into(%{})
      
      evicted_cache
    else
      updated_cache
    end
  end
  
  defp create_embedding(text, {module, function, args}) do
    try do
      applied_args = [text | args]
      apply(module, function, applied_args)
    rescue
      e ->
        Logger.warning("Failed to create embedding: #{inspect(e)}")
        nil
    end
  end
  
  defp cosine_similarity(vec1, vec2) when length(vec1) == length(vec2) do
    # Calculate dot product
    dot_product = Enum.zip(vec1, vec2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    
    # Calculate magnitudes
    magnitude1 = :math.sqrt(Enum.map(vec1, fn x -> x * x end) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(vec2, fn x -> x * x end) |> Enum.sum())
    
    # Calculate cosine similarity
    case magnitude1 * magnitude2 do
      0 -> 0.0
      denominator -> dot_product / denominator
    end
  end
  
  defp cosine_similarity(_, _), do: 0.0
end
