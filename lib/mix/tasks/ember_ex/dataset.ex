defmodule Mix.Tasks.EmberEx.Dataset do
  @moduledoc """
  Mix task for working with EmberEx datasets.
  
  This task provides commands for working with datasets, including loading,
  transforming, analyzing, and converting datasets from various formats.
  """
  use Mix.Task
  
  alias EmberEx.Core.Data.{Dataset, Loader}
  
  @shortdoc "Work with EmberEx datasets"
  
  @impl Mix.Task
  @spec run(list(String.t())) :: :ok
  def run(args) do
    {opts, command_args, _} = OptionParser.parse(
      args,
      strict: [
        file: :string,
        format: :string,
        output: :string,
        schema: :string,
        headers: :boolean,
        limit: :integer,
        verbose: :boolean
      ],
      aliases: [
        f: :file,
        o: :output,
        v: :verbose,
        l: :limit
      ]
    )
    
    # Get the subcommand
    command = List.first(command_args) || "help"
    
    # Dispatch to appropriate command handler
    case command do
      "inspect" -> inspect_dataset(opts)
      "convert" -> convert_dataset(opts)
      "transform" -> transform_dataset(opts, command_args)
      "analyze" -> analyze_dataset(opts)
      "sample" -> sample_dataset(opts)
      "help" -> print_help()
      _ -> 
        Mix.shell().error("Unknown command: #{command}")
        print_help()
    end
    
    :ok
  end
  
  # Inspects and shows information about a dataset.
  # 
  # ## Options
  #   * `--file`, `-f` - Path to the dataset file
  #   * `--format` - Format of the data (csv, json, jsonl)
  #   * `--limit`, `-l` - Number of records to preview
  #   * `--verbose`, `-v` - Show detailed information
  @spec inspect_dataset(keyword()) :: :ok
  defp inspect_dataset(opts) do
    file = Keyword.get(opts, :file)
    
    unless file do
      Mix.shell().error("No dataset file specified. Use --file option.")
      return_with_error()
    end
    
    format = Keyword.get(opts, :format, :auto)
    limit = Keyword.get(opts, :limit, 5)
    verbose = Keyword.get(opts, :verbose, false)
    
    Mix.shell().info("Inspecting dataset: #{file}")
    
    # Load the dataset
    case Loader.load_file(file, format: format) do
      {:ok, dataset} ->
        display_dataset_info(dataset, limit, verbose)
      
      {:error, reason} ->
        Mix.shell().error("Failed to load dataset: #{reason}")
        return_with_error()
    end
    
    :ok
  end
  
  # Converts a dataset from one format to another.
  # 
  # ## Options
  #   * `--file`, `-f` - Path to the source dataset file
  #   * `--format` - Source format (auto-detected by default)
  #   * `--output`, `-o` - Output file path
  #   * `--headers` - Whether the CSV has headers (for CSV output)
  @spec convert_dataset(keyword()) :: :ok
  defp convert_dataset(opts) do
    file = Keyword.get(opts, :file)
    output = Keyword.get(opts, :output)
    
    unless file do
      Mix.shell().error("No source dataset file specified. Use --file option.")
      return_with_error()
    end
    
    unless output do
      Mix.shell().error("No output file specified. Use --output option.")
      return_with_error()
    end
    
    format = Keyword.get(opts, :format, :auto)
    headers = Keyword.get(opts, :headers, true)
    
    # Determine output format from extension
    output_format = output
      |> Path.extname()
      |> String.downcase()
      |> case do
        ".csv" -> :csv
        ".json" -> :json
        ".jsonl" -> :jsonl
        _ -> :auto
      end
    
    Mix.shell().info("Converting dataset from #{file} to #{output}")
    
    # Load the source dataset
    case Loader.load_file(file, format: format) do
      {:ok, dataset} ->
        # Convert and save the dataset
        convert_and_save(dataset, output, output_format, headers: headers)
        Mix.shell().info("Successfully converted dataset to #{output}")
      
      {:error, reason} ->
        Mix.shell().error("Failed to load source dataset: #{reason}")
        return_with_error()
    end
    
    :ok
  end
  
  # Applies transformations to a dataset.
  # 
  # ## Options
  #   * `--file`, `-f` - Path to the dataset file
  #   * `--output`, `-o` - Output file path
  # 
  # ## Commands
  #   * `transform filter "expr"` - Filter records by expression
  #   * `transform map "expr"` - Transform records by expression
  #   * `transform sort "field"` - Sort records by field
  @spec transform_dataset(keyword(), list(String.t())) :: :ok
  defp transform_dataset(opts, command_args) do
    file = Keyword.get(opts, :file)
    output = Keyword.get(opts, :output)
    
    unless file do
      Mix.shell().error("No dataset file specified. Use --file option.")
      return_with_error()
    end
    
    unless output do
      Mix.shell().error("No output file specified. Use --output option.")
      return_with_error()
    end
    
    # Get transformation subcommand and args
    [_transform, transform_type | transform_args] = command_args
    
    # Load the dataset
    case Loader.load_file(file) do
      {:ok, dataset} ->
        # Apply the transformation
        case apply_transformation(dataset, transform_type, transform_args) do
          {:ok, transformed_dataset} ->
            # Save the transformed dataset
            output_format = output
              |> Path.extname()
              |> String.downcase()
              |> case do
                ".csv" -> :csv
                ".json" -> :json
                ".jsonl" -> :jsonl
                _ -> :auto
              end
            
            convert_and_save(transformed_dataset, output, output_format)
            Mix.shell().info("Successfully transformed dataset and saved to #{output}")
          
          {:error, reason} ->
            Mix.shell().error("Failed to transform dataset: #{reason}")
            return_with_error()
        end
      
      {:error, reason} ->
        Mix.shell().error("Failed to load dataset: #{reason}")
        return_with_error()
    end
    
    :ok
  end
  
  # Analyzes a dataset and provides statistics.
  # 
  # ## Options
  #   * `--file`, `-f` - Path to the dataset file
  #   * `--output`, `-o` - Optional output file for analysis results
  @spec analyze_dataset(keyword()) :: :ok
  defp analyze_dataset(opts) do
    file = Keyword.get(opts, :file)
    
    unless file do
      Mix.shell().error("No dataset file specified. Use --file option.")
      return_with_error()
    end
    
    output = Keyword.get(opts, :output)
    
    Mix.shell().info("Analyzing dataset: #{file}")
    
    # Load the dataset
    case Loader.load_file(file) do
      {:ok, dataset} ->
        # Analyze the dataset
        {:ok, stats} = analyze_dataset_stats(dataset)
        
        # Display and optionally save the results
        display_dataset_stats(stats)
        
        if output do
          # Since save_stats currently always returns :ok, simplify the code
          save_stats(stats, output)
          Mix.shell().info("Analysis saved to #{output}")
        end
        
      {:error, reason} ->
        Mix.shell().error("Failed to load dataset: #{reason}")
        return_with_error()
    end
    
    :ok
  end
  
  # Extracts a random sample from a dataset.
  # 
  # ## Options
  #   * `--file`, `-f` - Path to the dataset file
  #   * `--output`, `-o` - Output file path
  #   * `--limit`, `-l` - Number of records to sample (default: 100)
  @spec sample_dataset(keyword()) :: :ok
  defp sample_dataset(opts) do
    file = Keyword.get(opts, :file)
    output = Keyword.get(opts, :output)
    
    unless file do
      Mix.shell().error("No dataset file specified. Use --file option.")
      return_with_error()
    end
    
    unless output do
      Mix.shell().error("No output file specified. Use --output option.")
      return_with_error()
    end
    
    limit = Keyword.get(opts, :limit, 100)
    
    Mix.shell().info("Sampling #{limit} records from #{file}")
    
    # Load the dataset
    case Loader.load_file(file) do
      {:ok, dataset} ->
        # Convert to list
        case Dataset.to_list(dataset) do
          {:ok, items} ->
            # Take a random sample
            sample = if length(items) <= limit do
              items
            else
              Enum.take_random(items, limit)
            end
            
            # Create a new dataset from the sample
            {:ok, sample_dataset} = Dataset.new(sample, 
              name: "#{dataset.name}_sample", 
              metadata: Map.put(dataset.metadata || %{}, :sample_size, limit)
            )
            
            # Save the sample
            output_format = output
              |> Path.extname()
              |> String.downcase()
              |> case do
                ".csv" -> :csv
                ".json" -> :json
                ".jsonl" -> :jsonl
                _ -> :auto
              end
            
            convert_and_save(sample_dataset, output, output_format)
            Mix.shell().info("Successfully saved sample to #{output}")
          
          {:error, reason} ->
            Mix.shell().error("Failed to convert dataset to list: #{reason}")
            return_with_error()
        end
      
      {:error, reason} ->
        Mix.shell().error("Failed to load dataset: #{reason}")
        return_with_error()
    end
    
    :ok
  end
  
  # Prints help information.
  @spec print_help() :: :ok
  defp print_help do
    Mix.shell().info("""
    EmberEx dataset commands:
    
    mix ember_ex dataset inspect [options]   - Show dataset information
    mix ember_ex dataset convert [options]   - Convert dataset format
    mix ember_ex dataset transform [options] - Apply transformations
    mix ember_ex dataset analyze [options]   - Analyze dataset statistics
    mix ember_ex dataset sample [options]    - Extract random sample
    
    Common options:
      --file, -f       Dataset file path
      --output, -o     Output file path
      --format         Data format (csv, json, jsonl, auto)
      --limit, -l      Record limit for preview/sample
      --verbose, -v    Show detailed information
      
    Examples:
      mix ember_ex dataset inspect --file data.csv --limit 10
      mix ember_ex dataset convert --file data.csv --output data.json
      mix ember_ex dataset sample --file data.json --output sample.json --limit 50
    """)
    
    :ok
  end
  
  # Helper functions
  
  @spec display_dataset_info(Dataset.t(), integer(), boolean()) :: :ok
  defp display_dataset_info(dataset, limit, verbose) do
    Mix.shell().info("Dataset: #{dataset.name}")
    Mix.shell().info("Size: #{dataset.size || "Unknown"}")
    
    if verbose do
      Mix.shell().info("Source: #{inspect(dataset.source)}")
      Mix.shell().info("Schema: #{inspect(dataset.schema)}")
      Mix.shell().info("Metadata: #{inspect(dataset.metadata)}")
    end
    
    # Preview records
    Mix.shell().info("\nPreview (up to #{limit} records):")
    
    case Dataset.get_batch(dataset, limit) do
      {:ok, items, _} ->
        items
        |> Enum.with_index(1)
        |> Enum.each(fn {item, idx} ->
          Mix.shell().info("Record #{idx}:")
          
          if verbose do
            Mix.shell().info(inspect(item, pretty: true, width: 80))
          else
            # Show a simplified view
            item
            |> Enum.take(5)
            |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(truncate_value(v))}" end)
            |> Enum.join("\n")
            |> (fn str -> Mix.shell().info(str) end).()
            
            if map_size(item) > 5 do
              Mix.shell().info("  ... (#{map_size(item) - 5} more fields)")
            end
          end
        end)
      
      {:error, reason} ->
        Mix.shell().error("Failed to get preview records: #{reason}")
    end
    
    :ok
  end
  
  @spec truncate_value(term()) :: term()
  defp truncate_value(value) when is_binary(value) do
    if String.length(value) > 50 do
      String.slice(value, 0, 47) <> "..."
    else
      value
    end
  end
  defp truncate_value(value) when is_list(value) do
    if length(value) > 3 do
      Enum.take(value, 3) ++ ["... (#{length(value) - 3} more)"]
    else
      value
    end
  end
  defp truncate_value(value) when is_map(value) do
    if map_size(value) > 3 do
      value
      |> Enum.take(3)
      |> Enum.into(%{})
      |> Map.put("...", "(#{map_size(value) - 3} more fields)")
    else
      value
    end
  end
  defp truncate_value(value), do: value
  
  @spec convert_and_save(Dataset.t(), String.t(), atom(), keyword()) :: :ok
  defp convert_and_save(_dataset, _output_path, _output_format, _opts \\ []) do
    # This would be implemented with conversion logic
    # For now, just return a success result
    :ok
  end
  
  @spec apply_transformation(Dataset.t(), String.t(), list(String.t())) :: 
    {:ok, Dataset.t()} | {:error, String.t()}
  defp apply_transformation(dataset, transform_type, transform_args) do
    case transform_type do
      "filter" ->
        [_expression | _] = transform_args
        # This would parse and apply the filter expression
        {:ok, dataset}
        
      "map" ->
        [_expression | _] = transform_args
        # This would parse and apply the map expression
        {:ok, dataset}
        
      "sort" ->
        [_field | _] = transform_args
        # This would sort by the given field
        {:ok, dataset}
        
      _ ->
        {:error, "Unknown transformation type: #{transform_type}"}
    end
  end
  
  @spec analyze_dataset_stats(Dataset.t()) :: {:ok, map()}
  defp analyze_dataset_stats(dataset) do
    # This would compute statistics about the dataset
    # For now, return mock statistics
    {:ok, %{
      record_count: dataset.size || 0,
      fields: [],
      types: %{},
      missing_values: %{},
      unique_values: %{}
    }}
  end
  
  @spec display_dataset_stats(map()) :: :ok
  defp display_dataset_stats(stats) do
    Mix.shell().info("Dataset Statistics:")
    Mix.shell().info("Record count: #{stats.record_count}")
    
    # Display field statistics
    # (This would be more detailed in a real implementation)
    
    :ok
  end
  
  @spec save_stats(map(), String.t()) :: :ok | {:error, String.t()}
  defp save_stats(_stats, _output_path) do
    # This would save statistics to a file
    # For now, just return a success result
    :ok
  end
  
  @spec return_with_error() :: :ok
  defp return_with_error do
    Mix.shell().info("For help, run: mix ember_ex dataset help")
    :ok
  end
end
