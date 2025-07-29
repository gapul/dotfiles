use clap::Parser;
use tracing::{info, error};
use tracing_subscriber;

mod cli;
mod config;
mod error;

use cli::Cli;
use config::Config;
use error::Result;

fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cli = Cli::parse();
    
    info!("Starting {{PROJECT_NAME}} v{}", env!("CARGO_PKG_VERSION"));
    
    if let Err(e) = run(cli) {
        error!("Application error: {}", e);
        std::process::exit(1);
    }
    
    Ok(())
}

fn run(cli: Cli) -> Result<()> {
    match cli.command {
        cli::Commands::Run { input, output, verbose } => {
            if verbose {
                println!("Running in verbose mode");
            }
            
            let config = Config::load()?;
            info!("Loaded configuration: {:?}", config);
            
            // Main application logic here
            println!("Processing input: {:?}", input);
            
            if let Some(output_path) = output {
                println!("Output will be written to: {:?}", output_path);
            }
            
            println!("{{PROJECT_NAME}} completed successfully!");
        }
        
        cli::Commands::Config { show } => {
            if show {
                let config = Config::load()?;
                println!("Current configuration:");
                println!("{}", serde_json::to_string_pretty(&config)?);
            } else {
                println!("Use --show to display current configuration");
            }
        }
        
        cli::Commands::Version => {
            println!("{{PROJECT_NAME}} {}", env!("CARGO_PKG_VERSION"));
            println!("Built with Rust {}", env!("RUSTC_VERSION"));
        }
    }
    
    Ok(())
}