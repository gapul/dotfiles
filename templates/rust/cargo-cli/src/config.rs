use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use crate::error::{Result, AppError};

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub app_name: String,
    pub version: String,
    pub default_output_dir: PathBuf,
    pub log_level: String,
    pub features: ConfigFeatures,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConfigFeatures {
    pub json_output: bool,
    pub async_processing: bool,
    pub verbose_logging: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            app_name: "{{PROJECT_NAME}}".to_string(),
            version: env!("CARGO_PKG_VERSION").to_string(),
            default_output_dir: PathBuf::from("./output"),
            log_level: "info".to_string(),
            features: ConfigFeatures {
                json_output: true,
                async_processing: false,
                verbose_logging: false,
            },
        }
    }
}

impl Config {
    /// Load configuration from file or create default
    pub fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        
        if config_path.exists() {
            let content = std::fs::read_to_string(&config_path)
                .map_err(|e| AppError::Io {
                    message: format!("Failed to read config file: {}", config_path.display()),
                    source: e,
                })?;
            
            let config: Config = serde_json::from_str(&content)
                .map_err(|e| AppError::Config {
                    message: "Failed to parse config file".to_string(),
                    source: e.into(),
                })?;
            
            Ok(config)
        } else {
            // Create default config and save it
            let config = Self::default();
            config.save()?;
            Ok(config)
        }
    }
    
    /// Save configuration to file
    pub fn save(&self) -> Result<()> {
        let config_path = Self::config_path()?;
        
        // Create config directory if it doesn't exist
        if let Some(parent) = config_path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| AppError::Io {
                    message: format!("Failed to create config directory: {}", parent.display()),
                    source: e,
                })?;
        }
        
        let content = serde_json::to_string_pretty(self)
            .map_err(|e| AppError::Config {
                message: "Failed to serialize config".to_string(),
                source: e.into(),
            })?;
        
        std::fs::write(&config_path, content)
            .map_err(|e| AppError::Io {
                message: format!("Failed to write config file: {}", config_path.display()),
                source: e,
            })?;
        
        Ok(())
    }
    
    /// Get the configuration file path
    fn config_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .ok_or_else(|| AppError::Config {
                message: "Could not find config directory".to_string(),
                source: std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "Config directory not found"
                ).into(),
            })?;
        
        Ok(config_dir.join("{{PROJECT_NAME}}").join("config.json"))
    }
}