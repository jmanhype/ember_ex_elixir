defmodule Mix.Tasks.EmberEx do
  use Mix.Task

  @shortdoc "EmberEx CLI interface for executing operations"
  @moduledoc """
  Provides a command-line interface for EmberEx operations.

  ## General Usage

      mix ember_ex [command] [options]

  ## Available Commands

      run       Run an EmberEx operation or pipeline
      benchmark Benchmark optimization strategies
      dataset   Work with datasets
      help      Show detailed help for commands

  ## Examples

      # Show general help
      mix ember_ex help

      # Run a pipeline from a file
      mix ember_ex run --file pipeline.exs

      # Run benchmark tests
      mix ember_ex benchmark --strategies=all
  """

  @impl Mix.Task
  def run(args) do
    {opts, commands, _} = OptionParser.parse(
      args,
      strict: [verbose: :boolean, help: :boolean],
      aliases: [v: :verbose, h: :help]
    )

    # Display help if no commands or help option
    if Keyword.get(opts, :help) || commands == [] do
      print_help()
    else
      # Dispatch to appropriate command
      dispatch_command(List.first(commands), tl(commands), opts)
    end
  end

  defp dispatch_command("help", args, _opts) do
    case args do
      [] -> print_help()
      [command | _] -> print_command_help(command)
    end
  end

  defp dispatch_command("run", args, _opts) do
    Mix.shell().info("Executing EmberEx run command")
    
    # Parse command-specific options
    {run_opts, _run_args, _} = OptionParser.parse(
      args,
      strict: [file: :string, output: :string],
      aliases: [f: :file, o: :output]
    )
    
    file = Keyword.get(run_opts, :file)
    
    if file do
      Mix.shell().info("Running pipeline from file: #{file}")
      # Here you would implement the logic to load and run a pipeline
      # For example:
      # EmberEx.CLI.Runner.run_from_file(file, opts)
    else
      Mix.shell().error("No pipeline file specified. Use --file option.")
    end
  end

  defp dispatch_command("benchmark", args, _opts) do
    Mix.shell().info("Executing benchmark tests")
    
    # Parse command-specific options
    {benchmark_opts, _, _} = OptionParser.parse(
      args,
      strict: [strategies: :string, iterations: :integer],
      aliases: [s: :strategies, i: :iterations]
    )
    
    strategies = Keyword.get(benchmark_opts, :strategies, "all")
    iterations = Keyword.get(benchmark_opts, :iterations, 1)
    
    Mix.shell().info("Running benchmarks with strategies: #{strategies}, iterations: #{iterations}")
    
    # Here you would implement the logic to run benchmarks
    # For example:
    # EmberEx.CLI.Benchmark.run(strategies, iterations)
  end

  defp dispatch_command("dataset", args, _opts) do
    Mix.shell().info("Dataset operations")
    
    # Parse dataset sub-commands
    {dataset_opts, dataset_args, _} = OptionParser.parse(
      args,
      strict: [file: :string, format: :string],
      aliases: [f: :file]
    )
    
    case dataset_args do
      ["info" | file_args] ->
        file = Keyword.get(dataset_opts, :file) || List.first(file_args)
        if file do
          Mix.shell().info("Showing dataset info for: #{file}")
          # Implement show dataset info
          # EmberEx.CLI.Dataset.show_info(file, dataset_opts)
        else
          Mix.shell().error("No dataset file specified")
        end
        
      ["convert" | _] ->
        Mix.shell().info("Convert dataset format")
        # Implement dataset conversion
        
      _ ->
        Mix.shell().info("Available dataset commands: info, convert")
    end
  end

  defp dispatch_command(command, _args, _opts) do
    Mix.shell().error("Unknown command: #{command}")
    print_help()
  end

  defp print_help do
    Mix.shell().info(@moduledoc)
  end

  defp print_command_help("run") do
    Mix.shell().info("""
    mix ember_ex run [options]
    
    Options:
      --file, -f       Path to pipeline definition file
      --output, -o     Output file for results
      --verbose, -v    Show verbose output
    """)
  end

  defp print_command_help("benchmark") do
    Mix.shell().info("""
    mix ember_ex benchmark [options]
    
    Options:
      --strategies, -s  Strategies to benchmark (all, llm, structural, trace, enhanced)
      --iterations, -i  Number of benchmark iterations
      --verbose, -v     Show verbose output
    """)
  end

  defp print_command_help("dataset") do
    Mix.shell().info("""
    mix ember_ex dataset [command] [options]
    
    Commands:
      info     Display dataset information
      convert  Convert dataset between formats
    
    Options:
      --file, -f       Dataset file path
      --format         Target format for conversion
    """)
  end

  defp print_command_help(_) do
    Mix.shell().info("No detailed help available for this command")
    print_help()
  end
end
