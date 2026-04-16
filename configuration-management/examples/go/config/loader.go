package config

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
	"gopkg.in/yaml.v3"
)

type Config struct {
	App      AppConfig      `yaml:"app"`
	Database DatabaseConfig `yaml:"database"`
	Redis    RedisConfig    `yaml:"redis"`
	PubSub   PubSubConfig   `yaml:"pubsub"`
	GCP      GCPConfig      `yaml:"gcp"`
}

type AppConfig struct {
	Name     string        `yaml:"name"`
	Port     int           `yaml:"port"`
	LogLevel string        `yaml:"log_level"`
	Env      string        `yaml:"env"`
	Timeout  time.Duration `yaml:"timeout"`
}

type DatabaseConfig struct {
	Host            string        `yaml:"host"`
	Port            int           `yaml:"port"`
	Name            string        `yaml:"name"`
	User            string        `yaml:"user"`
	Password        string        `yaml:"-"`
	SSLMode         string        `yaml:"ssl_mode"`
	MaxConnections  int           `yaml:"max_connections"`
	ConnTimeout     time.Duration `yaml:"connection_timeout"`
	ConnMaxLifetime time.Duration `yaml:"conn_max_lifetime"`
}

type RedisConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Password string `yaml:"-"`
	DB       int    `yaml:"db"`
	SSL      bool   `yaml:"ssl"`
	PoolSize int    `yaml:"pool_size"`
}

type PubSubConfig struct {
	ProjectID           string        `yaml:"project_id"`
	SubscriptionTimeout time.Duration `yaml:"subscription_timeout"`
}

type GCPConfig struct {
	ProjectID string `yaml:"project_id"`
	Region    string `yaml:"region"`
}

type Loader struct {
	env         string
	projectID   string
	secretCache map[string]string
}

func NewLoader() *Loader {
	env := getEnv("APP_ENV", "local")
	projectID := getEnv("GCP_PROJECT_ID", "")
	
	return &Loader{
		env:         env,
		projectID:   projectID,
		secretCache: make(map[string]string),
	}
}

func (l *Loader) Load(ctx context.Context) (*Config, error) {
	cfg := &Config{}
	
	if err := l.loadDefaults(cfg); err != nil {
		return nil, fmt.Errorf("failed to load defaults: %w", err)
	}
	
	if err := l.loadEnvironmentConfig(cfg); err != nil {
		return nil, fmt.Errorf("failed to load environment config: %w", err)
	}
	
	if l.env != "local" && l.projectID != "" {
		if err := l.loadSecrets(ctx, cfg); err != nil {
			return nil, fmt.Errorf("failed to load secrets: %w", err)
		}
	}
	
	if err := l.loadFromEnvVars(cfg); err != nil {
		return nil, fmt.Errorf("failed to load from env vars: %w", err)
	}
	
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}
	
	return cfg, nil
}

func (l *Loader) loadDefaults(cfg *Config) error {
	defaultConfig := `
app:
  name: myapp
  port: 8080
  log_level: info
  timeout: 30s

database:
  port: 5432
  ssl_mode: require
  max_connections: 10
  connection_timeout: 30s
  conn_max_lifetime: 1h

redis:
  port: 6379
  ssl: true
  pool_size: 10

pubsub:
  subscription_timeout: 30s
`
	return yaml.Unmarshal([]byte(defaultConfig), cfg)
}

func (l *Loader) loadEnvironmentConfig(cfg *Config) error {
	configPath := fmt.Sprintf("config/config.%s.yaml", l.env)
	
	data, err := os.ReadFile(configPath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed to read config file: %w", err)
	}
	
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return fmt.Errorf("failed to parse config file: %w", err)
	}
	
	return nil
}

