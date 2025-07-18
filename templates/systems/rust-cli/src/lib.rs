//! {{PROJECT_NAME}} - Modern command-line application built with Rust
//!
//! This library provides the core functionality for the {{PROJECT_NAME}} CLI application.
//! It includes modules for command-line parsing, configuration management, and error handling.

pub mod cli;
pub mod config;
pub mod error;

pub use cli::{Cli, Commands};
pub use config::Config;
pub use error::{AppError, Result};

/// Application version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Application name
pub const APP_NAME: &str = env!("CARGO_PKG_NAME");

/// Main library function for programmatic usage
pub fn run_with_args(args: Vec<String>) -> Result<()> {
    use clap::Parser;
    
    let cli = Cli::try_parse_from(args)
        .map_err(|e| AppError::validation(format!("Invalid arguments: {}", e)))?;
    
    match cli.command {
        Commands::Run { input, output, verbose } => {
            let config = Config::load()?;
            
            // Core processing logic
            process_data(input, output, verbose, &config)
        }
        
        Commands::Config { show } => {
            if show {
                let config = Config::load()?;
                println!("{}", serde_json::to_string_pretty(&config)?);
            }
            Ok(())
        }
        
        Commands::Version => {
            println!("{} {}", APP_NAME, VERSION);
            Ok(())
        }
    }
}

/// Core data processing function
fn process_data(
    input: Option<std::path::PathBuf>,
    output: Option<std::path::PathBuf>,
    verbose: bool,
    config: &Config,
) -> Result<()> {
    if verbose {
        println!("Processing with configuration: {:?}", config);
    }
    
    // Implement your core logic here
    match input {
        Some(input_path) => {
            if verbose {
                println!("Processing file: {}", input_path.display());
            }
            
            // Read and process input file
            let _content = std::fs::read_to_string(&input_path)
                .map_err(|e| AppError::Io {
                    message: format!("Failed to read input file: {}", input_path.display()),
                    source: e,
                })?;
            
            // Process content here
            let result = "Processed content"; // Replace with actual processing
            
            // Write output if specified
            if let Some(output_path) = output {
                std::fs::write(&output_path, result)
                    .map_err(|e| AppError::Io {
                        message: format!("Failed to write output file: {}", output_path.display()),
                        source: e,
                    })?;
                
                if verbose {
                    println!("Output written to: {}", output_path.display());
                }
            } else {
                println!("{}", result);
            }
        }
        
        None => {
            if verbose {
                println!("No input file specified, using default behavior");
            }
            
            // Default behavior when no input is provided
            println!("{{PROJECT_NAME}} is ready! Use --help for usage information.");
        }
    }
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_version() {
        assert!(!VERSION.is_empty());
    }
    
    #[test]
    fn test_app_name() {
        assert_eq!(APP_NAME, "{{PROJECT_NAME}}");
    }
    
    #[test]
    fn test_config_creation() {
        let config = Config::default();
        assert_eq!(config.app_name, "{{PROJECT_NAME}}");
        assert!(!config.version.is_empty());
    }
}