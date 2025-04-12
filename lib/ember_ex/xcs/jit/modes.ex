defmodule EmberEx.XCS.JIT.Modes do
  @moduledoc """
  Defines the available JIT compilation modes for the EmberEx framework.
  
  These modes determine how operators and functions are optimized at runtime:
  
  - `:auto` - Automatically selects the best strategy based on the target's characteristics
  - `:trace` - Optimizes by tracing execution and generating specialized functions
  - `:structural` - Analyzes operator structure without execution to find optimizations
  - `:enhanced` - Combines structural analysis with execution tracing
  - `:llm` - Specialized optimization for Language Model operations with partial caching
  """
  
  @type t :: :auto | :trace | :structural | :enhanced | :llm
  
  @doc """
  Validates if a given term is a valid JIT mode.
  
  ## Parameters
  
  - mode: The term to validate
  
  ## Returns
  
  True if the term is a valid JIT mode, false otherwise
  
  ## Examples
  
      iex> EmberEx.XCS.JIT.Modes.valid?(:auto)
      true
      
      iex> EmberEx.XCS.JIT.Modes.valid?(:invalid_mode)
      false
  """
  @spec valid?(atom()) :: boolean()
  def valid?(mode) when mode in [:auto, :trace, :structural, :enhanced, :llm], do: true
  def valid?(_), do: false
  
  @doc """
  Converts a string representation to a JIT mode atom.
  
  ## Parameters
  
  - mode_str: String representation of a mode
  
  ## Returns
  
  The corresponding JIT mode atom or `:auto` if invalid
  
  ## Examples
  
      iex> EmberEx.XCS.JIT.Modes.from_string("trace")
      :trace
      
      iex> EmberEx.XCS.JIT.Modes.from_string("invalid")
      :auto
  """
  @spec from_string(String.t()) :: t()
  def from_string(mode_str) when is_binary(mode_str) do
    case String.downcase(mode_str) do
      "auto" -> :auto
      "trace" -> :trace
      "structural" -> :structural
      "enhanced" -> :enhanced
      "llm" -> :llm
      _ -> 
        require Logger
        Logger.warning("Unknown JIT mode '#{mode_str}', falling back to auto")
        :auto
    end
  end
end
