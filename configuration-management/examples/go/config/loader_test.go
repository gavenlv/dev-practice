package config

import (
	"testing"
	"os"
)

func TestLoader_Load(t *testing.T) {
	tests := []struct {
		name    string
		envVars map[string]string
		wantErr bool
	}{
		{
			name: "valid local config",
			envVars: map[string]string{
				"APP_ENV":           "local",
				"DATABASE_HOST":     "localhost",
				"DATABASE_NAME":     "testdb",
				"DATABASE_PASSWORD": "testpass",
				"REDIS_HOST":        "localhost",
			},
			wantErr: false,
		},
		{
			name: "missing required fields",
			envVars: map[string]string{
				"APP_ENV": "local",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			os.Clearenv()
			for k, v := range tt.envVars {
				os.Setenv(k, v)
			}

			loader := NewLoader()
			cfg, err := loader.Load(nil)

			if (err != nil) != tt.wantErr {
				t.Errorf("Loader.Load() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !tt.wantErr && cfg == nil {
				t.Error("Loader.Load() returned nil config")
			}
		})
	}
}

func TestConfig_Validate(t *testing.T) {
	tests := []struct {
		name    string
		config  *Config
		wantErr bool
	}{
		{
			name: "valid config",
			config: &Config{
				App: AppConfig{
					Name: "myapp",
					Port: 8080,
				},
				Database: DatabaseConfig{
					Host:     "localhost",
					Name:     "testdb",
					Password: "testpass",
					SSLMode:  "require",
				},
				Redis: RedisConfig{
					Host: "localhost",
				},
			},
			wantErr: false,
		},
		{
			name: "missing app name",
			config: &Config{
				App: AppConfig{
					Port: 8080,
				},
				Database: DatabaseConfig{
					Host:     "localhost",
					Name:     "testdb",
					Password: "testpass",
					SSLMode:  "require",
				},
				Redis: RedisConfig{
					Host: "localhost",
				},
			},
			wantErr: true,
		},
		{
			name: "invalid ssl mode",
			config: &Config{
				App: AppConfig{
					Name: "myapp",
					Port: 8080,
				},
				Database: DatabaseConfig{
					Host:     "localhost",
					Name:     "testdb",
					Password: "testpass",
					SSLMode:  "invalid",
				},
				Redis: RedisConfig{
					Host: "localhost",
				},
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Config.Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestConfig_GetDSN(t *testing.T) {
	cfg := &Config{
		Database: DatabaseConfig{
			Host:     "localhost",
			Port:     5432,
			User:     "testuser",
			Password: "testpass",
			Name:     "testdb",
			SSLMode:  "require",
		},
	}

	dsn := cfg.GetDSN()
	expected := "host=localhost port=5432 user=testuser password=testpass dbname=testdb sslmode=require"
	if dsn != expected {
		t.Errorf("GetDSN() = %v, want %v", dsn, expected)
	}
}
