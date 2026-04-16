"""
Configuration loader module for multi-environment configuration management.
"""

import os
import yaml
from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field
from pathlib import Path
from functools import lru_cache

try:
    from google.cloud import secretmanager
    HAS_SECRET_MANAGER = True
except ImportError:
    HAS_SECRET_MANAGER = False


@dataclass
class AppConfig:
    name: str = "myapp"
    port: int = 8080
    log_level: str = "info"
    env: str = "local"
    timeout: int = 30


@dataclass
class DatabaseConfig:
    host: str = "localhost"
    port: int = 5432
    name: str = ""
    user: str = ""
    password: str = ""
    ssl_mode: str = "require"
    max_connections: int = 10
    connection_timeout: int = 30
    conn_max_lifetime: int = 3600


@dataclass
class RedisConfig:
    host: str = "localhost"
    port: int = 6379
    password: str = ""
    db: int = 0
    ssl: bool = True
    pool_size: int = 10


@dataclass
class PubSubConfig:
    project_id: str = ""
    subscription_timeout: int = 30


@dataclass
class GCPConfig:
    project_id: str = ""
    region: str = ""


@dataclass
class Config:
    app: AppConfig = field(default_factory=AppConfig)
    database: DatabaseConfig = field(default_factory=DatabaseConfig)
    redis: RedisConfig = field(default_factory=RedisConfig)
    pubsub: PubSubConfig = field(default_factory=PubSubConfig)
    gcp: GCPConfig = field(default_factory=GCPConfig)


class ConfigValidationError(Exception):
    """Raised when configuration validation fails."""
    pass


class SecretManagerClient:
    """Wrapper for GCP Secret Manager."""
    
    def __init__(self, project_id: str):
        if not HAS_SECRET_MANAGER:
            raise ImportError("google-cloud-secret-manager is not installed")
        
        self.client = secretmanager.SecretManagerServiceClient()
        self.project_id = project_id
        self._cache: Dict[str, str] = {}
    
    @lru_cache(maxsize=100)
    def get_secret(self, secret_id: str, version: str = "latest") -> str:
        """Get a secret value from Secret Manager."""
        cache_key = f"{secret_id}:{version}"
        if cache_key in self._cache:
            return self._cache[cache_key]
        
        name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
        
        response = self.client.access_secret_version(request={"name": name})
        value = response.payload.data.decode("UTF-8")
        
        self._cache[cache_key] = value
        return value


