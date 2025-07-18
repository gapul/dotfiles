use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "{{PROJECT_NAME}}",
    about = "Modern command-line application built with Rust",
    version = env!("CARGO_PKG_VERSION"),
    author = env!("CARGO_PKG_AUTHORS"),
    long_about = None
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Run the main application
    Run {
        /// Input file or data
        #[arg(short, long)]
        input: Option<PathBuf>,
        
        /// Output file path
        #[arg(short, long)]
        output: Option<PathBuf>,
        
        /// Enable verbose output
        #[arg(short, long)]
        verbose: bool,
    },
    
    /// Configuration management
    Config {
        /// Show current configuration
        #[arg(long)]
        show: bool,
    },
    
    /// Show version information
    Version,
}