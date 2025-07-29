# Rust CLI Application Template Configuration
{
  name = "rust-cli";
  displayName = "Rust CLI Application";
  description = "Modern command-line application built with Rust";
  
  language = "rust";
  framework = "clap";
  type = "cli";
  
  rustEdition = "2021";
  msrv = "1.70.0";
  
  dependencies = [
    "clap = { version = \"4.4\", features = [\"derive\"] }"
    "serde = { version = \"1.0\", features = [\"derive\"] }"
    "serde_json = \"1.0\""
    "tokio = { version = \"1.0\", features = [\"full\"] }"
    "anyhow = \"1.0\""
    "thiserror = \"1.0\""
    "tracing = \"0.1\""
    "tracing-subscriber = \"0.3\""
    "env_logger = \"0.10\""
  ];
  
  devDependencies = [
    "assert_cmd = \"2.0\""
    "predicates = \"3.0\""
    "tempfile = \"3.0\""
    "criterion = \"0.5\""
  ];
  
  features = {
    default = [];
    json = ["serde_json"];
    async = ["tokio"];
  };
  
  files = [
    "Cargo.toml"
    "src/main.rs"
    "src/lib.rs"
    "src/cli.rs"
    "src/config.rs"
    "src/error.rs"
    "tests/integration_test.rs"
    "benches/benchmark.rs"
    "README.md"
  ];
  
  nixPackages = [
    "rustc"
    "cargo"
    "rust-analyzer"
    "rustfmt"
    "clippy"
  ];
}