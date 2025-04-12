defmodule EmberEx.XCS.JIT.Profiler do
  @moduledoc """
  Provides profiling capabilities for JIT optimization.
  
  This module helps to identify bottlenecks in the JIT compilation process,
  particularly during the analysis phase. It collects timing information
  and provides insights for optimization.
  """
  
  require Logger
  
  @doc """
  Profiles the execution of a function and returns its result along with timing data.
  
  ## Parameters
  
  - name: A label for the profiled section
  - func: The function to profile as a 0-arity function
  
  ## Returns
  
  A tuple of {result, timing_ms}
  """
  @spec profile(String.t(), function()) :: {term(), float()}
  def profile(name, func) when is_function(func, 0) do
    start_time = :os.system_time(:microsecond)
    result = func.()
    end_time = :os.system_time(:microsecond)
    elapsed_ms = (end_time - start_time) / 1000.0
    
    # Report timing to the metrics system
    report_timing(name, elapsed_ms)
    
    {result, elapsed_ms}
  end
  
  @doc """
  Profiles a function and logs timing information.
  
  This is a convenience wrapper around profile/2 that automatically logs
  the timing information and returns just the result.
  
  ## Parameters
  
  - name: A label for the profiled section
  - func: The function to profile as a 0-arity function
  - opts: Options for controlling the profiling:
    - :log_level - The level at which to log (default: :debug)
    - :threshold_ms - Only log if execution time exceeds this threshold (default: 0)
  
  ## Returns
  
  The result of the function
  """
  @spec profile_and_log(String.t(), function(), keyword()) :: term()
  def profile_and_log(name, func, opts \\ []) do
    log_level = Keyword.get(opts, :log_level, :debug)
    threshold_ms = Keyword.get(opts, :threshold_ms, 0)
    
    {result, elapsed_ms} = profile(name, func)
    
    if elapsed_ms >= threshold_ms do
      Logger.log(log_level, "#{name} took #{Float.round(elapsed_ms, 2)}ms")
    end
    
    result
  end
  
  @doc """
  Reports timing to the metrics collection system.
  
  ## Parameters
  
  - name: Name of the operation being timed
  - elapsed_ms: Elapsed time in milliseconds
  """
  @spec report_timing(String.t(), float()) :: :ok
  def report_timing(name, elapsed_ms) do
    # If EmberEx.Metrics exists, report to it
    if Code.ensure_loaded?(EmberEx.Metrics) && function_exported?(EmberEx.Metrics, :observe, 3) do
      EmberEx.Metrics.observe(:timer, "jit_#{name}_duration_ms", elapsed_ms)
    end
    
    :ok
  end
  
  @doc """
  Gets a summary of profiling data for analysis operations.
  
  ## Returns
  
  A map of profiling data with operation names as keys
  """
  @spec get_analysis_summary() :: map()
  def get_analysis_summary do
    # If metrics collector exists, get data from it
    if Code.ensure_loaded?(EmberEx.Metrics.Collector) && 
       function_exported?(EmberEx.Metrics.Collector, :get_histogram_data, 2) do
      EmberEx.Metrics.Collector.get_histogram_data(:timer, "jit_analysis")
    else
      %{}
    end
  end
end