func (l *Loader) loadSecrets(ctx context.Context, cfg *Config) error {
	client, err := secretmanager.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("failed to create secret manager client: %w", err)
	}
	defer client.Close()
	
	secrets := map[string]*string{
		fmt.Sprintf("%s/myapp/database/password", l.env): &cfg.Database.Password,
		fmt.Sprintf("%s/myapp/database/user", l.env):     &cfg.Database.User,
		fmt.Sprintf("%s/myapp/redis/password", l.env):    &cfg.Redis.Password,
	}
	
	for secretName, target := range secrets {
		value, err := l.getSecret(ctx, client, secretName)
		if err != nil {
			return fmt.Errorf("failed to get secret %s: %w", secretName, err)
		}
		*target = value
	}
	
	return nil
}

func (l *Loader) getSecret(ctx context.Context, client *secretmanager.Client, name string) (string, error) {
	if cached, ok := l.secretCache[name]; ok {
		return cached, nil
	}
	
	req := &secretmanagerpb.AccessSecretVersionRequest{
		Name: fmt.Sprintf("projects/%s/secrets/%s/versions/latest", l.projectID, name),
	}
	
	result, err := client.AccessSecretVersion(ctx, req)
	if err != nil {
		return "", err
	}
	
	value := string(result.Payload.Data)
	l.secretCache[name] = value
	
	return value, nil
}

func (l *Loader) loadFromEnvVars(cfg *Config) error {
	cfg.App.Env = l.env
	
	if v := os.Getenv("APP_PORT"); v != "" {
		if port, err := strconv.Atoi(v); err == nil {
			cfg.App.Port = port
		}
	}
	
	if v := os.Getenv("LOG_LEVEL"); v != "" {
		cfg.App.LogLevel = v
	}
	
	if v := os.Getenv("DATABASE_HOST"); v != "" {
		cfg.Database.Host = v
	}
	if v := os.Getenv("DATABASE_PORT"); v != "" {
		if port, err := strconv.Atoi(v); err == nil {
			cfg.Database.Port = port
		}
	}
	if v := os.Getenv("DATABASE_NAME"); v != "" {
		cfg.Database.Name = v
	}
	if v := os.Getenv("DATABASE_USER"); v != "" {
		cfg.Database.User = v
	}
	if v := os.Getenv("DATABASE_PASSWORD"); v != "" {
		cfg.Database.Password = v
	}
	
	if v := os.Getenv("REDIS_HOST"); v != "" {
		cfg.Redis.Host = v
	}
	if v := os.Getenv("REDIS_PASSWORD"); v != "" {
		cfg.Redis.Password = v
	}
	
	if v := os.Getenv("GCP_PROJECT_ID"); v != "" {
		cfg.GCP.ProjectID = v
		cfg.PubSub.ProjectID = v
	}
	if v := os.Getenv("GCP_REGION"); v != "" {
		cfg.GCP.Region = v
	}
	
	return nil
}

func (c *Config) Validate() error {
	var errors []string
	
	if c.App.Name == "" {
		errors = append(errors, "app.name is required")
	}
	if c.App.Port <= 0 || c.App.Port > 65535 {
		errors = append(errors, "app.port must be between 1 and 65535")
	}
	
	if c.Database.Host == "" {
		errors = append(errors, "database.host is required")
	}
	if c.Database.Name == "" {
		errors = append(errors, "database.name is required")
	}
	if c.Database.Password == "" {
		errors = append(errors, "database.password is required")
	}
	
	if c.Redis.Host == "" {
		errors = append(errors, "redis.host is required")
	}
	
	validSSLModes := map[string]bool{
		"disable":     true,
		"require":     true,
		"verify-ca":   true,
		"verify-full": true,
	}
	if !validSSLModes[c.Database.SSLMode] {
		errors = append(errors, "database.ssl_mode must be one of: disable, require, verify-ca, verify-full")
	}
	
	if len(errors) > 0 {
		return fmt.Errorf("validation errors:\n  - %s", strings.Join(errors, "\n  - "))
	}
	
	return nil
}

func (c *Config) GetDSN() string {
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Database.Host,
		c.Database.Port,
		c.Database.User,
		c.Database.Password,
		c.Database.Name,
		c.Database.SSLMode,
	)
}

func (c *Config) GetRedisAddr() string {
	return fmt.Sprintf("%s:%d", c.Redis.Host, c.Redis.Port)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
