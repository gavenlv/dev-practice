"""
Tests for configuration loader.
"""

import os
import pytest
from unittest.mock import patch, MagicMock

from config.loader import (
    Config,
    ConfigLoader,
    ConfigValidationError,
    AppConfig,
    DatabaseConfig,
    RedisConfig,
)


class TestConfigLoader:
    def test_load_local_config(self):
        """Test loading local configuration."""
        with patch.dict(os.environ, {
            "APP_ENV": "local",
            "DATABASE_HOST": "localhost",
            "DATABASE_NAME": "testdb",
            "DATABASE_PASSWORD": "testpass",
            "REDIS_HOST": "localhost",
        }):
            loader = ConfigLoader()
            config = loader.load()
            
            assert config.app.env == "local"
            assert config.database.host == "localhost"
            assert config.database.name == "testdb"
            assert config.redis.host == "localhost"
    
    def test_missing_required_fields(self):
        """Test validation fails for missing required fields."""
        with patch.dict(os.environ, {"APP_ENV": "local"}, clear=True):
            loader = ConfigLoader()
            
            with pytest.raises(ConfigValidationError) as exc_info:
                loader.load()
            
            assert "database.host is required" in str(exc_info.value)
    
    def test_env_var_override(self):
        """Test environment variables override config file."""
        with patch.dict(os.environ, {
            "APP_ENV": "local",
            "DATABASE_HOST": "localhost",
            "DATABASE_NAME": "testdb",
            "DATABASE_PASSWORD": "testpass",
            "REDIS_HOST": "localhost",
            "LOG_LEVEL": "debug",
            "DATABASE_PORT": "5433",
        }):
            loader = ConfigLoader()
            config = loader.load()
            
            assert config.app.log_level == "debug"
            assert config.database.port == 5433
    
    def test_invalid_ssl_mode(self):
        """Test validation fails for invalid SSL mode."""
        with patch.dict(os.environ, {
            "APP_ENV": "local",
            "DATABASE_HOST": "localhost",
            "DATABASE_NAME": "testdb",
            "DATABASE_PASSWORD": "testpass",
            "REDIS_HOST": "localhost",
            "DATABASE_SSL_MODE": "invalid",
        }):
            loader = ConfigLoader()
            
            with pytest.raises(ConfigValidationError) as exc_info:
                loader.load()
            
            assert "ssl_mode" in str(exc_info.value)


class TestConfig:
    def test_get_dsn(self):
        """Test DSN generation."""
        config = Config(
            database=DatabaseConfig(
                host="localhost",
                port=5432,
                user="testuser",
                password="testpass",
                name="testdb",
                ssl_mode="require",
            )
        )
        
        loader = ConfigLoader()
        dsn = loader.get_dsn(config)
        
        assert "host=localhost" in dsn
        assert "port=5432" in dsn
        assert "user=testuser" in dsn
        assert "dbname=testdb" in dsn
        assert "sslmode=require" in dsn
    
    def test_get_redis_url(self):
        """Test Redis URL generation."""
        config = Config(
            redis=RedisConfig(
                host="localhost",
                port=6379,
                password="redispass",
                db=0,
            )
        )
        
        loader = ConfigLoader()
        url = loader.get_redis_url(config)
        
        assert url == "redis://:redispass@localhost:6379/0"
