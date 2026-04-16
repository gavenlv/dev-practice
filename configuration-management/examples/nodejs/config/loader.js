/**
 * Configuration loader for multi-environment configuration management.
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

let SecretManagerServiceClient;
try {
  SecretManagerServiceClient = require('@google-cloud/secret-manager').SecretManagerServiceClient;
} catch (e) {
  SecretManagerServiceClient = null;
}

class ConfigValidationError extends Error {
  constructor(errors) {
    super('Configuration validation failed:\n  - ' + errors.join('\n  - '));
    this.name = 'ConfigValidationError';
    this.errors = errors;
  }
}

class AppConfig {
  constructor(data = {}) {
    this.name = data.name || 'myapp';
    this.port = data.port || 8080;
    this.logLevel = data.logLevel || data.log_level || 'info';
    this.env = data.env || 'local';
    this.timeout = data.timeout || 30;
  }
}

class DatabaseConfig {
  constructor(data = {}) {
    this.host = data.host || 'localhost';
    this.port = data.port || 5432;
    this.name = data.name || data.database || '';
    this.user = data.user || '';
    this.password = data.password || '';
    this.sslMode = data.sslMode || data.ssl_mode || 'require';
    this.maxConnections = data.maxConnections || data.max_connections || 10;
    this.connectionTimeout = data.connectionTimeout || data.connection_timeout || 30;
    this.connMaxLifetime = data.connMaxLifetime || data.conn_max_lifetime || 3600;
  }
}

class RedisConfig {
  constructor(data = {}) {
    this.host = data.host || 'localhost';
    this.port = data.port || 6379;
    this.password = data.password || '';
    this.db = data.db || 0;
    this.ssl = data.ssl !== undefined ? data.ssl : true;
    this.poolSize = data.poolSize || data.pool_size || 10;
  }
}

class PubSubConfig {
  constructor(data = {}) {
    this.projectId = data.projectId || data.project_id || '';
    this.subscriptionTimeout = data.subscriptionTimeout || data.subscription_timeout || 30;
  }
}

class GCPConfig {
  constructor(data = {}) {
    this.projectId = data.projectId || data.project_id || '';
    this.region = data.region || '';
  }
}

class Config {
  constructor(data = {}) {
    this.app = new AppConfig(data.app || {});
    this.database = new DatabaseConfig(data.database || {});
    this.redis = new RedisConfig(data.redis || {});
    this.pubsub = new PubSubConfig(data.pubsub || {});
    this.gcp = new GCPConfig(data.gcp || {});
  }
}

class SecretManagerClient {
  constructor(projectId) {
    if (!SecretManagerServiceClient) {
      throw new Error('@google-cloud/secret-manager is not installed');
    }
    
    this.client = new SecretManagerServiceClient();
    this.projectId = projectId;
    this.cache = new Map();
  }
  
  async getSecret(secretId, version = 'latest') {
    const cacheKey = `${secretId}:${version}`;
    
    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey);
    }
    
    const name = `projects/${this.projectId}/secrets/${secretId}/versions/${version}`;
    
    const [response] = await this.client.accessSecretVersion({ name });
    const value = response.payload.data.toString('utf8');
    
    this.cache.set(cacheKey, value);
    return value;
  }
}

class ConfigLoader {
  constructor(options = {}) {
    this.env = options.env || process.env.APP_ENV || 'local';
    this.projectId = options.projectId || process.env.GCP_PROJECT_ID || '';
    this.configDir = options.configDir || 'config';
    this.secretClient = null;
  }
  
  async load() {
    const config = new Config();
    
    this.loadDefaults(config);
    await this.loadEnvironmentConfig(config);
    
    if (this.env !== 'local' && this.projectId) {
      await this.loadSecrets(config);
    }
    
    this.loadFromEnvVars(config);
    this.validate(config);
    
    return config;
  }
  
  loadDefaults(config) {
    config.app = new AppConfig();
    config.database = new DatabaseConfig();
    config.redis = new RedisConfig();
    config.pubsub = new PubSubConfig();
    config.gcp = new GCPConfig();
  }
  
  async loadEnvironmentConfig(config) {
    const configFile = path.join(this.configDir, `config.${this.env}.yaml`);
    
    if (!fs.existsSync(configFile)) {
      return;
    }
    
    const content = fs.readFileSync(configFile, 'utf8');
    const data = yaml.load(content);
    
    if (!data) {
      return;
    }
    
    if (data.app) {
      config.app = new AppConfig({ ...config.app, ...data.app });
    }
    if (data.database) {
      config.database = new DatabaseConfig({ ...config.database, ...data.database });
    }
    if (data.redis) {
      config.redis = new RedisConfig({ ...config.redis, ...data.redis });
    }
    if (data.pubsub) {
      config.pubsub = new PubSubConfig({ ...config.pubsub, ...data.pubsub });
    }
    if (data.gcp) {
      config.gcp = new GCPConfig({ ...config.gcp, ...data.gcp });
    }
  }
  
  async getSecretClient() {
    if (!this.secretClient && this.projectId && SecretManagerServiceClient) {
      this.secretClient = new SecretManagerClient(this.projectId);
    }
    return this.secretClient;
  }
  
  async loadSecrets(config) {
    const client = await this.getSecretClient();
    if (!client) {
      return;
    }
    
    const secretMappings = {
      [`${this.env}/myapp/database/password`]: ['database', 'password'],
      [`${this.env}/myapp/database/user`]: ['database', 'user'],
      [`${this.env}/myapp/redis/password`]: ['redis', 'password'],
    };
    
    for (const [secretId, [section, attr]] of Object.entries(secretMappings)) {
      try {
        const value = await client.getSecret(secretId);
        config[section][attr] = value;
      } catch (e) {
        console.warn(`Warning: Failed to load secret ${secretId}: ${e.message}`);
      }
    }
  }
  
  loadFromEnvVars(config) {
    config.app.env = this.env;
    
    const envMappings = {
      APP_PORT: ['app', 'port', Number],
      LOG_LEVEL: ['app', 'logLevel', String],
      DATABASE_HOST: ['database', 'host', String],
      DATABASE_PORT: ['database', 'port', Number],
      DATABASE_NAME: ['database', 'name', String],
      DATABASE_USER: ['database', 'user', String],
      DATABASE_PASSWORD: ['database', 'password', String],
      DATABASE_SSL_MODE: ['database', 'sslMode', String],
      REDIS_HOST: ['redis', 'host', String],
      REDIS_PORT: ['redis', 'port', Number],
      REDIS_PASSWORD: ['redis', 'password', String],
      GCP_PROJECT_ID: ['gcp', 'projectId', String],
      GCP_REGION: ['gcp', 'region', String],
    };
    
    for (const [envVar, [section, attr, typeFunc]] of Object.entries(envMappings)) {
      const value = process.env[envVar];
      if (value !== undefined) {
        try {
          config[section][attr] = typeFunc(value);
        } catch (e) {
          console.warn(`Warning: Invalid value for ${envVar}: ${e.message}`);
        }
      }
    }
  }
  
  validate(config) {
    const errors = [];
    
    if (!config.app.name) {
      errors.push('app.name is required');
    }
    if (config.app.port <= 0 || config.app.port > 65535) {
      errors.push('app.port must be between 1 and 65535');
    }
    
    if (!config.database.host) {
      errors.push('database.host is required');
    }
    if (!config.database.name) {
      errors.push('database.name is required');
    }
    if (!config.database.password) {
      errors.push('database.password is required');
    }
    
    if (!config.redis.host) {
      errors.push('redis.host is required');
    }
    
    const validSSLModes = ['disable', 'require', 'verify-ca', 'verify-full'];
    if (!validSSLModes.includes(config.database.sslMode)) {
      errors.push(`database.sslMode must be one of: ${validSSLModes.join(', ')}`);
    }
    
    if (errors.length > 0) {
      throw new ConfigValidationError(errors);
    }
  }
  
  getDSN(config) {
    return (
      `host=${config.database.host} ` +
      `port=${config.database.port} ` +
      `user=${config.database.user} ` +
      `password=${config.database.password} ` +
      `dbname=${config.database.name} ` +
      `sslmode=${config.database.sslMode}`
    );
  }
  
  getRedisURL(config) {
    if (config.redis.password) {
      return `redis://:${config.redis.password}@${config.redis.host}:${config.redis.port}/${config.redis.db}`;
    }
    return `redis://${config.redis.host}:${config.redis.port}/${config.redis.db}`;
  }
}

async function loadConfig(options = {}) {
  const loader = new ConfigLoader(options);
  return loader.load();
}

module.exports = {
  Config,
  ConfigLoader,
  ConfigValidationError,
  AppConfig,
  DatabaseConfig,
  RedisConfig,
  PubSubConfig,
  GCPConfig,
  loadConfig,
};
