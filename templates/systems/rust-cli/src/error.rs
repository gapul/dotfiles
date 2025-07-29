use thiserror::Error;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("IO error: {message}")]
    Io {
        message: String,
        #[source]
        source: std::io::Error,
    },
    
    #[error("Configuration error: {message}")]
    Config {
        message: String,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    
    #[error("JSON parsing error")]
    Json(#[from] serde_json::Error),
    
    #[error("Validation error: {message}")]
    Validation { message: String },
    
    #[error("Network error: {message}")]
    Network {
        message: String,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    
    #[error("Processing error: {message}")]
    Processing { message: String },
    
    #[error("Unknown error: {message}")]
    Unknown { message: String },
}

impl AppError {
    pub fn validation<S: Into<String>>(message: S) -> Self {
        Self::Validation {
            message: message.into(),
        }
    }
    
    pub fn processing<S: Into<String>>(message: S) -> Self {
        Self::Processing {
            message: message.into(),
        }
    }
    
    pub fn unknown<S: Into<String>>(message: S) -> Self {
        Self::Unknown {
            message: message.into(),
        }
    }
}