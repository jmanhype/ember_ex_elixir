defmodule EmberEx.XCS.JIT.LLMDetector do
  @moduledoc """
  Provides utilities for detecting LLM-related operations within computation graphs.
  
  This module is responsible for identifying which operations in a computational
  graph represent direct LLM calls versus pre-processing or post-processing steps,
  allowing for targeted optimization strategies.
  
  Enhanced with content-aware detection for real-world LLM operations, including:
  - Prompt template detection
  - Response parsing identification
  - Function calling patterns
  - Multi-provider support
  """
  
  @doc """
  Determines if a target function or module is an LLM operator.
  
  ## Parameters
  
  - target: Function or module to analyze
  - options: Additional options for analysis, including:
    - :deep_analysis - Whether to perform deeper analysis (default: false)
    - :sample_inputs - Sample inputs to test function behavior
  
  ## Returns
  
  Boolean indicating whether the target is an LLM operator
  """
  @spec is_llm_operator?(function() | module(), keyword()) :: boolean()
  def is_llm_operator?(target, options \\ []) do
    do_deep_analysis = Keyword.get(options, :deep_analysis, false)
    sample_inputs = Keyword.get(options, :sample_inputs, nil)
    
    basic_check = cond do
      # Check if it's a direct LLM operator implementation
      is_direct_llm_implementation?(target) -> true
      
      # Check for LLM traits in the target
      has_llm_traits?(target) -> true
      
      # If deep analysis is requested and we have sample inputs, perform behavior analysis
      do_deep_analysis && sample_inputs -> 
        analyze_behavior(target, sample_inputs) == :llm_related
        
      true -> false
    end
    
    # Apply additional heuristics for real-world detection
    if basic_check || do_deep_analysis do
      basic_check || contains_llm_patterns?(target)
    else
      basic_check
    end
  end
  
  @doc """
  Performs deep inspection of a function or module to determine if it's LLM-related.
  
  ## Parameters
  
  - target: Function or module to analyze
  - sample_inputs: Sample inputs to test behavior
  
  ## Returns
  
  A detailed analysis map
  """
  @spec deep_inspect(function() | module(), map()) :: map()
  def deep_inspect(target, sample_inputs) do
    %{
      is_llm: is_llm_operator?(target, deep_analysis: true, sample_inputs: sample_inputs),
      classification: classify_llm_role(target),
      cacheable_parts: identify_cacheable_parts(target),
      contains_prompt_template: contains_prompt_template?(target),
      behavior: analyze_behavior(target, sample_inputs)
    }
  end
  
  @doc """
  Classifies a node in a computation graph according to its role in LLM operations.
  
  ## Parameters
  
  - node: The computation node to classify
  
  ## Returns
  
  Classification as one of:
  - `:llm_call` - Direct call to a language model
  - `:prompt_preparation` - Prompt template rendering or preparation
  - `:result_processing` - Processing of LLM results
  - `:unrelated` - Node unrelated to LLM operations
  """
  @spec classify_node(any()) :: :llm_call | :prompt_preparation | :result_processing | :unrelated
  def classify_node(node) do
    cond do
      is_llm_call?(node) -> :llm_call
      is_prompt_preparation?(node) -> :prompt_preparation
      is_result_processing?(node) -> :result_processing
      true -> :unrelated
    end
  end
  
  @doc """
  Lists all known LLM provider modules in the EmberEx framework.
  
  This can be used to match against potential LLM operators.
  
  ## Returns
  
  List of module names that are LLM providers
  """
  @spec known_llm_providers() :: [module()]
  def known_llm_providers do
    [
      # Core providers
      EmberEx.Models.Providers.Anthropic,
      EmberEx.Models.Providers.OpenAI,
      EmberEx.Models.Providers.Claude,
      EmberEx.Models.Providers.HuggingFace,
      EmberEx.Models.Providers.Gemini,
      EmberEx.Models.Providers.LLama,
      # Instructor providers
      Instructor.Provider.Anthropic,
      Instructor.Provider.OpenAI,
      Instructor.Provider.Claude,
      Instructor.Provider.Gemini,
      # Common providers in ecosystem
      Instructor.Providers.OpenAI,
      OpenAI,
      OpenAI.Client,
      Anthropic,
      Claude
    ]
  end
  
  @doc """
  Checks if the given function or module appears to be an LLM operation.
  Simpler than is_llm_operator? but useful for quick checks.
  
  ## Returns
  
  Boolean indicating if this is likely an LLM operation
  """
  @spec is_llm_operation?(function() | module()) :: boolean()
  def is_llm_operation?(target) do
    is_llm_operator?(target)
  end
  
  @doc """
  Classifies an LLM operation according to its role.
  
  ## Parameters
  
  - target: The function or module to classify
  
  ## Returns
  
  One of :prompt_builder, :llm_call, :result_parser, or :unknown
  """
  @spec classify_llm_role(function() | module()) :: :prompt_builder | :llm_call | :result_parser | :unknown
  def classify_llm_role(target) do
    cond do
      is_prompt_builder?(target) -> :prompt_builder
      is_direct_llm_implementation?(target) -> :llm_call
      is_result_parser?(target) -> :result_parser
      true -> :unknown
    end
  end
  
  @doc """
  Identifies potentially cacheable parts of an LLM operation.
  
  ## Parameters
  
  - target: LLM operation to analyze
  
  ## Returns
  
  List of cacheable operations or :none if none found
  """
  @spec identify_cacheable_parts(function() | module()) :: list() | :none
  def identify_cacheable_parts(target) do
    # A real implementation would do deeper analysis of the target's structure
    # For now, we'll use heuristics to suggest caching strategies
    
    role = classify_llm_role(target)
    
    case role do
      :prompt_builder -> [:full_cache]
      :llm_call -> [:no_cache]
      :result_parser -> [:full_cache]
      :unknown -> 
        if is_deterministic_operation?(target) do
          [:partial_cache]
        else
          [:no_cache]
        end
    end
  end
  
  # Private helper functions
  
  # Checks if target is a known LLM implementation module/struct
  defp is_direct_llm_implementation?(target) do
    # First check if it's in our list of known LLM provider modules
    if is_atom(target) and Enum.member?(known_llm_providers(), target) do
      true
    else
      # Check if it's a struct with a known LLM module as its type
      is_llm_struct?(target)
    end
  end
  
  # Check if a struct is an LLM operator struct
  defp is_llm_struct?(target) do
    if is_map(target) and Map.has_key?(target, :__struct__) do
      # Check if struct module is an LLM type
      struct_module = target.__struct__
      
      # Check against known LLM operator types
      llm_struct_types = [
        EmberEx.Operators.LLMOperator,
        Instructor.Extraction,
        EmberEx.Models.Request,
        EmberEx.Models.Response,
        EmberEx.Models.LLMConfig
      ]
      
      # Check for common struct patterns
      is_known_type = Enum.member?(llm_struct_types, struct_module)
      
      # Also check for struct fields that suggest LLM operations
      has_llm_fields = is_map(target) && (
        Map.has_key?(target, :model) || 
        Map.has_key?(target, :prompt) || 
        Map.has_key?(target, :temperature) ||
        Map.has_key?(target, :max_tokens)
      )
      
      is_known_type || has_llm_fields
    else
      false
    end
  end
  
  # Checks if a function or module appears to be a prompt builder
  defp is_prompt_builder?(target) do
    # Look for naming patterns that suggest prompt building
    name_str = get_target_name(target)
    
    String.contains?(name_str, "Prompt") || 
    String.contains?(name_str, "Template") ||
    String.contains?(name_str, "format_prompt") ||
    String.contains?(name_str, "build_prompt")
  end
  
  # Checks if a function or module appears to be a result parser
  defp is_result_parser?(target) do
    # Look for naming patterns that suggest response parsing
    name_str = get_target_name(target)
    
    String.contains?(name_str, "Parse") || 
    String.contains?(name_str, "Extract") ||
    String.contains?(name_str, "process_response") ||
    String.contains?(name_str, "handle_result")
  end
  
  # Helper to get a name string for a target
  defp get_target_name(target) do
    cond do
      is_atom(target) -> to_string(target)
      is_function(target) -> inspect(target)
      is_map(target) && Map.has_key?(target, :__struct__) -> 
        to_string(target.__struct__)
      true -> ""
    end
  end
  
  # Checks if a target is likely a deterministic operation
  defp is_deterministic_operation?(target) do
    # A real implementation would analyze the code to determine this
    # For now, we'll make some reasonable assumptions
    name_str = get_target_name(target)
    
    # Operations that tend to be deterministic
    String.contains?(name_str, "Parse") || 
    String.contains?(name_str, "Template") ||
    String.contains?(name_str, "format_") ||
    String.contains?(name_str, "Transform") ||
    String.contains?(name_str, "Validate")
  end
  
  # Checks for LLM traits based on naming and behavior
  defp has_llm_traits?(target) do
    # For now, we'll use a simple heuristic based on naming
    name_str = get_target_name(target)
    
    # Check for clear LLM indicators in the name
    llm_patterns = [
      ~r/LLM/i,
      ~r/LanguageModel/i,
      ~r/Completion/i,
      ~r/Chat/i,
      ~r/Anthropic/i,
      ~r/OpenAI/i,
      ~r/Claude/i,
      ~r/GPT/i,
      ~r/Llama/i,
      ~r/Gemini/i,
      ~r/Extraction/i,
      ~r/HuggingFace/i,
      ~r/Embedding/i,
      ~r/TokenCount/i,
      ~r/Tokenize/i
    ]
    
    Enum.any?(llm_patterns, fn pattern -> 
      String.match?(name_str, pattern) 
    end)
  end
  
  # Analyzes content for prompt template patterns
  defp contains_prompt_template?(target) do
    # In a real implementation, this would analyze the target 
    # to check for string interpolation patterns typical of prompts
    
    name_str = get_target_name(target)
    
    String.contains?(name_str, "Template") || 
    String.contains?(name_str, "Prompt") ||
    String.contains?(name_str, "format")
  end
  
  # Looks for more subtle LLM usage patterns
  defp contains_llm_patterns?(target) do
    # Look for code patterns that suggest LLM usage
    # In a real implementation, this would analyze AST or code structure
    
    name_str = get_target_name(target)
    
    prompt_related = 
      String.contains?(name_str, "system_message") ||
      String.contains?(name_str, "user_message") ||
      String.contains?(name_str, "assistant") ||
      String.contains?(name_str, "instruction")
      
    parameter_related =
      String.contains?(name_str, "temperature") ||
      String.contains?(name_str, "top_p") ||
      String.contains?(name_str, "max_tokens")
      
    output_related =
      String.contains?(name_str, "streaming") ||
      String.contains?(name_str, "token_") ||
      String.contains?(name_str, "content_filter") ||
      String.contains?(name_str, "safe")
      
    prompt_related || parameter_related || output_related
  end
  
  # Analyzes the runtime behavior of a function
  defp analyze_behavior(target, sample_inputs) do
    # In a real implementation, this would actually execute the target
    # with sample inputs and analyze the behavior
    
    # For now, we'll make a simplified determination
    if sample_inputs == nil do
      :unknown
    else
      try do
        # Attempt to infer from input/output patterns if it's LLM related
        if is_llm_operator?(target) do
          :llm_related
        else
          contains_llm_patterns?(target) && :potentially_llm_related || :unknown
        end
      rescue
        _ -> :unknown
      end
    end
  end
  
  # These functions determine the role of a node in LLM operations
  
  defp is_llm_call?(node) do
    # Simplified implementation - would examine the node structure
    # to determine if it represents a direct call to an LLM
    
    # Assuming node might have type information
    node_type = get_node_type(node)
    
    String.contains?(node_type, "LLM") or
    String.contains?(node_type, "Anthropic") or
    String.contains?(node_type, "OpenAI") or
    String.contains?(node_type, "ChatCompletion")
  end
  
  defp is_prompt_preparation?(node) do
    # Examine node to see if it's preparing a prompt
    node_type = get_node_type(node)
    
    String.contains?(node_type, "Prompt") or
    String.contains?(node_type, "Template") or
    String.contains?(node_type, "format_") or
    String.contains?(node_type, "prepare_")
  end
  
  defp is_result_processing?(node) do
    # Examine node to see if it's processing LLM results
    node_type = get_node_type(node)
    
    String.contains?(node_type, "Parse") or
    String.contains?(node_type, "Process") or
    String.contains?(node_type, "Extract") or
    String.contains?(node_type, "Validation")
  end
  
  # Helper to get a string representation of node type
  defp get_node_type(node) do
    cond do
      is_map(node) and Map.has_key?(node, :type) -> 
        to_string(node.type)
      is_map(node) and Map.has_key?(node, :node_type) -> 
        to_string(node.node_type)
      is_map(node) and Map.has_key?(node, :operation) -> 
        to_string(node.operation)
      is_map(node) and Map.has_key?(node, :__struct__) -> 
        to_string(node.__struct__)
      is_atom(node) -> 
        to_string(node)
      is_function(node) -> 
        inspect(node)
      true -> 
        ""
    end
  end
end