class ConfigLoader:
    """Configuration loader with multi-environment support."""
    
    def __init__(
        self,
        env: Optional[str] = None,
        project_id: Optional[str] = None,
        config_dir: str = "config",
    ):
        self.env = env or os.getenv("APP_ENV", "local")
        self.project_id = project_id or os.getenv("GCP_PROJECT_ID", "")
        self.config_dir = Path(config_dir)
        self._secret_client: Optional[SecretManagerClient] = None
    
    @property
    def secret_client(self) -> Optional[SecretManagerClient]:
        """Lazy initialization of Secret Manager client."""
        if self._secret_client is None and self.project_id and HAS_SECRET_MANAGER:
            self._secret_client = SecretManagerClient(self.project_id)
        return self._secret_client
    
    def load(self) -> Config:
        """Load configuration from all sources."""
        config = Config()
        
        self._load_defaults(config)
        self._load_environment_config(config)
        
        if self.env != "local" and self.secret_client:
            self._load_secrets(config)
        
        self._load_from_env_vars(config)
        self._validate(config)
        
        return config
    
    def _load_defaults(self, config: Config) -> None:
        """Load default configuration."""
        config.app = AppConfig()
        config.database = DatabaseConfig()
        config.redis = RedisConfig()
        config.pubsub = PubSubConfig()
        config.gcp = GCPConfig()
    
    def _load_environment_config(self, config: Config) -> None:
        """Load environment-specific configuration from YAML file."""
        config_file = self.config_dir / f"config.{self.env}.yaml"
        
        if not config_file.exists():
            return
        
        with open(config_file, "r") as f:
            data = yaml.safe_load(f)
        
        if not data:
            return
        
        if "app" in data:
            config.app = AppConfig(**{**config.app.__dict__, **data["app"]})
        if "database" in data:
            config.database = DatabaseConfig(
                **{**config.database.__dict__, **data["database"]}
            )
        if "redis" in data:
            config.redis = RedisConfig(**{**config.redis.__dict__, **data["redis"]})
        if "pubsub" in data:
            config.pubsub = PubSubConfig(**{**config.pubsub.__dict__, **data["pubsub"]})
        if "gcp" in data:
            config.gcp = GCPConfig(**{**config.gcp.__dict__, **data["gcp"]})
    
    def _load_secrets(self, config: Config) -> None:
        """Load secrets from GCP Secret Manager."""
        secret_mappings = {
            f"{self.env}/myapp/database/password": ("database", "password"),
            f"{self.env}/myapp/database/user": ("database", "user"),
            f"{self.env}/myapp/redis/password": ("redis", "password"),
        }
        
        for secret_id, (section, attr) in secret_mappings.items():
            try:
                value = self.secret_client.get_secret(secret_id)
                setattr(getattr(config, section), attr, value)
            except Exception as e:
                print(f"Warning: Failed to load secret {secret_id}: {e}")
    
    def _load_from_env_vars(self, config: Config) -> None:
        """Load configuration from environment variables."""
        config.app.env = self.env
        
        env_mappings = {
            "APP_PORT": ("app", "port", int),
            "LOG_LEVEL": ("app", "log_level", str),
            "DATABASE_HOST": ("database", "host", str),
            "DATABASE_PORT": ("database", "port", int),
            "DATABASE_NAME": ("database", "name", str),
            "DATABASE_USER": ("database", "user", str),
            "DATABASE_PASSWORD": ("database", "password", str),
            "DATABASE_SSL_MODE": ("database", "ssl_mode", str),
            "REDIS_HOST": ("redis", "host", str),
            "REDIS_PORT": ("redis", "port", int),
            "REDIS_PASSWORD": ("redis", "password", str),
            "GCP_PROJECT_ID": ("gcp", "project_id", str),
            "GCP_REGION": ("gcp", "region", str),
        }
        
        for env_var, (section, attr, type_func) in env_mappings.items():
            value = os.getenv(env_var)
            if value:
                try:
                    typed_value = type_func(value)
                    setattr(getattr(config, section), attr, typed_value)
                except ValueError as e:
                    print(f"Warning: Invalid value for {env_var}: {e}")
    
    def _validate(self, config: Config) -> None:
        """Validate configuration."""
        errors: List[str] = []
        
        if not config.app.name:
            errors.append("app.name is required")
        if not (0 < config.app.port <= 65535):
            errors.append("app.port must be between 1 and 65535")
        
        if not config.database.host:
            errors.append("database.host is required")
        if not config.database.name:
            errors.append("database.name is required")
        if not config.database.password:
            errors.append("database.password is required")
        
        if not config.redis.host:
            errors.append("redis.host is required")
        
        valid_ssl_modes = {"disable", "require", "verify-ca", "verify-full"}
        if config.database.ssl_mode not in valid_ssl_modes:
            errors.append(
                f"database.ssl_mode must be one of: {', '.join(valid_ssl_modes)}"
            )
        
        if errors:
            raise ConfigValidationError(
                "Configuration validation failed:\n  - " + "\n  - ".join(errors)
            )
    
    def get_dsn(self, config: Config) -> str:
        """Generate database connection string."""
        return (
            f"host={config.database.host} "
            f"port={config.database.port} "
            f"user={config.database.user} "
            f"password={config.database.password} "
            f"dbname={config.database.name} "
            f"sslmode={config.database.ssl_mode}"
        )
    
    def get_redis_url(self, config: Config) -> str:
        """Generate Redis connection URL."""
        if config.redis.password:
            return (
                f"redis://:{config.redis.password}@"
                f"{config.redis.host}:{config.redis.port}/{config.redis.db}"
            )
        return f"redis://{config.redis.host}:{config.redis.port}/{config.redis.db}"


def load_config(
    env: Optional[str] = None,
    project_id: Optional[str] = None,
) -> Config:
    """Convenience function to load configuration."""
    loader = ConfigLoader(env=env, project_id=project_id)
    return loader.load()


if __name__ == "__main__":
    config = load_config()
    print(f"Environment: {config.app.env}")
    print(f"Database Host: {config.database.host}")
    print(f"Redis Host: {config.redis.host}")
